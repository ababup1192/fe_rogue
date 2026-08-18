package syncagents

// Python の json モジュールと同じ字面のエラーを出す JSON 読みと、Python の repr。
//
// bin/sync-agents.py は manifest が壊れていたときに str(e) をそのまま画面へ出すので、
// エラーの文面（`Expecting ',' delimiter: line 1 column 8 (char 7)` など）も出力の一部になる。

import (
	"fmt"
	"math"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf16"
	"unicode/utf8"
)

// pyValue は Python 側の値。nil=None・bool・pyInt・pyFloat・string・pyList・*pyDict。
type pyValue interface{}

// pyInt は Python の int。桁数に上限が無いので 10 進の字面のまま持つ。
type pyInt string

// pyFloat は Python の float。
type pyFloat float64

// pyList は Python の list。
type pyList []pyValue

// pyDict は Python の dict。入れた順を覚える（repr の並びが出力に出る）。
type pyDict struct {
	keys []string
	vals map[string]pyValue
}

func newPyDict() *pyDict { return &pyDict{vals: map[string]pyValue{}} }

// set は Python の d[k] = v。既にある鍵は並びを変えずに値だけ差し替える。
func (d *pyDict) set(k string, v pyValue) {
	if _, ok := d.vals[k]; !ok {
		d.keys = append(d.keys, k)
	}
	d.vals[k] = v
}

func (d *pyDict) get(k string) (pyValue, bool) {
	v, ok := d.vals[k]
	return v, ok
}

func (d *pyDict) has(k string) bool {
	_, ok := d.vals[k]
	return ok
}

// pyErr は Python 側が str(e) として出す文字列を持つ。
type pyErr struct{ text string }

func (e *pyErr) Error() string { return e.text }

// jsonWS は Python の json が読み飛ばす空白（この 4 文字だけ）。
const jsonWS = " \t\n\r"

type pyScanner struct{ s []rune }

// fail は JSONDecodeError と同じ字面のエラーを作る。
// 行と桁は Python と同じくコードポイントで数える。
func (p *pyScanner) fail(msg string, pos int) error {
	line, col := 1, pos+1
	for i := 0; i < pos && i < len(p.s); i++ {
		if p.s[i] == '\n' {
			line++
			col = pos - i
		}
	}
	return &pyErr{fmt.Sprintf("%s: line %d column %d (char %d)", msg, line, col, pos)}
}

func (p *pyScanner) skipWS(i int) int {
	for i < len(p.s) && strings.ContainsRune(jsonWS, p.s[i]) {
		i++
	}
	return i
}

func (p *pyScanner) literalAt(i int, word string) bool {
	w := []rune(word)
	if i+len(w) > len(p.s) {
		return false
	}
	for k, r := range w {
		if p.s[i+k] != r {
			return false
		}
	}
	return true
}

// scanNumber は JSON の数を読む。読めなければ end = i を返す。
func (p *pyScanner) scanNumber(i int) (pyValue, int) {
	j := i
	if j < len(p.s) && p.s[j] == '-' {
		j++
	}
	switch {
	case j < len(p.s) && p.s[j] == '0':
		j++
	case j < len(p.s) && p.s[j] >= '1' && p.s[j] <= '9':
		for j < len(p.s) && p.s[j] >= '0' && p.s[j] <= '9' {
			j++
		}
	default:
		return nil, i
	}
	intEnd := j
	isFloat := false
	if j+1 < len(p.s) && p.s[j] == '.' && p.s[j+1] >= '0' && p.s[j+1] <= '9' {
		j += 2
		for j < len(p.s) && p.s[j] >= '0' && p.s[j] <= '9' {
			j++
		}
		isFloat = true
	}
	if j < len(p.s) && (p.s[j] == 'e' || p.s[j] == 'E') {
		k := j + 1
		if k < len(p.s) && (p.s[k] == '+' || p.s[k] == '-') {
			k++
		}
		if k < len(p.s) && p.s[k] >= '0' && p.s[k] <= '9' {
			for k < len(p.s) && p.s[k] >= '0' && p.s[k] <= '9' {
				k++
			}
			j = k
			isFloat = true
		}
	}
	text := string(p.s[i:j])
	if !isFloat {
		text = string(p.s[i:intEnd])
		if text == "-0" {
			text = "0"
		}
		return pyInt(text), intEnd
	}
	f, err := strconv.ParseFloat(text, 64)
	if err != nil {
		return nil, i
	}
	return pyFloat(f), j
}

