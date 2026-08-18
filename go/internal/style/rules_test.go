package style

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"testing"
)

// 正本は bin/lint-style.py。JSON がそこからずれていないかを機械で見る。
// WhyNot: 目視の約束にしないのは、閾値を Python 側だけ直したときに Go 版だけが
// 古い判定のまま緑を出すため。

// repoRoot はテストから見たリポジトリの根 (go/internal/style の 3 つ上)。
func repoRoot() string { return filepath.Join("..", "..", "..") }

func pythonSource(t *testing.T) string {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(repoRoot(), "bin", "lint-style.py"))
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

// pyNumber は `NAME = 0.35   # ...` の数を読む。
func pyNumber(t *testing.T, src, name string) float64 {
	t.Helper()
	m := regexp.MustCompile(`(?m)^` + name + ` = ([0-9.]+)`).FindStringSubmatch(src)
	if m == nil {
		t.Fatalf("bin/lint-style.py に %s が無い", name)
	}
	v, err := strconv.ParseFloat(m[1], 64)
	if err != nil {
		t.Fatal(err)
	}
	return v
}

var pyStrLiteral = regexp.MustCompile(`"([^"]*)"`)

// pyBlock は `NAME = <開き>` から最初の <閉じ> までの中身を返す。
func pyBlock(t *testing.T, src, name, open, close string) string {
	t.Helper()
	head := regexp.MustCompile(`(?m)^` + name + ` = ` + regexp.QuoteMeta(open)).FindStringIndex(src)
	if head == nil {
		t.Fatalf("bin/lint-style.py に %s が無い", name)
	}
	tail := strings.Index(src[head[1]:], close)
	if tail < 0 {
		t.Fatalf("bin/lint-style.py の %s の閉じが見つからない", name)
	}
	return src[head[1] : head[1]+tail]
}

func pyStrings(t *testing.T, src, name, open, close string) []string {
	t.Helper()
	var found []string
	for _, m := range pyStrLiteral.FindAllStringSubmatch(pyBlock(t, src, name, open, close), -1) {
		found = append(found, m[1])
	}
	return found
}

// pyPairs は `"key": 12.0,` の並びを読む。
func pyPairs(body string) map[string]float64 {
	out := map[string]float64{}
	for _, m := range regexp.MustCompile(`"(\w+)": ([0-9.]+)`).FindAllStringSubmatch(body, -1) {
		v, err := strconv.ParseFloat(m[2], 64)
		if err != nil {
			continue
		}
		out[m[1]] = v
	}
	return out
}

func loadRulesFile(t *testing.T) rulesFile {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(repoRoot(), RulesPath))
	if err != nil {
		t.Fatal(err)
	}
	var f rulesFile
	if err := json.Unmarshal(data, &f); err != nil {
		t.Fatal(err)
	}
	return f
}

func TestRulesMatchPythonNumbers(t *testing.T) {
	src := pythonSource(t)
	f := loadRulesFile(t)
	numbers := []struct {
		py  string
		got float64
	}{
		{"SOFT_STEP", float64(*f.SoftStep)},
		{"MAX_UNIT", float64(*f.MaxUnit)},
		{"GRID_FOUND", *f.GridFound},
		{"ELLIPSE_IOU", *f.EllipseIoU},
		{"REGION_MIN", *f.RegionMin},
		{"REGION_CAP", float64(*f.RegionCap)},
		{"REGION_QUANT", float64(*f.RegionQuant)},
		{"ELLIPSE_WARN", *f.EllipseWarn},
		{"SAME_AA", *f.SameAa},
		{"SAME_COLOR_RATIO", *f.SameColorRatio},
	}
	for _, n := range numbers {
		if want := pyNumber(t, src, n.py); n.got != want {
			t.Errorf("%s が bin/lint-style.py とずれている: JSON %v / Python %v", n.py, n.got, want)
		}
	}
}

func TestRulesMatchPythonLists(t *testing.T) {
	src := pythonSource(t)
	f := loadRulesFile(t)

	edges := regexp.MustCompile(`\d+`).FindAllString(pyBlock(t, src, "STEP_EDGES", "(", ")"), -1)
	if len(edges) != len(f.StepEdges) {
		t.Fatalf("stepEdges の数が Python と違う: %v", f.StepEdges)
	}
	for i, e := range edges {
		if strconv.Itoa(f.StepEdges[i]) != e {
			t.Errorf("stepEdges[%d] が %d (Python は %s)", i, f.StepEdges[i], e)
		}
	}

	labels := pyStrings(t, src, "STEP_LABELS", "(", ")")
	if strings.Join(labels, "|") != strings.Join(f.StepLabels, "|") {
		t.Errorf("stepLabels が Python とずれている: %v / %v", f.StepLabels, labels)
	}

	blocks := pyStrings(t, src, "BLOCK_NAMES", "[", "\n]")
	var flat []string
	for _, row := range f.BlockNames {
		flat = append(flat, row...)
	}
	if strings.Join(blocks, "|") != strings.Join(flat, "|") {
		t.Errorf("blockNames が Python とずれている: %v / %v", flat, blocks)
	}
}

