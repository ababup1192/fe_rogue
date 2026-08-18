package status

// 規約データが Python 版 (bin/status.py) と同じ値かを見る。
// 片方だけ直すとここで落ちる。

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"testing"
)

func repoRoot(t *testing.T) string {
	t.Helper()
	root, err := filepath.Abs(filepath.Join("..", "..", ".."))
	if err != nil {
		t.Fatalf("リポジトリの根が分かりません: %v", err)
	}
	return root
}

func loadPython(t *testing.T) string {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(repoRoot(t), "bin", "status.py"))
	if err != nil {
		t.Fatalf("bin/status.py を読めません: %v", err)
	}
	return string(data)
}

// pyInt は Python 側の 1 つの数を正規表現で抜く。
func pyInt(t *testing.T, src, pattern string) int {
	t.Helper()
	m := regexp.MustCompile(pattern).FindStringSubmatch(src)
	if m == nil {
		t.Fatalf("bin/status.py に %s が見当たりません", pattern)
	}
	n, err := strconv.Atoi(m[1])
	if err != nil {
		t.Fatalf("%s の数を読めません: %v", pattern, err)
	}
	return n
}

func TestRulesMatchPython(t *testing.T) {
	rules, err := LoadRules(repoRoot(t))
	if err != nil {
		t.Fatalf("規約データを読めません: %v", err)
	}
	src := loadPython(t)

	cases := []struct {
		name    string
		got     int
		pattern string
	}{
		{"maxLines", rules.MaxLines, `MAX_LINES = (\d+)`},
		{"buildWarnEntries", rules.BuildWarnEntries, `BUILD_WARN_ENTRIES = (\d+)`},
		{"ageJustNowSeconds", int(rules.AgeJustNowSeconds), `if sec < (\d+):\n        return "たった今"`},
		{"ageMinuteSeconds", int(rules.AgeMinuteSeconds), `if sec < (\d+):\n        return "%d分前"`},
		{"ageHourSeconds", int(rules.AgeHourSeconds), `if sec < (\d+):\n        return "%d時間前"`},
		{"gitLogCount", rules.GitLogCount, `git\("log", "--oneline", "-(\d+)"\)`},
		{"greensShown", rules.GreensShown, `greens\[:(\d+)\]`},
		{"referenceBadShown", rules.ReferenceBadShown, `bad\[:(\d+)\]`},
		{"budgetDetailLines", rules.BudgetDetailLines, `startswith\("  "\)\]\[:(\d+)\]`},
		{"ticketsShown", rules.TicketsShown, `dirs\[:(\d+)\]`},
		{"ticketSummaryWidth", rules.TicketSummaryWidth, `summary\[:(\d+)\]`},
		{"notesShown", rules.NotesShown, `shown >= (\d+)`},
		{"notesWidth", rules.NotesWidth, `out\.append\("  " \+ s\[:(\d+)\]\)`},
	}
	for _, c := range cases {
		if want := pyInt(t, src, c.pattern); c.got != want {
			t.Errorf("%s が Python 版とずれています: Go %d / Python %d", c.name, c.got, want)
		}
	}
}

func TestSectionOrderMatchesPython(t *testing.T) {
	rules, err := LoadRules(repoRoot(t))
	if err != nil {
		t.Fatalf("規約データを読めません: %v", err)
	}
	src := loadPython(t)
	m := regexp.MustCompile(`(?s)for section in \((.*?)\):`).FindStringSubmatch(src)
	if m == nil {
		t.Fatal("bin/status.py の main() に節の並びが見当たりません")
	}
	var want []string
	for _, part := range strings.Split(m[1], ",") {
		if name := strings.TrimSpace(part); name != "" {
			want = append(want, name)
		}
	}
	if strings.Join(rules.Sections, ",") != strings.Join(want, ",") {
		t.Errorf("節の並びが Python 版とずれています:\n  Go     %v\n  Python %v", rules.Sections, want)
	}
}

func TestSectionNamesAreAllKnown(t *testing.T) {
	rules, err := LoadRules(repoRoot(t))
	if err != nil {
		t.Fatalf("規約データを読めません: %v", err)
	}
	if len(rules.Sections) != len(sectionsByName) {
		t.Fatalf("節の数が合いません: 規約 %d / 実装 %d", len(rules.Sections), len(sectionsByName))
	}
	for _, name := range rules.Sections {
		if _, ok := sectionsByName[name]; !ok {
			t.Errorf("実装に無い節が規約データにあります: %s", name)
		}
	}
}

func TestTestLogsDirMatchesPython(t *testing.T) {
	rules, err := LoadRules(repoRoot(t))
	if err != nil {
		t.Fatalf("規約データを読めません: %v", err)
	}
	src := loadPython(t)
	if !strings.Contains(src, `glob.glob(os.path.join("`+rules.TestLogsDir+`", "*.log"))`) {
		t.Errorf("testLogsDir が Python 版とずれています: %s", rules.TestLogsDir)
	}
}

func TestBuildDirsMatchPython(t *testing.T) {
	rules, err := LoadRules(repoRoot(t))
	if err != nil {
		t.Fatalf("規約データを読めません: %v", err)
	}
	src := loadPython(t)
	for _, g := range rules.BuildGlobs {
		if !strings.Contains(src, `glob.glob("`+g+`")`) {
			t.Errorf("buildGlobs に Python 版に無い物があります: %s", g)
		}
	}
	for _, d := range rules.BuildDirs {
		if !strings.Contains(src, `"`+d+`"`) {
			t.Errorf("buildDirs に Python 版に無い物があります: %s", d)
		}
	}
}

func TestLoadRulesMissingFile(t *testing.T) {
	if _, err := LoadRules(t.TempDir()); err == nil {
		t.Fatal("規約ファイルが無いのにエラーになりません")
	}
}

func TestLoadRulesBrokenJSON(t *testing.T) {
	root := t.TempDir()
	writeRule(t, root, "{ こわれている")
	if _, err := LoadRules(root); err == nil {
		t.Fatal("JSON が壊れているのにエラーになりません")
	}
}

func TestLoadRulesMissingKey(t *testing.T) {
	root := repoRoot(t)
	data, err := os.ReadFile(filepath.Join(root, RulesPath))
	if err != nil {
		t.Fatalf("規約ファイルを読めません: %v", err)
	}
	var full map[string]any
	if err := json.Unmarshal(data, &full); err != nil {
		t.Fatalf("規約ファイルが JSON ではありません: %v", err)
	}
	for key := range full {
		if key == "note" {
			continue
		}
		short := map[string]any{}
		for k, v := range full {
			if k != key {
				short[k] = v
			}
		}
		body, err := json.Marshal(short)
		if err != nil {
			t.Fatalf("組み直せません: %v", err)
		}
		tmp := t.TempDir()
		writeRule(t, tmp, string(body))
		if _, err := LoadRules(tmp); err == nil {
			t.Errorf("%s が無いのにエラーになりません", key)
		}
	}
}

func writeRule(t *testing.T, root, body string) {
	t.Helper()
	dir := filepath.Join(root, filepath.Dir(RulesPath))
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatalf("置き場を作れません: %v", err)
	}
	if err := os.WriteFile(filepath.Join(root, RulesPath), []byte(body), 0o644); err != nil {
		t.Fatalf("規約ファイルを書けません: %v", err)
	}
}
