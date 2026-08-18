package checkrefs

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
)

// repoRoot はこのテストから見たリポジトリの根。
func repoRoot(t *testing.T) string {
	t.Helper()
	wd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	root := filepath.Join(wd, "..", "..", "..")
	if _, err := os.Stat(filepath.Join(root, "bin", "check-refs.py")); err != nil {
		t.Fatalf("リポジトリの根が見つかりません: %v", err)
	}
	return root
}

func pythonSource(t *testing.T) string {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(repoRoot(t), "bin", "check-refs.py"))
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

// pyLiterals は `NAME = [` のような宣言の中の文字列を並び順のまま取り出す。
func pyLiterals(src, decl string, closeCh byte) ([]string, bool) {
	i := strings.Index(src, decl)
	if i < 0 {
		return nil, false
	}
	i += len(decl)
	out := []string{}
	for i < len(src) {
		switch src[i] {
		case '#':
			for i < len(src) && src[i] != '\n' {
				i++
			}
		case '"':
			j := i + 1
			var b strings.Builder
			for j < len(src) && src[j] != '"' {
				if src[j] == '\\' && j+1 < len(src) {
					b.WriteByte(src[j+1])
					j += 2
					continue
				}
				b.WriteByte(src[j])
				j++
			}
			out = append(out, b.String())
			i = j + 1
		case closeCh:
			return out, true
		default:
			i++
		}
	}
	return nil, false
}

func equalStrings(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

func sortedCopy(items []string) []string {
	out := append([]string{}, items...)
	sort.Strings(out)
	return out
}

// pyQuote は Python の "..." リテラルの中の書き方に直す。
func pyQuote(s string) string { return strings.ReplaceAll(s, `"`, `\"`) }

// TestRulesMatchPython は規約データが bin/check-refs.py と食い違っていないかを見る。
func TestRulesMatchPython(t *testing.T) {
	src := pythonSource(t)
	rules, err := LoadRules(repoRoot(t))
	if err != nil {
		t.Fatal(err)
	}

	lists := []struct {
		name    string
		decl    string
		close   byte
		got     []string
		unorder bool
	}{
		{"BUNDLE_REQUIRED", "BUNDLE_REQUIRED = [", ']', rules.BundleRequired, false},
		{"BUNDLE_WINDOWS_EXTRA", "BUNDLE_WINDOWS_EXTRA = [", ']', rules.BundleWindowsExtra, false},
		{"TEMPLATE_REQUIRED", "TEMPLATE_REQUIRED = [", ']', rules.TemplateRequired, false},
		{"SKIP_MARKS", "SKIP_MARKS = (", ')', rules.SkipMarks, false},
		{"BUNDLE_SKIP_ON_WINDOWS", "BUNDLE_SKIP_ON_WINDOWS = {", '}',
			keysOf(rules.BundleSkipOnWindows), true},
	}
	for _, l := range lists {
		want, ok := pyLiterals(src, l.decl, l.close)
		if !ok {
			t.Fatalf("%s を bin/check-refs.py から読み取れません", l.name)
		}
		got := l.got
		if l.unorder {
			want, got = sortedCopy(want), sortedCopy(got)
		}
		if !equalStrings(want, got) {
			t.Errorf("%s が食い違っています\nPython: %q\nJSON:   %q", l.name, want, got)
		}
	}

	patterns := map[string]string{
		"pathPattern":           `(?<![\w$.:/-])(bin|docs)/[A-Za-z0-9_*/.-]+`,
		"enginePathPattern":     `\$\(ENGINE\)/((?:bin|docs)/[A-Za-z0-9_*/.-]+)`,
		"rulePattern":           `\.claude/rules/([A-Za-z0-9_-]+\.md)`,
		"hookPattern":           `\.claude/hooks/([A-Za-z0-9_.-]+\.py)`,
		"genesisStarterPattern": `starter\s*=\s*"([^"]*)"`,
		"commentPattern":        `(^|\s)@?#.*$`,
		"echoPattern":           `\b(echo|printf)\s+("[^"]*"|'[^']*')`,
		"lastSegmentPattern":    `/[^/]+$`,
	}
	raw, err := os.ReadFile(filepath.Join(repoRoot(t), RulesPath))
	if err != nil {
		t.Fatal(err)
	}
	var doc map[string]any
	if err := json.Unmarshal(raw, &doc); err != nil {
		t.Fatal(err)
	}
	for key, want := range patterns {
		got, _ := doc[key].(string)
		if got != want {
			t.Errorf("%s が bin/check-refs.py と食い違っています\nPython: %s\nJSON:   %s", key, want, got)
		}
		if !strings.Contains(src, want) {
			t.Errorf("%s の正規表現が bin/check-refs.py に見当たりません: %s", key, want)
		}
	}

	// 一覧に出せない小さな語彙は、.py の書き方そのものを探して食い違いを見る。
	snippets := []string{
		`rstrip("` + pyQuote(rules.TrimChars) + `")`,
		`for key in ("` + strings.Join(rules.ManifestKeys, `", "`) + `"):`,
		`rel not in ("` + strings.Join(keysOf(rules.DistExempt), `", "`) + `")`,
	}
	for _, g := range rules.TemplateGlobs {
		snippets = append(snippets, `ROOT.glob("`+g+`")`)
	}
	for _, s := range keysOf(rules.EnginePathSkip) {
		snippets = append(snippets, `if rel == "`+s+`":`)
	}
	for _, s := range snippets {
		if !strings.Contains(src, s) {
			t.Errorf("bin/check-refs.py に見当たりません: %s", s)
		}
	}
}

func keysOf(m map[string]bool) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

func TestLoadRulesWithoutFile(t *testing.T) {
	if _, err := LoadRules(t.TempDir()); err == nil {
		t.Fatal("規約ファイルが無いのにエラーになりません")
	}
}

func TestLoadRulesWithBrokenJSON(t *testing.T) {
	root := t.TempDir()
	writeRules(t, root, "{ this is not json")
	if _, err := LoadRules(root); err == nil {
		t.Fatal("壊れた JSON なのにエラーになりません")
	}
}

func TestLoadRulesWithMissingKey(t *testing.T) {
	src, err := os.ReadFile(filepath.Join(repoRoot(t), RulesPath))
	if err != nil {
		t.Fatal(err)
	}
	var doc map[string]any
	if err := json.Unmarshal(src, &doc); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"bundleRequired", "templateRequired", "pathPattern", "skipMarks"} {
		kept := doc[key]
		delete(doc, key)
		data, err := json.Marshal(doc)
		if err != nil {
			t.Fatal(err)
		}
		root := t.TempDir()
		writeRules(t, root, string(data))
		if _, err := LoadRules(root); err == nil {
			t.Errorf("%s が欠けているのにエラーになりません", key)
		}
		doc[key] = kept
	}
}

// TestUnstrippableLookaroundStops は剥がし切れない先読み・後読みで止まることを見る。
func TestUnstrippableLookaroundStops(t *testing.T) {
	for _, pattern := range []string{`(?<=a)bin/x`, `bin/(?!x)y`, `a(?=b)c`} {
		if _, err := compileGuarded(pattern); err == nil {
			t.Errorf("剥がし切れない %s が黙って通りました", pattern)
		}
	}
}

func writeRules(t *testing.T, root, body string) {
	t.Helper()
	dir := filepath.Join(root, "bin", "lint-rules")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "check-refs.json"), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}
