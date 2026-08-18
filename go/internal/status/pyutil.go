package status

// Python 版 (bin/status.py) と字面をそろえるための小物。
// 文字列・パス・ファイル走査で Go と Python の既定が食い違う所だけを置く。
//
// WhyNot: pxlib へ足さないのは、同じ土台を別の人が同時に移植中で、共有ファイルを
// 触ると衝突するため。ここに置いた物が 2 本目の客を得たら pxlib へ寄せてよい。

import (
	"os"
	"path"
	"regexp"
	"strings"
	"unicode"
	"unicode/utf8"
)

// isPySpace は Python の str.strip() / str.split(None) が空白とみなす範囲。
// WhyNot: unicode.IsSpace だけに任せないのは、Python が \x1c〜\x1f も落とすため。
func isPySpace(r rune) bool {
	switch r {
	case 0x1c, 0x1d, 0x1e, 0x1f:
		return true
	}
	return unicode.IsSpace(r)
}

// pyStrip は Python の str.strip()（引数なし）と同じ範囲を落とす。
func pyStrip(s string) string { return strings.TrimFunc(s, isPySpace) }

// pyRStrip は Python の str.rstrip()（引数なし）と同じ範囲を落とす。
func pyRStrip(s string) string { return strings.TrimRightFunc(s, isPySpace) }

// pyLStripHash は Python の str.lstrip("#")。先頭の "#" をすべて落とす。
func pyLStripHash(s string) string { return strings.TrimLeft(s, "#") }

// pySplitWS1 は Python の str.split(None, 1)。
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

// pyHead は Python の s[:n]（コードポイント数で切る）。
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

// pyDropTail は Python の s[:-n]（末尾 n コードポイントを落とす）。
func pyDropTail(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return ""
	}
	return string(r[:len(r)-n])
}

// pySplitLines は Python の str.splitlines()。
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

// pyFileLines は `for line in fh` の切り方（\n / \r\n / \r の 3 つだけ）。
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

// universalNewlines は Python のテキスト読み（newline=None）が行う行末の均し。
// WhyNot: 均さずに読むと read() した本文に \r が残り、`in` 検査や read(400) の
// 文字数が Python とずれる。
func universalNewlines(s string) string {
	if !strings.ContainsRune(s, '\r') {
		return s
	}
	s = strings.ReplaceAll(s, "\r\n", "\n")
	return strings.ReplaceAll(s, "\r", "\n")
}

// readTextPy は open(path, encoding="utf-8", errors="replace").read() と同じ文字列。
func readTextPy(path string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	return universalNewlines(decodeReplace(data)), nil
}

// pyBasename は Python の os.path.basename。
// WhyNot: filepath.Base を使わないのは、末尾が "/" のとき Python は空文字を返し、
// Go は 1 つ手前の要素を返すため。
func pyBasename(p string) string {
	i := strings.LastIndex(p, "/")
	if i < 0 {
		return p
	}
	return p[i+1:]
}

// pyDirname は Python の os.path.dirname。
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

// pySpaceClass は Python の正規表現 \s（Unicode の空白）に当たる文字クラス。
// WhyNot: Go の \s は ASCII の 5 種類だけなので、そのままでは全角空白を含む行で
// 判定が食い違う。
const pySpaceClass = `[\t\n\v\f\r\x{1c}-\x{1f} \x{85}\x{a0}\x{1680}\x{2000}-\x{200a}\x{2028}\x{2029}\x{202f}\x{205f}\x{3000}]`

// pyNonSpaceClass は Python の正規表現 \S。
const pyNonSpaceClass = `[^\t\n\v\f\r\x{1c}-\x{1f} \x{85}\x{a0}\x{1680}\x{2000}-\x{200a}\x{2028}\x{2029}\x{202f}\x{205f}\x{3000}]`

// compilePySpace は \s と \S を Unicode 版に差し替えてから組む。
func compilePySpace(src string) *regexp.Regexp {
	src = strings.ReplaceAll(src, `\s`, pySpaceClass)
	src = strings.ReplaceAll(src, `\S`, pyNonSpaceClass)
	return regexp.MustCompile(src)
}

// ---- glob ----------------------------------------------------------------

func hasMagic(s string) bool { return strings.ContainsAny(s, "*?[") }

// fnmatchName は Python の fnmatch（1 つの名前と 1 つのパターン）。
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
// 当たらなければ -1。閉じない '[' はただの文字として扱う（Python と同じ）。
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

// pyGlob は Python の glob.glob(pattern) と同じ並びの相対パスを返す。
// base は Python のカレントに当たるディレクトリ。
//
// WhyNot: filepath.Glob を使わないのは 2 点で意味が違うため。
//   - Go は名前順に並べ替える。Python は readdir の並びのまま返すので、
//     並べ替えると mtime 順に落とす前の並びが変わり、同着の行順がずれる。
//   - Go は "." で始まる名前も "*" に当てる。Python は当てない。
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

// iterdir は os.scandir と同じ並びの名前。dironly ならディレクトリだけ。
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
