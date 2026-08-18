package sprite

// 規約データの読み込みが「黙って既定値へ倒れない」ことと、
// source of truthである規約ファイル (JSON) の値がそのまま効くことを縛る。

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func repoRoot(t *testing.T) string {
	t.Helper()
	root, err := filepath.Abs(filepath.Join("..", "..", ".."))
	if err != nil {
		t.Fatalf("リポジトリの根を求められない: %v", err)
	}
	return root
}

func TestLoadRulesMissingFile(t *testing.T) {
	_, err := LoadRules(t.TempDir())
	if err == nil {
		t.Fatal("規約ファイルが無いのにエラーにならない (既定値へ倒れている)")
	}
}

func TestLoadRulesMissingKey(t *testing.T) {
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, "bin", "lint-rules"), 0o755); err != nil {
		t.Fatal(err)
	}
	body := `{"rules":["structure"],"transparentChars":["."],"excludedDirs":["build"],"maxColors":12}`
	if err := os.WriteFile(filepath.Join(root, RulesPath), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	_, err := LoadRules(root)
	if err == nil {
		t.Fatal("キーが欠けているのにエラーにならない")
	}
	if !strings.Contains(err.Error(), "maxColorsBig") {
		t.Fatalf("欠けているキーの名前が出ない: %v", err)
	}
}

func TestLoadRulesBrokenJSON(t *testing.T) {
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, "bin", "lint-rules"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, RulesPath), []byte("{"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadRules(root); err == nil {
		t.Fatal("壊れた JSON なのにエラーにならない")
	}
}

// TestExemptPatternIsUnicodeAware は全角空白を挟んでも除外記法を読めるかを見る。
func TestExemptPatternIsUnicodeAware(t *testing.T) {
	rules, err := LoadRules(repoRoot(t))
	if err != nil {
		t.Fatalf("規約を読めない: %v", err)
	}
	got, ok := rules.exemptOf("対象外　(orphan)　全角空白を挟んだ書き方")
	if !ok {
		t.Fatal("全角空白を挟むと除外記法を読めない")
	}
	if !got.rules["orphan"] || len(got.rules) != 1 {
		t.Fatalf("規則の絞り込みが効いていない: %v", got.rules)
	}
	if got.reason != "全角空白を挟んだ書き方" {
		t.Fatalf("理由の切り出しがずれている: %q", got.reason)
	}
}
