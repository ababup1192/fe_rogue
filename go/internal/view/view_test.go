package view

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/ababup1192/flix_game_engine/go/internal/pxlib"
)

// repoRoot はテストから見たリポジトリの根 (go/internal/view の 3 つ上)。
func repoRoot() string { return filepath.Join("..", "..", "..") }

// fixture は 1 ケース分の入れ子を作り、その根を返す。
func fixture(t *testing.T, files map[string]string) string {
	t.Helper()
	root := t.TempDir()
	rules, err := os.ReadFile(filepath.Join(repoRoot(), RulesPath))
	if err != nil {
		t.Fatal(err)
	}
	files[RulesPath] = string(rules)
	for rel, body := range files {
		path := filepath.Join(root, filepath.FromSlash(rel))
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

func run(t *testing.T, root string, args ...string) (string, string, int) {
	t.Helper()
	var out, errOut strings.Builder
	code, err := Run(&out, &errOut, root, args)
	if err != nil {
		t.Fatalf("Run が失敗した: %v", err)
	}
	return out.String(), errOut.String(), code
}

const rectOnly = `mod View {
    pub def draw(): Unit =
        RawDraw.box(1) ; RawDraw.boxAt(2) ; RawDraw.circle(3) ;
        Render.circleAt(4) ; Item.Box(5) ; RawDraw.orBoxAt(6) ; Render.star(7)
}
`

func TestRectOnlyViewFails(t *testing.T) {
	root := fixture(t, map[string]string{"templates/a/src/View.flix": rectOnly})
	out, errOut, code := run(t, root)
	if code != 1 {
		t.Fatalf("終了コードが %d (期待 1)\nstdout=%q\nstderr=%q", code, out, errOut)
	}
	want := "templates/a/src/View.flix: 描画がほぼ矩形と円だけです（矩形系 6 / 全体 7）—" +
		" Box が 1 回、box が 1 回、boxAt が 1 回、circle が 1 回、circleAt が 1 回、orBoxAt が 1 回。"
	if !strings.Contains(errOut, want) {
		t.Errorf("stderr に指摘が無い:\n%s", errOut)
	}
	if !strings.HasPrefix(out, "OK:") && out != "" {
		t.Errorf("stdout に余計な行がある: %q", out)
	}
}

func TestRichViewPasses(t *testing.T) {
	src := `mod View {
    pub def draw(): Unit =
        RawDraw.box(1) ; Render.vgrad(2) ; PxSprite.draw(3) ;
        Material.of(4) ; Render.glowAt(5)
}
`
	root := fixture(t, map[string]string{"templates/a/src/View.flix": src})
	out, _, code := run(t, root)
	if code != 0 {
		t.Fatalf("終了コードが %d (期待 0)", code)
	}
	if out != "OK: 矩形だけの View はありません（除外 0 件）\n" {
		t.Errorf("stdout が違う: %q", out)
	}
}

func TestFewDrawsIsNotJudged(t *testing.T) {
	src := "mod View { pub def draw(): Unit = RawDraw.box(1) ; RawDraw.box(2) }\n"
	root := fixture(t, map[string]string{"templates/a/src/View.flix": src})
	_, _, code := run(t, root)
	if code != 0 {
		t.Errorf("部品 2 個で判定してしまった (終了コード %d)", code)
	}
}

func TestCommentLinesAreNotCounted(t *testing.T) {
	src := "// Render.vgrad Render.star PxSprite Material Scatter FxDoc Anim\n" + rectOnly
	root := fixture(t, map[string]string{"templates/a/src/View.flix": src})
	_, errOut, code := run(t, root)
	if code != 1 {
		t.Fatalf("コメントに部品名を並べただけで合格した (終了コード %d)", code)
	}
	if !strings.Contains(errOut, "全体 7") {
		t.Errorf("コメント行を数えている:\n%s", errOut)
	}
}

func TestExemptCommentSkips(t *testing.T) {
	src := "// lint-view: 対象外 — 下請けだけを持つ\n" + rectOnly
	root := fixture(t, map[string]string{"templates/a/src/View.flix": src})
	out, _, code := run(t, root)
	if code != 0 {
		t.Fatalf("除外が効いていない (終了コード %d)", code)
	}
	want := "除外: " + pxlib.PosixPath(root) + "/templates/a/src/View.flix — 下請けだけを持つ\n" +
		"OK: 矩形だけの View はありません（除外 1 件）\n"
	if out != want {
		t.Errorf("stdout が違う:\n%s", out)
	}
}

func TestExemptWithoutReason(t *testing.T) {
	src := "// lint-view: 対象外\n" + rectOnly
	root := fixture(t, map[string]string{"templates/a/src/View.flix": src})
	out, _, _ := run(t, root)
	if !strings.Contains(out, "— （理由が書かれていません）") {
		t.Errorf("理由なしの印が出ていない:\n%s", out)
	}
}

func TestHudSmellWarns(t *testing.T) {
	root := fixture(t, map[string]string{
		"templates/a/src/View.flix":             "mod View { pub def draw(): Unit = Render.text(\"score\") }\n",
		"templates/a/src/render/GifRender.flix": "mod G { pub def go(): Unit = Render.text(\"x\") }\n",
	})
	out, _, code := run(t, root)
	if code != 0 {
		t.Fatalf("匂いは警告だけのはずが終了コード %d", code)
	}
	if !strings.Contains(out, "警告: "+pxlib.PosixPath(root)+"/templates/a — 文字（Render.text / TextDraw）") {
		t.Errorf("HUD の匂いが鳴っていない:\n%s", out)
	}
	if !strings.Contains(out, "（警告のみ・失敗にはしません）") {
		t.Errorf("警告の末尾が違う:\n%s", out)
	}
}

func TestHudSmellQuietWithHudView(t *testing.T) {
	root := fixture(t, map[string]string{
		"templates/a/src/View.flix": "mod View { pub def draw(): Unit = Render.text(\"score\") }\n",
		"templates/a/src/Hud.flix":  "mod Hud { pub def f(): Unit = App.withHudView(x) }\n",
	})
	out, _, _ := run(t, root)
	if strings.Contains(out, "警告:") {
		t.Errorf("withHudView があるのに鳴った:\n%s", out)
	}
}

func TestHudSmellIgnoresRenderDir(t *testing.T) {
	root := fixture(t, map[string]string{
		"templates/a/src/render/GifRender.flix": "mod G { pub def go(): Unit = Render.text(\"x\") }\n",
		"templates/a/src/World.flix":            "mod W { pub def f(): Unit = () }\n",
	})
	out, _, _ := run(t, root)
	if strings.Contains(out, "警告:") {
		t.Errorf("render/ の文字で鳴った:\n%s", out)
	}
}

func TestHudSmellOncePerProject(t *testing.T) {
	root := fixture(t, map[string]string{
		"templates/a/src/View.flix":  "mod View { pub def draw(): Unit = Render.text(\"a\") }\n",
		"templates/a/src/Other.flix": "mod Other { pub def draw(): Unit = TextDraw.at(1) }\n",
	})
	out, _, _ := run(t, root)
	if n := strings.Count(out, "警告:"); n != 1 {
		t.Errorf("ゲーム 1 本に警告が %d 回出た", n)
	}
}

func TestMissingRulesFileAborts(t *testing.T) {
	root := t.TempDir()
	var out, errOut strings.Builder
	code, err := Run(&out, &errOut, root, nil)
	if err == nil {
		t.Fatal("規約ファイルが無いのにエラーを返さなかった")
	}
	if code == 0 {
		t.Errorf("規約ファイルが無いのに終了コード 0")
	}
	if out.String() != "" {
		t.Errorf("規約が読めないのに何か出力した: %q", out.String())
	}
}

func TestBrokenRulesFileAborts(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, filepath.FromSlash(RulesPath))
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("{\"rectPattern\": \"x\"}"), 0o644); err != nil {
		t.Fatal(err)
	}
	var out, errOut strings.Builder
	if _, err := Run(&out, &errOut, root, nil); err == nil {
		t.Fatal("欠けた規約ファイルを受け入れてしまった")
	}
}

func TestProjectRootOf(t *testing.T) {
	cases := map[string]string{
		"templates/a/src/View.flix":       "templates/a",
		"templates/a/src/render/G.flix":   "templates/a",
		"/x/y/src/View.flix":              "/x/y",
		"src/View.flix":                   ".",
		"./templates/a/src/../src/V.flix": "templates/a/src/..",
	}
	for in, want := range cases {
		got, ok := projectRootOf(in)
		if !ok || got != want {
			t.Errorf("projectRootOf(%q) = %q,%v (期待 %q)", in, got, ok, want)
		}
	}
	if _, ok := projectRootOf("templates/a/View.flix"); ok {
		t.Error("src が無いのに根を見つけた")
	}
}
