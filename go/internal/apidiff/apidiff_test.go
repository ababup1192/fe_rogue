package apidiff

// What: レコード・enum の中身の割り方、宣言の突き合わせ（消えた / 増えた / 中身が変わった /
// doc コメントだけの差と折り返しだけの差は鳴らない）、eff の op が増えたら直す物に入ること、
// schema の増減、バージョンの大小、1 つ前のタグの選び方、
// タグが引けないときにエラーを出さずに成功しないこと、出す口と終了コード。

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

var testDocKinds = []string{"fx", "sprite", "shader"}

func TestMembersOfSplitsRecordAtTopLevelCommasOnly(t *testing.T) {
	got := membersOf("pub type alias Sprite = { anchor = Vec2.Vec2, frames = Map[String, List[String]], clips = Map[String, Clip] }")
	if strings.Join(got, ",") != "anchor,frames,clips" {
		t.Errorf("got=%v", got)
	}
}

func TestMembersOfReadsEnumVariants(t *testing.T) {
	got := membersOf("pub enum Loop { case Forward, case PingPong, case Once }")
	if strings.Join(got, ",") != "Forward,PingPong,Once" {
		t.Errorf("got=%v", got)
	}
}

func TestDiffMembersFindsRenamedField(t *testing.T) {
	removed, added := diffMembers(
		"pub type alias Sprite = { anchor = Vec2.Vec2, loop = Loop }",
		"pub type alias Sprite = { anchor = Vec2.Vec2, clips = Map[String, Clip] }")
	if strings.Join(removed, ",") != "loop" || strings.Join(added, ",") != "clips" {
		t.Errorf("removed=%v added=%v", removed, added)
	}
}

// def に中身の増減を当てると、引数と戻り値の別々のレコードの名前が 1 つに混ざり、
// 「どこが変わったか」を読み違えさせる。
func TestHasMembersIsFalseForDef(t *testing.T) {
	if hasMembers("pub def add(a: {x = Int32}, b: {x = Int32}): {x = Int32}") {
		t.Error("def を中身の増減の対象にしています")
	}
	if !hasMembers("pub type alias A = { x = Int32 }") || !hasMembers("pub enum E { case A }") {
		t.Error("type alias / enum が対象から外れています")
	}
}

func TestVersionComparesNumericallyNotLexically(t *testing.T) {
	if !versionLess(parseVersion("0.9.0"), parseVersion("0.10.0")) {
		t.Error("0.9.0 < 0.10.0 のはず（字の順だと逆になる）")
	}
}

func TestSameVersionIsNotLess(t *testing.T) {
	if versionLess(parseVersion("0.31.0"), parseVersion("0.31.0")) {
		t.Error("同じバージョンは小さくない")
	}
}

func TestNonNumericVersionIsUnreadable(t *testing.T) {
	if parseVersion("0.31.0-rc1") != nil {
		t.Error("数でない字は読めない扱いのはず")
	}
}

