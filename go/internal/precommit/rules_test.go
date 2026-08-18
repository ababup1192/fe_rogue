package precommit

import (
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"testing"
)

// source of truth は bin/precommit.py と bin/lint-images.py。JSON がそこから
// ずれていないかを機械で見る。
// WhyNot: 目視の約束にしないのは、検査の並びや置き場の決まりを Python 側だけ
// 直したときに Go 版だけが古い規約のまま緑を出すため。

func pySource(t *testing.T, name string) string {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(repoRoot(t), "bin", name))
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

var spaces = regexp.MustCompile(`\s+`)

// flat は改行とインデントを 1 個の空白に潰す（複数行に折り返したタプルを 1 行として見る）。
func flat(src string) string { return spaces.ReplaceAllString(src, " ") }

// joined は Python の暗黙の文字列連結（"..." 改行 "..."）を 1 本につなぐ。
var joinRe = regexp.MustCompile("\"\\s*\\n\\s*f?\"")

func joined(src string) string { return joinRe.ReplaceAllString(src, "") }

// pyTuple は `NAME = ( ... )` の中の引用符つき文字列を並び順に取り出す。
func pyTuple(t *testing.T, src, name string) []string {
	t.Helper()
	m := regexp.MustCompile(`(?s)` + name + ` = \((.*?)\)`).FindStringSubmatch(src)
	if m == nil {
		t.Fatalf("%s が見つからない", name)
	}
	var out []string
	for _, q := range regexp.MustCompile(`"([^"]*)"`).FindAllStringSubmatch(m[1], -1) {
		out = append(out, q[1])
	}
	return out
}

func sameList(t *testing.T, what string, got, want []string) {
	t.Helper()
	if strings.Join(got, "|") != strings.Join(want, "|") {
		t.Errorf("%s が Python とずれている: JSON=%v Python=%v", what, got, want)
	}
}

func rulesOfRepo(t *testing.T) *Rules {
	t.Helper()
	rules, err := LoadRules(repoRoot(t))
	if err != nil {
		t.Fatal(err)
	}
	return rules
}

func TestChecksMatchPython(t *testing.T) {
	src := pySource(t, "precommit.py")
	rules := rulesOfRepo(t)

	calls := regexp.MustCompile(`run_lint\("([^"]+)", "([^"]+)"([^)]*)\)`).FindAllStringSubmatch(src, -1)
	if len(calls) != len(rules.Checks) {
		t.Fatalf("検査の本数が違う: JSON=%d Python=%d", len(rules.Checks), len(calls))
	}
	for i, c := range rules.Checks {
		if c.Tool != calls[i][1] || c.Sub != calls[i][2] {
			t.Errorf("%d 本目が違う: JSON=(%s,%s) Python=(%s,%s)",
				i+1, c.Tool, c.Sub, calls[i][1], calls[i][2])
		}
		for _, f := range c.Flags {
			if !strings.Contains(calls[i][3], `"`+f+`"`) {
				t.Errorf("%s の旗 %s が Python の呼び口に無い", c.ID, f)
			}
		}
		if strings.Contains(calls[i][3], `"--`) && len(c.Flags) == 0 {
			t.Errorf("%s は Python が旗を渡しているのに JSON に無い", c.ID)
		}
		// *flix / *ui のように可変長で渡しているかどうかを見る。
		wantsFiles := strings.Contains(calls[i][3], "*")
		if wantsFiles != (c.Pass == "matched") {
			t.Errorf("%s の pass が違う: JSON=%s Python=%q", c.ID, c.Pass, calls[i][3])
		}
	}
}

