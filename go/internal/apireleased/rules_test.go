package apireleased

// What: 規約データが読めること・欠けを見つけること・Python 版と食い違わないこと。

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// repoRoot はこのテストから見たリポジトリの根。
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

func TestRulesMatchPythonPackages(t *testing.T) {
	data, err := os.ReadFile(filepath.Join(repoRoot, "bin", "check-api-released.py"))
	if err != nil {
		t.Skipf("Python 版が読めない: %v", err)
	}
	block := pyPkgs.FindStringSubmatch(string(data))
	if block == nil {
		t.Fatal("Python 版から PKGS を読めなかった")
	}
	var want []string
	for _, m := range pyStr.FindAllStringSubmatch(block[1], -1) {
		want = append(want, m[1])
	}
	rules, err := LoadRules(repoRoot)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Join(want, ",") != strings.Join(rules.Packages, ",") {
		t.Errorf("PKGS が Python %v / JSON %v", want, rules.Packages)
	}
}
