package status

// 出力の字面をそろえるための小物。文字列・パス・ファイル走査で、Go の標準の既定が
// この道具に要る規則と食い違う所だけを置く。
//
// WhyNot: pxlib へ足さないのは、同じ土台を別の人が同時に触っていて、共有ファイルを
// 触ると衝突するため。ここに置いた物が 2 本目の客を得たら pxlib へ寄せてよい。

import (
	"os"
	"path"
	"regexp"
	"strings"
	"unicode"
	"unicode/utf8"
)

// isPySpace は前後を削るとき・空白で切るときに空白とみなす範囲。
// WhyNot: unicode.IsSpace だけに任せないのは、\x1c〜\x1f も空白として落とす必要があるため。
func isPySpace(r rune) bool {
	switch r {
	case 0x1c, 0x1d, 0x1e, 0x1f:
		return true
	}
	return unicode.IsSpace(r)
}

// pyStrip は前後の空白（isPySpace の範囲）を落とす。
func pyStrip(s string) string { return strings.TrimFunc(s, isPySpace) }

// pyRStrip は末尾の空白（isPySpace の範囲）を落とす。
func pyRStrip(s string) string { return strings.TrimRightFunc(s, isPySpace) }

// pyLStripHash は先頭の "#" をすべて落とす。
func pyLStripHash(s string) string { return strings.TrimLeft(s, "#") }

// pySplitWS1 は先頭の空白を飛ばし、次の空白で 2 つに切る。後ろ側の先頭の空白も落とす。
// 空白しか無ければ nil。
func pySplitWS1(s string) []string {
	r := []rune(s)
	i := 0
	for i < len(r) && isPySpace(r[i]) {
		i++
	}
	if i >= len(r) {
		return nil
	}
	start := i
	for i < len(r) && !isPySpace(r[i]) {
		i++
	}
	first := string(r[start:i])
	for i < len(r) && isPySpace(r[i]) {
		i++
	}
	if i >= len(r) {
		return []string{first}
	}
	return []string{first, string(r[i:])}
}

// pyHead は先頭 n コードポイントを返す。
// WhyNot: s[:n] のバイト切りにしないのは、日本語 1 文字が 3 バイトになって
// 切る位置がまるごとずれるため。
func pyHead(s string, n int) string {
	if n <= 0 {
		return ""
	}
	if len(s) < n {
		return s
	}
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n])
}

// pyDropTail は末尾 n コードポイントを落とす。
func pyDropTail(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return ""
	}
	return string(r[:len(r)-n])
}

// pySplitLines は行末とみなす文字が広い方の行分け
// (\n \v \f \r \r\n \x1c \x1d \x1e U+0085 U+2028 U+2029)。
func pySplitLines(s string) []string {
	var lines []string
	start := 0
	for i := 0; i < len(s); {
		r, size := utf8.DecodeRuneInString(s[i:])
		switch r {
		case '\n', '\v', '\f', '\r', 0x1c, 0x1d, 0x1e, 0x85, 0x2028, 0x2029:
			lines = append(lines, s[start:i])
			i += size
			if r == '\r' && i < len(s) && s[i] == '\n' {
				i++
			}
			start = i
		default:
			i += size
		}
	}
	if start < len(s) {
		lines = append(lines, s[start:])
	}
	return lines
}

// pyFileLines はファイルを 1 行ずつ読むときの切り方（\n / \r\n / \r の 3 つだけ）。
// WhyNot: pySplitLines を使わないのは、あちらが \v \f \x1c なども行末に数えるため。
func pyFileLines(s string) []string {
	var lines []string
	start := 0
	for i := 0; i < len(s); i++ {
		switch s[i] {
		case '\n':
			lines = append(lines, s[start:i])
			start = i + 1
		case '\r':
			lines = append(lines, s[start:i])
			if i+1 < len(s) && s[i+1] == '\n' {
				i++
			}
			start = i + 1
		}
	}
	if start < len(s) {
		lines = append(lines, s[start:])
	}
	return lines
}

// decodeReplace は不正なバイトを U+FFFD にする（errors="replace"）。
func decodeReplace(data []byte) string {
	if utf8.Valid(data) {
		return string(data)
	}
	var b strings.Builder
	for i := 0; i < len(data); {
		r, size := utf8.DecodeRune(data[i:])
		if r == utf8.RuneError && size == 1 {
			b.WriteRune(utf8.RuneError)
			i++
			continue
		}
		b.Write(data[i : i+size])
		i += size
	}
	return b.String()
}

// universalNewlines はテキストとして読むときの行末の均し（\r\n と \r を \n にする）。
// WhyNot: 均さずに読むと本文に \r が残り、字面の照合や先頭 400 文字の切り出しで
// 位置がずれる。
func universalNewlines(s string) string {
	if !strings.ContainsRune(s, '\r') {
		return s
	}
	s = strings.ReplaceAll(s, "\r\n", "\n")
	return strings.ReplaceAll(s, "\r", "\n")
}

// readTextPy は UTF-8 として読み、壊れたバイトを U+FFFD へ替え、行末を均した文字列を返す。
func readTextPy(path string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	return universalNewlines(decodeReplace(data)), nil
}

// pyBasename は最後の "/" より後ろの部分。
// WhyNot: filepath.Base を使わないのは、末尾が "/" のときに空文字が欲しいのに、
// Go は 1 つ手前の要素を返すため。
func pyBasename(p string) string {
	i := strings.LastIndex(p, "/")
	if i < 0 {
		return p
	}
	return p[i+1:]
}

// pyDirname は最後の "/" より前の部分（"/" が無ければ空文字・先頭の "/" だけなら "/"）。
func pyDirname(p string) string {
	i := strings.LastIndex(p, "/")
	if i < 0 {
		return ""
	}
	if i == 0 {
		return "/"
	}
	return p[:i]
}

