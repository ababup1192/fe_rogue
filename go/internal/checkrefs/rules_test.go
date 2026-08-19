package checkrefs

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"testing"
)

// repoRoot はこのテストから見たリポジトリのルート。
func repoRoot(t *testing.T) string {
	t.Helper()
	wd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	root := filepath.Join(wd, "..", "..", "..")
	if _, err := os.Stat(filepath.Join(root, "bin", "lint-rules", "check-refs.json")); err != nil {
		t.Fatalf("リポジトリのルートが見つかりません: %v", err)
	}
	return root
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