// pkgTree は engine_world/src に 1 本だけ置いた偽のリポを組む。
func pkgTree(t *testing.T, body string) string {
	t.Helper()
	dir := t.TempDir()
	src := filepath.Join(dir, "engine_world", "src")
	if err := os.MkdirAll(src, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(src, "A.flix"), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	return dir
}

func diffOf(t *testing.T, before, after string) Result {
	t.Helper()
	res := newResult()
	fillDiff(&res, pkgTree(t, before), pkgTree(t, after), testDocKinds)
	return res
}

func TestRemovedDeclarationIsBreaking(t *testing.T) {
	res := diffOf(t, "mod M {\n    pub def gone(): Int32 = 0\n}\n", "mod M {\n}\n")
	if len(res.Breaking) != 1 {
		t.Fatalf("breaking=%v", res.Breaking)
	}
	if res.Breaking[0].Name != "gone" {
		t.Errorf("name=%q", res.Breaking[0].Name)
	}
	if res.Breaking[0].Kind != "removed" {
		t.Errorf("kind=%q", res.Breaking[0].Kind)
	}
	if res.Breaking[0].Before == "" {
		t.Error("消える前の宣言が空です")
	}
}

func TestChangedSignatureIsBreaking(t *testing.T) {
	res := diffOf(t,
		"mod M {\n    pub def kept(a: Int32): Int32 = a\n}\n",
		"mod M {\n    pub def kept(a: Int32, b: Int32): Int32 = a\n}\n")
	if len(res.Breaking) != 1 || res.Breaking[0].Kind != "changed" {
		t.Fatalf("breaking=%v", res.Breaking)
	}
}

func TestNewDeclarationIsNotBreaking(t *testing.T) {
	res := diffOf(t, "mod M {\n}\n", "mod M {\n    pub def fresh(): Int32 = 1\n}\n")
	if len(res.Breaking) != 0 {
		t.Fatalf("breaking=%v", res.Breaking)
	}
	if len(res.Added) != 1 || res.Added[0].Name != "fresh" {
		t.Errorf("added=%v", res.Added)
	}
}

// Flix の handler は全 op を書かないと通らないので、op が増えると既にある handler が壊れる。
func TestAddedEffOpIsBreaking(t *testing.T) {
	res := diffOf(t,
		"mod M {\n    pub eff Sound {\n        def play(): Unit\n    }\n}\n",
		"mod M {\n    pub eff Sound {\n        def play(): Unit\n        def stop(): Unit\n    }\n}\n")
	names := []string{}
	for _, c := range res.Breaking {
		names = append(names, c.Name)
	}
	if !contains(names, "Sound.stop") {
		t.Errorf("増えた op が直す物に入っていません breaking=%v added=%v", names, res.Added)
	}
}

// doc コメントだけの書き直しを「API が変わった」と読むと、
// バージョンを跨ぐたびに何十件も偽の「直す物」が出る。
func TestDocCommentOnlyChangeIsQuiet(t *testing.T) {
	res := diffOf(t,
		"mod M {\n    /// 古い説明。\n    pub def f(): Int32 = 0\n}\n",
		"mod M {\n    /// 新しい説明に書き直した。\n    pub def f(): Int32 = 0\n}\n")
	if len(res.Breaking) != 0 || len(res.Added) != 0 {
		t.Errorf("breaking=%v added=%v", res.Breaking, res.Added)
	}
}

// 長い宣言を複数行へ折り返しただけで鳴ると、読む側が本物の非互換を見失う。
func TestLineWrappingOnlyChangeIsQuiet(t *testing.T) {
	res := diffOf(t,
		"mod M {\n    pub def f(a: Int32, b: Int32): Int32 = a\n}\n",
		"mod M {\n    pub def f(\n        a: Int32,\n        b: Int32\n    ): Int32 = a\n}\n")
	if len(res.Breaking) != 0 {
		t.Errorf("breaking=%v", res.Breaking)
	}
}

// レコードは行型なのでフィールドの順に意味が無い。並べ替えだけで直す物にはしない。
func TestReorderedFieldsAreQuiet(t *testing.T) {
	res := diffOf(t,
		"mod M {\n    pub type alias A = { x = Int32, y = Int32 }\n}\n",
		"mod M {\n    pub type alias A = { y = Int32, x = Int32 }\n}\n")
	if len(res.Breaking) != 0 {
		t.Errorf("breaking=%v", res.Breaking)
	}
}

// 同じ名前が別の mod に居るとき、片方が消えたのをもう片方の存在で隠さない。
func TestSameNameInDifferentModsIsKeptApart(t *testing.T) {
	res := diffOf(t,
		"mod A {\n    pub def draw(): Int32 = 0\n}\nmod B {\n    pub def draw(): Int32 = 0\n}\n",
		"mod B {\n    pub def draw(): Int32 = 0\n}\n")
	if len(res.Breaking) != 1 || res.Breaking[0].Mod != "A" {
		t.Errorf("breaking=%v", res.Breaking)
	}
}

func schemaTree(t *testing.T, names ...string) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "docs"), 0o755); err != nil {
		t.Fatal(err)
	}
	for _, n := range names {
		if err := os.WriteFile(filepath.Join(dir, "docs", n), []byte("{}"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return dir
}

// 消えた schema を見落とすと、その種は「診られない」側へ移り、
// 退行が「元々 schema が無い種」の報告に化ける。
func TestRemovedSchemaIsReported(t *testing.T) {
	got := diffSchemas(schemaTree(t, "fx.schema.json"), schemaTree(t))
	if len(got) != 1 || got[0].Name != "fx.schema.json" || got[0].Kind != "removed" {
		t.Errorf("got=%v", got)
	}
}

func TestAddedSchemaIsReported(t *testing.T) {
	got := diffSchemas(schemaTree(t), schemaTree(t, "ui.schema.json"))
	if len(got) != 1 || got[0].Kind != "added" {
		t.Errorf("got=%v", got)
	}
}

func TestUndiagnosableDocsNamesKindsWithoutSchema(t *testing.T) {
	got := undiagnosableDocs(schemaTree(t, "fx.schema.json"), testDocKinds)
	if contains(got, "fx") {
		t.Errorf("schema のある種を診られない側に入れています: %v", got)
	}
	if !contains(got, "shader") {
		t.Errorf("schema の無い種が挙がっていません: %v", got)
	}
}

func TestRunNeedsFrom(t *testing.T) {
	var out, errOut strings.Builder
	code, err := Run(&out, &errOut, t.TempDir(), nil)
	if err != nil || code != 2 {
		t.Fatalf("code=%d err=%v", code, err)
	}
	if !strings.Contains(errOut.String(), "--from") {
		t.Errorf("errOut=%q", errOut.String())
	}
}

// `--from --json` の打ち間違いでフラグをバージョン名として git へ渡さない。
func TestRunRejectsFlagAsVersion(t *testing.T) {
	var out, errOut strings.Builder
	code, _ := Run(&out, &errOut, t.TempDir(), []string{"--from", "--json"})
	if code != 2 {
		t.Errorf("code=%d out=%q", code, out.String())
	}
}

// 規約データを消しただけで「診られない種は 1 つもありません」と嘘の緑を出さない。
func TestRunNeedsRules(t *testing.T) {
	var out, errOut strings.Builder
	code, err := Run(&out, &errOut, t.TempDir(), []string{"--from", "none"})
	if code == 0 || err == nil {
		t.Fatalf("code=%d err=%v", code, err)
	}
}

func rulesTree(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "bin", "lint-rules"), 0o755); err != nil {
		t.Fatal(err)
	}
	body := `{"docKinds":["fx","shader"]}`
	if err := os.WriteFile(filepath.Join(dir, RulesPath), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	return dir
}

func TestRunFromNoneSaysThereIsNothingToCompare(t *testing.T) {
	var out, errOut strings.Builder
	code, err := Run(&out, &errOut, rulesTree(t), []string{"--from", "none"})
	if err != nil || code != 0 {
		t.Fatalf("code=%d err=%v", code, err)
	}
	if !strings.Contains(out.String(), "初リリース") {
		t.Errorf("out=%q", out.String())
	}
}

// JSON の一覧が経路によって null と [] に割れると、読む側が 2 通りの場合分けを強いられる。
func TestJSONAlwaysHasArraysNotNull(t *testing.T) {
	var out, errOut strings.Builder
	if _, err := Run(&out, &errOut, rulesTree(t), []string{"--from", "none", "--json"}); err != nil {
		t.Fatal(err)
	}
	var got map[string]any
	if err := json.Unmarshal([]byte(out.String()), &got); err != nil {
		t.Fatalf("JSON になっていません: %v\n%s", err, out.String())
	}
	for _, key := range []string{"breaking", "added", "schemas", "undiagnosableDocs", "notices"} {
		if got[key] == nil {
			t.Errorf("%s が null です", key)
		}
	}
}

// エラーを出さずに 0 で終わると「非互換ゼロ」と見分けが付かず、壊れたバージョンを配ってしまう。
func TestRunFailsLoudlyWhenTagCannotBeResolved(t *testing.T) {
	dir := rulesTree(t)
	git(t, dir, "init", "--quiet")
	var out, errOut strings.Builder
	code, err := Run(&out, &errOut, dir, []string{"--from", "v9.9.9"})
	if code == 0 || err == nil {
		t.Fatalf("タグが無いのに %d で終わりました out=%q", code, out.String())
	}
	// git の英語をそのまま流すと、git のバージョンが変わるたびに golden が壊れる。
	if strings.Contains(err.Error(), "fatal:") {
		t.Errorf("git の生のメッセージが漏れています: %v", err)
	}
}

func TestFetchPreviousTagFailsWhenNoOlderTagExists(t *testing.T) {
	dir := t.TempDir()
	git(t, dir, "init", "--quiet")
	if err := os.WriteFile(filepath.Join(dir, "Makefile"), []byte("VERSION := 0.1.0\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, _, err := fetchPreviousTag(dir); err == nil {
		t.Error("前のタグが無いのに選べてしまいました")
	}
}

func TestFetchPreviousTagPicksLargestBelowCurrent(t *testing.T) {
	dir := t.TempDir()
	git(t, dir, "init", "--quiet")
	git(t, dir, "config", "user.email", "t@example.com")
	git(t, dir, "config", "user.name", "t")
	if err := os.WriteFile(filepath.Join(dir, "Makefile"), []byte("VERSION := 0.31.0\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	git(t, dir, "add", "-A")
	git(t, dir, "commit", "--quiet", "-m", "x")
	// v0.9.0 が字の順では最大になる並び。数として比べているかを見る。
	for _, tag := range []string{"v0.9.0", "v0.28.0", "v0.30.0", "v0.32.0"} {
		git(t, dir, "tag", tag)
	}
	got, _, err := fetchPreviousTag(dir)
	if err != nil {
		t.Fatal(err)
	}
	if got != "v0.30.0" {
		t.Errorf("got=%q（v0.32.0 は今より後・v0.9.0 は字の順の罠）", got)
	}
}

// fetch できなかったことを知らせないと、古いタグのまま何バージョンも前を「1 つ前」と読む。
func TestFetchPreviousTagTellsWhenFetchFailed(t *testing.T) {
	dir := t.TempDir()
	git(t, dir, "init", "--quiet")
	git(t, dir, "config", "user.email", "t@example.com")
	git(t, dir, "config", "user.name", "t")
	if err := os.WriteFile(filepath.Join(dir, "Makefile"), []byte("VERSION := 0.31.0\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	git(t, dir, "add", "-A")
	git(t, dir, "commit", "--quiet", "-m", "x")
	git(t, dir, "tag", "v0.30.0")
	_, notice, err := fetchPreviousTag(dir)
	if err != nil {
		t.Fatal(err)
	}
	// origin が無いので fetch は必ず失敗する。
	if !strings.Contains(notice, "fail-open") {
		t.Errorf("告知がありません notice=%q", notice)
	}
}

// 長い宣言を頭から一定の長さで切ると、前後が同じ文字列になって何も読めなくなる。
func TestBeforeAfterLinesShowTheDifference(t *testing.T) {
	head := strings.Repeat("a", 300)
	c := Change{Kind: "changed", Before: "pub def f(" + head + "X): Unit", After: "pub def f(" + head + "Y): Unit"}
	lines := beforeAfterLines(c)
	if len(lines) != 2 {
		t.Fatalf("lines=%v", lines)
	}
	if lines[0] == lines[1] {
		t.Fatalf("前後が同じ行になっています: %q", lines[0])
	}
	if !strings.Contains(lines[0], "X") || !strings.Contains(lines[1], "Y") {
		t.Errorf("違う所が出ていません: %v", lines)
	}
}

func contains(list []string, s string) bool {
	for _, x := range list {
		if x == s {
			return true
		}
	}
	return false
}

func git(t *testing.T, dir string, args ...string) {
	t.Helper()
	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
}
