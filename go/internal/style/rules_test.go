package style

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// 何を見るか: 規約データ (bin/lint-rules/style.json) が検査の期待する形か。
// WhyNot: 目視の約束にしないのは、閾値を規約データで直したときに検査が古い判定の
// まま緑を出すため。

// repoRoot はテストから見たリポジトリの根 (go/internal/style の 3 つ上)。
func repoRoot() string { return filepath.Join("..", "..", "..") }

var pyStrLiteral = regexp.MustCompile(`"([^"]*)"`)

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

func TestLoadRulesFromRepo(t *testing.T) {
	rules, err := LoadRules(repoRoot())
	if err != nil {
		t.Fatal(err)
	}
	if !rules.isHandName("smooth") || rules.isHandName("pixel") {
		t.Errorf("--hand の受け付けが規約とずれている: %v", rules.HandNames)
	}
}

func TestLoadRulesMissingFile(t *testing.T) {
	if _, err := LoadRules(t.TempDir()); err == nil {
		t.Fatal("規約ファイルが無いのにエラーにならない")
	}
}

func TestLoadRulesBrokenJSON(t *testing.T) {
	root := t.TempDir()
	writeRules(t, root, "{ これは JSON ではない }")
	if _, err := LoadRules(root); err == nil {
		t.Fatal("壊れた JSON なのにエラーにならない")
	}
}

func TestLoadRulesMissingKey(t *testing.T) {
	root := t.TempDir()
	data, err := os.ReadFile(filepath.Join(repoRoot(), RulesPath))
	if err != nil {
		t.Fatal(err)
	}
	var m map[string]any
	if err := json.Unmarshal(data, &m); err != nil {
		t.Fatal(err)
	}
	delete(m, "ellipseWarn")
	out, err := json.Marshal(m)
	if err != nil {
		t.Fatal(err)
	}
	writeRules(t, root, string(out))
	_, err = LoadRules(root)
	if err == nil || !strings.Contains(err.Error(), "ellipseWarn") {
		t.Fatalf("キー欠けを名指しで止めていない: %v", err)
	}
}

func writeRules(t *testing.T, root, body string) {
	t.Helper()
	dir := filepath.Join(root, "bin", "lint-rules")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "style.json"), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}