func TestRulesMatchPythonHands(t *testing.T) {
	src := pythonSource(t)
	f := loadRulesFile(t)
	hands := pyBlock(t, src, "HANDS", "{", "\n}")
	for _, hand := range []string{"coarse", "fine"} {
		body := regexp.MustCompile(`"` + hand + `": \{([^}]*)\}`).FindStringSubmatch(hands)
		if body == nil {
			t.Fatalf("bin/lint-style.py の HANDS に %s が無い", hand)
		}
		want := pyPairs(body[1])
		got := f.Hands[hand]
		if got == nil {
			t.Fatalf("style.json の hands に %s が無い", hand)
		}
		pairs := map[string]float64{
			"aa_warn":     got.AaWarn,
			"aa_bad":      got.AaBad,
			"grid_warn":   got.GridWarn,
			"grid_bad":    got.GridBad,
			"cover_warn":  float64(got.CoverWarn),
			"cover_bad":   float64(got.CoverBad),
			"colors_warn": float64(got.ColorsWarn),
			"colors_bad":  float64(got.ColorsBad),
		}
		if len(want) != len(pairs) {
			t.Errorf("%s のしきい値の数が Python と違う: %d / %d", hand, len(pairs), len(want))
		}
		for key, v := range pairs {
			if want[key] != v {
				t.Errorf("hands.%s.%s が %v (Python は %v)", hand, key, v, want[key])
			}
		}
	}
}

func TestRulesMatchPythonSmooth(t *testing.T) {
	src := pythonSource(t)
	f := loadRulesFile(t)
	want := pyPairs(pyBlock(t, src, "SMOOTH", "{", "\n}"))
	pairs := map[string]float64{
		"aa_min":     f.Smooth.AaMin,
		"grid_max":   f.Smooth.GridMax,
		"colors_min": float64(f.Smooth.ColorsMin),
	}
	if len(want) != len(pairs) {
		t.Errorf("smooth のしきい値の数が Python と違う: %d / %d", len(pairs), len(want))
	}
	for key, v := range pairs {
		if want[key] != v {
			t.Errorf("smooth.%s が %v (Python は %v)", key, v, want[key])
		}
	}
}

func TestRulesMatchPythonWords(t *testing.T) {
	src := pythonSource(t)
	f := loadRulesFile(t)

	hints := pyBlock(t, src, "HAND_HINTS", "{", "\n}")
	found := regexp.MustCompile(`"(\w+)": \("([^"]*)"\)`).FindAllStringSubmatch(hints, -1)
	if len(found) != len(f.HandHints) {
		t.Fatalf("handHints の数が Python と違う: %d / %d", len(f.HandHints), len(found))
	}
	for _, m := range found {
		if f.HandHints[m[1]] != m[2] {
			t.Errorf("handHints.%s が %q (Python は %q)", m[1], f.HandHints[m[1]], m[2])
		}
	}

	guess := regexp.MustCompile(`\("(\w+)", \(([^)]*)\)\)`).FindAllStringSubmatch(src, -1)
	if len(guess) != len(f.HandGuess) {
		t.Fatalf("handGuess の数が Python と違う: %d / %d", len(f.HandGuess), len(guess))
	}
	for i, m := range guess {
		if f.HandGuess[i].Hand != m[1] {
			t.Errorf("handGuess[%d] の名前が %q (Python は %q)", i, f.HandGuess[i].Hand, m[1])
		}
		var words []string
		for _, w := range pyStrLiteral.FindAllStringSubmatch(m[2], -1) {
			words = append(words, w[1])
		}
		if strings.Join(words, "|") != strings.Join(f.HandGuess[i].Words, "|") {
			t.Errorf("handGuess[%d] の語が %v (Python は %v)", i, f.HandGuess[i].Words, words)
		}
	}

	valid := regexp.MustCompile(`hand not in \(([^)]*)\)`).FindStringSubmatch(src)
	if valid == nil {
		t.Fatal("bin/lint-style.py に --hand の受け付け一覧が無い")
	}
	var names []string
	for _, m := range pyStrLiteral.FindAllStringSubmatch(valid[1], -1) {
		names = append(names, m[1])
	}
	if strings.Join(names, "|") != strings.Join(f.HandNames, "|") {
		t.Errorf("handNames が %v (Python は %v)", f.HandNames, names)
	}
}

func TestLoadRulesFromRepo(t *testing.T) {
	rules, err := LoadRules(repoRoot())
	if err != nil {
		t.Fatal(err)
	}
	if !rules.isHandName("smooth") || rules.isHandName("pixel") {
		t.Errorf("--hand の受け付けが規約とずれている: %v", rules.HandNames)
	}
}

func TestLoadRulesMissingFile(t *testing.T) {
	if _, err := LoadRules(t.TempDir()); err == nil {
		t.Fatal("規約ファイルが無いのにエラーにならない")
	}
}

func TestLoadRulesBrokenJSON(t *testing.T) {
	root := t.TempDir()
	writeRules(t, root, "{ これは JSON ではない }")
	if _, err := LoadRules(root); err == nil {
		t.Fatal("壊れた JSON なのにエラーにならない")
	}
}

func TestLoadRulesMissingKey(t *testing.T) {
	root := t.TempDir()
	data, err := os.ReadFile(filepath.Join(repoRoot(), RulesPath))
	if err != nil {
		t.Fatal(err)
	}
	var m map[string]any
	if err := json.Unmarshal(data, &m); err != nil {
		t.Fatal(err)
	}
	delete(m, "ellipseWarn")
	out, err := json.Marshal(m)
	if err != nil {
		t.Fatal(err)
	}
	writeRules(t, root, string(out))
	_, err = LoadRules(root)
	if err == nil || !strings.Contains(err.Error(), "ellipseWarn") {
		t.Fatalf("キー欠けを名指しで止めていない: %v", err)
	}
}

func writeRules(t *testing.T, root, body string) {
	t.Helper()
	dir := filepath.Join(root, "bin", "lint-rules")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "style.json"), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}
