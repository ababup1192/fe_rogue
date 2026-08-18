package fallback

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// 何を見るか: 規約データ (bin/lint-rules/fallback.json) が検査の期待する形か。
// WhyNot: 目視の約束にしないのは、規約データを直したときに検査が古い判定のまま
// 緑を出すため。

var pyLiteral = regexp.MustCompile(`"([^"]*)"`)

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

func TestLoadRulesFromRepo(t *testing.T) {
	rules, err := LoadRules(repoRoot())
	if err != nil {
		t.Fatal(err)
	}
	if len(rules.Exempt) != len(rules.ExemptKeys) {
		t.Errorf("除外の鍵が重複している: %d / %d", len(rules.ExemptKeys), len(rules.Exempt))
	}
	if !sortedAsc(rules.ExemptKeys) {
		t.Errorf("除外の鍵が並んでいない: %v", rules.ExemptKeys)
	}
	if m := rules.Def.FindStringSubmatch("    pub def loadThing(x: Int): Int ="); m == nil || m[1] != "loadThing" {
		t.Errorf("def の関数名を拾えていない: %v", m)
	}
}

func sortedAsc(v []string) bool {
	for i := 1; i < len(v); i++ {
		if v[i-1] > v[i] {
			return false
		}
	}
	return true
}

func TestMissingRulesFileAborts(t *testing.T) {
	var out, errOut strings.Builder
	code, err := Run(&out, &errOut, t.TempDir(), nil)
	if err == nil {
		t.Fatal("規約ファイルが無いのにエラーを返さなかった")
	}
	if code == 0 {
		t.Errorf("規約ファイルが無いのに終了コード 0")
	}
	if out.String() != "" {
		t.Errorf("規約が読めないのに何か出力した: %q", out.String())
	}
}

func TestBrokenRulesFileAborts(t *testing.T) {
	cases := map[string]string{
		"JSON が壊れている": "{",
		"鍵が欠けている":     `{"srcRoots": ["a/src"], "bugPattern": "x"}`,
		"正規表現が壊れている":  `{"srcRoots": [], "bugPattern": "(", "defPattern": "x", "stringPattern": "y", "exempt": {}}`,
	}
	for name, body := range cases {
		root := t.TempDir()
		path := filepath.Join(root, RulesPath)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
		var out, errOut strings.Builder
		if _, err := Run(&out, &errOut, root, nil); err == nil {
			t.Errorf("%s のに受け入れてしまった", name)
		}
	}
}
