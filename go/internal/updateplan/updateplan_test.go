package updateplan

// What: ゲームの flix.toml からバージョンを読むこと、当たり所の絞り込み
// （識別子の切れ目・JSON はフィールド名・生成物は探さない）、当たらなかった数を言うこと、
// 生成した材料から追随例を引くこと（新しいバージョンが勝つ・跨いだ範囲だけ）、
// 出す口と終了コード。

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/ababup1192/flix_game_engine/go/internal/apidiff"
)

func write(t *testing.T, dir, rel, body string) string {
	t.Helper()
	path := filepath.Join(dir, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func changeOf(mod, name string, removed []string) apidiff.Change {
	return apidiff.Change{
		Key:            apidiff.Key{Package: "engine_world", Mod: mod, Name: name},
		Kind:           "changed",
		MembersRemoved: removed,
	}
}

func TestGameEngineVersionReadsTheDependencyLine(t *testing.T) {
	dir := t.TempDir()
	write(t, dir, "flix.toml", "[dependencies]\n"+
		`"github:ababup1192/flix_game_engine" = { version = "0.28.0", security = "unrestricted" }`+"\n")
	got, err := gameEngineVersion(dir)
	if err != nil || got != "0.28.0" {
		t.Errorf("got=%q err=%v", got, err)
	}
}

// 依存行が無いのを既定へ倒すと、比べる相手を取り違えたまま指示書を書いてしまう。
func TestGameWithoutTheDependencyLineIsAnError(t *testing.T) {
	dir := t.TempDir()
	write(t, dir, "flix.toml", "[package]\nname = \"x\"\n")
	if _, err := gameEngineVersion(dir); err == nil {
		t.Error("依存行が無いのに読めてしまいました")
	}
}

// draw のような一般語で全部の行が当たると、指示書が当たり所の一覧に埋もれる。
func TestLineMentionsNeedsTheQualifiedName(t *testing.T) {
	c := changeOf("PxSprite", "draw", nil)
	if lineMentions("        myDraw(a, b)", c, false) {
		t.Error("裸の名前で当たっています")
	}
	if lineMentions("        PxSpriteAtlas.drawAll(a)", c, false) {
		t.Error("識別子の途中で当たっています")
	}
	if !lineMentions("        PxSprite.draw(doc, s, f)", c, false) {
		t.Error("呼び出しを拾えていません")
	}
}

// Doc の実物に Flix の型名は 1 つも書かれていない。フィールド名で見ないと永久に当たらない。
func TestJSONIsMatchedByFieldName(t *testing.T) {
	c := changeOf("PxSpriteDoc", "Sprite", []string{"loop"})
	if !lineMentions(`      "loop": "forward"`, c, true) {
		t.Error("JSON のフィールドを拾えていません")
	}
	if lineMentions(`      "loop": "forward"`, c, false) {
		t.Error("Flix のソースを JSON の書き方で拾っています")
	}
	// 値の側に同じ字が並ぶだけの行（配った規約データ）は当たり所ではない。
	if lineMentions(`  "rules": ["pop", "loop", "palette"],`, c, true) {
		t.Error("キーでない字面で当たっています")
	}
}

// bin/ は engine から配られた道具。そこの当たりを直せと言われても直せない。
func TestScanFilesSkipsDistributedTools(t *testing.T) {
	dir := t.TempDir()
	write(t, dir, "src/World.flix", "x")
	write(t, dir, "bin/lint-rules/anim.json", "x")
	write(t, dir, ".claude/skills/a/SKILL.md", "x")
	got := scanFiles(dir)
	if len(got) != 1 {
		t.Errorf("got=%v", got)
	}
}

// lib/ と build/ は取り込んだ物と生成物。そこの当たりを直せと言われても直せない。
func TestScanFilesSkipsGeneratedAndVendored(t *testing.T) {
	dir := t.TempDir()
	write(t, dir, "src/World.flix", "x")
	write(t, dir, "lib/github/a/b.flix", "x")
	write(t, dir, "build/class/c.flix", "x")
	write(t, dir, "reference/d.json", "x")
	got := scanFiles(dir)
	if len(got) != 1 || !strings.HasSuffix(got[0], "World.flix") {
		t.Errorf("got=%v", got)
	}
}

func TestNarrowKeepsOnlyWhatTheGameUses(t *testing.T) {
	dir := t.TempDir()
	write(t, dir, "src/World.flix", "mod W {\n    def f(): Unit = PxSprite.draw(a)\n}\n")
	res := apidiff.Result{Breaking: []apidiff.Change{
		changeOf("PxSprite", "draw", nil),
		changeOf("DocTable", "activeDocs", nil),
	}}
	items, missed := narrow(dir, res)
	if len(items) != 1 || items[0].Name != "PxSprite.draw" {
		t.Fatalf("items=%v", items)
	}
	if missed != 1 {
		t.Errorf("当たらなかった数=%d", missed)
	}
	if len(items[0].Hits) != 1 || items[0].Hits[0].Line != 2 {
		t.Errorf("当たり所=%v", items[0].Hits)
	}
}

// 「差分は 20 件あったのに 2 件しか書いていない」を、隠したと読まれないようにする。
func TestBuildSaysHowManyDidNotApply(t *testing.T) {
	body := build("0.28.0", apidiff.Result{To: "0.31.0"}, nil, 18, "")
	if !strings.Contains(body, "他に 18 件") {
		t.Errorf("当たらなかった数が出ていません:\n%s", body)
	}
}

func TestBuildTellsHowToVerify(t *testing.T) {
	body := build("0.28.0", apidiff.Result{To: "0.31.0"}, nil, 0, "")
	for _, want := range []string{"make check", "make test", "make reference-check"} {
		if !strings.Contains(body, want) {
			t.Errorf("%s が出ていません", want)
		}
	}
}

func migrationsTree(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	write(t, dir, "docs/migrations/0.29.0.auto.md",
		"### 1. M.f（engine）\n\nengine 自身はこう直しました:\n\n```diff\n-old29\n+new29\n```\n")
	write(t, dir, "docs/migrations/0.30.0.auto.md",
		"### 1. M.f（engine）\n\nengine 自身はこう直しました:\n\n```diff\n-old30\n+new30\n```\n")
	return dir
}

// 改名が連鎖したとき、古い方を渡すと途中で死んだ書き方へ直させてしまう。
func TestFollowUpExamplesPrefersTheNewerVersion(t *testing.T) {
	got, _ := FollowUpExamples(migrationsTree(t), "0.28.0", "")
	if !strings.Contains(got["M.f"], "new30") {
		t.Errorf("新しい方が勝っていません: %q", got["M.f"])
	}
}

// ゲームが既に持っているバージョンより前の材料を渡すと、直し済みの物を直させる。
func TestFollowUpExamplesSkipsWhatTheGameAlreadyHas(t *testing.T) {
	got, _ := FollowUpExamples(migrationsTree(t), "0.29.0", "")
	if strings.Contains(got["M.f"], "new29") {
		t.Errorf("既に持っているバージョンの材料が混ざっています: %q", got["M.f"])
	}
	if !strings.Contains(got["M.f"], "new30") {
		t.Errorf("上げ先までの材料が落ちています: %q", got["M.f"])
	}
}

// 上げ先より後の材料を渡すと、まだ来ていない変更を直させる。
func TestFollowUpExamplesStopsAtTheTarget(t *testing.T) {
	got, _ := FollowUpExamples(migrationsTree(t), "0.28.0", "0.29.0")
	if strings.Contains(got["M.f"], "new30") {
		t.Errorf("上げ先より後の材料が混ざっています: %q", got["M.f"])
	}
}

// 0.9.0 は 0.10.0 より前。字の順で比べると逆になる。
func TestVersionsAreComparedNumerically(t *testing.T) {
	if !(padVersion("0.9.0") < padVersion("0.10.0")) {
		t.Error("0.9.0 < 0.10.0 になっていません")
	}
}

func TestRunNeedsGame(t *testing.T) {
	var out, errOut strings.Builder
	code, _ := Run(&out, &errOut, t.TempDir(), nil)
	if code != 2 || !strings.Contains(errOut.String(), "--game") {
		t.Errorf("code=%d errOut=%q", code, errOut.String())
	}
}

func TestRunRejectsMissingGame(t *testing.T) {
	var out, errOut strings.Builder
	code, err := Run(&out, &errOut, t.TempDir(),
		[]string{"--game", filepath.Join(t.TempDir(), "nope")})
	if code == 0 || err == nil {
		t.Errorf("無いフォルダで code=%d err=%v", code, err)
	}
}

// --to に v を付けたときも範囲が同じでないと、上げ先より後の材料まで混ざる。
func TestTargetWorksWithOrWithoutTheVPrefix(t *testing.T) {
	dir := migrationsTree(t)
	bare, _ := FollowUpExamples(dir, "0.28.0", "0.29.0")
	tagged, _ := FollowUpExamples(dir, "v0.28.0", "v0.29.0")
	if bare["M.f"] != tagged["M.f"] {
		t.Errorf("v の有無で変わっています bare=%q tagged=%q", bare["M.f"], tagged["M.f"])
	}
	if strings.Contains(tagged["M.f"], "new30") {
		t.Error("上げ先より後の材料が混ざっています")
	}
}

// 材料そのものが無いのを「例が無いバージョンだった」と読ませない。
func TestMissingMaterialIsToldApartFromNoExample(t *testing.T) {
	got, notice := FollowUpExamples(t.TempDir(), "0.28.0", "")
	if len(got) != 0 {
		t.Errorf("got=%v", got)
	}
	if notice == "" {
		t.Error("材料が無いことを知らせていません")
	}
}

// 説明や注記を「壊れた呼び出し」と読むと、エージェントがコメントを書き替える。
func TestCommentLinesAreNotHits(t *testing.T) {
	c := changeOf("PxSprite", "anchorOffsetOf", nil)
	if lineMentions("    // 旧: PxSprite.anchorOffsetOf は flipX を取っていた", c, false) {
		t.Error("コメント行を当たり所にしています")
	}
	if lineMentions("    /// PxSprite.anchorOffsetOf の話", c, false) {
		t.Error("doc コメントを当たり所にしています")
	}
	if !lineMentions("    PxSprite.anchorOffsetOf(d, s, f, 1)", c, false) {
		t.Error("呼び出しを落としています")
	}
}

// ゲームが自分で作った JSON の "loop": 1 行で、直す物が丸ごと 1 件でっち上がっていた。
func TestUnrelatedJSONIsNotADocFile(t *testing.T) {
	c := changeOf("PxSpriteDoc", "Sprite", []string{"loop"})
	if isDocFile("assets/mydata.json", c) {
		t.Error("無関係な JSON を Doc として見ています")
	}
	if !isDocFile("assets/hero.sprite.json", c) {
		t.Error("その種の Doc を見落としています")
	}
	// Doc でない mod（末尾が Doc でない）は、どの JSON にも当てない。
	if isDocFile("assets/hero.sprite.json", changeOf("PxSprite", "draw", []string{"loop"})) {
		t.Error("Doc でない mod で JSON に当てています")
	}
}

// handler は修飾なしで書くので当たり所が出せない。落とすと確実に壊れる変更が消える。
func TestAddedEffOpIsKeptEvenWithoutHits(t *testing.T) {
	dir := t.TempDir()
	write(t, dir, "src/World.flix", "mod W {\n}\n")
	res := apidiff.Result{Breaking: []apidiff.Change{
		{Key: apidiff.Key{Package: "engine", Mod: "M", Name: "Sound.stop"}, Kind: "added"},
	}}
	items, missed := narrow(dir, res)
	if len(items) != 1 {
		t.Fatalf("items=%v missed=%d", items, missed)
	}
	body := build("0.1.0", res, items, missed, "")
	if !strings.Contains(body, "機械では出せません") {
		t.Errorf("出せない旨が書かれていません:\n%s", body)
	}
}

// Studio が同梱している engine には .git が無い。そこで諦めると、Studio から呼んだ
// ときだけ「当たる非互換の数で赤の意味を分ける」仕組みがまるごと働かない。
func TestFallsBackToTheBundledMaterialsWithoutGit(t *testing.T) {
	root := migrationsTree(t)
	game := t.TempDir()
	write(t, game, "flix.toml", "[dependencies]\n"+
		`"github:ababup1192/flix_game_engine" = { version = "0.28.0" }`+"\n")
	write(t, game, "src/World.flix", "mod W {\n    def f(): Unit = M.f(1)\n}\n")

	plan, err := Build(root, game, "")
	if err != nil {
		t.Fatalf("材料があるのに諦めています: %v", err)
	}
	if plan.Count != 1 {
		t.Errorf("当たる数=%d body=%s", plan.Count, plan.Body)
	}
	if !strings.Contains(plan.Body, "src/World.flix:2") {
		t.Errorf("当たり所が出ていません: %s", plan.Body)
	}
	if !strings.Contains(plan.Body, "new30") {
		t.Errorf("追随例が貼られていません: %s", plan.Body)
	}
	// 突き合わせより弱い出し方だと分かる印が要る（JSON の Doc は出ない）。
	if !strings.Contains(plan.Body, "名前だけで探しています") {
		t.Errorf("弱い出し方だと言っていません: %s", plan.Body)
	}
}

// 使っていない名前まで数えると、直す物が 0 件でも「正常系」に見えて巻き戻しが働かない。
func TestFallbackCountsOnlyWhatTheGameUses(t *testing.T) {
	root := migrationsTree(t)
	game := t.TempDir()
	write(t, game, "flix.toml", "[dependencies]\n"+
		`"github:ababup1192/flix_game_engine" = { version = "0.28.0" }`+"\n")
	write(t, game, "src/World.flix", "mod W {\n    def f(): Unit = ()\n}\n")

	plan, err := Build(root, game, "")
	if err != nil {
		t.Fatal(err)
	}
	if plan.Count != 0 {
		t.Errorf("使っていないのに数えています: %d", plan.Count)
	}
	if !strings.Contains(plan.Body, "他に 1 件") {
		t.Errorf("当たらなかった数が出ていません: %s", plan.Body)
	}
}

// 材料も git も無いときは、数えられないことを言う（0 件と混ぜない）。
func TestFallbackStillFailsWithoutMaterials(t *testing.T) {
	root := t.TempDir()
	game := t.TempDir()
	write(t, game, "flix.toml", "[dependencies]\n"+
		`"github:ababup1192/flix_game_engine" = { version = "0.28.0" }`+"\n")
	if _, err := Build(root, game, ""); err == nil {
		t.Error("材料が無いのに数えられたことにしています")
	}
}
