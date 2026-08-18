package genrules

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// source of truth は bin/gen-rules.py。JSON がそこからずれていないかを機械で見る。
// WhyNot: 目視の約束にしないのは、ルールを Python 側だけ足したときに Go 版だけが
// 古い 3 本のまま緑を出すため。

var pyLiteral = regexp.MustCompile(`"([^"]*)"`)

func pythonSource(t *testing.T) string {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(repoRoot(), "bin", "gen-rules.py"))
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

// pyBlock は `NAME = (` か `NAME = {` から対応する閉じ括弧の直前までを返す。
func pyBlock(t *testing.T, src, name, open, closeTok string) string {
	t.Helper()
	head := regexp.MustCompile(`(?m)^` + name + ` = \` + open).FindStringIndex(src)
	if head == nil {
		t.Fatalf("bin/gen-rules.py に %s が無い", name)
	}
	tail := strings.Index(src[head[1]:], "\n"+closeTok)
	if tail < 0 {
		// 1 行で閉じる形 (OUT_DIRS)。
		tail = strings.Index(src[head[1]:], closeTok)
		if tail < 0 {
			t.Fatalf("bin/gen-rules.py の %s の閉じ括弧が見つからない", name)
		}
	}
	return src[head[1] : head[1]+tail]
}

// dropComments は行末の # 以降を落とす（RULES の中の注意書きを拾わないため）。
func dropComments(s string) string {
	var kept []string
	for _, line := range strings.Split(s, "\n") {
		if i := strings.Index(line, "#"); i >= 0 {
			line = line[:i]
		}
		kept = append(kept, line)
	}
	return strings.Join(kept, "\n")
}

func literals(s string) []string {
	out := []string{}
	for _, m := range pyLiteral.FindAllStringSubmatch(s, -1) {
		out = append(out, m[1])
	}
	return out
}

// pyRules は bin/gen-rules.py の RULES を読んで [出力名, 元の doc, glob...] に開く。
func pyRules(t *testing.T, src string) []RuleSpec {
	t.Helper()
	block := dropComments(pyBlock(t, src, "RULES", "{", "}"))
	entry := regexp.MustCompile(`(?s)"([^"]+\.md)":\s*\(\s*"([^"]+)",\s*\[(.*?)\],`)
	var specs []RuleSpec
	for _, m := range entry.FindAllStringSubmatch(block, -1) {
		specs = append(specs, RuleSpec{Out: m[1], Src: m[2], Globs: literals(m[3])})
	}
	if len(specs) == 0 {
		t.Fatal("bin/gen-rules.py の RULES を読めなかった")
	}
	return specs
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

	wantBanner := strings.Join(literals(pyBlock(t, src, "BANNER", "(", ")")), "")
	if *f.Banner != wantBanner {
		t.Errorf("banner が bin/gen-rules.py とずれている\n JSON:   %s\n Python: %s", *f.Banner, wantBanner)
	}

	wantDirs := literals(pyBlock(t, src, "OUT_DIRS", "(", ")"))
	if strings.Join(*f.OutDirs, "\x00") != strings.Join(wantDirs, "\x00") {
		t.Errorf("outDirs が bin/gen-rules.py とずれている: %v (Python %v)", *f.OutDirs, wantDirs)
	}

	want := pyRules(t, src)
	got := *f.Rules
	if len(got) != len(want) {
		t.Fatalf("rules の本数が %d (Python %d)", len(got), len(want))
	}
	for i := range want {
		if got[i].Out != want[i].Out || got[i].Src != want[i].Src {
			t.Errorf("rules[%d] が %s <- %s (Python %s <- %s)",
				i, got[i].Out, got[i].Src, want[i].Out, want[i].Src)
			continue
		}
		if strings.Join(got[i].Globs, "\x00") != strings.Join(want[i].Globs, "\x00") {
			t.Errorf("rules[%d] (%s) の globs がずれている\n JSON:   %v\n Python: %v",
				i, got[i].Out, got[i].Globs, want[i].Globs)
		}
	}
}

func TestLoadRulesFromRepo(t *testing.T) {
	rules, err := LoadRules(repoRoot())
	if err != nil {
		t.Fatal(err)
	}
	if len(rules.Rules) == 0 {
		t.Fatal("ルールが 1 本も無い")
	}
	if rules.Rules[0].Out != "drawing.md" {
		t.Errorf("1 本目が %s (期待 drawing.md)", rules.Rules[0].Out)
	}
	if len(rules.OutDirs) != 2 {
		t.Errorf("配り先が %d 個", len(rules.OutDirs))
	}
	if !strings.Contains(rules.Banner, "{src}") {
		t.Errorf("banner に {src} が無い: %q", rules.Banner)
	}
}

func TestMissingRulesFileAborts(t *testing.T) {
	if _, err := LoadRules(t.TempDir()); err == nil {
		t.Fatal("規約ファイルが無いのにエラーを返さなかった")
	}
}

func TestPartialRulesFileAborts(t *testing.T) {
	root := t.TempDir()
	writeRules(t, root, `{"banner": "x"}`)
	err := loadErr(t, root)
	if !strings.Contains(err.Error(), "rules") {
		t.Errorf("欠けているキーの名前が出ていない: %v", err)
	}
}

func TestRuleWithoutSourceAborts(t *testing.T) {
	root := t.TempDir()
	writeRules(t, root, `{"banner":"x","rules":[{"out":"a.md"}],"outDirs":[]}`)
	if err := loadErr(t, root); !strings.Contains(err.Error(), "out か src") {
		t.Errorf("src の無い項目を受け入れてしまった: %v", err)
	}
}

func TestBrokenRulesFileAborts(t *testing.T) {
	root := t.TempDir()
	writeRules(t, root, "{")
	loadErr(t, root)
}

func writeRules(t *testing.T, root, body string) {
	t.Helper()
	path := filepath.Join(root, RulesPath)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

func loadErr(t *testing.T, root string) error {
	t.Helper()
	_, err := LoadRules(root)
	if err == nil {
		t.Fatal("壊れた規約ファイルを受け入れてしまった")
	}
	return err
}
