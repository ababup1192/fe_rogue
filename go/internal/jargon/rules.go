package jargon

// 規約データ (bin/lint-rules/jargon.json) の読み込みと、
// そこに書かれた後読み・先読みを Go の正規表現で表し直す言い換え。

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"unicode/utf8"

	"github.com/ababup1192/flix_game_engine/go/internal/pxlib"
)

// RulesPath は規約データの置き場（リポジトリの根からの相対）。
var RulesPath = filepath.Join("bin", "lint-rules", "jargon.json")

type rulesFile struct {
	Words []wordEntry `json:"words"`
}

type wordEntry struct {
	Word    *string `json:"word"`
	Pattern *string `json:"pattern"`
	Better  *string `json:"better"`
	English *string `json:"english"`
	Stage   *string `json:"stage"`
}

// Rule は 1 語ぶんの規約。すべて JSON から来る。
type Rule struct {
	Word    string
	Better  string
	English string
	Stage   string
	match   *matcher
}

// Search はその行にこの語が出るかを返す。
func (r *Rule) Search(s string) bool { return r.match.Search(s) }

// prevKanjiGuard は規約データに書かれる「直前が漢字なら当てない」後読みの字面。
const prevKanjiGuard = "(?<![一-龥])"

// reMeta は先読みの中身・選択肢の字面をそのまま比べてよいかの判定に使う。
const reMeta = `[]()|\^$.*+?{}`

// matcher は規約データの正規表現を「ゆるく当てて、前後の 1 文字を自分で見て捨てる」形に
// 置き換えた物。Go の正規表現には先読み・後読みが無い。
//
// WhyNot: 先読みの文字までマッチに含めて消費する書き方にしないのは、隣り合って出る語を
// 取りこぼすため（`札札幌` の 1 つ目の札が消える）。位置だけ見て捨てれば取りこぼさない。
type matcher struct {
	re *pxlib.PyRegexp
	// noPrevKanji は直前の 1 文字が漢字なら捨てる（後読みの代わり）。
	noPrevKanji bool
	// notNext は直後の 1 文字がこの集合にあれば捨てる（先読みの代わり）。
	notNext map[rune]bool
	// notNextWhen は先読みが付いていた選択肢。空なら全部の当たりに効く。
	notNextWhen string
}

// isCJKIdeograph は文字が漢字の範囲 [一-龥] にあるかを返す。
func isCJKIdeograph(r rune) bool { return r >= 0x4E00 && r <= 0x9FA5 }

// compileGuarded は規約データの正規表現を、ゆるい正規表現と前後 1 文字の判定に分ける。
func compileGuarded(pattern string) (*matcher, error) {
	m := &matcher{}
	src := pattern
	if strings.HasPrefix(src, prevKanjiGuard) {
		src = strings.TrimPrefix(src, prevKanjiGuard)
		m.noPrevKanji = true
	}
	if head, set, when, ok := cutTrailingLookahead(src); ok {
		src, m.notNext, m.notNextWhen = head, set, when
		if strings.ContainsAny(when, reMeta) {
			return nil, fmt.Errorf("先読みの付いた選択肢が字面で比べられません: %s", pattern)
		}
	}
	if strings.Contains(src, "(?<") || strings.Contains(src, "(?!") || strings.Contains(src, "(?=") {
		return nil, fmt.Errorf("Go の正規表現に無い先読み・後読みが残っています: %s", pattern)
	}
	re, err := pxlib.CompilePy(src)
	if err != nil {
		return nil, err
	}
	m.re = re
	return m, nil
}

// cutTrailingLookahead は末尾の否定先読みを切り離して (残り, 捨てる文字, 効く選択肢) を返す。
func cutTrailingLookahead(src string) (head string, set map[rune]bool, when string, ok bool) {
	i := strings.LastIndex(src, "(?!")
	if i < 0 || !strings.HasSuffix(src, ")") {
		return "", nil, "", false
	}
	inner := src[i+3 : len(src)-1]
	if strings.HasPrefix(inner, "[") && strings.HasSuffix(inner, "]") {
		inner = inner[1 : len(inner)-1]
	}
	if inner == "" || strings.ContainsAny(inner, reMeta) {
		return "", nil, "", false
	}
	set = map[rune]bool{}
	for _, r := range inner {
		set[r] = true
	}
	head = src[:i]
	// 先読みは最後の選択肢だけに付いている（`降ろす|降ろさ|降ろし(?!物)`）。
	if j := strings.LastIndex(head, "|"); j >= 0 {
		when = head[j+1:]
	}
	return head, set, when, true
}