// pySpaceClass は Unicode の空白すべてに当たる文字クラス。
// WhyNot: Go の \s は ASCII の 5 種類だけなので、そのままでは全角空白を含む行で
// 判定が食い違う。
const pySpaceClass = `[\t\n\v\f\r\x{1c}-\x{1f} \x{85}\x{a0}\x{1680}\x{2000}-\x{200a}\x{2028}\x{2029}\x{202f}\x{205f}\x{3000}]`

// pyNonSpaceClass は pySpaceClass の裏返し（空白以外に当たる）。
const pyNonSpaceClass = `[^\t\n\v\f\r\x{1c}-\x{1f} \x{85}\x{a0}\x{1680}\x{2000}-\x{200a}\x{2028}\x{2029}\x{202f}\x{205f}\x{3000}]`

// compilePySpace は \s と \S を Unicode 版に差し替えてから組む。
func compilePySpace(src string) *regexp.Regexp {
	src = strings.ReplaceAll(src, `\s`, pySpaceClass)
	src = strings.ReplaceAll(src, `\S`, pyNonSpaceClass)
	return regexp.MustCompile(src)
}

// ---- glob ----------------------------------------------------------------

func hasMagic(s string) bool { return strings.ContainsAny(s, "*?[") }

// fnmatchName はシェル風のワイルドカード（* ? [...]）で 1 つの名前を照合する。
func fnmatchName(pattern, name string) bool {
	return fnmatchRunes([]rune(pattern), []rune(name))
}

func fnmatchRunes(pat, name []rune) bool {
	// 素直な後戻り付き突き合わせ。パターンは短いので速さは要らない。
	pi, ni := 0, 0
	star, mark := -1, 0
	for ni < len(name) {
		switch {
		case pi < len(pat) && pat[pi] == '*':
			star, mark = pi, ni
			pi++
		case pi < len(pat) && pat[pi] == '?':
			pi++
			ni++
		case pi < len(pat) && pat[pi] == '[':
			end := matchBracket(pat, pi, name[ni])
			if end < 0 {
				if star < 0 {
					return false
				}
				mark++
				pi, ni = star+1, mark
				continue
			}
			pi, ni = end, ni+1
		case pi < len(pat) && pat[pi] == name[ni]:
			pi++
			ni++
		default:
			if star < 0 {
				return false
			}
			mark++
			pi, ni = star+1, mark
		}
	}
	for pi < len(pat) && pat[pi] == '*' {
		pi++
	}
	return pi == len(pat)
}

// matchBracket は pat[i] の '[' から始まる集合が c に当たれば集合の次の位置を返す。
// 当たらなければ -1。閉じない '[' はただの文字として扱う。
func matchBracket(pat []rune, i int, c rune) int {
	j := i + 1
	neg := false
	if j < len(pat) && (pat[j] == '!' || pat[j] == '^') {
		neg = true
		j++
	}
	if j < len(pat) && pat[j] == ']' {
		j++
	}
	for j < len(pat) && pat[j] != ']' {
		j++
	}
	if j >= len(pat) {
		if pat[i] == c {
			return i + 1
		}
		return -1
	}
	body := pat[i+1 : j]
	if neg {
		body = body[1:]
	}
	hit := false
	for k := 0; k < len(body); k++ {
		if k+2 < len(body) && body[k+1] == '-' {
			if body[k] <= c && c <= body[k+2] {
				hit = true
			}
			k += 2
			continue
		}
		if body[k] == c {
			hit = true
		}
	}
	if hit != neg {
		return j + 1
	}
	return -1
}

// pyGlob は pattern に当たる相対パスを、ディレクトリを読んだ並びのまま返す。
// base は照合の基準になるディレクトリ。
//
// WhyNot: filepath.Glob を使わないのは 2 点で意味が違うため。
//   - Go は名前順に並べ替える。並べ替えると mtime 順に落とす前の並びが変わり、
//     同着の行順がずれる。
//   - Go は "." で始まる名前も "*" に当てる。ここでは当てない。
func pyGlob(base, pattern string) []string {
	comps := strings.Split(pattern, "/")
	var out []string
	globRec(base, comps, 0, "", &out)
	return out
}

func globRec(base string, comps []string, i int, prefix string, out *[]string) {
	comp := comps[i]
	last := i == len(comps)-1
	if !hasMagic(comp) {
		p := joinRel(prefix, comp)
		if last {
			if _, err := os.Lstat(path.Join(base, p)); err == nil {
				*out = append(*out, p)
			}
			return
		}
		globRec(base, comps, i+1, p, out)
		return
	}
	names := iterdir(path.Join(base, prefix), !last)
	hidden := strings.HasPrefix(comp, ".")
	for _, name := range names {
		if !hidden && strings.HasPrefix(name, ".") {
			continue
		}
		if !fnmatchName(comp, name) {
			continue
		}
		p := joinRel(prefix, name)
		if last {
			*out = append(*out, p)
			continue
		}
		globRec(base, comps, i+1, p, out)
	}
}

func joinRel(prefix, name string) string {
	if prefix == "" {
		return name
	}
	return prefix + "/" + name
}

// iterdir はディレクトリを読んだ並びのままの名前。dironly ならディレクトリだけ。
func iterdir(dir string, dironly bool) []string {
	f, err := os.Open(dir)
	if err != nil {
		return nil
	}
	names, err := f.Readdirnames(-1)
	f.Close()
	if err != nil {
		return nil
	}
	if !dironly {
		return names
	}
	var out []string
	for _, name := range names {
		if info, err := os.Stat(path.Join(dir, name)); err == nil && info.IsDir() {
			out = append(out, name)
		}
	}
	return out
}
