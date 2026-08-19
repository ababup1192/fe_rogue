package stageengine

import (
	"os"
	"path/filepath"
	"testing"
)

// 入れ子の JSON からサブコマンド名を拾えること。
func TestDeclaredSubsCollectsNestedNames(t *testing.T) {
	dir := t.TempDir()
	write := func(name, body string) {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	write("precommit.json", `{"sub":"images","checks":[{"sub":"flix-reserved"},{"sub":"view"}]}`)
	write("hooks.json", `{"hooks":{"art":{"lints":[{"sub":"palette"}]}}}`)
	write("note.txt", "拾わない")

	got, err := declaredSubs(dir)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"flix-reserved", "images", "palette", "view"}
	if len(got) != len(want) {
		t.Fatalf("拾った数が違う: %v", got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("%d 番目が違う: %v", i, got)
		}
	}
}

// 検査データの場所が無いときは、黙って 0 個にせず理由を返すこと。
func TestDeclaredSubsFailsWhenRulesMissing(t *testing.T) {
	if _, err := declaredSubs(filepath.Join(t.TempDir(), "居ない")); err == nil {
		t.Fatal("場所が無いのにエラーにならない")
	}
}
