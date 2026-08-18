package renderbudget

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// source of truthは bin/lint-rules/check-render-budget.json。読み込みがそこからずれていないかを機械で見る。
// WhyNot: 目視の約束にしないのは、閾値を JSON 側だけ直したときにコードが
// 古い上限のまま緑を出すため。

func TestLoadRulesFromRepo(t *testing.T) {
	rules, err := LoadRules(repoRoot())
	if err != nil {
		t.Fatal(err)
	}
	if rules.DefaultCap != 2000 {
		t.Errorf("defaultCap が %d", rules.DefaultCap)
	}
	if rules.driftLimit(100) != 300 {
		t.Errorf("基準 100 のドリフト上限が %d (期待 300)", rules.driftLimit(100))
	}
	if rules.driftLimit(1000) != 1500 {
		t.Errorf("基準 1000 のドリフト上限が %d (期待 1500)", rules.driftLimit(1000))
	}
}

func TestMissingRulesFileAborts(t *testing.T) {
	if _, err := LoadRules(t.TempDir()); err == nil {
		t.Fatal("規約ファイルが無いのにエラーを返さなかった")
	}
}

func TestPartialRulesFileAborts(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, RulesPath)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(`{"defaultCap": 10}`), 0o644); err != nil {
		t.Fatal(err)
	}
	_, err := LoadRules(root)
	if err == nil {
		t.Fatal("キーの欠けた規約ファイルを受け入れてしまった")
	}
	if !strings.Contains(err.Error(), "driftFactor") {
		t.Errorf("欠けているキーの名前が出ていない: %v", err)
	}
}

func TestBrokenRulesFileAborts(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, RulesPath)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("{"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadRules(root); err == nil {
		t.Fatal("壊れた JSON を受け入れてしまった")
	}
}
