package uioverflow

// エラーと値を検査の出力へ載せる字面にする小物。
//
// WhyNot: Go の error をそのまま出さないのは、読めないファイルの行が
// この形に決まっているため (`[Errno 2] No such file or directory: 'a.ui.json'`)。
// errno 番号・英語の説明・ファイル名のクォートまで組み立てないとこの形にならない。

import (
	"errors"
	"fmt"
	"sort"
	"strings"
	"syscall"
	"unicode"
)

// pyOSError は errno 番号・説明・パスを並べた 1 行を返す。
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

// pyRepr は文字列をクォートで囲む。単引用符を含み二重引用符を含まないときだけ " で囲む。
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

// pyReprList は文字列の並びを [ ] で囲んだ 1 行にする。
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
