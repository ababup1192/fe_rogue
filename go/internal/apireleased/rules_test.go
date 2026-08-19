package apireleased

// What: 規約データ (bin/lint-rules/check-api-released.json) が読めること・欠けを見つけること。

import (
	"os"
	"path/filepath"
	"regexp"
	"testing"
)

// repoRoot はこのテストから見たリポジトリのルート。
const repoRoot = "../../.."

func TestLoadRulesReadsRepoRules(t *testing.T) {
	rules, err := LoadRules(repoRoot)
	if err != nil {
		t.Fatal(err)
	}
	if len(rules.Packages) != 3 {
		t.Errorf("packages が %d 件", len(rules.Packages))
	}
}

func TestLoadRulesFailsWhenFileMissing(t *testing.T) {
	if _, err := LoadRules(t.TempDir()); err == nil {
		t.Error("規約ファイルが無いのにエラーにならない")
	}
}

func TestLoadRulesFailsWhenPackagesMissing(t *testing.T) {
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "bin", "lint-rules"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, RulesPath), []byte(`{}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadRules(dir); err == nil {
		t.Error("packages が無いのにエラーにならない")
	}
}

var pyPkgs = regexp.MustCompile(`(?s)PKGS\s*=\s*\((.*?)\)`)
var pyStr = regexp.MustCompile(`"([^"]*)"`)
