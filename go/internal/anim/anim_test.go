package anim

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func rulesForTest(t *testing.T) *Rules {
	t.Helper()
	rules, err := LoadRules(repoRoot())
	if err != nil {
		t.Fatal(err)
	}
	return rules
}

func runAnim(t *testing.T, args ...string) (string, int) {
	t.Helper()
	var out strings.Builder
	code, err := Run(&out, repoRoot(), args)
	if err != nil {
		t.Fatalf("Run が失敗した: %v", err)
	}
	return out.String(), code
}

// TestFixturesMatchExpected は負の見本 13 件を expected.txt と突き合わせる。
// WhyNot: 本物のリポではこの検査が 1 件も鳴らないので、見本だけが判定の本体を通す。
func TestFixturesMatchExpected(t *testing.T) {
	dir := filepath.Join(repoRoot(), "testdata", "lint", "anim")
	cases, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	seen := 0
	for _, c := range cases {
		if !c.IsDir() {
			continue
		}
		name := c.Name()
		want, err := os.ReadFile(filepath.Join(dir, name, "expected.txt"))
		if err != nil {
			continue
		}
		seen++
		t.Run(name, func(t *testing.T) {
			got, code := runAnim(t, filepath.Join(dir, name, "input.sprite.json"))
			got += fmt.Sprintf("[exit=%d]\n", code)
			if got != string(want) {
				t.Errorf("出力が expected.txt と違う\n--- got ---\n%s--- want ---\n%s", got, want)
			}
		})
	}
	if seen != 13 {
		t.Errorf("見本が %d 件しか無い (期待 13)", seen)
	}
}

func TestRepoIsQuiet(t *testing.T) {
	out, code := runAnim(t)
	if code != 0 {
		t.Errorf("終了コードが %d (期待 0)", code)
	}
	if !strings.HasSuffix(out, "ファイル / 注意 0 件\n") {
		t.Errorf("本物のリポで鳴っている: %q", out)
	}
}

func TestStrictRelabelsAndFails(t *testing.T) {
	path := filepath.Join(repoRoot(), "testdata", "lint", "anim", "pop-frame-swap", "input.sprite.json")
	out, code := runAnim(t, path, "--strict")
	if code != 1 {
		t.Errorf("--strict の終了コードが %d (期待 1)", code)
	}
	if !strings.Contains(out, "  NG: ") || strings.Contains(out, "  注意: ") {
		t.Errorf("--strict で見出しが NG になっていない: %q", out)
	}
}

func TestSelfTestAllPass(t *testing.T) {
	out, code := runAnim(t, "--self-test")
	if code != 0 {
		t.Errorf("自己検査の終了コードが %d (期待 0)", code)
	}
	if !strings.HasSuffix(out, "\n9/9 件 OK\n") {
		t.Errorf("自己検査が 9/9 で終わっていない: %q", out)
	}
}

// TestChangeShareSlackBoundary は ±2 の探索範囲の境界を縛る。
// WhyNot: 「2 か 4 か」で結果が全く変わるので、オフバイワンをここで止める。
func TestChangeShareSlackBoundary(t *testing.T) {
	r := rulesForTest(t)
	block := func(pad int) []string {
		row := strings.Repeat(".", pad) + "oooo" + strings.Repeat(".", 12-pad-4)
		return []string{row, row, row, row}
	}
	if got := r.changeShare(block(0), block(2)); got != 0 {
		t.Errorf("2px の平行移動で %v (期待 0)", got)
	}
	if got := r.changeShare(block(0), block(4)); got == 0 {
		t.Errorf("4px の平行移動が 0 になった (探索範囲が広すぎる)")
	}
}

// TestAreaDriftAlwaysSigned は縮んだコマも +N% と書くことを見る。
func TestAreaDriftAlwaysSigned(t *testing.T) {
	r := rulesForTest(t)
	notes := r.checkFrames("s",
		[]frame{{"a", []string{"oooo"}}, {"b", []string{"oo.."}}},
		skipSet("pop", "ground", "bob", "palette"))
	if len(notes) != 1 || !strings.Contains(notes[0], "面積が +50% ずれる") {
		t.Errorf("縮んだコマの字面が違う: %v", notes)
	}
}

// TestSequencesNeedTrailingDigits は番号の無いコマが動きの列に入らないことを縛る。
func TestSequencesNeedTrailingDigits(t *testing.T) {
	doc, err := decodeOrdered([]byte(`{"idle":[],"walk_0":[],"walk_1":[],"hit":[],"cast2":[],"cast3":[]}`))
	if err != nil {
		t.Fatal(err)
	}
	got := sequences(doc.(*obj))
	if len(got) != 2 {
		t.Fatalf("動きの列が %d 本 (期待 2): %v", len(got), got)
	}
	if strings.Join(got["walk"], ",") != "walk_0,walk_1" {
		t.Errorf("walk が %v", got["walk"])
	}
	if strings.Join(got["cast"], ",") != "cast2,cast3" {
		t.Errorf("cast が %v", got["cast"])
	}
}

// TestViewDictKeepsWrittenOrder は方向の並びが JSON に書かれた順のままかを見る。
// WhyNot: 名前順に並べ替えると {'front': 5, 'side': 7} の字面が入れ替わる。
func TestViewDictKeepsWrittenOrder(t *testing.T) {
	r := rulesForTest(t)
	dir := t.TempDir()
	path := filepath.Join(dir, "a.sprite.json")
	body := `{"sprites":{
	  "walker_side":{"frames":{"idle":["..oo..","..oo..","..oo..","..oo.."]}},
	  "walker_front":{"frames":{"idle":["..oo..","..oo..","..oo..","......"]}}
	}}`
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	notes, err := r.checkDoc(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(notes) == 0 || !strings.Contains(notes[0], "{'side': 3, 'front': 2}") {
		t.Errorf("接地行の字面が書かれた順になっていない: %v", notes)
	}
}

func TestExcludedRules(t *testing.T) {
	got := excludedRules("対象外(pop、 area) — 変身する")
	if len(got) != 2 || !got["pop"] || !got["area"] {
		t.Errorf("除外の読み取りが %v", got)
	}
	if len(excludedRules("ふつうの説明")) != 0 {
		t.Error("対象外と書いていないのに除外が出た")
	}
	if len(excludedRules(42)) != 0 {
		t.Error("文字列でない値から除外が出た")
	}
}

func TestPyRepr(t *testing.T) {
	cases := [][2]string{
		{"x", "'x'"},
		{"'", `"'"`},
		{"\\", `'\\'`},
		{"あ", "'あ'"},
		{"\n", `'\n'`},
	}
	for _, c := range cases {
		if got := pyRepr(c[0]); got != c[1] {
			t.Errorf("pyRepr(%q) が %s (期待 %s)", c[0], got, c[1])
		}
	}
	if got := pyStrList([]string{"a", "b"}); got != "['a', 'b']" {
		t.Errorf("pyStrList が %s", got)
	}
}

func TestPyFloatAndPercent(t *testing.T) {
	if got := pyFloat(0.60); got != "0.6" {
		t.Errorf("pyFloat(0.60) が %s", got)
	}
	if got := pyFloat(0.90); got != "0.9" {
		t.Errorf("pyFloat(0.90) が %s", got)
	}
	if got := pyPercent(0.45); got != "45%" {
		t.Errorf("pyPercent(0.45) が %s", got)
	}
	if got := pySignedPercent(0.25); got != "+25%" {
		t.Errorf("pySignedPercent(0.25) が %s", got)
	}
}
