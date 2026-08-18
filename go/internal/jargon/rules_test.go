package jargon

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// 正本は bin/lint-jargon.py の WORDS。JSON がそこからずれていないかを機械で見る。
// WhyNot: 目視の約束にしないのは、語を Python 側だけ直したときに Go 版だけが
// 古い語彙のまま緑を出すため。

// repoRoot はテストから見たリポジトリの根 (go/internal/jargon の 3 つ上)。
func repoRoot() string { return filepath.Join("..", "..", "..") }

// pythonWords は bin/lint-jargon.py の WORDS = [ ... ] の中身を返す。
func pythonWords(t *testing.T) string {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(repoRoot(), "bin", "lint-jargon.py"))
	if err != nil {
		t.Fatal(err)
	}
	src := string(data)
	head := strings.Index(src, "WORDS = [")
	if head < 0 {
		t.Fatal("bin/lint-jargon.py に WORDS が無い")
	}
	rest := src[head:]
	tail := strings.Index(rest, "\n]")
	if tail < 0 {
		t.Fatal("bin/lint-jargon.py の WORDS の閉じ括弧が見つからない")
	}
	return rest[:tail]
}

func loadJSONWords(t *testing.T) rulesFile {
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
	block := pythonWords(t)
	f := loadJSONWords(t)
	entries := strings.Count(block, `, "error"),`) + strings.Count(block, `, "warn"),`)
	if len(f.Words) != entries {
		t.Fatalf("語の数が %d (bin/lint-jargon.py は %d)", len(f.Words), entries)
	}
	for _, w := range f.Words {
		head := `("` + *w.Word + `", None,`
		if w.Pattern != nil {
			head = `("` + *w.Word + `", r"` + *w.Pattern + `",`
		}
		if !strings.Contains(block, head) {
			t.Errorf("bin/lint-jargon.py に無い語か見つけ方: %s", head)
		}
		for _, lit := range []string{*w.Better, *w.English, *w.Stage} {
			if !strings.Contains(block, `"`+lit+`"`) {
				t.Errorf("「%s」の %q が bin/lint-jargon.py に無い", *w.Word, lit)
			}
		}
	}
}

func TestLoadRulesFromRepo(t *testing.T) {
	rules, err := LoadRules(repoRoot())
	if err != nil {
		t.Fatal(err)
	}
	if len(rules) != 33 {
		t.Fatalf("語が %d 個 (期待 33)", len(rules))
	}
	stopped := 0
	for _, r := range rules {
		if r.Stage == "error" {
			stopped++
		}
	}
	if stopped != 14 {
		t.Errorf("止める語が %d 個 (期待 14)", stopped)
	}
}

// ruleOf は語で 1 本引く。
func ruleOf(t *testing.T, word string) *Rule {
	t.Helper()
	rules, err := LoadRules(repoRoot())
	if err != nil {
		t.Fatal(err)
	}
	for _, r := range rules {
		if r.Word == word {
			return r
		}
	}
	t.Fatalf("「%s」が規約に無い", word)
	return nil
}

// 後読み・先読みの言い換えが効いているか。ここが Go の正規表現で唯一書き換えた所。
func TestGuards(t *testing.T) {
	cases := []struct {
		word string
		text string
		want bool
	}{
		{"器", "この器を洗う", true},
		{"器", "楽器は正常に鳴った", false},
		{"器", "器", false},
		{"札", "札を出す", true},
		{"札", "札幌に出張する", false},
		{"札", "改札を抜ける", false},
		{"札", "札", true},
		{"降ろす", "案を降ろす", true},
		{"降ろす", "案を降ろさない", true},
		{"降ろす", "案を降ろした", true},
		{"降ろす", "棚から降ろし物を確認する", false},
		{"拍", "この曲は8拍で区切る", true},
		{"拍", "観客の拍手が鳴り止まない", false},
		{"拍", "拍車をかける", false},
		{"拍", "脈拍を測る", false},
	}
	for _, c := range cases {
		if got := ruleOf(t, c.word).Search(c.text); got != c.want {
			t.Errorf("「%s」が %q で %v (期待 %v)", c.word, c.text, got, c.want)
		}
	}
}

// 先読みの文字を消費すると、隣り合って出た語を取りこぼす。
func TestAdjacentWordsAreNotSwallowed(t *testing.T) {
	cases := []struct{ word, text string }{
		{"札", "札札幌"},
		{"拍", "拍拍手"},
		{"降ろす", "降ろし物を降ろす"},
		{"器", "楽器は器を持つ"},
	}
	for _, c := range cases {
		if !ruleOf(t, c.word).Search(c.text) {
			t.Errorf("「%s」が %q を取りこぼした", c.word, c.text)
		}
	}
}

func TestEscapeLiteralMatchesPython(t *testing.T) {
	if got := escapeLiteral("a.b*c"); got != `a\.b\*c` {
		t.Errorf("escapeLiteral が %q", got)
	}
	if got := escapeLiteral("関所"); got != "関所" {
		t.Errorf("漢字を escape してしまった: %q", got)
	}
}

func TestMissingRulesFileAborts(t *testing.T) {
	if _, err := LoadRules(t.TempDir()); err == nil {
		t.Fatal("規約ファイルが無いのにエラーを返さなかった")
	}
}

func TestBrokenRulesFileAborts(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, RulesPath)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	body := `{"words": [{"word": "x", "pattern": null, "better": "y", "english": "z"}]}`
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadRules(root); err == nil {
		t.Fatal("stage の無い語を受け入れてしまった")
	}
}

func TestUnsupportedLookaroundIsRejected(t *testing.T) {
	if _, err := compileGuarded(`あ(?<!い)う`); err == nil {
		t.Fatal("途中の後読みを受け入れてしまった")
	}
}
