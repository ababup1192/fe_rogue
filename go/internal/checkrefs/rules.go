package checkrefs

// 規約データ (bin/lint-rules/check-refs.json) の読み込みと、そこに書かれた
// 後読み・先読み・Unicode を広く見る \s \b \w を Go の正規表現で表し直す言い換え。

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/ababup1192/flix_game_engine/go/internal/pxlib"
)

// RulesPath は規約データの置き場（リポジトリのルートからの相対）。
var RulesPath = filepath.Join("bin", "lint-rules", "check-refs.json")

// pySpaceClass は規約データの \s が指す広い範囲。
// Go の \s は [\t\n\f\r ] しか含まないので、\v (0x0b)・\x1c-\x1f・\x85・
// Unicode の Z 類を書き足す。全角空白でインデントした行を空白と数えるために要る。
const pySpaceClass = `[\s\v\x{1c}-\x{1f}\x{85}\p{Z}]`

// reMeta は後読みの中身を字面として読んでよいかの判定に使う。
const reMeta = `[]()|\^$*+?{}`

// matcher は規約データの正規表現を「ゆるく当てて、前後の 1 文字を Go 側で見て捨てる」形に
// 置き換えた物。
//
// WhyNot: 先読み・後読みの文字までマッチに含めて消費する書き方にしないのは、隣り合って
// 出る語を取りこぼすため（`-docs/*bin/y` の `bin/y` が消える）。位置だけ見て捨てれば
// 取りこぼさない。
type matcher struct {
	re *pxlib.PyRegexp
	// sub は同じゆるい正規表現の素の形。丸括弧の中身を取り出すためだけに使う。
	sub *regexp.Regexp
	// notPrevWord は直前の 1 文字が語の文字なら捨てる（Unicode の \b・\w 後読みの代わり）。
	notPrevWord bool
	// notPrev は直前の 1 文字がこの集合にあれば捨てる（後読みの代わり）。
	notPrev map[rune]bool
	// notNext は直後の 1 文字がこの集合にあれば捨てる（先読みの代わり）。
	notNext map[rune]bool
	// notNextWhen は先読みが付いていた選択肢。空なら全部の当たりに効く。
	notNextWhen string
}

// isPyWord は語の文字か（Unicode の文字・数字・下線）。
func isPyWord(r rune) bool { return r == '_' || unicode.IsLetter(r) || unicode.IsDigit(r) }

// widenPySpace は \s を上の広い範囲へ書き換える。
func widenPySpace(pattern string) string {
	return strings.ReplaceAll(pattern, `\s`, pySpaceClass)
}

// compileGuarded は規約データの正規表現を、ゆるい正規表現と前後 1 文字の判定に分ける。
func compileGuarded(pattern string) (*matcher, error) {
	m := &matcher{}
	src := widenPySpace(pattern)
	if head, set, word, ok := cutLeadingLookbehind(src); ok {
		src, m.notPrev, m.notPrevWord = head, set, word
	}
	if strings.HasPrefix(src, `\b`) {
		src, m.notPrevWord = strings.TrimPrefix(src, `\b`), true
	}
	if head, set, when, ok := cutTrailingLookahead(src); ok {
		if strings.ContainsAny(when, reMeta) {
			return nil, fmt.Errorf("先読みの付いた選択肢が字面で比べられません: %s", pattern)
		}
		src, m.notNext, m.notNextWhen = head, set, when
	}
	if strings.Contains(src, "(?<") || strings.Contains(src, "(?!") || strings.Contains(src, "(?=") {
		return nil, fmt.Errorf("Go の正規表現に無い先読み・後読みが残っています: %s", pattern)
	}
	re, err := pxlib.CompilePy(src)
	if err != nil {
		return nil, err
	}
	sub, err := regexp.Compile(widenPyWord(src))
	if err != nil {
		return nil, err
	}
	m.re, m.sub = re, sub
	return m, nil
}

// widenPyWord は \w を Unicode の文字・数字・下線へ広げる（pxlib.CompilePy と同じ形）。
func widenPyWord(pattern string) string {
	return strings.ReplaceAll(pattern, `\w`, `[\p{L}\p{N}_]`)
}