// TestMatcherLiteralsAreInPython は絞り込みに使う文字列が Python 側にそのまま在るか見る。
func TestMatcherLiteralsAreInPython(t *testing.T) {
	src := flat(pySource(t, "precommit.py"))
	rules := rulesOfRepo(t)

	var walk func(what string, m Matcher)
	walk = func(what string, m Matcher) {
		for _, sub := range m.AnyOf {
			walk(what, sub)
		}
		for _, group := range [][]string{m.Suffixes, m.Prefixes, m.Substrings, m.Basenames} {
			if len(group) == 0 {
				continue
			}
			lit := `"` + strings.Join(group, `", "`) + `"`
			if len(group) > 1 {
				lit = "(" + lit + ")"
			}
			if !strings.Contains(src, lit) {
				t.Errorf("%s の %s が bin/precommit.py に無い", what, lit)
			}
		}
	}
	for _, c := range rules.Checks {
		walk(c.ID, c.When)
	}
	walk("docsSync", rules.DocsSync.When)
	if !strings.Contains(src, `"`+rules.DocsSync.Target+`"`) &&
		!strings.Contains(src, `, "`+rules.DocsSync.Target+`"`) {
		t.Errorf("docsSync.target が bin/precommit.py に無い")
	}
}

func TestStagedImageRulesMatchLintImages(t *testing.T) {
	src := pySource(t, "lint-images.py")
	s := rulesOfRepo(t).StagedImages

	sameList(t, "imageExts", s.ImageExts, pyTuple(t, src, "IMAGE_EXTS"))
	sameList(t, "allowedPrefixes", s.AllowedPrefixes, pyTuple(t, src, "ALLOWED_PREFIXES"))
	sameList(t, "allowedSubstrings", s.AllowedSubstrings, pyTuple(t, src, "ALLOWED_SUBSTRINGS"))
	sameList(t, "allowedSuffixes", s.AllowedSuffixes, pyTuple(t, src, "ALLOWED_SUFFIXES"))
	sameList(t, "allowedExact", s.AllowedExact, pyTuple(t, src, "ALLOWED_EXACT"))

	m := regexp.MustCompile(`GALLERY_MAX_FILE_BYTES = (\d+) \* (\d+)`).FindStringSubmatch(src)
	if m == nil {
		t.Fatal("GALLERY_MAX_FILE_BYTES が見つからない")
	}
	a, _ := strconv.ParseInt(m[1], 10, 64)
	b, _ := strconv.ParseInt(m[2], 10, 64)
	if s.GalleryMaxFileBytes != a*b {
		t.Errorf("galleryMaxFileBytes が違う: JSON=%d Python=%d", s.GalleryMaxFileBytes, a*b)
	}
	if !strings.Contains(pySource(t, "precommit.py"), `"`+s.GalleryPrefix+`"`) {
		t.Errorf("galleryPrefix が bin/precommit.py に無い")
	}
}

func TestFailOpenMessagesMatchPython(t *testing.T) {
	src := joined(pySource(t, "precommit.py"))
	f := rulesOfRepo(t).FailOpen
	for _, msg := range []string{f.ToolMissing, f.MakeMissing, f.TargetMissing} {
		if !strings.Contains(src, msg) {
			t.Errorf("fail-open の文面が bin/precommit.py に無い: %q", msg)
		}
	}
	if !strings.Contains(src, "probe.returncode == "+strconv.Itoa(f.TargetMissingExitCode)) {
		t.Errorf("make -q の判定に使う終了コードが Python とずれている")
	}
}

// TestGateMessagesMatchPython は Go のコードに直書きした文面が Python 側と同じか見る。
func TestGateMessagesMatchPython(t *testing.T) {
	src := joined(pySource(t, "precommit.py"))
	for _, msg := range []string{
		"[pre-commit] 画像 ",
		" 件:",
		"— 追跡してよい置き場ではありません。生成した絵は git に入れない決まりです。" +
			"人に見せる絵なら docs/gallery/ へ (上限あり)",
		" — 1 枚の上限 ",
		" (docs/gallery/README.md)",
		"[pre-commit] 注意: 過去から追跡されている絵に違反が残っています" +
			" (このコミットは止めません): python3 bin/fge images で一覧",
		"[pre-commit] 止めました。直してから再コミット" +
			" (どうしても通すなら git commit --no-verify)",
	} {
		if !strings.Contains(src, msg) {
			t.Errorf("文面が bin/precommit.py に無い: %q", msg)
		}
	}
}
