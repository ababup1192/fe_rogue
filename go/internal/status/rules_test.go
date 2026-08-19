package status

// 規約データ (JSON) と実装が同じ節を持つかを見る。片方だけ直すとここで落ちる。

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func repoRoot(t *testing.T) string {
	t.Helper()
	root, err := filepath.Abs(filepath.Join("..", "..", ".."))
	if err != nil {
		t.Fatalf("リポジトリのルートが分かりません: %v", err)
	}
	return root
}

func TestSectionNamesAreAllKnown(t *testing.T) {
	rules, err := LoadRules(repoRoot(t))
	if err != nil {
		t.Fatalf("規約データを読めません: %v", err)
	}
	if len(rules.Sections) != len(sectionsByName) {
		t.Fatalf("節の数が合いません: 規約 %d / 実装 %d", len(rules.Sections), len(sectionsByName))
	}
	for _, name := range rules.Sections {
		if _, ok := sectionsByName[name]; !ok {
			t.Errorf("実装に無い節が規約データにあります: %s", name)
		}
	}
}

func TestLoadRulesMissingFile(t *testing.T) {
	if _, err := LoadRules(t.TempDir()); err == nil {
		t.Fatal("規約ファイルが無いのにエラーになりません")
	}
}

func TestLoadRulesBrokenJSON(t *testing.T) {
	root := t.TempDir()
	writeRule(t, root, "{ こわれている")
	if _, err := LoadRules(root); err == nil {
		t.Fatal("JSON が壊れているのにエラーになりません")
	}
}

func TestLoadRulesMissingKey(t *testing.T) {
	root := repoRoot(t)
	data, err := os.ReadFile(filepath.Join(root, RulesPath))
	if err != nil {
		t.Fatalf("規約ファイルを読めません: %v", err)
	}
	var full map[string]any
	if err := json.Unmarshal(data, &full); err != nil {
		t.Fatalf("規約ファイルが JSON ではありません: %v", err)
	}
	for key := range full {
		if key == "note" {
			continue
		}
		short := map[string]any{}
		for k, v := range full {
			if k != key {
				short[k] = v
			}
		}
		body, err := json.Marshal(short)
		if err != nil {
			t.Fatalf("組み直せません: %v", err)
		}
		tmp := t.TempDir()
		writeRule(t, tmp, string(body))
		if _, err := LoadRules(tmp); err == nil {
			t.Errorf("%s が無いのにエラーになりません", key)
		}
	}
}

func writeRule(t *testing.T, root, body string) {
	t.Helper()
	dir := filepath.Join(root, filepath.Dir(RulesPath))
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatalf("置き場を作れません: %v", err)
	}
	if err := os.WriteFile(filepath.Join(root, RulesPath), []byte(body), 0o644); err != nil {
		t.Fatalf("規約ファイルを書けません: %v", err)
	}
}
