package fallback

// 規約データ (bin/lint-rules/fallback.json) の読み込み。

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"unicode/utf8"

	"github.com/ababup1192/flix_game_engine/go/internal/pxlib"
)

// RulesPath は規約データの置き場（リポジトリの根からの相対）。
var RulesPath = filepath.Join("bin", "lint-rules", "fallback.json")

// pySpaceClass は規約データの `\s` が指す広い文字集合 (Unicode の空白すべて)。
//
// WhyNot: Go の `\s` をそのまま使わないのは、Go が [\t\n\f\r ] だけを空白とみなし、
// 全角空白や NBSP でインデントを書いた行を見落とすため。
const pySpaceClass = `[\t\n\v\f\r \x{1c}-\x{1f}\x{85}\p{Z}]`

type rulesFile struct {
	SrcRoots      []string          `json:"srcRoots"`
	BugPattern    *string           `json:"bugPattern"`
	DefPattern    *string           `json:"defPattern"`
	StringPattern *string           `json:"stringPattern"`
	Exempt        map[string]string `json:"exempt"`
}

// Rules は検査が使う規約。すべて JSON から来る。
type Rules struct {
	SrcRoots   []string
	Exempt     map[string]string
	ExemptKeys []string // 出力に使う並び (Exempt のキーを名前順に並べた物)
	Bug        *pyWordRe
	Def        *regexp.Regexp
	String     *regexp.Regexp
}

// pyWordRe は先頭の `\b` を Unicode の語境界として扱う正規表現。
//
// WhyNot: Go の `\b` をそのまま使わないのは、Go の語が ASCII 限定なため。
// `あbug!` は語の途中なのに、Go の `\b` は語の始まりと数えて拾ってしまう。
type pyWordRe struct {
	re     *pxlib.PyRegexp
	leadWB bool
}

func compilePyWord(pattern string) (*pyWordRe, error) {
	body, leadWB := pattern, false
	if strings.HasPrefix(body, `\b`) {
		body, leadWB = body[2:], true
	}
	re, err := pxlib.CompilePy(strings.ReplaceAll(body, `\s`, pySpaceClass))
	if err != nil {
		return nil, err
	}
	return &pyWordRe{re: re, leadWB: leadWB}, nil
}

// Search は文字列のどこかに当たりがあるか。
func (p *pyWordRe) Search(s string) bool {
	for pos := 0; pos <= len(s); {
		start, _, ok := p.re.FindIndexFrom(s, pos)
		if !ok {
			return false
		}
		if p.leadWB && isPyWordBefore(s, start) {
			pos = start + 1
			continue
		}
		return true
	}
	return false
}

func isPyWordBefore(s string, i int) bool {
	if i <= 0 {
		return false
	}
	r, _ := utf8.DecodeLastRuneInString(s[:i])
	return isPyWordRune(r)
}

// compilePyRaw は規約データの正規表現の \s \w を Unicode の広い範囲へ書き換えて組み立てる。
func compilePyRaw(pattern string) (*regexp.Regexp, error) {
	src := strings.ReplaceAll(pattern, `\s`, pySpaceClass)
	src = strings.ReplaceAll(src, `\w`, `[\p{L}\p{N}_]`)
	return regexp.Compile(src)
}

// LoadRules は規約データを読む。
// WhyNot: 読めないときに既定値へ倒さないのは、規約ファイルを消しただけで
// 検査が黙って緑になる穴を作らないため。呼ぶ側は必ずエラーで止める。
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
	missing := ""
	switch {
	case f.SrcRoots == nil:
		missing = "srcRoots"
	case f.BugPattern == nil:
		missing = "bugPattern"
	case f.DefPattern == nil:
		missing = "defPattern"
	case f.StringPattern == nil:
		missing = "stringPattern"
	case f.Exempt == nil:
		missing = "exempt"
	}
	if missing != "" {
		return nil, fmt.Errorf("規約ファイルに %s がありません (%s)", missing, path)
	}
	bug, err := compilePyWord(*f.BugPattern)
	if err != nil {
		return nil, fmt.Errorf("規約ファイルの bugPattern が正規表現として壊れています (%s): %v", path, err)
	}
	def, err := compilePyRaw(*f.DefPattern)
	if err != nil {
		return nil, fmt.Errorf("規約ファイルの defPattern が正規表現として壊れています (%s): %v", path, err)
	}
	str, err := compilePyRaw(*f.StringPattern)
	if err != nil {
		return nil, fmt.Errorf("規約ファイルの stringPattern が正規表現として壊れています (%s): %v", path, err)
	}
	keys := make([]string, 0, len(f.Exempt))
	for k := range f.Exempt {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return &Rules{
		SrcRoots:   f.SrcRoots,
		Exempt:     f.Exempt,
		ExemptKeys: keys,
		Bug:        bug,
		Def:        def,
		String:     str,
	}, nil
}
