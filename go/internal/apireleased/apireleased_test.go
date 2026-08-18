package apireleased

// What: 作業ツリー側とタグ側の宣言の拾い方、fail-open の 2 経路、語で絞る 3 通り、
// 出す口（stdout / stderr）と終了コード。

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestVersionReadsMakefile(t *testing.T) {
	dir := t.TempDir()
	write(t, dir, "Makefile", "all:\nVERSION := 1.2.3\n")
	v, ok, err := version(dir)
	if err != nil || !ok || v != "1.2.3" {
		t.Errorf("v=%q ok=%v err=%v", v, ok, err)
	}
}

func TestVersionMissingIsNotAnError(t *testing.T) {
	dir := t.TempDir()
	write(t, dir, "Makefile", "all:\n")
	_, ok, err := version(dir)
	if err != nil || ok {
		t.Errorf("ok=%v err=%v", ok, err)
	}
}

func TestPerModuleCollectsDeclarations(t *testing.T) {
	got := perModule("mod Depth {\n    pub def world(): Int32 = 0\n    pub enum Band { case A }\n}\n")
	if len(got) != 1 || got[0].Mod != "Depth" {
		t.Fatalf("got=%v", got)
	}
	if strings.Join(got[0].Names, ",") != "world,Band" {
		t.Errorf("names=%v", got[0].Names)
	}
}

// Python 版は re.split で平らに切るので、内側の mod の後ろに書いた宣言は内側に属する。
func TestPerModuleSplitsFlatOnNestedMod(t *testing.T) {
	got := perModule("mod Outer {\nmod Inner {\n    pub def a(): Unit = ()\n}\n    pub def b(): Unit = ()\n}\n")
	if len(got) != 2 || got[0].Mod != "Outer" || got[1].Mod != "Inner" {
		t.Fatalf("got=%v", got)
	}
	if len(got[0].Names) != 0 {
		t.Errorf("Outer に %v が付いている", got[0].Names)
	}
	if strings.Join(got[1].Names, ",") != "a,b" {
		t.Errorf("Inner の names=%v", got[1].Names)
	}
}