// Search は行のどこかにこの語が出るかを返す。
func (m *matcher) Search(s string) bool {
	for pos := 0; pos <= len(s); {
		start, end, found := m.re.FindIndexFrom(s, pos)
		if !found {
			return false
		}
		if m.accept(s, start, end) {
			return true
		}
		// 捨てた当たりの 1 文字先から探し直す（消費すると隣り合う語を取りこぼす）。
		_, size := utf8.DecodeRuneInString(s[start:])
		if size <= 0 {
			size = 1
		}
		pos = start + size
	}
	return false
}

// accept は前後 1 文字の判定。
func (m *matcher) accept(s string, start, end int) bool {
	if m.noPrevKanji && start > 0 {
		r, _ := utf8.DecodeLastRuneInString(s[:start])
		if isCJKIdeograph(r) {
			return false
		}
	}
	if len(m.notNext) > 0 && end < len(s) {
		if m.notNextWhen == "" || s[start:end] == m.notNextWhen {
			r, _ := utf8.DecodeRuneInString(s[end:])
			if m.notNext[r] {
				return false
			}
		}
	}
	return true
}

// LoadRules は規約データを読む。
// WhyNot: 読めないときに既定値へ落とさないのは、規約ファイルを消しただけで
// 検査が何も知らせずに緑になる穴を作らないため。呼ぶ側は必ずエラーで止める。
func LoadRules(root string) ([]*Rule, error) {
	path := filepath.Join(root, RulesPath)
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("規約ファイルを読めません: %v", err)
	}
	var f rulesFile
	if err := json.Unmarshal(data, &f); err != nil {
		return nil, fmt.Errorf("規約ファイルが JSON として壊れています (%s): %v", path, err)
	}
	if len(f.Words) == 0 {
		return nil, fmt.Errorf("規約ファイルに words がありません (%s)", path)
	}
	rules := make([]*Rule, 0, len(f.Words))
	for i, w := range f.Words {
		missing := ""
		switch {
		case w.Word == nil:
			missing = "word"
		case w.Better == nil:
			missing = "better"
		case w.English == nil:
			missing = "english"
		case w.Stage == nil:
			missing = "stage"
		}
		if missing != "" {
			return nil, fmt.Errorf("規約ファイルの %d 語目に %s がありません (%s)", i+1, missing, path)
		}
		if *w.Stage != "error" && *w.Stage != "warn" {
			return nil, fmt.Errorf("規約ファイルの「%s」の stage が error でも warn でもありません (%s)", *w.Word, path)
		}
		rule, err := newRule(*w.Word, w.Pattern, *w.Better, *w.English, *w.Stage)
		if err != nil {
			return nil, fmt.Errorf("規約ファイルの「%s」の pattern が使えません (%s): %v", *w.Word, path, err)
		}
		rules = append(rules, rule)
	}
	return rules, nil
}

// newRule は 1 語ぶんの規約を組み立てる。pattern が無ければ語をそのまま探す。
func newRule(word string, pattern *string, better, english, stage string) (*Rule, error) {
	src := escapeLiteral(word)
	if pattern != nil {
		src = *pattern
	}
	m, err := compileGuarded(src)
	if err != nil {
		return nil, err
	}
	return &Rule{Word: word, Better: better, English: english, Stage: stage, match: m}, nil
}

// escapeLiteral は文字列を、正規表現の中で字面どおりに当たる形へ逃がす。
func escapeLiteral(s string) string {
	var b strings.Builder
	for _, r := range s {
		if r < utf8.RuneSelf && strings.ContainsRune("()[]{}?*+-|^$\\.&~# \t\n\r\v\f", r) {
			b.WriteByte('\\')
		}
		b.WriteRune(r)
	}
	return b.String()
}
