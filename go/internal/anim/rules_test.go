package anim

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"testing"
)

// 正本は bin/lint-anim.py。JSON がそこからずれていないかを機械で見る。
// WhyNot: 目視の約束にしないのは、閾値を Python 側だけ直したときに Go 版だけが
// 古い判定のまま緑を出すため。

// repoRoot はテストから見たリポジトリの根 (go/internal/anim の 3 つ上)。
func repoRoot() string { return filepath.Join("..", "..", "..") }

func pythonSource(t *testing.T) string {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(repoRoot(), "bin", "lint-anim.py"))
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

// pyNumber は `NAME = 0.45      # ...` の数を読む。
func pyNumber(t *testing.T, src, name string) float64 {
	t.Helper()
	m := regexp.MustCompile(`(?m)^` + name + ` = ([0-9.]+)`).FindStringSubmatch(src)
	if m == nil {
		t.Fatalf("bin/lint-anim.py に %s が無い", name)
	}
	v, err := strconv.ParseFloat(m[1], 64)
	if err != nil {
		t.Fatal(err)
	}
	return v
}

var pyStrLiteral = regexp.MustCompile(`"([^"]*)"`)

// pyBracket は `NAME = <開き> ... <閉じ>` の中の文字列リテラルを並び順で返す。
func pyBracket(t *testing.T, src, name, open, close string) []string {
	t.Helper()
	head := regexp.MustCompile(`(?m)^` + name + ` = ` + regexp.QuoteMeta(open)).FindStringIndex(src)
	if head == nil {
		t.Fatalf("bin/lint-anim.py に %s が無い", name)
	}
	tail := strings.Index(src[head[1]:], close)
	if tail < 0 {
		t.Fatalf("bin/lint-anim.py の %s の閉じが見つからない", name)
	}
	var found []string
	for _, m := range pyStrLiteral.FindAllStringSubmatch(src[head[1]:head[1]+tail], -1) {
		found = append(found, m[1])
	}
	return found
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

func TestRulesMatchPython(t *testing.T) {
	src := pythonSource(t)
	f := loadRulesFile(t)
	numbers := []struct {
		name string
		got  float64
		py   string
	}{
		{"maxPopShare", *f.MaxPopShare, "MAX_POP_SHARE"},
		{"maxAreaDrift", *f.MaxAreaDrift, "MAX_AREA_DRIFT"},
		{"maxBob", float64(*f.MaxBob), "MAX_BOB"},
		{"minSideRatio", *f.MinSideRatio, "MIN_SIDE_RATIO"},
		{"maxSideRatio", *f.MaxSideRatio, "MAX_SIDE_RATIO"},
		{"minBackIou", *f.MinBackIoU, "MIN_BACK_IOU"},
		{"footTolerance", float64(*f.FootTolerance), "FOOT_TOLERANCE"},
	}
	for _, c := range numbers {
		if want := pyNumber(t, src, c.py); c.got != want {
			t.Errorf("%s が bin/lint-anim.py とずれている: JSON %v / Python %v", c.name, c.got, want)
		}
	}
	if got, want := strings.Join(f.Rules, ","), strings.Join(pyBracket(t, src, "RULES", "(", ")"), ","); got != want {
		t.Errorf("rules がずれている\n JSON:   %s\n Python: %s", got, want)
	}
	if got, want := strings.Join(f.GameRoots, ","),
		strings.Join(pyBracket(t, src, "GAME_ROOTS", "(", ")"), ","); got != want {
		t.Errorf("gameRoots がずれている\n JSON:   %s\n Python: %s", got, want)
	}
	if got, want := sortedJoin(f.Transparent),
		sortedJoin(pyBracket(t, src, "TRANSPARENT", "{", "}")); got != want {
		t.Errorf("transparent がずれている\n JSON:   %q\n Python: %q", got, want)
	}
	if got, want := sortedJoin(f.ExcludedDirs),
		sortedJoin(pyBracket(t, src, "EXCLUDED_DIRS", "{", "}")); got != want {
		t.Errorf("excludedDirs がずれている\n JSON:   %s\n Python: %s", got, want)
	}

	// DIRECTIONS は "語尾": "方向" の並びなので 2 個ずつ組にする。
	flat := pyBracket(t, src, "DIRECTIONS", "{", "\n}")
	if len(flat)%2 != 0 {
		t.Fatalf("DIRECTIONS の組が奇数個: %v", flat)
	}
	want := map[string]string{}
	for i := 0; i < len(flat); i += 2 {
		want[flat[i]] = flat[i+1]
	}
	if len(want) != len(f.Directions) {
		t.Fatalf("directions の数がずれている: JSON %d / Python %d", len(f.Directions), len(want))
	}
	for k, v := range want {
		if f.Directions[k] != v {
			t.Errorf("directions[%q] が %q (Python は %q)", k, f.Directions[k], v)
		}
	}
}

func sortedJoin(items []string) string {
	c := append([]string(nil), items...)
	sort.Strings(c)
	return strings.Join(c, ",")
}

func TestLoadRulesFromRepo(t *testing.T) {
	rules, err := LoadRules(repoRoot())
	if err != nil {
		t.Fatal(err)
	}
	if !rules.Transparent['.'] || !rules.Transparent[' '] || rules.Transparent['o'] {
		t.Errorf("透明の字の集合がおかしい: %v", rules.Transparent)
	}
	if rules.Directions["west"] != "side_w" {
		t.Errorf("west が %q (期待 side_w)", rules.Directions["west"])
	}
}

func TestLoadRulesFailsWithoutFile(t *testing.T) {
	if _, err := LoadRules(t.TempDir()); err == nil {
		t.Fatal("規約ファイルが無いのにエラーにならなかった")
	}
}
