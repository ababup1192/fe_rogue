package pxlib

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestSplitLinesHandlesCRLF(t *testing.T) {
	got := SplitLines("a\r\nb\rc\nd")
	want := []string{"a", "b", "c", "d"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("SplitLines = %q", got)
	}
}

func TestSplitLinesDropsTrailingEmpty(t *testing.T) {
	if got := SplitLines("a\n"); len(got) != 1 {
		t.Errorf("末尾の改行で空行が増えた: %q", got)
	}
}

func TestPosixPathNormalizes(t *testing.T) {
	cases := map[string]string{
		"./a/b":  "a/b",
		"a//b":   "a/b",
		"a/./b":  "a/b",
		"a/../b": "a/../b",
		"/a/b":   "/a/b",
		"//a/b":  "//a/b",
		"///a/b": "/a/b",
		"":       ".",
		".":      ".",
	}
	for in, want := range cases {
		if got := PosixPath(in); got != want {
			t.Errorf("PosixPath(%q) = %q (期待 %q)", in, got, want)
		}
	}
}

func TestDecodeReplaceMarksBadBytes(t *testing.T) {
	got := DecodeReplace([]byte{'a', 0xff, 'b'})
	if got != "a�b" {
		t.Errorf("DecodeReplace = %q", got)
	}
}

func TestRglobKeepsReaddirOrder(t *testing.T) {
	dir := t.TempDir()
	for _, rel := range []string{"z.flix", "a.flix", "sub/m.flix", "sub/deep/n.flix", "skip.txt"} {
		p := filepath.Join(dir, filepath.FromSlash(rel))
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, nil, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	got := Rglob(dir, ".flix")
	if len(got) != 4 {
		t.Fatalf("拾った数が %d (期待 4): %q", len(got), got)
	}
	// 深さ優先で、同じ階層のファイルはサブディレクトリより先に出る。
	if filepath.Base(got[len(got)-1]) != "n.flix" {
		t.Errorf("並びが深さ優先でない: %q", got)
	}
	for _, p := range got {
		if filepath.Ext(p) != ".flix" {
			t.Errorf(".flix 以外を拾った: %s", p)
		}
	}
}

func TestCompilePyPrefersLongerAlternative(t *testing.T) {
	re, err := CompilePy(`(?:box|boxAt)\b`)
	if err != nil {
		t.Fatal(err)
	}
	if got := re.FindAll("boxAt "); len(got) != 1 || got[0] != "boxAt" {
		t.Errorf("FindAll = %q (期待 [boxAt])", got)
	}
}

func TestCompilePyWordBoundaryIsUnicode(t *testing.T) {
	re, err := CompilePy(`(?:box|boxAt)\b`)
	if err != nil {
		t.Fatal(err)
	}
	// Go の \b は ASCII だけを語とみなすので、この 2 つは素の regexp では鳴ってしまう。
	for _, s := range []string{"boxあ", "boxAtあ"} {
		if got := re.FindAll(s); len(got) != 0 {
			t.Errorf("FindAll(%q) = %q (Python は 0 件)", s, got)
		}
	}
}
