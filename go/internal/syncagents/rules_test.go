package syncagents

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// source of truth は bin/sync-agents.py。JSON がそこからずれていないかを機械で見る。
// WhyNot: 目視の約束にしないのは、配り先や見に行く先を Python 側だけ直したときに
// Go 版だけが古い値で他のリポへ書き込むため。

func repoRoot() string { return filepath.Join("..", "..", "..") }

func pythonSource(t *testing.T) string {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(repoRoot(), "bin", "sync-agents.py"))
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

// pathExpr は "a/b" を Python 側の書き方 `"a" / "b"` に直す。
func pathExpr(rel string) string {
	parts := strings.Split(rel, "/")
	for i, p := range parts {
		parts[i] = `"` + p + `"`
	}
	return strings.Join(parts, " / ")
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

	for _, tc := range []struct {
		what string
		want string
	}{
		{"manifestPath", pathExpr(*f.ManifestPath)},
		{"skillsDir", pathExpr(*f.SkillsDir)},
		{"rulesDir", pathExpr(*f.RulesDir)},
		{"coreDoc", pathExpr(*f.CoreDoc)},
		{"localDoc", `"` + *f.LocalDoc + `"`},
		{"agentsMd", `"` + *f.AgentsMd + `"`},
		{"claudeMd", `"` + *f.ClaudeMd + `"`},
		{"claudeMdBody", `"@AGENTS.md\n"`},
		{"skillFile", `"` + *f.SkillFile + `"`},
		{"skillLinkPattern", *f.SkillLinkPattern},
		{"lintPrefix", `"` + *f.LintPrefix + `"`},
		{"sentenceSep", `"` + *f.SentenceSep + `"`},
		{"triggerSuffix", `"` + *f.TriggerSuffix + `"`},
	} {
		if !strings.Contains(src, tc.want) {
			t.Errorf("%s が bin/sync-agents.py に見つからない: %s", tc.what, tc.want)
		}
	}

	if *f.ClaudeMdBody != "@AGENTS.md\n" {
		t.Errorf("claudeMdBody が %q", *f.ClaudeMdBody)
	}
	keys := "(" + `"` + strings.Join(*f.ManifestKeys, `", "`) + `"` + ")"
	if !strings.Contains(src, keys) {
		t.Errorf("manifestKeys が bin/sync-agents.py とずれている: %s", keys)
	}
	roots := *f.SkillLinkRoots
	if len(roots) == 0 || roots[0] != *f.SkillsDir {
		t.Errorf("skillLinkRoots の 1 つ目は skillsDir と同じはず: %v", roots)
	}
	for _, rel := range roots[1:] {
		if !strings.Contains(src, pathExpr(rel)) {
			t.Errorf("skillLinkRoots の %s が bin/sync-agents.py に無い", rel)
		}
	}
}

func TestLoadRulesFromRepo(t *testing.T) {
	rules, err := LoadRules(repoRoot())
	if err != nil {
		t.Fatal(err)
	}
	if len(rules.ManifestKeys) != 3 {
		t.Fatalf("manifestKeys が %d 個", len(rules.ManifestKeys))
	}
	if rules.ManifestKeys[keyCopyDirs] != "copyDirs" {
		t.Errorf("3 つ目のキーが %s", rules.ManifestKeys[keyCopyDirs])
	}
	if rules.SkillLink.NumSubexp() != 1 {
		t.Errorf("skillLinkPattern の丸括弧が %d 組", rules.SkillLink.NumSubexp())
	}
}

func TestMissingRulesFileAborts(t *testing.T) {
	if _, err := LoadRules(t.TempDir()); err == nil {
		t.Fatal("規約ファイルが無いのにエラーを返さなかった")
	}
}

func TestPartialRulesFileAborts(t *testing.T) {
	root := t.TempDir()
	writeRules(t, root, `{"manifestPath": "x"}`)
	err := loadErr(t, root)
	if !strings.Contains(err.Error(), "manifestKeys") {
		t.Errorf("欠けているキーの名前が出ていない: %v", err)
	}
}

func TestBrokenRulesFileAborts(t *testing.T) {
	root := t.TempDir()
	writeRules(t, root, "{")
	loadErr(t, root)
}

func TestWrongKeyCountAborts(t *testing.T) {
	root := t.TempDir()
	full, err := os.ReadFile(filepath.Join(repoRoot(), RulesPath))
	if err != nil {
		t.Fatal(err)
	}
	body := strings.Replace(string(full),
		`["copy", "copyIfAbsent", "copyDirs"]`, `["copy", "copyDirs"]`, 1)
	writeRules(t, root, body)
	if err := loadErr(t, root); !strings.Contains(err.Error(), "manifestKeys") {
		t.Errorf("キーの数を見ていない: %v", err)
	}
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
