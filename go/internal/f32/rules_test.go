package f32

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

// source of truthは bin/lint-rules/f32.json の EXEMPT。読み込みがそこからずれていないかを機械で見る。
// WhyNot: 目視の約束にしないのは、除外を JSON 側だけ直したときにコードが
// 古い判定のまま緑を出すため。

func TestLoadRulesWithoutFile(t *testing.T) {
	if _, err := LoadRules(t.TempDir()); err == nil {
		t.Fatal("規約ファイルが無いのにエラーが返らない")
	}
}

func TestLoadRulesWithoutExemptKey(t *testing.T) {
	root := t.TempDir()
	writeRules(t, root, `{"exempts": {}}`)
	if _, err := LoadRules(root); err == nil {
		t.Fatal("exempt が無いのにエラーが返らない")
	}
}

func TestLoadRulesWithBrokenJSON(t *testing.T) {
	root := t.TempDir()
	writeRules(t, root, `{"exempt": `)
	if _, err := LoadRules(root); err == nil {
		t.Fatal("壊れた JSON でエラーが返らない")
	}
}

func TestLoadRulesWithoutReason(t *testing.T) {
	root := t.TempDir()
	writeRules(t, root, `{"exempt": {"A.b": ""}}`)
	if _, err := LoadRules(root); err == nil {
		t.Fatal("理由が空なのにエラーが返らない")
	}
}

func TestRepoRulesAreValidJSON(t *testing.T) {
	data, err := os.ReadFile(filepath.Join(repoRoot(), RulesPath))
	if err != nil {
		t.Fatal(err)
	}
	var any map[string]any
	if err := json.Unmarshal(data, &any); err != nil {
		t.Fatal(err)
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
