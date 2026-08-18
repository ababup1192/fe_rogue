package view

import (
	"regexp"
	"testing"
)

// source of truthは bin/lint-view.py。JSON がそこからずれていないかを機械で見る。
// WhyNot: 目視の約束にしないのは、規約を Python 側だけ直したときに Go 版だけが
// 古い判定のまま緑を出すため。

var pyLiteral = regexp.MustCompile(`r?"([^"]*)"`)

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