func write(t *testing.T, dir, rel, body string) {
	t.Helper()
	full := filepath.Join(dir, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(full, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

const rulesJSON = `{"packages":["engine","engine_world","engine_tools"]}`

// fakeRepo は使い捨ての git リポを組み、tag が空でなければタグを打つ。
func fakeRepo(t *testing.T, tag string) string {
	t.Helper()
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git が無い環境")
	}
	dir := t.TempDir()
	write(t, dir, "bin/lint-rules/check-api-released.json", rulesJSON)
	write(t, dir, "Makefile", "VERSION := 0.1.0\n")
	write(t, dir, "engine/src/Depth.flix", "mod Depth {\n    pub def world(): Int32 = 0\n}\n")
	write(t, dir, "engine_world/src/Board.flix", "mod Board {\n    pub def make(): Unit = ()\n}\n")
	write(t, dir, "engine_tools/src/Bakery.flix", "mod Bakery {\n    pub def bake(): Unit = ()\n}\n")
	git(t, dir, "init", "-q")
	git(t, dir, "add", "-A")
	git(t, dir, "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false",
		"commit", "-q", "-m", "release")
	if tag != "" {
		git(t, dir, "tag", tag)
	}
	return dir
}

func git(t *testing.T, dir string, args ...string) {
	t.Helper()
	full := append([]string{"-C", dir}, args...)
	if out, err := exec.Command("git", full...).CombinedOutput(); err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
}

func run(t *testing.T, dir string, args ...string) (string, string, int) {
	t.Helper()
	var out, errOut strings.Builder
	code, err := Run(&out, &errOut, dir, args, Options{})
	if err != nil {
		t.Fatalf("検査が動かなかった: %v", err)
	}
	return out.String(), errOut.String(), code
}

func TestRunAllReleasedSaysNothing(t *testing.T) {
	out, errOut, code := run(t, fakeRepo(t, "v0.1.0"))
	if out != "" || errOut != "" || code != 0 {
		t.Errorf("out=%q err=%q code=%d", out, errOut, code)
	}
}

func TestRunListsUnreleasedDeclaration(t *testing.T) {
	dir := fakeRepo(t, "v0.1.0")
	write(t, dir, "engine/src/Depth.flix",
		"mod Depth {\n    pub def world(): Int32 = 0\n    pub def bands(): Int32 = 2\n}\n")
	out, errOut, code := run(t, dir)
	want := "[api] 未リリース（v0.1.0 の fpkg に無い。ゲームから引くとコンパイルで落ちる）:\n  Depth.bands\n"
	if out != want || errOut != "" || code != 0 {
		t.Errorf("out=%q err=%q code=%d", out, errOut, code)
	}
}

func TestRunListsUnreleasedModule(t *testing.T) {
	dir := fakeRepo(t, "v0.1.0")
	write(t, dir, "engine_world/src/Tilemap.flix", "mod Tilemap {\n    pub def toItems(): Unit = ()\n}\n")
	out, _, _ := run(t, dir)
	if !strings.HasSuffix(out, "  Tilemap.toItems\n") {
		t.Errorf("out=%q", out)
	}
}

func TestRunNeedleMatchesDeclaration(t *testing.T) {
	dir := fakeRepo(t, "v0.1.0")
	write(t, dir, "engine/src/Depth.flix",
		"mod Depth {\n    pub def world(): Int32 = 0\n    pub def bands(): Int32 = 2\n}\n")
	out, _, _ := run(t, dir, "bands")
	want := "[api] 注意: 次は未リリース。v0.1.0 の fpkg には無いのでゲームからは引けない:\n  Depth.bands\n"
	if out != want {
		t.Errorf("out=%q", out)
	}
}

func TestRunNeedleMatchesModuleCaseInsensitively(t *testing.T) {
	dir := fakeRepo(t, "v0.1.0")
	write(t, dir, "engine/src/Depth.flix",
		"mod Depth {\n    pub def world(): Int32 = 0\n    pub def bands(): Int32 = 2\n}\n")
	out, _, _ := run(t, dir, "depth")
	if !strings.HasSuffix(out, "  Depth.bands\n") {
		t.Errorf("out=%q", out)
	}
}

func TestRunNeedleMatchesNothing(t *testing.T) {
	dir := fakeRepo(t, "v0.1.0")
	write(t, dir, "engine/src/Depth.flix",
		"mod Depth {\n    pub def world(): Int32 = 0\n    pub def bands(): Int32 = 2\n}\n")
	out, _, code := run(t, dir, "tilemap")
	if out != "" || code != 0 {
		t.Errorf("out=%q code=%d", out, code)
	}
}

func TestRunTagMissingIsFailOpen(t *testing.T) {
	dir := fakeRepo(t, "")
	write(t, dir, "engine/src/Depth.flix",
		"mod Depth {\n    pub def world(): Int32 = 0\n    pub def bands(): Int32 = 2\n}\n")
	out, errOut, code := run(t, dir)
	if out != "" || errOut != "" || code != 0 {
		t.Errorf("out=%q err=%q code=%d", out, errOut, code)
	}
}

func TestRunVersionMissingIsFailOpen(t *testing.T) {
	dir := fakeRepo(t, "v0.1.0")
	write(t, dir, "Makefile", "all:\n")
	write(t, dir, "engine/src/Depth.flix",
		"mod Depth {\n    pub def world(): Int32 = 0\n    pub def bands(): Int32 = 2\n}\n")
	out, _, code := run(t, dir)
	if out != "" || code != 0 {
		t.Errorf("out=%q code=%d", out, code)
	}
}

func TestRunFailsWhenRulesMissing(t *testing.T) {
	var out, errOut strings.Builder
	code, err := Run(&out, &errOut, t.TempDir(), nil, Options{})
	if err == nil || code != 2 {
		t.Errorf("規約が無いのに code=%d err=%v", code, err)
	}
}
