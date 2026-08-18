package f32

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func repoRoot() string { return filepath.Join("..", "..", "..") }

// runOn は 1 ファイルだけを検査して出力と終了コードを返す。
func runOn(t *testing.T, exempt map[string]string, body string) (string, int) {
	t.Helper()
	root := t.TempDir()
	path := filepath.Join(root, "Sample.flix")
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	var out, errOut strings.Builder
	code, err := Run(&out, &errOut, root, []string{path}, Options{Exempt: exempt})
	if err != nil {
		t.Fatal(err)
	}
	if errOut.Len() != 0 {
		t.Fatalf("stderr に %q が出た", errOut.String())
	}
	return out.String(), code
}

const sampleF32 = "mod Demo {\n    pub def setScale(value: Float32): Unit = ()\n}\n"

func TestPubFloat32Fires(t *testing.T) {
	out, code := runOn(t, map[string]string{}, sampleF32)
	if code != 1 {
		t.Fatalf("終了コードが %d", code)
	}
	if !strings.Contains(out, "Sample.flix: Demo.setScale の pub 面に Float32 があります") {
		t.Fatalf("違反の行が出ていない: %q", out)
	}
}

func TestExemptSilencesTheHit(t *testing.T) {
	out, code := runOn(t, map[string]string{"Demo.setScale": "テスト用"}, sampleF32)
	if code != 0 {
		t.Fatalf("除外したのに終了コードが %d (%s)", code, out)
	}
	if !strings.Contains(out, "[lint-f32] OK (pub 面の Float32 1 件 / 除外 1 件)") {
		t.Fatalf("OK の行が %q", out)
	}
}

func TestStaleExemptFires(t *testing.T) {
	out, code := runOn(t, map[string]string{"Ghost.longGoneFn": "テスト用"},
		"mod Demo {\n    pub def quiet(): Unit = ()\n}\n")
	if code != 1 {
		t.Fatalf("終了コードが %d", code)
	}
	if !strings.Contains(out, "Ghost.longGoneFn は EXEMPT に載っていますが") {
		t.Fatalf("古い除外の行が出ていない: %q", out)
	}
}

func TestFloat32InCommentIsIgnored(t *testing.T) {
	out, code := runOn(t, map[string]string{},
		"mod Demo {\n    // Float32 と書いただけ\n    pub def quiet(): Unit = ()\n}\n")
	if code != 0 {
		t.Fatalf("コメントの Float32 で鳴った: %s", out)
	}
}

func TestFloat32AsPartOfLongerWordIsIgnored(t *testing.T) {
	out, code := runOn(t, map[string]string{},
		"mod Demo {\n    pub def keep(v: MyFloat32x): Unit = ()\n}\n")
	if code != 0 {
		t.Fatalf("語の一部の Float32 で鳴った: %s", out)
	}
}

// TestFloat32AfterMultibyteRune は Go の `\b` が ASCII しか語とみなさない罠を縛る。
func TestFloat32AfterMultibyteRune(t *testing.T) {
	if hasFloat32("あFloat32") {
		t.Error("直前が漢字なのに語の区切りと読んだ")
	}
	if !hasFloat32("(Float32)") {
		t.Error("括弧に挟まれた Float32 を拾えない")
	}
}

func TestSelfTest(t *testing.T) {
	var out, errOut strings.Builder
	code, err := Run(&out, &errOut, repoRoot(), []string{"--self-test"}, Options{})
	if err != nil {
		t.Fatal(err)
	}
	if code != 0 {
		t.Fatalf("終了コードが %d (%s)", code, out.String())
	}
	if !strings.HasPrefix(out.String(), "[lint-f32] self-test OK") {
		t.Fatalf("自己検査の出力が %q", out.String())
	}
}

func TestUnknownFlagIsIgnored(t *testing.T) {
	// Python 版は --check を黙って無視して通常の検査を走らせる。
	var out, errOut strings.Builder
	code, err := Run(&out, &errOut, repoRoot(), []string{"--check"}, Options{})
	if err != nil {
		t.Fatal(err)
	}
	if code != 0 {
		t.Fatalf("--check で終了コードが %d (%s)", code, out.String())
	}
}

func TestMissingFileStops(t *testing.T) {
	var out, errOut strings.Builder
	code, err := Run(&out, &errOut, repoRoot(),
		[]string{filepath.Join(t.TempDir(), "無い.flix")}, Options{Exempt: map[string]string{}})
	if err == nil {
		t.Fatal("無いファイルを黙って飛ばした")
	}
	if code != 2 {
		t.Fatalf("終了コードが %d (検査が動かなかったのは 2)", code)
	}
}
