package uioverflow

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// repoRoot はテストから見たリポジトリの根 (go/internal/uioverflow の 3 つ上)。
func repoRoot() string { return filepath.Join("..", "..", "..") }

// fixture は 1 ケース分の入れ子を作り、その根を返す。
func fixture(t *testing.T, files map[string]string) string {
	t.Helper()
	root := t.TempDir()
	rules, err := os.ReadFile(filepath.Join(repoRoot(), RulesPath))
	if err != nil {
		t.Fatal(err)
	}
	if files == nil {
		files = map[string]string{}
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

// notesOf は JSON 1 つ分の注意一覧を返す。
func notesOf(t *testing.T, doc string) []string {
	t.Helper()
	rules, err := LoadRules(repoRoot())
	if err != nil {
		t.Fatal(err)
	}
	v, err := LoadsPyJSON(doc)
	if err != nil {
		t.Fatal(err)
	}
	return rules.CheckDoc(v, &stats{})
}

func TestFixedWidthTextWithoutWrapIsNoted(t *testing.T) {
	notes := notesOf(t, `{"version":1,"root":{"name":"panel","width":120,
		"children":[{"name":"label","widget":"text","text":"ながい"}]}}`)
	if len(notes) != 1 {
		t.Fatalf("注意が %d 件 (期待 1): %v", len(notes), notes)
	}
	want := `panel/label: 固定幅 120px の枠内の text が wrap も fit も宣言していない ` +
		`— 長い文言が来るとはみ出す。折るなら "wrap": "auto"、` +
		`意図的な 1 行固定なら "lint-ui": "対象外 — 理由" を書く`
	if notes[0] != want {
		t.Errorf("文面が違う:\n Go:   %s\n 期待: %s", notes[0], want)
	}
}

func TestWrapDeclarations(t *testing.T) {
	cases := map[string]int{
		`"wrap":"auto"`:  0,
		`"wrap":96`:      0,
		`"wrap":0`:       1,
		`"wrap":true`:    1, // flex wrap は別物
		`"fit":true`:     0,
		`"fit":1`:        1,
		`"widget":"box"`: 0,
	}
	for decl, want := range cases {
		doc := `{"version":1,"root":{"name":"panel","width":120,"children":[
			{"name":"label","widget":"text",` + decl + `}]}}`
		if got := len(notesOf(t, doc)); got != want {
			t.Errorf("%s で注意 %d 件 (期待 %d)", decl, got, want)
		}
	}
}

func TestWidthLookup(t *testing.T) {
	cases := map[string]string{
		// grow は素通しして更に上の固定幅を見る
		`{"version":1,"root":{"name":"o","width":200,"children":[{"name":"i","width":"grow",
			"children":[{"name":"t","widget":"text"}]}]}}`: "固定幅 200px",
		// text 自身の固定幅も枠として見る
		`{"version":1,"root":{"name":"p","children":[{"name":"t","widget":"text","width":80}]}}`: "固定幅 80px",
		// auto-size (width 未指定) は構造上はみ出せないので対象外
		`{"version":1,"root":{"name":"p","children":[{"name":"t","widget":"text"}]}}`: "",
		// grow の上が auto なら見逃す側
		`{"version":1,"root":{"name":"o","children":[{"name":"i","width":"grow",
			"children":[{"name":"t","widget":"text"}]}]}}`: "",
		// 小数の幅は余分な 0 を付けずに出す
		`{"version":1,"root":{"name":"p","width":120.5,"children":[{"name":"t","widget":"text"}]}}`: "固定幅 120.5px",
		// 真偽値の width は幅ではない
		`{"version":1,"root":{"name":"p","width":true,"children":[{"name":"t","widget":"text"}]}}`: "",
	}
	for doc, want := range cases {
		notes := notesOf(t, doc)
		if want == "" {
			if len(notes) != 0 {
				t.Errorf("対象外のはずが鳴った: %v", notes)
			}
			continue
		}
		if len(notes) != 1 || !strings.Contains(notes[0], want) {
			t.Errorf("%s が出ていない: %v", want, notes)
		}
	}
}

func TestExemptNeedsReason(t *testing.T) {
	base := `{"version":1,"root":{"name":"p","width":120,"children":[
		{"name":"t","widget":"text"%s}]}}`
	if got := len(notesOf(t, strings.Replace(base, "%s", `,"lint-ui":"対象外 — 桁固定"`, 1))); got != 0 {
		t.Errorf("理由付きの除外が効いていない (%d 件)", got)
	}
	if got := len(notesOf(t, strings.Replace(base, "%s", `,"lint-ui":"あとで直す"`, 1))); got != 1 {
		t.Errorf("理由の無い文字列で除外された (%d 件)", got)
	}
	if got := len(notesOf(t, strings.Replace(base, "%s", `,"lint-ui":true`, 1))); got != 1 {
		t.Errorf("真偽値で除外された (%d 件)", got)
	}
}

func TestExcludedDocIsSkippedWhole(t *testing.T) {
	doc := `{"version":1,"lint-ui":"対象外 — 全部","root":{"name":"p","width":120,
		"children":[{"name":"t","widget":"text"}]}}`
	if got := len(notesOf(t, doc)); got != 0 {
		t.Errorf("ファイル最上位の除外が効いていない (%d 件)", got)
	}
}

func TestInstanceNodeIsCountedNotWalked(t *testing.T) {
	root := fixture(t, map[string]string{"a.ui.json": `{"version":1,"root":{"name":"p","width":120,
		"children":[{"name":"sub","instance":"assets/ui/sub.ui.json","widget":"text"}]}}`})
	out, _, code := run(t, root, filepath.Join(root, "a.ui.json"))
	if code != 0 || strings.Contains(out, "宣言していない") {
		t.Errorf("instance ノードを歩いてしまった:\n%s", out)
	}
	if !strings.Contains(out, "(instance 参照ノード 1 件は対象外)") {
		t.Errorf("instance の件数が出ていない:\n%s", out)
	}
}

func TestUseTemplateIsMerged(t *testing.T) {
	doc := `{"version":1,"templates":{"fixed":{"width":150}},
		"root":{"name":"p","use":"fixed","children":[{"name":"t","widget":"text"}]}}`
	notes := notesOf(t, doc)
	if len(notes) != 1 || !strings.Contains(notes[0], "固定幅 150px") {
		t.Errorf("use テンプレの width を重ねていない: %v", notes)
	}
}

func TestNodeWinsOverTemplate(t *testing.T) {
	doc := `{"version":1,"templates":{"fixed":{"width":150}},
		"root":{"name":"p","use":"fixed","width":"grow","children":[{"name":"t","widget":"text"}]}}`
	if got := len(notesOf(t, doc)); got != 0 {
		t.Errorf("ノード側の width が勝っていない (%d 件)", got)
	}
}

func TestUnnamedNodeIsShown(t *testing.T) {
	doc := `{"version":1,"root":{"width":120,"children":[{"widget":"text"}]}}`
	notes := notesOf(t, doc)
	if len(notes) != 1 || !strings.HasPrefix(notes[0], "(無名)/(無名): ") {
		t.Errorf("無名ノードの呼び名が違う: %v", notes)
	}
}

func TestStrictTurnsNotesIntoNG(t *testing.T) {
	root := fixture(t, map[string]string{"a.ui.json": `{"version":1,"root":{"name":"p","width":120,
		"children":[{"name":"t","widget":"text"}]}}`})
	target := filepath.Join(root, "a.ui.json")
	out, _, code := run(t, root, target)
	if code != 0 || !strings.Contains(out, "  注意: ") || !strings.Contains(out, "/ 注意 1 件") {
		t.Errorf("既定は注意どまりのはず: %d\n%s", code, out)
	}
	out, _, code = run(t, root, target, "--strict")
	if code != 1 || !strings.Contains(out, "  NG: ") || !strings.Contains(out, "/ NG 1 件") {
		t.Errorf("--strict で NG に上がっていない: %d\n%s", code, out)
	}
}

func TestUnreadableFileReportsPythonMessage(t *testing.T) {
	root := fixture(t, nil)
	out, _, code := run(t, root, filepath.Join(root, "no-such.ui.json"))
	want := "(読めない JSON: [Errno 2] No such file or directory: '" +
		filepath.Join(root, "no-such.ui.json") + "')"
	if !strings.Contains(out, want) || code != 0 {
		t.Errorf("Python と同じ字面になっていない:\n%s\n 期待: %s", out, want)
	}
}

func TestBrokenJSONReportsPythonMessage(t *testing.T) {
	root := fixture(t, map[string]string{"a.ui.json": "{\"a\": 1 \"b\": 2}"})
	out, _, _ := run(t, root, filepath.Join(root, "a.ui.json"))
	want := "(読めない JSON: Expecting ',' delimiter: line 1 column 9 (char 8))"
	if !strings.Contains(out, want) {
		t.Errorf("Python と同じ字面になっていない:\n%s\n 期待: %s", out, want)
	}
}

func TestDiscoverWalksTemplatesOnly(t *testing.T) {
	ok := `{"version":1,"root":{"name":"p"}}`
	root := fixture(t, map[string]string{
		"templates/a/assets/ui/x.ui.json":  ok,
		"templates/a/build/skip.ui.json":   ok,
		"templates/a/gallery/skip.ui.json": ok,
		"templates/b/y.ui.json":            ok,
		"templates/note.txt":               "not a dir entry",
		"outside/z.ui.json":                ok,
		"templates/a/assets/ui/z.json":     ok,
	})
	rules, err := LoadRules(root)
	if err != nil {
		t.Fatal(err)
	}
	got := rules.discover(root)
	want := []string{
		filepath.Join(root, "templates/a/assets/ui/x.ui.json"),
		filepath.Join(root, "templates/b/y.ui.json"),
	}
	if strings.Join(got, "\n") != strings.Join(want, "\n") {
		t.Errorf("見つけたファイルが違う:\n%v\n期待:\n%v", got, want)
	}
}

func TestDiscoverFallsBackToRoot(t *testing.T) {
	root := fixture(t, map[string]string{"assets/x.ui.json": `{"version":1,"root":{"name":"p"}}`})
	rules, err := LoadRules(root)
	if err != nil {
		t.Fatal(err)
	}
	got := rules.discover(root)
	if len(got) != 1 || filepath.Base(got[0]) != "x.ui.json" {
		t.Errorf("templates/ が無いとき自分の下を見ていない: %v", got)
	}
}

func TestSelfTestPasses(t *testing.T) {
	out, _, code := run(t, repoRoot(), "--self-test")
	if code != 0 {
		t.Fatalf("self-test が落ちた (%d):\n%s", code, out)
	}
	if !strings.HasSuffix(out, "\n12/12 件 OK\n") {
		t.Errorf("self-test の締めが違う:\n%s", out)
	}
	if strings.Contains(out, "NG") {
		t.Errorf("self-test に NG がある:\n%s", out)
	}
}

func TestEmptyRunStillPrintsNote(t *testing.T) {
	root := fixture(t, nil)
	out, _, code := run(t, root)
	if code != 0 {
		t.Fatalf("終了コードが %d", code)
	}
	if !strings.HasSuffix(out, LimitsNote+"\n") {
		t.Errorf("但し書きが出ていない:\n%s", out)
	}
}
