package syncagents

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// 規約ファイル (JSON) が実装の求める形になっているかを機械で見る。
// WhyNot: 目視の約束にしないのは、欠けた規約に気づかないまま他のリポへ書き込むため。

func repoRoot() string { return filepath.Join("..", "..", "..") }

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