// scanString は Python の c_scanstring と同じ位置・同じ文面でしくじる。
func (p *pyScanner) scanString(begin int) (string, int, error) {
	var b strings.Builder
	i := begin + 1
	for {
		if i >= len(p.s) {
			return "", 0, p.fail("Unterminated string starting at", begin)
		}
		c := p.s[i]
		switch {
		case c == '"':
			return b.String(), i + 1, nil
		case c == '\\':
			if i+1 >= len(p.s) {
				return "", 0, p.fail("Unterminated string starting at", begin)
			}
			esc := p.s[i+1]
			i += 2
			switch esc {
			case '"':
				b.WriteRune('"')
			case '\\':
				b.WriteRune('\\')
			case '/':
				b.WriteRune('/')
			case 'b':
				b.WriteRune('\b')
			case 'f':
				b.WriteRune('\f')
			case 'n':
				b.WriteRune('\n')
			case 'r':
				b.WriteRune('\r')
			case 't':
				b.WriteRune('\t')
			case 'u':
				v, ok := p.hex4(i)
				if !ok {
					return "", 0, p.fail("Invalid \\uXXXX escape", i-1)
				}
				i += 4
				if utf16.IsSurrogate(rune(v)) && i+1 < len(p.s) && p.s[i] == '\\' && p.s[i+1] == 'u' {
					if lo, ok := p.hex4(i + 2); ok {
						if r := utf16.DecodeRune(rune(v), rune(lo)); r != utf8.RuneError {
							b.WriteRune(r)
							i += 6
							continue
						}
					}
				}
				b.WriteRune(rune(v))
			default:
				return "", 0, p.fail("Invalid \\escape", i-2)
			}
		case c <= 0x1f:
			return "", 0, p.fail("Invalid control character at", i)
		default:
			b.WriteRune(c)
			i++
		}
	}
}

func (p *pyScanner) hex4(i int) (int, bool) {
	if i+4 > len(p.s) {
		return 0, false
	}
	v := 0
	for k := 0; k < 4; k++ {
		d := p.s[i+k]
		switch {
		case d >= '0' && d <= '9':
			v = v*16 + int(d-'0')
		case d >= 'a' && d <= 'f':
			v = v*16 + int(d-'a') + 10
		case d >= 'A' && d <= 'F':
			v = v*16 + int(d-'A') + 10
		default:
			return 0, false
		}
	}
	return v, true
}

func (p *pyScanner) scanValue(i int) (pyValue, int, error) {
	if i >= len(p.s) {
		return nil, 0, p.fail("Expecting value", i)
	}
	switch {
	case p.s[i] == '"':
		return p.scanString(i)
	case p.s[i] == '{':
		return p.scanObject(i)
	case p.s[i] == '[':
		return p.scanArray(i)
	case p.literalAt(i, "null"):
		return nil, i + 4, nil
	case p.literalAt(i, "true"):
		return true, i + 4, nil
	case p.literalAt(i, "false"):
		return false, i + 5, nil
	case p.literalAt(i, "NaN"):
		return pyFloat(math.NaN()), i + 3, nil
	case p.literalAt(i, "Infinity"):
		return pyFloat(math.Inf(1)), i + 8, nil
	case p.literalAt(i, "-Infinity"):
		return pyFloat(math.Inf(-1)), i + 9, nil
	}
	if v, end := p.scanNumber(i); end > i {
		return v, end, nil
	}
	return nil, 0, p.fail("Expecting value", i)
}

func (p *pyScanner) scanObject(i int) (pyValue, int, error) {
	d := newPyDict()
	end := p.skipWS(i + 1)
	if end < len(p.s) && p.s[end] == '}' {
		return d, end + 1, nil
	}
	for {
		if end >= len(p.s) || p.s[end] != '"' {
			return nil, 0, p.fail("Expecting property name enclosed in double quotes", end)
		}
		key, next, err := p.scanString(end)
		if err != nil {
			return nil, 0, err
		}
		end = p.skipWS(next)
		if end >= len(p.s) || p.s[end] != ':' {
			return nil, 0, p.fail("Expecting ':' delimiter", end)
		}
		end = p.skipWS(end + 1)
		val, next, err := p.scanValue(end)
		if err != nil {
			return nil, 0, err
		}
		d.set(key, val)
		end = p.skipWS(next)
		if end >= len(p.s) {
			return nil, 0, p.fail("Expecting ',' delimiter", end)
		}
		if p.s[end] == '}' {
			return d, end + 1, nil
		}
		if p.s[end] != ',' {
			return nil, 0, p.fail("Expecting ',' delimiter", end)
		}
		end = p.skipWS(end + 1)
	}
}

