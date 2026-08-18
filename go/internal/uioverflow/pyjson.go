package uioverflow

// Python の json モジュールと同じ読み方・同じ失敗の字面を出す JSON パーサ。
//
// WhyNot: encoding/json を使わないのは、読めない JSON のときに Python 版が
// 例外の文面をそのまま出力へ流すため (`(読めない JSON: Expecting ',' delimiter:
// line 1 column 8 (char 7))`)。位置と文面まで含めて写さないとバイト一致しない。
// 位置は「文字」で数える (Go の既定のバイト位置ではない)。

import (
	"fmt"
	"math"
	"strconv"
	"strings"
	"unicode/utf16"
)

// decodeError は Python の json.JSONDecodeError と同じ字面を出す。
type decodeError struct {
	msg string
	pos int
	doc []rune
}

func (e *decodeError) Error() string {
	line, col := 1, e.pos+1
	for i := 0; i < e.pos && i < len(e.doc); i++ {
		if e.doc[i] == '\n' {
			line++
			col = e.pos - i
		}
	}
	return fmt.Sprintf("%s: line %d column %d (char %d)", e.msg, line, col, e.pos)
}

type decoder struct{ r []rune }

func (d *decoder) err(msg string, pos int) error {
	return &decodeError{msg: msg, pos: pos, doc: d.r}
}

// skipWS は Python の json が読み飛ばす空白 (空白・タブ・改行・復帰) だけを飛ばす。
func (d *decoder) skipWS(i int) int {
	for i < len(d.r) {
		switch d.r[i] {
		case ' ', '\t', '\n', '\r':
			i++
		default:
			return i
		}
	}
	return i
}

func (d *decoder) at(i int) rune {
	if i < 0 || i >= len(d.r) {
		return -1
	}
	return d.r[i]
}

func (d *decoder) literal(i int, word string) bool {
	if i+len(word) > len(d.r) {
		return false
	}
	return string(d.r[i:i+len(word)]) == word
}

// LoadsPyJSON は Python の json.loads と同じ値・同じエラーを返す。
func LoadsPyJSON(s string) (any, error) {
	d := &decoder{r: []rune(s)}
	i := d.skipWS(0)
	v, end, err := d.scanOnce(i)
	if err != nil {
		return nil, err
	}
	end = d.skipWS(end)
	if end != len(d.r) {
		return nil, d.err("Extra data", end)
	}
	return v, nil
}

func (d *decoder) scanOnce(i int) (any, int, error) {
	switch d.at(i) {
	case '"':
		return d.scanString(i + 1)
	case '{':
		return d.parseObject(i + 1)
	case '[':
		return d.parseArray(i + 1)
	}
	switch {
	case d.literal(i, "null"):
		return nil, i + 4, nil
	case d.literal(i, "true"):
		return true, i + 4, nil
	case d.literal(i, "false"):
		return false, i + 5, nil
	}
	if v, end, ok := d.scanNumber(i); ok {
		return v, end, nil
	}
	switch {
	case d.literal(i, "NaN"):
		return math.NaN(), i + 3, nil
	case d.literal(i, "Infinity"):
		return math.Inf(1), i + 8, nil
	case d.literal(i, "-Infinity"):
		return math.Inf(-1), i + 9, nil
	}
	return nil, 0, d.err("Expecting value", i)
}

// scanNumber は Python の NUMBER_RE と同じ形だけを数として読む。
func (d *decoder) scanNumber(i int) (float64, int, bool) {
	start := i
	if d.at(i) == '-' {
		i++
	}
	switch {
	case d.at(i) == '0':
		i++
	case d.at(i) >= '1' && d.at(i) <= '9':
		for d.at(i) >= '0' && d.at(i) <= '9' {
			i++
		}
	default:
		return 0, 0, false
	}
	if d.at(i) == '.' && d.at(i+1) >= '0' && d.at(i+1) <= '9' {
		i++
		for d.at(i) >= '0' && d.at(i) <= '9' {
			i++
		}
	}
	if e := d.at(i); e == 'e' || e == 'E' {
		j := i + 1
		if d.at(j) == '+' || d.at(j) == '-' {
			j++
		}
		if d.at(j) >= '0' && d.at(j) <= '9' {
			for d.at(j) >= '0' && d.at(j) <= '9' {
				j++
			}
			i = j
		}
	}
	v, err := strconv.ParseFloat(string(d.r[start:i]), 64)
	if err != nil {
		// WhyNot: 桁あふれを失敗にしないのは、Python の float() が inf を返して
		// 読み込み自体は成功するため。
		if strings.Contains(err.Error(), "value out of range") {
			return v, i, true
		}
		return 0, 0, false
	}
	return v, i, true
}

