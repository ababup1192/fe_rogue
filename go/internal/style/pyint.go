package style

// Python の int(文字列) の受け取り方を写す。
// WhyNot: strconv.Atoi をそのまま使わないのは、Python が前後の空白と桁区切りの
// アンダースコア ("1_0" = 10) を受け取り、Go が受け取らないため。受け取る形が
// 違うと --unit の読み違いだけで出力がまるごとずれる。

import (
	"strconv"
	"strings"
	"unicode"
)

// pyInt は Python の int() と同じ物を受け取る。受け取れなければ false。
func pyInt(s string) (int, bool) {
	t := strings.TrimFunc(s, unicode.IsSpace)
	sign := 1
	if strings.HasPrefix(t, "+") {
		t = t[1:]
	} else if strings.HasPrefix(t, "-") {
		sign = -1
		t = t[1:]
	}
	if t == "" {
		return 0, false
	}
	// アンダースコアは数字と数字の間に 1 つずつだけ置ける。
	var digits strings.Builder
	prevUnderscore := true
	for i, r := range t {
		if r == '_' {
			if prevUnderscore || i == len(t)-1 {
				return 0, false
			}
			prevUnderscore = true
			continue
		}
		if r < '0' || r > '9' {
			return 0, false
		}
		prevUnderscore = false
		digits.WriteRune(r)
	}
	n, err := strconv.Atoi(digits.String())
	if err != nil {
		return 0, false
	}
	return sign * n, true
}
