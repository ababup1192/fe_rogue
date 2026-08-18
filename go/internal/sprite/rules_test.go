package sprite

// 規約データの読み込みが「黙って既定値へ倒れない」ことと、
// 正本 (bin/lint-sprite.py) と値がずれていないことを縛る。

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

func repoRoot(t *testing.T) string {
	t.Helper()
	root, err := filepath.Abs(filepath.Join("..", "..", ".."))
	if err != nil {
		t.Fatalf("リポジトリの根を求められない: %v", err)
	}
	return root
}

func TestLoadRulesMissingFile(t *testing.T) {
	_, err := LoadRules(t.TempDir())
	if err == nil {
		t.Fatal("規約ファイルが無いのにエラーにならない (既定値へ倒れている)")
	}
}

func TestLoadRulesMissingKey(t *testing.T) {
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, "bin", "lint-rules"), 0o755); err != nil {
		t.Fatal(err)
	}
	body := `{"rules":["structure"],"transparentChars":["."],"excludedDirs":["build"],"maxColors":12}`
	if err := os.WriteFile(filepath.Join(root, RulesPath), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	_, err := LoadRules(root)
	if err == nil {
		t.Fatal("キーが欠けているのにエラーにならない")
	}
	if !strings.Contains(err.Error(), "maxColorsBig") {
		t.Fatalf("欠けているキーの名前が出ない: %v", err)
	}
}

func TestLoadRulesBrokenJSON(t *testing.T) {
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, "bin", "lint-rules"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, RulesPath), []byte("{"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadRules(root); err == nil {
		t.Fatal("壊れた JSON なのにエラーにならない")
	}
}

// TestRulesMatchPython は bin/lint-sprite.py の定数と JSON がずれたら落ちる。
func TestRulesMatchPython(t *testing.T) {
	root := repoRoot(t)
	src, err := os.ReadFile(filepath.Join(root, "bin", "lint-sprite.py"))
	if err != nil {
		t.Fatalf("正本を読めない: %v", err)
	}
	python := string(src)
	rules, err := LoadRules(root)
	if err != nil {
		t.Fatalf("規約を読めない: %v", err)
	}

	numOf := func(name string) string {
		re := regexp.MustCompile(`(?m)^` + name + ` = ([0-9.]+)`)
		m := re.FindStringSubmatch(python)
		if m == nil {
			t.Fatalf("正本に %s が無い", name)
		}
		return m[1]
	}
	// JSON 側の値も同じ字面で読み出して、丸めの差を挟まずに比べる。
	var raw map[string]json.RawMessage
	data, err := os.ReadFile(filepath.Join(root, RulesPath))
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(data, &raw); err != nil {
		t.Fatal(err)
	}
	for jsonKey, pyName := range map[string]string{
		"maxColors":        "MAX_COLORS",
		"maxColorsBig":     "MAX_COLORS_BIG",
		"bigSide":          "BIG_SIDE",
		"textureFill":      "TEXTURE_FILL",
		"minOrphanCells":   "MIN_ORPHAN_CELLS",
		"minConnectCells":  "MIN_CONNECT_CELLS",
		"connectShown":     "CONNECT_SHOWN",
		"jaggyMinCount":    "JAGGY_MIN_COUNT",
		"bandingMinRun":    "BANDING_MIN_RUN",
		"silhouetteMinOcc": "SILHOUETTE_MIN_OCC",
		"deltaEMin":        "DELTA_E_MIN",
	} {
		got := strings.TrimSpace(string(raw[jsonKey]))
		if want := numOf(pyName); got != want {
			t.Errorf("%s が正本 (%s = %s) とずれている: %s", jsonKey, pyName, want, got)
		}
	}

	wantRules := []string{"structure", "orphan", "connect", "palette", "jaggy", "banding", "corner", "silhouette"}
	for _, name := range wantRules {
		if !strings.Contains(python, `"`+name+`"`) {
			t.Errorf("正本に規則 %s が無い", name)
		}
	}
	if strings.Join(rules.RuleNames, ",") != strings.Join(wantRules, ",") {
		t.Errorf("規則の並びが正本とずれている: %v", rules.RuleNames)
	}

	for _, dir := range []string{"build", "lib", ".git", "gallery", ".devbox", "node_modules", "testdata"} {
		if !rules.ExcludedDirs[dir] {
			t.Errorf("excludedDirs に %s が無い", dir)
		}
	}
	if len(rules.ExcludedDirs) != 7 {
		t.Errorf("excludedDirs の数が正本 (7) と違う: %d", len(rules.ExcludedDirs))
	}
	if !rules.TransparentChars['.'] || !rules.TransparentChars[' '] || len(rules.TransparentChars) != 2 {
		t.Errorf("transparentChars が正本 {\".\", \" \"} とずれている: %v", rules.TransparentChars)
	}
	if !strings.Contains(python, `re.search(r"対象外\s*(?:\(([^)]*)\))?", value)`) {
		t.Error("正本の除外記法の正規表現が変わっている (exemptPattern を見直す)")
	}
	if !strings.Contains(python, `re.sub(r"^\s*\([^)]*\)", "", tail)`) {
		t.Error("正本の括弧落としの正規表現が変わっている (exemptParenPattern を見直す)")
	}
}

// TestExemptPatternIsUnicodeAware は Python の \s (Unicode) を写せているかを見る。
func TestExemptPatternIsUnicodeAware(t *testing.T) {
	rules, err := LoadRules(repoRoot(t))
	if err != nil {
		t.Fatalf("規約を読めない: %v", err)
	}
	got, ok := rules.exemptOf("対象外　(orphan)　全角空白を挟んだ書き方")
	if !ok {
		t.Fatal("全角空白を挟むと除外記法を読めない")
	}
	if !got.rules["orphan"] || len(got.rules) != 1 {
		t.Fatalf("規則の絞り込みが効いていない: %v", got.rules)
	}
	if got.reason != "全角空白を挟んだ書き方" {
		t.Fatalf("理由の切り出しがずれている: %q", got.reason)
	}
}