func (d *decoder) scanString(i int) (string, int, error) {
	begin := i - 1
	var b strings.Builder
	for {
		if i >= len(d.r) {
			return "", 0, d.err("Unterminated string starting at", begin)
		}
		c := d.r[i]
		switch {
		case c == '"':
			return b.String(), i + 1, nil
		case c < 0x20:
			return "", 0, d.err("Invalid control character at", i)
		case c != '\\':
			b.WriteRune(c)
			i++
			continue
		}
		i++
		if i >= len(d.r) {
			return "", 0, d.err("Unterminated string starting at", begin)
		}
		esc := d.r[i]
		if esc != 'u' {
			plain := map[rune]rune{'"': '"', '\\': '\\', '/': '/', 'b': '\b',
				'f': '\f', 'n': '\n', 'r': '\r', 't': '\t'}
			ch, ok := plain[esc]
			if !ok {
				return "", 0, d.err(`Invalid \escape`, i-1)
			}
			b.WriteRune(ch)
			i++
			continue
		}
		i++
		cp, ok := d.hex4(i)
		if !ok {
			return "", 0, d.err(`Invalid \uXXXX escape`, i-1)
		}
		i += 4
		if utf16.IsSurrogate(rune(cp)) && cp >= 0xd800 && cp <= 0xdbff &&
			d.at(i) == '\\' && d.at(i+1) == 'u' {
			if lo, ok2 := d.hex4(i + 2); ok2 && lo >= 0xdc00 && lo <= 0xdfff {
				b.WriteRune(utf16.DecodeRune(rune(cp), rune(lo)))
				i += 6
				continue
			}
		}
		b.WriteRune(rune(cp))
	}
}

func (d *decoder) hex4(i int) (int, bool) {
	if i+4 > len(d.r) {
		return 0, false
	}
	n := 0
	for k := 0; k < 4; k++ {
		c := d.r[i+k]
		switch {
		case c >= '0' && c <= '9':
			n = n*16 + int(c-'0')
		case c >= 'a' && c <= 'f':
			n = n*16 + int(c-'a') + 10
		case c >= 'A' && c <= 'F':
			n = n*16 + int(c-'A') + 10
		default:
			return 0, false
		}
	}
	return n, true
}

func (d *decoder) parseObject(i int) (map[string]any, int, error) {
	obj := map[string]any{}
	i = d.skipWS(i)
	if d.at(i) == '}' {
		return obj, i + 1, nil
	}
	for {
		if d.at(i) != '"' {
			return nil, 0, d.err("Expecting property name enclosed in double quotes", i)
		}
		key, end, err := d.scanString(i + 1)
		if err != nil {
			return nil, 0, err
		}
		i = d.skipWS(end)
		if d.at(i) != ':' {
			return nil, 0, d.err("Expecting ':' delimiter", i)
		}
		i = d.skipWS(i + 1)
		value, end, err := d.scanOnce(i)
		if err != nil {
			return nil, 0, err
		}
		obj[key] = value
		i = d.skipWS(end)
		if d.at(i) == '}' {
			return obj, i + 1, nil
		}
		if d.at(i) != ',' {
			return nil, 0, d.err("Expecting ',' delimiter", i)
		}
		i = d.skipWS(i + 1)
	}
}

func (d *decoder) parseArray(i int) ([]any, int, error) {
	values := []any{}
	i = d.skipWS(i)
	if d.at(i) == ']' {
		return values, i + 1, nil
	}
	for {
		value, end, err := d.scanOnce(i)
		if err != nil {
			return nil, 0, err
		}
		values = append(values, value)
		i = d.skipWS(end)
		if d.at(i) == ']' {
			return values, i + 1, nil
		}
		if d.at(i) != ',' {
			return nil, 0, d.err("Expecting ',' delimiter", i)
		}
		i = d.skipWS(i + 1)
	}
}
