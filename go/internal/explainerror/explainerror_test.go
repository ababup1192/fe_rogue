package explainerror

import (
	"path/filepath"
	"strings"
	"testing"
)

func repoRoot() string { return filepath.Join("..", "..", "..") }

func load(t *testing.T) *Rules {
	t.Helper()
	r, err := LoadRules(repoRoot())
	if err != nil {
		t.Fatal(err)
	}
	return r
}

const twoErrors = `-- Type Error [E5252] ---- src/Foo.flix

>> Unable to unify.

12 |     let x = foo(1i64);

-- Resolution Error [E3138] ---- test/TestBar.flix

>> Undefined name.

40 |   Bar.baz(1)

Compilation failed with 2 error(s).
`

// 成功は 1 行に畳む。
func TestOkIsOneLine(t *testing.T) {
	got := Summarize(load(t), twoErrors, Options{Status: 0, HasStatus: true})
	if got != "[check] OK (警告 2 件)" {
		t.Errorf("got %q", got)
	}
}

// 全文の置き場を渡したら、成功の 1 行にも案内が付く。
func TestOkNotesLogPath(t *testing.T) {
	got := Summarize(load(t), twoErrors, Options{Status: 0, HasStatus: true, LogPath: "check.log"})
	if got != "[check] OK (警告 2 件 — 全文は check.log)" {
		t.Errorf("got %q", got)
	}
}

// 失敗は 1 件目を全文、残りを file:line の一覧に畳む。
func TestFailureShowsFirstBlockAndRest(t *testing.T) {
	got := Summarize(load(t), twoErrors, Options{Status: 1, HasStatus: true, LogPath: "check.log"})
	for _, want := range []string{
		"-- Type Error [E5252] ---- src/Foo.flix",
		"残り 1 件:",
		"  test/TestBar.flix:40 — Resolution Error [E3138]",
		"Compilation failed with 2 error(s).",
		"全文: check.log",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("%q が出ていない:\n%s", want, got)
		}
	}
}

// 処方箋は今表示している 1 件目に対して引く。
func TestPrescriptionComesFromFirstBlock(t *testing.T) {
	got := Summarize(load(t), twoErrors, Options{Status: 1, HasStatus: true})
	if !strings.HasSuffix(got, "処方箋: レコードは Eq/Order を持てない。比較したい値は名前付き 1 フィールド enum で包む (詳細は /compile-fix)") {
		t.Errorf("got %q", got)
	}
}

// 1 件目に当たりが無いときだけ、残りの見出し行へ下がる。
func TestPrescriptionFallsBackToLaterHeads(t *testing.T) {
	text := "-- Weird Error [E0001] ---- src/Odd.flix\n\n7 |  odd\n\n" +
		"-- Type Error [E6217] ---- src/B.flix\n\n9 |  bar\n"
	got := Summarize(load(t), text, Options{Status: 1, HasStatus: true})
	if !strings.Contains(got, "checked_ecast は不要") {
		t.Errorf("got %q", got)
	}
}

// エラーブロックが読めない失敗出力は要約せず素通しする。
func TestUnknownFormatPassesThrough(t *testing.T) {
	text := "resolving dependencies...\nerror: could not download\n"
	got := Summarize(load(t), text, Options{Status: 1, HasStatus: true, LogPath: "check.log"})
	if got != "resolving dependencies...\nerror: could not download" {
		t.Errorf("got %q", got)
	}
}

// --status が無いときは、エラーブロックの有無で失敗を決める。
func TestStatuslessUsesBlocks(t *testing.T) {
	if got := Summarize(load(t), "全部緑\n", Options{}); got != "[check] OK" {
		t.Errorf("got %q", got)
	}
	if got := Summarize(load(t), twoErrors, Options{}); !strings.Contains(got, "残り 1 件:") {
		t.Errorf("got %q", got)
	}
}

// 色付けの制御文字は落としてから照合する。
func TestAnsiIsStripped(t *testing.T) {
	text := "\x1b[31m-- Type Error [E6217] ---- \x1b[0msrc/A.flix\n\n  7 | foo\n"
	got := Summarize(load(t), text, Options{Status: 1, HasStatus: true})
	if strings.Contains(got, "\x1b") {
		t.Errorf("制御文字が残っている: %q", got)
	}
	if !strings.HasPrefix(got, "-- Type Error [E6217] ---- src/A.flix") {
		t.Errorf("got %q", got)
	}
}

// 最初のエラーブロックだけ抜く (フックが使う口)。
func TestFirstErrorBlockStopsAtNextHead(t *testing.T) {
	got := FirstErrorBlock(load(t), twoErrors, 15, 10)
	if strings.Contains(got, "E3138") {
		t.Errorf("2 件目まで拾っている:\n%s", got)
	}
	if !strings.HasPrefix(got, "-- Type Error [E5252]") {
		t.Errorf("got %q", got)
	}
}

// 見出しが 1 つも無ければ末尾だけ返す。
func TestFirstErrorBlockFallsBackToTail(t *testing.T) {
	got := FirstErrorBlock(load(t), "a\nb\nc\nd\n", 15, 2)
	if got != "c\nd" {
		t.Errorf("got %q", got)
	}
}

func TestParseArgs(t *testing.T) {
	o := ParseArgs([]string{"--status", "3", "--log", "x.log"})
	if !o.HasStatus || o.Status != 3 || o.LogPath != "x.log" {
		t.Errorf("got %+v", o)
	}
}

// 数でない --status は「渡っていない」に倒す (パイプの途中で落ちない)。
func TestParseArgsIgnoresBadStatus(t *testing.T) {
	if o := ParseArgs([]string{"--status", "x"}); o.HasStatus {
		t.Errorf("got %+v", o)
	}
}

func TestLoadRulesAbortsWhenMissing(t *testing.T) {
	if _, err := LoadRules(t.TempDir()); err == nil {
		t.Error("規約ファイルが無いのに緑で通った")
	}
}