// cutLeadingLookbehind は先頭の否定後読み `(?<![...])` を切り離して
// (残り, 捨てる文字, 語の文字も捨てるか) を返す。
func cutLeadingLookbehind(src string) (head string, set map[rune]bool, word bool, ok bool) {
	if !strings.HasPrefix(src, "(?<![") {
		return "", nil, false, false
	}
	end := strings.Index(src, "])")
	if end < 0 {
		return "", nil, false, false
	}
	inner, rest := src[len("(?<!["):end], src[end+2:]
	set = map[rune]bool{}
	runes := []rune(inner)
	for i := 0; i < len(runes); i++ {
		r := runes[i]
		if r == '\\' && i+1 < len(runes) {
			i++
			switch runes[i] {
			case 'w':
				word = true
			case 's':
				return "", nil, false, false
			default:
				set[runes[i]] = true
			}
			continue
		}
		// WhyNot: 途中の - を字面として扱わないのは、そこだけ範囲指定の意味になり、
		// 黙って別の集合を作ってしまうため。読めない形は当てずに諦める。
		if r == '-' && i != 0 && i != len(runes)-1 {
			return "", nil, false, false
		}
		// 文字集合の中で意味を持つのは先頭の ^ だけ（] は切り出しで先に当たる）。
		if r == '^' && i == 0 {
			return "", nil, false, false
		}
		set[r] = true
	}
	return rest, set, word, true
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
	// 先読みは最後の選択肢だけに付いている（`降ろす jargon-ok: 検査するルールの書き方そのものを説明している|降ろさ|降ろし(?!物)`）。
	if j := strings.LastIndex(head, "|"); j >= 0 {
		when = head[j+1:]
	}
	return head, set, when, true
}

