package flixreserved

// 何を守るか: 識別子の置き場 4 か所で予約語を見つけること、
// 連結・比較・矢印・コメント・文字列では鳴らないこと。

import (
	"strings"
	"testing"
)

func testRules() *Rules {
	return &Rules{
		ScopeSuffixes: []string{".flix"},
		SkipPrefixes:  []string{"build/", "testdata/"},
		Words:         map[string]string{"from": "→ start", "into": "→ dest", "run": "→ launch"},
	}
}

func words(hits []Hit) string {
	var out []string
	for _, h := range hits {
		out = append(out, h.Word+"/"+h.Kind)
	}
	return strings.Join(out, " ")
}

// 識別子の置き場 4 か所。
func TestFindsReservedWordsInEveryNamePosition(t *testing.T) {
	for _, tc := range []struct{ code, want string }{
		{"    let into = versionsDir(home);", "into/let の名前"},
		{"    pub def run(x: Int32): Int32 = x", "run/def の名前"},
		{"    pub def f(r: {tool = String, from = String}): String = r#tool", "from/レコードの項目名"},
		{"    def g(from: String): String = from", "from/引数の名前"},
	} {
		got := words(testRules().textHits("a.flix", tc.code))
		if got != tc.want {
			t.Fatalf("%q: %q を期待 %q", tc.code, got, tc.want)
		}
	}
}

// 名前の置き場に見えるだけの形では鳴らない。
func TestQuietOnLookAlikes(t *testing.T) {
	for _, code := range []string{
		"        case from :: rest => rest",           // 連結
		"        if (from == other) 1 else 2",         // 比較
		"            case Some(from) => from",         // match の矢印
		"    // from を into へ渡す",                      // コメント
		`    let args = "--from" :: "--into" :: Nil;`, // 文字列の中
		"    let fromDir = x;",                        // 予約語で始まるだけの名前
	} {
		if hits := testRules().textHits("a.flix", code); len(hits) != 0 {
			t.Fatalf("%q で鳴った: %s", code, words(hits))
		}
	}
}

// 名指しで渡したファイルは、除外の置き場にあっても見る (見本を鳴らせるように)。
func TestNamedPathIgnoresSkipPrefixes(t *testing.T) {
	r := testRules()
	if !r.IsFlix("testdata/lint/x/sample.flix") {
		t.Fatal("名指しの見本を飛ばした")
	}
	if r.InScope("testdata/lint/x/sample.flix") {
		t.Fatal("全量で見本を拾った")
	}
}

// 拡張子が違う物は読まない。
func TestOnlyFlixFiles(t *testing.T) {
	if testRules().IsFlix("a.elm") {
		t.Fatal(".elm を読もうとした")
	}
}
