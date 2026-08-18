package view

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"testing"
)

// 正本は bin/lint-view.py。JSON がそこからずれていないかを機械で見る。
// WhyNot: 目視の約束にしないのは、規約を Python 側だけ直したときに Go 版だけが
// 古い判定のまま緑を出すため。

var pyLiteral = regexp.MustCompile(`r?"([^"]*)"`)

func pythonSource(t *testing.T) string {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(repoRoot(), "bin", "lint-view.py"))
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

// pyConcat は `NAME = ...(\n ... )` の中の文字列リテラルをつないで返す。
func pyConcat(t *testing.T, src, name string) string {
	t.Helper()
	head := regexp.MustCompile(`(?m)^` + name + ` = (?:re\.compile)?\(`).FindStringIndex(src)
	if head == nil {
		t.Fatalf("bin/lint-view.py に %s が無い", name)
	}
	tail := strings.Index(src[head[1]:], "\n)")
	if tail < 0 {
		t.Fatalf("bin/lint-view.py の %s の閉じ括弧が見つからない", name)
	}
	var b strings.Builder
	for _, m := range pyLiteral.FindAllStringSubmatch(src[head[1]:head[1]+tail], -1) {
		b.WriteString(m[1])
	}
	return b.String()
}

func pyNumber(t *testing.T, src, name string) int {
	t.Helper()
	m := regexp.MustCompile(`(?m)^` + name + ` = (\d+)$`).FindStringSubmatch(src)
	if m == nil {
		t.Fatalf("bin/lint-view.py に %s が無い", name)
	}
	n, err := strconv.Atoi(m[1])
	if err != nil {
		t.Fatal(err)
	}
	return n
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
	checks := []struct {
		name string
		got  string
		want string
	}{
		{"rectPattern", *f.RectPattern, pyConcat(t, src, "RECT")},
		{"richPattern", *f.RichPattern, pyConcat(t, src, "RICH")},
		{"destinations", *f.Destinations, pyConcat(t, src, "DESTINATIONS")},
	}
	for _, c := range checks {
		if c.got != c.want {
			t.Errorf("%s が bin/lint-view.py とずれている\n JSON:   %s\n Python: %s", c.name, c.got, c.want)
		}
	}
	if *f.MinDraws != pyNumber(t, src, "MIN_DRAWS") {
		t.Errorf("minDraws が bin/lint-view.py とずれている: %d", *f.MinDraws)
	}
	if *f.RectPct != pyNumber(t, src, "RECT_PCT") {
		t.Errorf("rectPct が bin/lint-view.py とずれている: %d", *f.RectPct)
	}
}

func TestLoadRulesFromRepo(t *testing.T) {
	rules, err := LoadRules(repoRoot())
	if err != nil {
		t.Fatal(err)
	}
	if got := len(rules.Rect.FindAll("RawDraw.boxAt(1) Item.Box(2)")); got != 2 {
		t.Errorf("矩形系の数が %d (期待 2)", got)
	}
	if got := rules.Rect.FindAll("RawDraw.boxAt(1)")[0]; got != "RawDraw.boxAt" {
		t.Errorf("boxAt でなく %q を拾った", got)
	}
}