// accept は前後 1 文字の判定。
func (m *matcher) accept(s string, start, end int) bool {
	if (m.notPrevWord || len(m.notPrev) > 0) && start > 0 {
		r, _ := utf8.DecodeLastRuneInString(s[:start])
		if m.notPrevWord && isPyWord(r) {
			return false
		}
		if m.notPrev[r] {
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

// span は当たった範囲（バイト位置）。
type span struct{ start, end int }

// FindAll は前から順に当たりを返す。
//
// WhyNot: 捨てた当たりを飛ばさず「1 文字先」から探し直すのは、捨てた当たりの内側から
// 始まる次の当たりを取りこぼさないため。
func (m *matcher) FindAll(s string) []span {
	var found []span
	for pos := 0; pos <= len(s); {
		start, end, ok := m.re.FindIndexFrom(s, pos)
		if !ok {
			break
		}
		if m.accept(s, start, end) {
			found = append(found, span{start, end})
			if end == start {
				pos = end + 1
			} else {
				pos = end
			}
			continue
		}
		_, size := utf8.DecodeRuneInString(s[start:])
		if size <= 0 {
			size = 1
		}
		pos = start + size
	}
	return found
}

// Group1 は 1 番目の丸括弧の中身を返す。
func (m *matcher) Group1(s string, sp span) string {
	loc := m.sub.FindStringSubmatchIndex(s[sp.start:])
	if loc == nil || len(loc) < 4 || loc[2] < 0 {
		return ""
	}
	return s[sp.start+loc[2] : sp.start+loc[3]]
}

// Rules は検査が使う規約。すべて JSON から来る。
type Rules struct {
	BundleRequired      []string
	BundleSkipOnWindows map[string]bool
	BundleWindowsExtra  []string
	TemplateRequired    []string
	SkipMarks           []string
	TrimChars           string
	ManifestKeys        []string
	TemplateGlobs       []string
	EnginePathSkip      map[string]bool
	DistExempt          map[string]bool

	Path           *matcher
	EnginePath     *matcher
	Rule           *matcher
	Hook           *matcher
	GenesisStarter *matcher
	Comment        *regexp.Regexp
	LastSegment    *regexp.Regexp
	Echo           *matcher
}

type rulesFile struct {
	BundleRequired        *[]string `json:"bundleRequired"`
	BundleSkipOnWindows   *[]string `json:"bundleSkipOnWindows"`
	BundleWindowsExtra    *[]string `json:"bundleWindowsExtra"`
	TemplateRequired      *[]string `json:"templateRequired"`
	SkipMarks             *[]string `json:"skipMarks"`
	TrimChars             *string   `json:"trimChars"`
	ManifestKeys          *[]string `json:"manifestKeys"`
	TemplateGlobs         *[]string `json:"templateGlobs"`
	EnginePathSkip        *[]string `json:"enginePathSkip"`
	DistExempt            *[]string `json:"distExempt"`
	PathPattern           *string   `json:"pathPattern"`
	EnginePathPattern     *string   `json:"enginePathPattern"`
	RulePattern           *string   `json:"rulePattern"`
	HookPattern           *string   `json:"hookPattern"`
	GenesisStarterPattern *string   `json:"genesisStarterPattern"`
	CommentPattern        *string   `json:"commentPattern"`
	LastSegmentPattern    *string   `json:"lastSegmentPattern"`
	EchoPattern           *string   `json:"echoPattern"`
}

// LoadRules は規約データを読む。
// WhyNot: 読めないときに既定値へ落とさないのは、規約ファイルを消しただけで検査の意味が
// 静かに変わる穴を作らないため。呼ぶ側は必ずエラーで止める。
func LoadRules(root string) (*Rules, error) {
	path := filepath.Join(root, RulesPath)
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("規約ファイルを読めません: %v", err)
	}
	var f rulesFile
	if err := json.Unmarshal(data, &f); err != nil {
		return nil, fmt.Errorf("規約ファイルが JSON として壊れています (%s): %v", path, err)
	}
	lists := []struct {
		name string
		p    *[]string
	}{
		{"bundleRequired", f.BundleRequired},
		{"bundleSkipOnWindows", f.BundleSkipOnWindows},
		{"bundleWindowsExtra", f.BundleWindowsExtra},
		{"templateRequired", f.TemplateRequired},
		{"skipMarks", f.SkipMarks},
		{"manifestKeys", f.ManifestKeys},
		{"templateGlobs", f.TemplateGlobs},
		{"enginePathSkip", f.EnginePathSkip},
		{"distExempt", f.DistExempt},
	}
	for _, l := range lists {
		if l.p == nil {
			return nil, fmt.Errorf("規約ファイルに %s がありません (%s)", l.name, path)
		}
	}
	pats := []struct {
		name string
		p    *string
	}{
		{"trimChars", f.TrimChars},
		{"pathPattern", f.PathPattern},
		{"enginePathPattern", f.EnginePathPattern},
		{"rulePattern", f.RulePattern},
		{"hookPattern", f.HookPattern},
		{"genesisStarterPattern", f.GenesisStarterPattern},
		{"commentPattern", f.CommentPattern},
		{"lastSegmentPattern", f.LastSegmentPattern},
		{"echoPattern", f.EchoPattern},
	}
	for _, p := range pats {
		if p.p == nil {
			return nil, fmt.Errorf("規約ファイルに %s がありません (%s)", p.name, path)
		}
	}
	if len(*f.BundleRequired) == 0 {
		return nil, fmt.Errorf("規約ファイルの bundleRequired が空です (%s)", path)
	}
	if len(*f.TemplateRequired) == 0 {
		return nil, fmt.Errorf("規約ファイルの templateRequired が空です (%s)", path)
	}
	r := &Rules{
		BundleRequired:      *f.BundleRequired,
		BundleSkipOnWindows: setOf(*f.BundleSkipOnWindows),
		BundleWindowsExtra:  *f.BundleWindowsExtra,
		TemplateRequired:    *f.TemplateRequired,
		SkipMarks:           *f.SkipMarks,
		TrimChars:           *f.TrimChars,
		ManifestKeys:        *f.ManifestKeys,
		TemplateGlobs:       *f.TemplateGlobs,
		EnginePathSkip:      setOf(*f.EnginePathSkip),
		DistExempt:          setOf(*f.DistExempt),
	}
	built := []struct {
		name string
		src  string
		dst  **matcher
	}{
		{"pathPattern", *f.PathPattern, &r.Path},
		{"enginePathPattern", *f.EnginePathPattern, &r.EnginePath},
		{"rulePattern", *f.RulePattern, &r.Rule},
		{"hookPattern", *f.HookPattern, &r.Hook},
		{"genesisStarterPattern", *f.GenesisStarterPattern, &r.GenesisStarter},
		{"echoPattern", *f.EchoPattern, &r.Echo},
	}
	for _, b := range built {
		m, err := compileGuarded(b.src)
		if err != nil {
			return nil, fmt.Errorf("規約ファイルの %s が使えません (%s): %v", b.name, path, err)
		}
		*b.dst = m
	}
	comment, err := regexp.Compile(widenPySpace(*f.CommentPattern))
	if err != nil {
		return nil, fmt.Errorf("規約ファイルの commentPattern が使えません (%s): %v", path, err)
	}
	r.Comment = comment
	lastSeg, err := regexp.Compile(widenPySpace(*f.LastSegmentPattern))
	if err != nil {
		return nil, fmt.Errorf("規約ファイルの lastSegmentPattern が使えません (%s): %v", path, err)
	}
	r.LastSegment = lastSeg
	return r, nil
}

func setOf(items []string) map[string]bool {
	out := map[string]bool{}
	for _, s := range items {
		out[s] = true
	}
	return out
}