func (p *pyScanner) scanArray(i int) (pyValue, int, error) {
	list := pyList{}
	end := p.skipWS(i + 1)
	if end < len(p.s) && p.s[end] == ']' {
		return list, end + 1, nil
	}
	for {
		val, next, err := p.scanValue(end)
		if err != nil {
			return nil, 0, err
		}
		list = append(list, val)
		end = p.skipWS(next)
		if end >= len(p.s) {
			return nil, 0, p.fail("Expecting ',' delimiter", end)
		}
		if p.s[end] == ']' {
			return list, end + 1, nil
		}
		if p.s[end] != ',' {
			return nil, 0, p.fail("Expecting ',' delimiter", end)
		}
		end = p.skipWS(end + 1)
	}
}

// pyJSONLoads は Python の json.loads と同じ値・同じエラー文面を返す。
func pyJSONLoads(text string) (pyValue, error) {
	p := &pyScanner{s: []rune(text)}
	if len(p.s) > 0 && p.s[0] == '\uFEFF' {
		return nil, p.fail("Unexpected UTF-8 BOM (decode using utf-8-sig)", 0)
	}
	start := p.skipWS(0)
	v, end, err := p.scanValue(start)
	if err != nil {
		return nil, err
	}
	end = p.skipWS(end)
	if end != len(p.s) {
		return nil, p.fail("Extra data", end)
	}
	return v, nil
}

// pyRepr は Python の repr() と同じ字面を返す。
func pyRepr(v pyValue) string {
	switch t := v.(type) {
	case nil:
		return "None"
	case bool:
		if t {
			return "True"
		}
		return "False"
	case pyInt:
		return string(t)
	case pyFloat:
		return pyFloatRepr(float64(t))
	case string:
		return pyReprString(t)
	case pyList:
		parts := make([]string, 0, len(t))
		for _, e := range t {
			parts = append(parts, pyRepr(e))
		}
		return "[" + strings.Join(parts, ", ") + "]"
	case *pyDict:
		parts := make([]string, 0, len(t.keys))
		for _, k := range t.keys {
			parts = append(parts, pyReprString(k)+": "+pyRepr(t.vals[k]))
		}
		return "{" + strings.Join(parts, ", ") + "}"
	}
	return fmt.Sprintf("%v", v)
}

// pyReprString は Python の repr(str)。' を含み " を含まないときだけ二重引用符で挟む。
func pyReprString(s string) string {
	quote := byte('\'')
	if strings.ContainsRune(s, '\'') && !strings.ContainsRune(s, '"') {
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
			b.WriteString("\\n")
		case r == '\r':
			b.WriteString("\\r")
		case r == '\t':
			b.WriteString("\\t")
		case r < 0x20 || r == 0x7f:
			fmt.Fprintf(&b, "\\x%02x", r)
		case r < 0x80 || pyIsPrintable(r):
			b.WriteRune(r)
		case r <= 0xff:
			fmt.Fprintf(&b, "\\x%02x", r)
		case r <= 0xffff:
			fmt.Fprintf(&b, "\\u%04x", r)
		default:
			fmt.Fprintf(&b, "\\U%08x", r)
		}
	}
	b.WriteByte(quote)
	return b.String()
}

// pyIsPrintable は Python の str.isprintable()（空白は半角スペースだけが印字可能）。
func pyIsPrintable(r rune) bool {
	if r == ' ' {
		return true
	}
	if unicode.IsSpace(r) {
		return false
	}
	return !unicode.In(r, unicode.C, unicode.Zs, unicode.Zl, unicode.Zp)
}

// pyFloatRepr は Python の repr(float)。指数へ切り替える境目が Go の %g と違う。
func pyFloatRepr(f float64) string {
	switch {
	case math.IsNaN(f):
		return "nan"
	case math.IsInf(f, 1):
		return "inf"
	case math.IsInf(f, -1):
		return "-inf"
	}
	mant := strconv.FormatFloat(f, 'e', -1, 64)
	exp := 0
	if i := strings.IndexByte(mant, 'e'); i >= 0 {
		exp, _ = strconv.Atoi(mant[i+1:])
	}
	if exp < -4 || exp >= 16 {
		s := strconv.FormatFloat(f, 'E', -1, 64)
		i := strings.IndexByte(s, 'E')
		digits, e := s[:i], s[i+1:]
		sign := "+"
		if e[0] == '+' || e[0] == '-' {
			sign, e = string(e[0]), e[1:]
		}
		if len(e) < 2 {
			e = "0" + e
		}
		return digits + "e" + sign + e
	}
	s := strconv.FormatFloat(f, 'f', -1, 64)
	if !strings.ContainsRune(s, '.') {
		s += ".0"
	}
	return s
}
