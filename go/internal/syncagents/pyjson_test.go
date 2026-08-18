package syncagents

import "testing"

// 期待値は python3 -c 'import json; json.loads(...)' で実際に出た文面。

func TestPyJSONErrorText(t *testing.T) {
	for _, tc := range []struct{ in, want string }{
		{"", "Expecting value: line 1 column 1 (char 0)"},
		{"  ", "Expecting value: line 1 column 3 (char 2)"},
		{"{", "Expecting property name enclosed in double quotes: line 1 column 2 (char 1)"},
		{`{"a"}`, "Expecting ':' delimiter: line 1 column 5 (char 4)"},
		{`{"a":}`, "Expecting value: line 1 column 6 (char 5)"},
		{`{"a":1,}`, "Expecting property name enclosed in double quotes: line 1 column 8 (char 7)"},
		{`{"a":1 "b":2}`, "Expecting ',' delimiter: line 1 column 8 (char 7)"},
		{"{'a':1}", "Expecting property name enclosed in double quotes: line 1 column 2 (char 1)"},
		{"[1,2", "Expecting ',' delimiter: line 1 column 5 (char 4)"},
		{"[1,2,]", "Expecting value: line 1 column 6 (char 5)"},
		{"{} x", "Extra data: line 1 column 4 (char 3)"},
		{"1 2", "Extra data: line 1 column 3 (char 2)"},
		{"01", "Extra data: line 1 column 2 (char 1)"},
		{"1.", "Extra data: line 1 column 2 (char 1)"},
		{"tru", "Expecting value: line 1 column 1 (char 0)"},
		{`"abc`, "Unterminated string starting at: line 1 column 1 (char 0)"},
		{"\"a\tb\"", "Invalid control character at: line 1 column 3 (char 2)"},
		{`"a\qb"`, "Invalid \\escape: line 1 column 3 (char 2)"},
		{`"a\u12"`, "Invalid \\uXXXX escape: line 1 column 4 (char 3)"},
		{`"ab\uzzzz"`, "Invalid \\uXXXX escape: line 1 column 5 (char 4)"},
		{"\n\n{\"a\" 1}", "Expecting ':' delimiter: line 3 column 6 (char 7)"},
		{"[\n 1,\n 2\n", "Expecting ',' delimiter: line 4 column 1 (char 9)"},
		{`{"a":[1,2],}`, "Expecting property name enclosed in double quotes: line 1 column 12 (char 11)"},
		{"-", "Expecting value: line 1 column 1 (char 0)"},
	} {
		_, err := pyJSONLoads(tc.in)
		if err == nil {
			t.Errorf("%q が通ってしまった", tc.in)
			continue
		}
		if err.Error() != tc.want {
			t.Errorf("%q の文面が\n got  %s\n want %s", tc.in, err.Error(), tc.want)
		}
	}
}

// 桁は Python と同じくコードポイントで数える（バイトで数えると日本語で狂う）。
func TestPyJSONColumnCountsRunes(t *testing.T) {
	_, err := pyJSONLoads(`{"あいう":1 "b":2}`)
	if err == nil {
		t.Fatal("通ってしまった")
	}
	if err.Error() != "Expecting ',' delimiter: line 1 column 10 (char 9)" {
		t.Errorf("桁が %s", err.Error())
	}
}

func TestPyJSONValues(t *testing.T) {
	v, err := pyJSONLoads(`{"a":1,"a":2,"b":[true,null,1.5,"x"]}`)
	if err != nil {
		t.Fatal(err)
	}
	d, ok := v.(*pyDict)
	if !ok {
		t.Fatalf("dict にならない: %T", v)
	}
	// 後から入れた値が勝ち、並びは最初に入れた所のまま（repr がその順で出る）。
	if got := pyRepr(d); got != `{'a': 2, 'b': [True, None, 1.5, 'x']}` {
		t.Errorf("repr が %s", got)
	}
}

func TestPyReprQuoting(t *testing.T) {
	for _, tc := range []struct{ in, want string }{
		{"it's", `"it's"`},
		{`say "hi"`, `'say "hi"'`},
		{"both ' and \"", `'both \' and "'`},
		{"tab\there", `'tab\there'`},
		{"日本語", `'日本語'`},
	} {
		if got := pyReprString(tc.in); got != tc.want {
			t.Errorf("repr(%q) が %s (期待 %s)", tc.in, got, tc.want)
		}
	}
}

func TestPyFloatRepr(t *testing.T) {
	for _, tc := range []struct {
		in   float64
		want string
	}{
		{1.5, "1.5"},
		{100, "100.0"},
		{1e16, "1e+16"},
		{1e15, "1000000000000000.0"},
		{0.0001, "0.0001"},
		{0.00001, "1e-05"},
		{-0.5, "-0.5"},
	} {
		if got := pyFloatRepr(tc.in); got != tc.want {
			t.Errorf("repr(%v) が %s (期待 %s)", tc.in, got, tc.want)
		}
	}
}

func TestPyStrKeepsStringBare(t *testing.T) {
	if got := pyStr("bin/fge"); got != "bin/fge" {
		t.Errorf("str が %s", got)
	}
	if got := pyStr(pyInt("12")); got != "12" {
		t.Errorf("str が %s", got)
	}
}
