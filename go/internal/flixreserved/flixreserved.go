// Package flixreserved は、Flix の予約語を識別子に使っていないかを見る。
//
// 踏むと Flix はパースで止まらず、壊れた構文木のまま型検査へ進んで発散する。
// 画面には赤も警告も出ず、ただ終わらない。人が読む決まりでは守れないので、
// 保存時とコミット時に機械で止める。
package flixreserved

import (
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"sort"
	"strings"
)

// Hit は 1 件の違反。
type Hit struct {
	Path string
	Line int
	Word string
	Kind string
	Hint string
}

// 識別子が置かれる場所。それぞれ「名前が来るはずの位置」だけを見る。
var (
	letPat   = regexp.MustCompile(`(?:^|[\s({;])let\s+([A-Za-z_][A-Za-z0-9_]*)\s*=`)
	defPat   = regexp.MustCompile(`\bdef\s+([A-Za-z_][A-Za-z0-9_]*)\s*[(\[]`)
	fieldPat = regexp.MustCompile(`[{,]\s*([A-Za-z_][A-Za-z0-9_]*)\s*=`)
	paramPat = regexp.MustCompile(`[(,]\s*([A-Za-z_][A-Za-z0-9_]*)\s*:`)
)

// FileHits は指定したファイルだけを見る。
func (r *Rules) FileHits(root string, paths []string) []Hit {
	var hits []Hit
	for _, p := range paths {
		if !r.IsFlix(p) {
			continue
		}
		data, err := os.ReadFile(absOf(root, p))
		if err != nil {
			continue
		}
		hits = append(hits, r.textHits(p, string(data))...)
	}
	return hits
}

func (r *Rules) textHits(path, text string) []Hit {
	var hits []Hit
	for i, line := range strings.Split(text, "\n") {
		code := stripNoise(line)
		if code == "" {
			continue
		}
		for _, f := range []struct {
			pat  *regexp.Regexp
			kind string
		}{
			{letPat, "let の名前"},
			{defPat, "def の名前"},
			{fieldPat, "レコードの項目名"},
			{paramPat, "引数の名前"},
		} {
			for _, m := range f.pat.FindAllStringSubmatchIndex(code, -1) {
				word := code[m[2]:m[3]]
				hint, bad := r.Words[word]
				if !bad {
					continue
				}
				// WhyNot: 記号が 2 つ続く形を見送る — `case Foo => …` の矢印と
				// `a == b` の比較、`x :: xs` の連結を、名前の置き場と読み違えるため
				// （Go の正規表現に先読みが無いので、ここで見る）。
				if doubled(code, m[3]) {
					continue
				}
				hits = append(hits, Hit{Path: path, Line: i + 1, Word: word, Kind: f.kind, Hint: hint})
			}
		}
	}
	return hits
}

// doubled は名前の後ろの記号が 2 つ続いているか (`=>` `==` `::`)。
func doubled(code string, at int) bool {
	for i := at; i < len(code); i++ {
		switch code[i] {
		case ' ', '\t':
			continue
		case '=', ':':
			if i+1 >= len(code) {
				return false
			}
			return code[i+1] == '>' || code[i+1] == '=' || code[i+1] == ':'
		default:
			return false
		}
	}
	return false
}

// stripNoise はコメントと文字列の中身を落とす。
// WhyNot: 落とさないと、説明文やコマンドの引数 ("--from" 等) を識別子と読み違える。
func stripNoise(line string) string {
	var b strings.Builder
	inStr := false
	for i := 0; i < len(line); i++ {
		c := line[i]
		switch {
		case inStr:
			if c == '\\' {
				i++
				continue
			}
			if c == '"' {
				inStr = false
				b.WriteByte(' ')
			}
		case c == '"':
			inStr = true
			b.WriteByte(' ')
		case c == '/' && i+1 < len(line) && line[i+1] == '/':
			return b.String()
		default:
			b.WriteByte(c)
		}
	}
	return b.String()
}

// Run は fge flix-reserved の本体。
func Run(out, errOut *strings.Builder, root string, args []string) (int, error) {
	rules, err := LoadRules(root)
	if err != nil {
		return 2, err
	}
	var files []string
	all := false
	for _, a := range args {
		switch {
		case a == "--all":
			all = true
		case !strings.HasPrefix(a, "--"):
			files = append(files, a)
		}
	}
	if all {
		paths, err := rules.allPaths(root)
		if err != nil {
			return 2, err
		}
		files = paths
	}
	if len(files) == 0 {
		fmt.Fprintln(out, "[lint-flix-reserved] 見るファイルがありません")
		return 0, nil
	}
	hits := rules.FileHits(root, files)
	if len(hits) == 0 {
		fmt.Fprintf(out, "[lint-flix-reserved] OK (%d ファイル)\n", len(files))
		return 0, nil
	}
	for _, h := range hits {
		fmt.Fprintf(errOut, "!! %s:%d %s に予約語 %q — %s\n", h.Path, h.Line, h.Kind, h.Word, h.Hint)
	}
	fmt.Fprintf(errOut, "予約語を識別子に使うと、Flix はパースで止まらず型検査が終わらなくなります"+
		" (画面には何も出ません)。docs/flix-conventions.md を見てください\n")
	return 1, nil
}

func (r *Rules) allPaths(root string) ([]string, error) {
	tracked, err := git(root, "ls-files", "-z")
	if err != nil {
		return nil, err
	}
	untracked, err := git(root, "ls-files", "-z", "-o", "--exclude-standard")
	if err != nil {
		return nil, err
	}
	seen := map[string]bool{}
	var paths []string
	for _, p := range append(strings.Split(tracked, "\x00"), strings.Split(untracked, "\x00")...) {
		if p == "" || !r.InScope(p) || seen[p] {
			continue
		}
		seen[p] = true
		paths = append(paths, p)
	}
	sort.Strings(paths)
	return paths, nil
}

func git(root string, args ...string) (string, error) {
	cmd := exec.Command("git", args...)
	cmd.Dir = root
	body, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("git %s が失敗しました: %v", strings.Join(args, " "), err)
	}
	return string(body), nil
}

func absOf(root, path string) string {
	if strings.HasPrefix(path, "/") {
		return path
	}
	return root + "/" + path
}
