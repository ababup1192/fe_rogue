package renderbudget

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"testing"
)

// source of truth は bin/check-render-budget.py。JSON がそこからずれていないかを機械で見る。
// WhyNot: 目視の約束にしないのは、閾値を Python 側だけ直したときに Go 版だけが
// 古い上限のまま緑を出すため。

func pythonSource(t *testing.T) string {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(repoRoot(), "bin", "check-render-budget.py"))
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func pyValue(t *testing.T, src, name string) string {
	t.Helper()
	m := regexp.MustCompile(`(?m)^` + name + ` = ([0-9.]+)$`).FindStringSubmatch(src)
	if m == nil {
		t.Fatalf("bin/check-render-budget.py に %s が無い", name)
	}
	return m[1]
}

func TestRulesMatchPython(t *testing.T) {
	src := pythonSource(t)
	data, err := os.ReadFile(filepath.Join(repoRoot(), RulesPath))
	if err != nil {
		t.Fatal(err)
	}
	var f rulesFile
	if err := json.Unmarshal(data, &f); err != nil {
		t.Fatal(err)
	}
	if got, want := strconv.FormatInt(*f.DefaultCap, 10), pyValue(t, src, "DEFAULT_CAP"); got != want {
		t.Errorf("defaultCap が bin/check-render-budget.py とずれている: %s (Python %s)", got, want)
	}
	if got, want := strconv.FormatFloat(*f.DriftFactor, 'g', -1, 64), pyValue(t, src, "DRIFT_FACTOR"); got != want {
		t.Errorf("driftFactor が bin/check-render-budget.py とずれている: %s (Python %s)", got, want)
	}
	if got, want := strconv.FormatInt(*f.DriftFloor, 10), pyValue(t, src, "DRIFT_FLOOR"); got != want {
		t.Errorf("driftFloor が bin/check-render-budget.py とずれている: %s (Python %s)", got, want)
	}
}

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
