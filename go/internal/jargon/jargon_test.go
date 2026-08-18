package jargon

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func repoRules(t *testing.T) []*Rule {
	t.Helper()
	rules, err := LoadRules(repoRoot())
	if err != nil {
		t.Fatal(err)
	}
	return rules
}

// found は 1 行を検査して、当たった語を並べて返す。
func found(t *testing.T, kind, line string, wholeFile bool) []string {
	t.Helper()
	var words []string
	for _, h := range check("x", kind, strings.Split(line, "\n"), repoRules(t), wholeFile) {
		words = append(words, h.rule.Word)
	}
	return words
}

func TestKindOf(t *testing.T) {
	cases := map[string]string{
		"a/b/README.md":     "md",
		"src/View.flix":     "flix",
		"src/Main.elm":      "elm",
		"a.sprite.json":     "json",
		"bin/x.py":          "py",
		"Makefile":          "make",
		"mk/game.mk":        "make",
		`win\path\Makefile`: "make",
		"bin/fge":           "",
		"a/Makefile.bak":    "",
	}
	for in, want := range cases {
		if got := kindOf(in); got != want {
			t.Errorf("kindOf(%q) = %q (期待 %q)", in, got, want)
		}
	}
}

// 最大の誤検知源はゲームのセリフ。文字列リテラルは見ない。
func TestStringLiteralIsNotProse(t *testing.T) {
	if got := found(t, "flix", `let msg = "関所を通っておくれ"`, true); len(got) != 0 {
		t.Errorf("文字列リテラルで鳴った: %v", got)
	}
	if got := found(t, "flix", "// 関所で止める", true); len(got) != 1 || got[0] != "関所" {
		t.Errorf("コメントで鳴らなかった: %v", got)
	}
}

func TestEscapeSkipsTheLine(t *testing.T) {
	if got := found(t, "flix", "// 関所で止める  jargon-ok: 説明のため", true); len(got) != 0 {
		t.Errorf("逃げ道の印が効いていない: %v", got)
	}
	if got := found(t, "flix", "// 関所で止める  jargon-ok： 全角のコロン", true); len(got) != 0 {
		t.Errorf("全角のコロンで効かなかった: %v", got)
	}
}

// --all はファイル全体を読んでコードブロックを飛ばす。差分の + 行では追えないので見る。
func TestMdFenceOnlyWhenWholeFile(t *testing.T) {
	src := "```\n関所\n```"
	if got := found(t, "md", src, true); len(got) != 0 {
		t.Errorf("コードブロックの中で鳴った: %v", got)
	}
	if got := found(t, "md", "関所", false); len(got) != 1 {
		t.Errorf("差分の + 行で鳴らなかった: %v", got)
	}
	if got := found(t, "md", "`関所` は使わない", true); len(got) != 0 {
		t.Errorf("行内のコードで鳴った: %v", got)
	}
}

// Python の docstring と Elm のブロックコメントも --all のときだけ追う。
func TestBlockCommentsOnlyWhenWholeFile(t *testing.T) {
	py := "\"\"\"説明\n関所のこと\n\"\"\"\nx = 1"
	if got := found(t, "py", py, true); len(got) != 1 {
		t.Errorf("docstring を読めていない: %v", got)
	}
	if got := found(t, "py", "関所のこと", false); len(got) != 0 {
		t.Errorf("差分の + 行で docstring を追ってしまった: %v", got)
	}
	elm := "{- 説明\n関所のこと\n-}"
	if got := found(t, "elm", elm, true); len(got) != 1 {
		t.Errorf("ブロックコメントを読めていない: %v", got)
	}
	if got := found(t, "elm", "-- 関所のこと", false); len(got) != 1 {
		t.Errorf("行コメントで鳴らなかった: %v", got)
	}
}

func TestMakeEchoIsProse(t *testing.T) {
	if got := found(t, "make", "\t@echo \"  make x   関所の検査\"", true); len(got) != 1 {
		t.Errorf("@echo の文言で鳴らなかった: %v", got)
	}
	if got := found(t, "make", "\tgit commit -m \"関所\"", true); len(got) != 0 {
		t.Errorf("echo でない行で鳴った: %v", got)
	}
}

// JSON は説明のキーだけを見る。並びは読んだ順のまま。
func TestJSONWalkKeepsOrder(t *testing.T) {
	body := `{"note": "関所A", "text": "関所B", "child": {"help": "関所C"},
	          "list": [{"label": "関所D"}]}`
	hits, ok := checkJSONFile("a.json", body, repoRules(t))
	if !ok {
		t.Fatal("JSON を読めなかった")
	}
	var got []string
	for _, h := range hits {
		got = append(got, h.excerpt)
	}
	want := []string{"関所A", "関所C", "関所D"}
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Errorf("拾った値が %v (期待 %v)", got, want)
	}
	for _, h := range hits {
		if h.lineno != 0 {
			t.Errorf("構造で歩いたのに行番号が付いている: %d", h.lineno)
		}
	}
}

