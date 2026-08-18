package uioverflow

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"
)

// 正本は bin/lint-ui-overflow.py。JSON がそこからずれていないかを機械で見る。
// WhyNot: 目視の約束にしないのは、規約を Python 側だけ直したときに Go 版だけが
// 古い判定のまま緑を出すため。

var pyLiteral = regexp.MustCompile(`"([^"]*)"`)

func pythonSource(t *testing.T) string {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(repoRoot(), "bin", "lint-ui-overflow.py"))
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

// pyOne は 1 つの丸括弧付き部分文字列を取り出す。
func pyOne(t *testing.T, src, pattern string) string {
	t.Helper()
	m := regexp.MustCompile(pattern).FindStringSubmatch(src)
	if m == nil {
		t.Fatalf("bin/lint-ui-overflow.py に %s が無い", pattern)
	}
	return m[1]
}

// pyList は `NAME = <括弧>...` の中の文字列リテラルを返す。
func pyList(t *testing.T, src, name string) []string {
	t.Helper()
	body := pyOne(t, src, `(?m)^`+name+` = .(.*).$`)
	var found []string
	for _, m := range pyLiteral.FindAllStringSubmatch(body, -1) {
		found = append(found, m[1])
	}
	return found
}

func TestRulesMatchPython(t *testing.T) {
	src := pythonSource(t)
	data, err := os.ReadFile(filepath.Join(repoRoot(), RulesPath))
	if err != nil {
		t.Fatal(err)
	}
	var f rulesFile
	if err := json.Unmarshal(data, &f); err != nil {
		t.Fatal(err)
	}

	lists := []struct {
		name      string
		got, want []string
	}{
		{"gameRoots", f.GameRoots, pyList(t, src, "GAME_ROOTS")},
		{"excludedDirs", sortedCopy(f.ExcludedDirs), sortedCopy(pyList(t, src, "EXCLUDED_DIRS"))},
	}
	for _, c := range lists {
		if strings.Join(c.got, "\x00") != strings.Join(c.want, "\x00") {
			t.Errorf("%s が bin/lint-ui-overflow.py とずれている\n JSON:   %v\n Python: %v", c.name, c.got, c.want)
		}
	}

	words := []struct{ name, got, want string }{
		{"suffix", *f.Suffix, pyOne(t, src, `n\.endswith\("([^"]*)"\)`)},
		{"exemptKey", *f.ExemptKey, pyOne(t, src, `text = node\.get\("([^"]*)"\)`)},
		{"exemptMarker", *f.ExemptMarker, pyOne(t, src, `and "([^"]*)" in text`)},
		{"textWidget", *f.TextWidget, pyOne(t, src, `merged\.get\("widget"\) == "([^"]*)"`)},
		{"wrapAuto", *f.WrapAuto, pyOne(t, src, `isinstance\(wrap, str\) and wrap == "([^"]*)"`)},
		{"growWidth", *f.GrowWidth, pyOne(t, src, `if value == "([^"]*)":`)},
	}
	for _, c := range words {
		if c.got != c.want {
			t.Errorf("%s が bin/lint-ui-overflow.py とずれている\n JSON:   %s\n Python: %s", c.name, c.got, c.want)
		}
	}
}

func TestLimitsNoteMatchesPython(t *testing.T) {
	src := pythonSource(t)
	head := strings.Index(src, "LIMITS_NOTE = (")
	if head < 0 {
		t.Fatal("bin/lint-ui-overflow.py に LIMITS_NOTE が無い")
	}
	tail := strings.Index(src[head:], "\n)")
	var b strings.Builder
	for _, m := range pyLiteral.FindAllStringSubmatch(src[head:head+tail], -1) {
		b.WriteString(m[1])
	}
	if b.String() != LimitsNote {
		t.Errorf("但し書きがずれている\n Go:     %s\n Python: %s", LimitsNote, b.String())
	}
}

func TestMissingRulesFileAborts(t *testing.T) {
	var out, errOut strings.Builder
	code, err := Run(&out, &errOut, t.TempDir(), nil)
	if err == nil {
		t.Fatal("規約ファイルが無いのにエラーを返さなかった")
	}
	if code == 0 {
		t.Errorf("規約ファイルが無いのに終了コード 0")
	}
	if out.String() != "" {
		t.Errorf("規約が読めないのに何か出力した: %q", out.String())
	}
}

func TestBrokenRulesFileAborts(t *testing.T) {
	cases := map[string]string{
		"JSON が壊れている": "{",
		"鍵が欠けている":     `{"gameRoots": ["templates"], "excludedDirs": []}`,
	}
	for name, body := range cases {
		root := t.TempDir()
		path := filepath.Join(root, RulesPath)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
		var out, errOut strings.Builder
		if _, err := Run(&out, &errOut, root, nil); err == nil {
			t.Errorf("%s のに受け入れてしまった", name)
		}
	}
}

func TestExcludedDirsAreSorted(t *testing.T) {
	rules, err := LoadRules(repoRoot())
	if err != nil {
		t.Fatal(err)
	}
	if !sort.StringsAreSorted(rules.ExcludedDirs) {
		t.Errorf("除外ディレクトリが並んでいない: %v", rules.ExcludedDirs)
	}
}
