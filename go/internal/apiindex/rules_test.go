package apiindex

// What: 規約データ (bin/lint-rules/check-api-index.json) が読めること・欠けを見つけること。

import (
	"os"
	"path/filepath"
	"regexp"
	"testing"
)

// repoRoot はこのテストから見たリポジトリの根。
const repoRoot = "../../.."

func TestLoadRulesReadsRepoRules(t *testing.T) {
	rules, err := LoadRules(repoRoot)
	if err != nil {
		t.Fatal(err)
	}
	if len(rules.Targets) != 2 {
		t.Errorf("targets が %d 件", len(rules.Targets))
	}
}

func TestLoadRulesFailsWhenFileMissing(t *testing.T) {
	if _, err := LoadRules(t.TempDir()); err == nil {
		t.Error("規約ファイルが無いのにエラーにならない")
	}
}

func TestLoadRulesFailsWhenKeyMissing(t *testing.T) {
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "bin", "lint-rules"), 0o755); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, RulesPath)
	if err := os.WriteFile(path, []byte(`{"targets":[{"src":"a","doc":"b"}]}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadRules(dir); err == nil {
		t.Error("extraDefSources が無いのにエラーにならない")
	}
}

func TestLoadRulesFailsWhenExemptHasNoReason(t *testing.T) {
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "bin", "lint-rules"), 0o755); err != nil {
		t.Fatal(err)
	}
	body := `{"targets":[{"src":"a","doc":"b"}],"extraDefSources":[],` +
		`"exempt":{"X":""},"skipDirs":[],"fileExts":[]}`
	if err := os.WriteFile(filepath.Join(dir, RulesPath), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadRules(dir); err == nil {
		t.Error("理由の無い除外があるのにエラーにならない")
	}
}

var pyPair = regexp.MustCompile(`"([^"]*)":\s*"([^"]*)"`)
var pyStr = regexp.MustCompile(`"([^"]*)"`)
var pyTuple = regexp.MustCompile(`\("([^"]*)",\s*"([^"]*)"\)`)
