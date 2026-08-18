package uioverflow

import (
	"math"
	"testing"
)

// 期待値は python3 の json モジュールに同じ入力を食わせて写した物。
// WhyNot: encoding/json のエラーで代用しないのは、読めない JSON のとき Python 版が
// 例外の文面をそのまま出力へ流すため。位置は文字数え (バイト数えではない)。
func TestPyJSONErrorsMatchPython(t *testing.T) {
	cases := map[string]string{
		"":                "Expecting value: line 1 column 1 (char 0)",
		"   ":             "Expecting value: line 1 column 4 (char 3)",
		"{":               "Expecting property name enclosed in double quotes: line 1 column 2 (char 1)",
		"[":               "Expecting value: line 1 column 2 (char 1)",
		"nul":             "Expecting value: line 1 column 1 (char 0)",
		`{"a"}`:           "Expecting ':' delimiter: line 1 column 5 (char 4)",
		`{"a" 1}`:         "Expecting ':' delimiter: line 1 column 6 (char 5)",
		`{"a":}`:          "Expecting value: line 1 column 6 (char 5)",
		`{"a":1,}`:        "Expecting property name enclosed in double quotes: line 1 column 8 (char 7)",
		`{"a":1 "b":2}`:   "Expecting ',' delimiter: line 1 column 8 (char 7)",
		`{a:1}`:           "Expecting property name enclosed in double quotes: line 1 column 2 (char 1)",
		`{"a":"b"`:        "Expecting ',' delimiter: line 1 column 9 (char 8)",
		"[1,]":            "Expecting value: line 1 column 4 (char 3)",
		"[1,2,]":          "Expecting value: line 1 column 6 (char 5)",
		"[1 2]":           "Expecting ',' delimiter: line 1 column 4 (char 3)",
		"[[[":             "Expecting value: line 1 column 4 (char 3)",
		"{}x":             "Extra data: line 1 column 3 (char 2)",
		`{"a":1}}`:        "Extra data: line 1 column 8 (char 7)",
		"01":              "Extra data: line 1 column 2 (char 1)",
		"1.":              "Extra data: line 1 column 2 (char 1)",
		"-":               "Expecting value: line 1 column 1 (char 0)",
		`"abc`:            "Unterminated string starting at: line 1 column 1 (char 0)",
		`"\"`:             "Unterminated string starting at: line 1 column 1 (char 0)",
		"\"a\tb\"":        "Invalid control character at: line 1 column 3 (char 2)",
		`"a\qb"`:          `Invalid \escape: line 1 column 3 (char 2)`,
		`"a\u12"`:         `Invalid \uXXXX escape: line 1 column 4 (char 3)`,
		`"\uZZZZ"`:        `Invalid \uXXXX escape: line 1 column 3 (char 2)`,
		`"\u"`:            `Invalid \uXXXX escape: line 1 column 3 (char 2)`,
		"{\"a\":1}\n\n{}": "Extra data: line 3 column 1 (char 9)",
		`{"あ":"い"}x`:      "Extra data: line 1 column 10 (char 9)",
		`["あ", 1`:         "Expecting ',' delimiter: line 1 column 8 (char 7)",
	}
	for src, want := range cases {
		_, err := LoadsPyJSON(src)
		if err == nil {
			t.Errorf("%q が読めてしまった (期待 %q)", src, want)
			continue
		}
		if err.Error() != want {
			t.Errorf("%q のエラーが違う\n Go:     %s\n Python: %s", src, err, want)
		}
	}
}

func TestPyJSONValues(t *testing.T) {
	obj, err := LoadsPyJSON(`{"a": 1, "b": [true, false, null], "c": "é😀", "d": 1e999, "e": -0.5}`)
	if err != nil {
		t.Fatal(err)
	}
	m := obj.(map[string]any)
	if m["a"] != float64(1) {
		t.Errorf("a = %v", m["a"])
	}
	if arr := m["b"].([]any); len(arr) != 3 || arr[0] != true || arr[1] != false || arr[2] != nil {
		t.Errorf("b = %v", m["b"])
	}
	if m["c"] != "é😀" {
		t.Errorf("c = %q", m["c"])
	}
	if !math.IsInf(m["d"].(float64), 1) {
		t.Errorf("d = %v (Python の float() は桁あふれで inf)", m["d"])
	}
	if m["e"] != -0.5 {
		t.Errorf("e = %v", m["e"])
	}
	if v, err := LoadsPyJSON("NaN"); err != nil || !math.IsNaN(v.(float64)) {
		t.Errorf("NaN = %v %v", v, err)
	}
	if v, err := LoadsPyJSON(`{"a":1,"a":2}`); err != nil || v.(map[string]any)["a"] != float64(2) {
		t.Errorf("同じ鍵は後勝ちのはず: %v %v", v, err)
	}
}

func TestPyG(t *testing.T) {
	cases := map[float64]string{
		120: "120", 0: "0", 120.5: "120.5", 1234567: "1.23457e+06",
		0.0001: "0.0001", 0.00001: "1e-05", -8: "-8", 1e16: "1e+16",
	}
	for in, want := range cases {
		if got := pyG(in); got != want {
			t.Errorf("pyG(%v) = %q (Python は %q)", in, got, want)
		}
	}
}

func TestPyRepr(t *testing.T) {
	cases := map[string]string{
		"a.ui.json": `'a.ui.json'`,
		"it's":      `"it's"`,
		`a"b`:       `'a"b'`,
		"日本語":       `'日本語'`,
		"a\nb":      `'a\nb'`,
	}
	for in, want := range cases {
		if got := pyRepr(in); got != want {
			t.Errorf("pyRepr(%q) = %s (Python は %s)", in, got, want)
		}
	}
}