func TestBrokenJSONFallsBackToLines(t *testing.T) {
	if _, ok := checkJSONFile("a.json", `{"note": "関所",`, repoRules(t)); ok {
		t.Error("壊れた JSON を読めたことにしてしまった")
	}
	// 行ごとの検査でも説明キーだけを見る。
	if got := found(t, "json", `{"note": "関所で止める", "text": "関所を通っておくれ"}`, true); len(got) != 1 {
		t.Errorf("行ごとの JSON 検査が %v", got)
	}
}

// 抜き書きは 70 文字で切る。バイト数で切ると日本語が途中で割れる。
func TestExcerptIsCountedInRunes(t *testing.T) {
	long := "  " + strings.Repeat("あ", 100) + "  "
	got := excerptOf(long)
	if n := len([]rune(got)); n != 70 {
		t.Errorf("抜き書きが %d 文字 (期待 70)", n)
	}
}

func TestWarnSummaryKeepsFirstSeenOnTies(t *testing.T) {
	rules := repoRules(t)
	byWord := map[string]*Rule{}
	for _, r := range rules {
		byWord[r.Word] = r
	}
	warns := []hit{
		{rule: byWord["帯"]}, {rule: byWord["段"]}, {rule: byWord["帯"]}, {rule: byWord["段"]},
	}
	if got := warnSummary(warns); got != "帯×2 / 段×2" {
		t.Errorf("まとめが %q", got)
	}
}

func TestWarnSummaryShowsTopEight(t *testing.T) {
	rules := repoRules(t)
	var warns []hit
	shown := 0
	for _, r := range rules {
		if r.Stage != "warn" {
			continue
		}
		shown++
		warns = append(warns, hit{rule: r})
	}
	if shown < 9 {
		t.Fatalf("注意の語が %d 個しかない", shown)
	}
	if n := strings.Count(warnSummary(warns), " / "); n != 7 {
		t.Errorf("まとめに 8 語より多い/少ない (区切りが %d 個)", n)
	}
}

// ステージした差分は + 行だけを見る。行番号は @@ から数える。
func TestDiffHits(t *testing.T) {
	diff := strings.Join([]string{
		"diff --git a/docs/x.md b/docs/x.md",
		"--- a/docs/x.md",
		"+++ b/docs/x.md",
		"@@ -0,0 +12,3 @@",
		"+```",
		"+関所で止める",
		"+```",
		"-関所を消した行",
		"diff --git a/bin/lint-jargon.py b/bin/lint-jargon.py",
		"+++ b/bin/lint-jargon.py",
		"@@ -1,0 +2 @@",
		"+# 関所を通す",
		"+++ b/assets/a.png",
		"@@ -1,0 +2 @@",
		"+関所",
	}, "\n")
	hits := diffHits(diff, repoRules(t))
	if len(hits) != 1 {
		t.Fatalf("当たりが %d 件 (期待 1): %+v", len(hits), hits)
	}
	if hits[0].path != "docs/x.md" || hits[0].lineno != 13 || hits[0].rule.Word != "関所" {
		t.Errorf("当たりが %s:%d 「%s」", hits[0].path, hits[0].lineno, hits[0].rule.Word)
	}
}

// 負の見本 1 ケースを端から端まで通す。
func TestRunMatchesFixture(t *testing.T) {
	for _, name := range []string{"utsuwa-fires", "utsuwa-no-fire", "haku-fires", "orosu-no-fire"} {
		dir := filepath.Join("testdata", "lint", "jargon", name)
		expected, err := os.ReadFile(filepath.Join(repoRoot(), dir, "expected.txt"))
		if err != nil {
			t.Fatal(err)
		}
		cmd, err := os.ReadFile(filepath.Join(repoRoot(), dir, "cmd.txt"))
		if err != nil {
			t.Fatal(err)
		}
		var args []string
		if strings.Contains(string(cmd), "--show-warn") {
			args = append(args, "--show-warn")
		}
		args = append(args, filepath.ToSlash(filepath.Join(dir, "Sample.flix")))
		var out, errOut strings.Builder
		code, err := Run(&out, &errOut, repoRoot(), args)
		if err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		body := string(expected)
		body = strings.ReplaceAll(body, "[exit=0]\n", "")
		body = strings.ReplaceAll(body, "[exit=1]\n", "")
		if out.String() != body {
			t.Errorf("%s の出力が違う:\n--- got\n%s--- want\n%s", name, out.String(), body)
		}
		wantCode := 0
		if strings.Contains(string(expected), "[exit=1]") {
			wantCode = 1
		}
		if code != wantCode {
			t.Errorf("%s の終了コードが %d (期待 %d)", name, code, wantCode)
		}
	}
}
