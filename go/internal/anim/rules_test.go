package anim

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"
)

// source of truthは bin/lint-rules/anim.json。読み込みがそこからずれていないかを機械で見る。
// WhyNot: 目視の約束にしないのは、閾値を JSON 側だけ直したときにコードが
// 古い判定のまま緑を出すため。

// repoRoot はテストから見たリポジトリの根 (go/internal/anim の 3 つ上)。
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

func sortedJoin(items []string) string {
	c := append([]string(nil), items...)
	sort.Strings(c)
	return strings.Join(c, ",")
}

func TestLoadRulesFromRepo(t *testing.T) {
	rules, err := LoadRules(repoRoot())
	if err != nil {
		t.Fatal(err)
	}
	if !rules.Transparent['.'] || !rules.Transparent[' '] || rules.Transparent['o'] {
		t.Errorf("透明の字の集合がおかしい: %v", rules.Transparent)
	}
	if rules.Directions["west"] != "side_w" {
		t.Errorf("west が %q (期待 side_w)", rules.Directions["west"])
	}
}

func TestLoadRulesFailsWithoutFile(t *testing.T) {
	if _, err := LoadRules(t.TempDir()); err == nil {
		t.Fatal("規約ファイルが無いのにエラーにならなかった")
	}
}
