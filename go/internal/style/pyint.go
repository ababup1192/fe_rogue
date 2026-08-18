package style

// コマンドラインの数値の受け取り方。前後の空白と桁区切りのアンダースコア
// ("1_0" = 10) も受け取る。
// WhyNot: strconv.Atoi をそのまま使わないのは、この 2 つを弾いてしまい、
// 打ち間違いでない --unit まで「知らないオプション」に落ちるため。

import (
	"strconv"
	"strings"
	"unicode"
)

// pyInt は 10 進の整数を読む。読めなければ false。
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
