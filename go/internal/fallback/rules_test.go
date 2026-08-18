package fallback

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// 正本は bin/lint-fallback.py。JSON がそこからずれていないかを機械で見る。
// WhyNot: 目視の約束にしないのは、規約を Python 側だけ直したときに Go 版だけが
// 古い判定のまま緑を出すため。

var pyLiteral = regexp.MustCompile(`"([^"]*)"`)

func pythonSource(t *testing.T) string {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(repoRoot(), "bin", "lint-fallback.py"))
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

// pyBlock は `NAME = <開き括弧>` から行頭の閉じ括弧までの中身を返す。
func pyBlock(t *testing.T, src, name, closer string) string {
	t.Helper()
	head := regexp.MustCompile(`(?m)^` + name + ` = .$`).FindStringIndex(src)
	if head == nil {
		t.Fatalf("bin/lint-fallback.py に %s が無い", name)
	}
	tail := strings.Index(src[head[1]:], "\n"+closer)
	if tail < 0 {
		t.Fatalf("bin/lint-fallback.py の %s の閉じ括弧が見つからない", name)
	}
	return src[head[1] : head[1]+tail]
}

// pyStrings はブロック内の文字列リテラルを出てきた順に返す。
func pyStrings(block string) []string {
	var found []string
	for _, m := range pyLiteral.FindAllStringSubmatch(block, -1) {
		found = append(found, m[1])
	}
	return found
}

func pyPattern(t *testing.T, src, name, quote string) string {
	t.Helper()
	m := regexp.MustCompile(`(?m)^` + name + ` = re\.compile\(r` + quote + `(.*)` + quote + `\)$`).FindStringSubmatch(src)
	if m == nil {
		t.Fatalf("bin/lint-fallback.py に %s が無い", name)
	}
	return m[1]
}

func loadRulesFile(t *testing.T) rulesFile {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(repoRoot(), RulesPath))
	if err != nil {
		t.Fatal(err)
	}
	var f rulesFile
	if err := json.Unmarshal(data, &f); err != nil {
		t.Fatal(err)
	}
	return f
}

func TestRulesMatchPython(t *testing.T) {
	src := pythonSource(t)
	f := loadRulesFile(t)

	wantRoots := pyStrings(pyBlock(t, src, "SRC_ROOTS", "]"))
	if strings.Join(f.SrcRoots, "\x00") != strings.Join(wantRoots, "\x00") {
		t.Errorf("srcRoots が bin/lint-fallback.py とずれている\n JSON:   %v\n Python: %v", f.SrcRoots, wantRoots)
	}

	flat := pyStrings(pyBlock(t, src, "EXEMPT", "}"))
	if len(flat)%2 != 0 {
		t.Fatalf("EXEMPT の鍵と理由が対になっていない (%d 個)", len(flat))
	}
	want := map[string]string{}
	for i := 0; i < len(flat); i += 2 {
		want[flat[i]] = flat[i+1]
	}
	if len(want) != len(f.Exempt) {
		t.Errorf("exempt の件数が違う: JSON %d / Python %d", len(f.Exempt), len(want))
	}
	for key, reason := range want {
		got, ok := f.Exempt[key]
		if !ok {
			t.Errorf("exempt に %s が無い", key)
			continue
		}
		if got != reason {
			t.Errorf("exempt[%s] の理由がずれている\n JSON:   %s\n Python: %s", key, got, reason)
		}
	}

	checks := []struct{ name, got, want string }{
		{"bugPattern", *f.BugPattern, pyPattern(t, src, "BUG", `"`)},
		{"defPattern", *f.DefPattern, pyPattern(t, src, "DEF", `"`)},
		{"stringPattern", *f.StringPattern, pyPattern(t, src, "STRING", `'`)},
	}
	for _, c := range checks {
		if c.got != c.want {
			t.Errorf("%s が bin/lint-fallback.py とずれている\n JSON:   %s\n Python: %s", c.name, c.got, c.want)
		}
	}
}

func TestLoadRulesFromRepo(t *testing.T) {
	rules, err := LoadRules(repoRoot())
	if err != nil {
		t.Fatal(err)
	}
	if len(rules.Exempt) != len(rules.ExemptKeys) {
		t.Errorf("除外の鍵が重複している: %d / %d", len(rules.ExemptKeys), len(rules.Exempt))
	}
	if !sortedAsc(rules.ExemptKeys) {
		t.Errorf("除外の鍵が並んでいない: %v", rules.ExemptKeys)
	}
	if m := rules.Def.FindStringSubmatch("    pub def loadThing(x: Int): Int ="); m == nil || m[1] != "loadThing" {
		t.Errorf("def の関数名を拾えていない: %v", m)
	}
}

func sortedAsc(v []string) bool {
	for i := 1; i < len(v); i++ {
		if v[i-1] > v[i] {
			return false
		}
	}
	return true
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
		"鍵が欠けている":     `{"srcRoots": ["a/src"], "bugPattern": "x"}`,
		"正規表現が壊れている":  `{"srcRoots": [], "bugPattern": "(", "defPattern": "x", "stringPattern": "y", "exempt": {}}`,
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
