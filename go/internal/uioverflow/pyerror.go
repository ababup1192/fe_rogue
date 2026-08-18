package uioverflow

// Python の例外・値を print したときの字面を作る小物。
//
// WhyNot: Go の error をそのまま出さないのは、Python 版が str(OSError) を
// 出力へ流すため (`[Errno 2] No such file or directory: 'a.ui.json'`)。
// errno 番号・英語の説明・ファイル名のクォートまで写さないとバイト一致しない。

import (
	"errors"
	"fmt"
	"sort"
	"strings"
	"syscall"
	"unicode"
)

// pyOSError は Python の str(OSError) と同じ字面を返す。
func pyOSError(err error, path string) string {
	var errno syscall.Errno
	if errors.As(err, &errno) {
		return fmt.Sprintf("[Errno %d] %s: %s", int(errno), capitalize(errno.Error()), pyRepr(path))
	}
	return err.Error()
}

func capitalize(s string) string {
	if s == "" {
		return s
	}
	r := []rune(s)
	r[0] = unicode.ToUpper(r[0])
	return string(r)
}

// pyRepr は Python の repr(str) と同じクォート選び・同じ逃がし方をする。
func pyRepr(s string) string {
	quote := byte('\'')
	if strings.Contains(s, "'") && !strings.Contains(s, `"`) {
		quote = '"'
	}
	var b strings.Builder
	b.WriteByte(quote)
	for _, r := range s {
		switch {
		case r == rune(quote) || r == '\\':
			b.WriteByte('\\')
			b.WriteRune(r)
		case r == '\n':
			b.WriteString(`\n`)
		case r == '\r':
			b.WriteString(`\r`)
		case r == '\t':
			b.WriteString(`\t`)
		case r < 0x20 || r == 0x7f:
			fmt.Fprintf(&b, `\x%02x`, r)
		default:
			b.WriteRune(r)
		}
	}
	b.WriteByte(quote)
	return b.String()
}

// pyReprList は Python の repr(list[str]) と同じ字面を返す。
func pyReprList(v []string) string {
	parts := make([]string, 0, len(v))
	for _, s := range v {
		parts = append(parts, pyRepr(s))
	}
	return "[" + strings.Join(parts, ", ") + "]"
}

// sortedCopy は元を変えずに並べ替えた写しを返す。
func sortedCopy(v []string) []string {
	out := append([]string(nil), v...)
	sort.Strings(out)
	return out
}
