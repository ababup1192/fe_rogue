package apiindex

// What: 規約データが読めること・欠けを見つけること・Python 版と食い違わないこと。

import (
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"
)

// repoRoot はこのテストから見たリポジトリの根。
const repoRoot = "../../.."

func TestLoadRulesReadsRepoRules(t *testing.T) {
	rules, err := LoadRules(repoRoot)
	if err != nil {
		t.Fatal(err)
	}
	if len(rules.Targets) != 2 {
		t.Errorf("targets が %d 件", len(rules.Targets))
	}
}

func TestLoadRulesFailsWhenFileMissing(t *testing.T) {
	if _, err := LoadRules(t.TempDir()); err == nil {
		t.Error("規約ファイルが無いのにエラーにならない")
	}
}

func TestLoadRulesFailsWhenKeyMissing(t *testing.T) {
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "bin", "lint-rules"), 0o755); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, RulesPath)
	if err := os.WriteFile(path, []byte(`{"targets":[{"src":"a","doc":"b"}]}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadRules(dir); err == nil {
		t.Error("extraDefSources が無いのにエラーにならない")
	}
}

func TestLoadRulesFailsWhenExemptHasNoReason(t *testing.T) {
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "bin", "lint-rules"), 0o755); err != nil {
		t.Fatal(err)
	}
	body := `{"targets":[{"src":"a","doc":"b"}],"extraDefSources":[],` +
		`"exempt":{"X":""},"skipDirs":[],"fileExts":[]}`
	if err := os.WriteFile(filepath.Join(dir, RulesPath), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadRules(dir); err == nil {
		t.Error("理由の無い除外があるのにエラーにならない")
	}
}

// pyText は Python 版の本文。
func pyText(t *testing.T) string {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(repoRoot, "bin", "check-api-index.py"))
	if err != nil {
		t.Skipf("Python 版が読めない: %v", err)
	}
	return string(data)
}

// pyBlock は `名前 = {` から次の `}` だけの行までを返す。
func pyBlock(src, name string) string {
	start := strings.Index(src, name+" = {")
	if start < 0 {
		return ""
	}
	rest := src[start:]
	end := strings.Index(rest, "\n}")
	if end < 0 {
		return rest
	}
	return rest[:end]
}

var pyPair = regexp.MustCompile(`"([^"]*)":\s*"([^"]*)"`)
var pyStr = regexp.MustCompile(`"([^"]*)"`)
var pyTuple = regexp.MustCompile(`\("([^"]*)",\s*"([^"]*)"\)`)

func TestRulesMatchPythonTargets(t *testing.T) {
	src := pyText(t)
	var want []Target
	for _, m := range pyTuple.FindAllStringSubmatch(pyBlock2(src, "TARGETS = ["), -1) {
		want = append(want, Target{Src: m[1], Doc: m[2]})
	}
	rules, err := LoadRules(repoRoot)
	if err != nil {
		t.Fatal(err)
	}
	if len(want) != len(rules.Targets) {
		t.Fatalf("TARGETS が Python %d 件 / JSON %d 件", len(want), len(rules.Targets))
	}
	for i := range want {
		if want[i] != rules.Targets[i] {
			t.Errorf("TARGETS[%d] が Python %v / JSON %v", i, want[i], rules.Targets[i])
		}
	}
}

// pyBlock2 は `名前` で始まる括弧の並びを、次の `]` の行までで返す。
func pyBlock2(src, head string) string {
	start := strings.Index(src, head)
	if start < 0 {
		return ""
	}
	rest := src[start:]
	end := strings.Index(rest, "\n]")
	if end < 0 {
		return rest
	}
	return rest[:end]
}

func TestRulesMatchPythonExempt(t *testing.T) {
	src := pyText(t)
	want := map[string]string{}
	for _, m := range pyPair.FindAllStringSubmatch(pyBlock(src, "EXEMPT"), -1) {
		want[m[1]] = m[2]
	}
	rules, err := LoadRules(repoRoot)
	if err != nil {
		t.Fatal(err)
	}
	if len(want) == 0 {
		t.Fatal("Python 版から EXEMPT を読めなかった")
	}
	for key, reason := range want {
		if rules.Exempt[key] != reason {
			t.Errorf("EXEMPT %q が Python %q / JSON %q", key, reason, rules.Exempt[key])
		}
	}
	if len(want) != len(rules.Exempt) {
		t.Errorf("EXEMPT が Python %d 件 / JSON %d 件", len(want), len(rules.Exempt))
	}
}

func TestRulesMatchPythonSets(t *testing.T) {
	src := pyText(t)
	rules, err := LoadRules(repoRoot)
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		head string
		got  map[string]bool
	}{
		{"SKIP_DIRS = {", rules.SkipDirs},
		{"FILE_EXTS = {", rules.FileExts},
	} {
		line := pyLine(src, tc.head)
		var want []string
		for _, m := range pyStr.FindAllStringSubmatch(line, -1) {
			want = append(want, m[1])
		}
		if len(want) == 0 {
			t.Fatalf("Python 版から %s を読めなかった", tc.head)
		}
		var got []string
		for k := range tc.got {
			got = append(got, k)
		}
		sort.Strings(want)
		sort.Strings(got)
		if strings.Join(want, ",") != strings.Join(got, ",") {
			t.Errorf("%s が Python %v / JSON %v", tc.head, want, got)
		}
	}
}

// pyLine は head で始まる 1 行を返す。
func pyLine(src, head string) string {
	start := strings.Index(src, head)
	if start < 0 {
		return ""
	}
	rest := src[start:]
	if end := strings.Index(rest, "\n"); end >= 0 {
		return rest[:end]
	}
	return rest
}

func TestRulesMatchPythonExtraDefSources(t *testing.T) {
	src := pyText(t)
	rules, err := LoadRules(repoRoot)
	if err != nil {
		t.Fatal(err)
	}
	for _, extra := range rules.ExtraDefSources {
		if !strings.Contains(src, `"`+extra+`"`) {
			t.Errorf("extraDefSources の %q が Python 版に出てこない", extra)
		}
	}
	if len(rules.ExtraDefSources) != 1 {
		t.Errorf("extraDefSources が %d 件", len(rules.ExtraDefSources))
	}
}
