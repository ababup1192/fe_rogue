package uioverflow

import (
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"
)

// 判定の値は JSON の規約ファイルが正本。その形が崩れていないかを機械で見る。
// WhyNot: 目視の約束にしないのは、規約が欠けたり壊れたりしたまま
// 検査だけが緑を出すため。

var pyLiteral = regexp.MustCompile(`"([^"]*)"`)

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
		"鍵が欠けている":     `{"gameRoots": ["templates"], "excludedDirs": []}`,
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

func TestExcludedDirsAreSorted(t *testing.T) {
	rules, err := LoadRules(repoRoot())
	if err != nil {
		t.Fatal(err)
	}
	if !sort.StringsAreSorted(rules.ExcludedDirs) {
		t.Errorf("除外ディレクトリが並んでいない: %v", rules.ExcludedDirs)
	}
}
