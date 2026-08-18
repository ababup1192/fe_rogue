package pxlib

// 色の近さ (CIEDE2000)。
//
// WhyNot: Lab のユークリッド距離 (CIE76) にしないのは、彩度の高い色 — とくに青 — で
// 人の目より大きく出るため。少数パレットのドット絵は鮮やかな色を並べるので、
// そこで緩むと「近すぎる 2 色」の検査がいちばん効いてほしい場面で何もせず通ってしまう。

import (
	"math"
	"strconv"
	"strings"
)

// Lab は CIE L*a*b* の 3 値。
type Lab [3]float64

// LabOfHex は "#rrggbb" を Lab にする (D65・sRGB)。
func LabOfHex(hex string) Lab {
	body := strings.TrimPrefix(hex, "#")
	var c [3]float64
	for i := 0; i < 3; i++ {
		v, _ := strconv.ParseUint(body[i*2:i*2+2], 16, 8)
		c[i] = float64(v) / 255.0
	}
	lin := func(v float64) float64 {
		if v <= 0.04045 {
			return v / 12.92
		}
		return math.Pow((v+0.055)/1.055, 2.4)
	}
	r, g, b := lin(c[0]), lin(c[1]), lin(c[2])
	x := (0.4124*r + 0.3576*g + 0.1805*b) / 0.95047
	y := 0.2126*r + 0.7152*g + 0.0722*b
	z := (0.0193*r + 0.1192*g + 0.9505*b) / 1.08883
	f := func(t float64) float64 {
		if t > 0.008856 {
			return math.Cbrt(t)
		}
		return 7.787*t + 16.0/116.0
	}
	fx, fy, fz := f(x), f(y), f(z)
	return Lab{116*fy - 16, 500 * (fx - fy), 200 * (fy - fz)}
}

func degrees(rad float64) float64 { return rad * 180 / math.Pi }
func radians(deg float64) float64 { return deg * math.Pi / 180 }

func hueOf(ap, b float64) float64 {
	if ap == 0 && b == 0 {
		return 0.0
	}
	d := math.Mod(degrees(math.Atan2(b, ap)), 360)
	if d < 0 {
		d += 360
	}
	return d
}

// DeltaELab は Lab 2 点の CIEDE2000 の色差。
func DeltaELab(a, b Lab) float64 {
	l1, a1, b1 := a[0], a[1], a[2]
	l2, a2, b2 := b[0], b[1], b[2]

	cBar := (math.Hypot(a1, b1) + math.Hypot(a2, b2)) / 2
	g := 0.5 * (1 - math.Sqrt(math.Pow(cBar, 7)/(math.Pow(cBar, 7)+math.Pow(25.0, 7))))
	ap1, ap2 := (1+g)*a1, (1+g)*a2
	cp1, cp2 := math.Hypot(ap1, b1), math.Hypot(ap2, b2)
	hp1, hp2 := hueOf(ap1, b1), hueOf(ap2, b2)

	dL := l2 - l1
	dC := cp2 - cp1
	var dH, hBar float64
	if cp1*cp2 == 0 {
		dH = 0.0
		hBar = hp1 + hp2
	} else {
		dH = hp2 - hp1
		if dH > 180 {
			dH -= 360
		} else if dH < -180 {
			dH += 360
		}
		total := hp1 + hp2
		if math.Abs(hp1-hp2) <= 180 {
			hBar = total / 2
		} else if total < 360 {
			hBar = (total + 360) / 2
		} else {
			hBar = (total - 360) / 2
		}
	}
	bigH := 2 * math.Sqrt(cp1*cp2) * math.Sin(radians(dH)/2)

	lBar := (l1 + l2) / 2
	cpBar := (cp1 + cp2) / 2
	t := 1 -
		0.17*math.Cos(radians(hBar-30)) +
		0.24*math.Cos(radians(2*hBar)) +
		0.32*math.Cos(radians(3*hBar+6)) -
		0.20*math.Cos(radians(4*hBar-63))
	sL := 1 + (0.015*math.Pow(lBar-50, 2))/math.Sqrt(20+math.Pow(lBar-50, 2))
	sC := 1 + 0.045*cpBar
	sH := 1 + 0.015*cpBar*t
	rT := -2 * math.Sqrt(math.Pow(cpBar, 7)/(math.Pow(cpBar, 7)+math.Pow(25.0, 7))) *
		math.Sin(radians(60*math.Exp(-math.Pow((hBar-275)/25, 2))))

	termC, termH := dC/sC, bigH/sH
	return math.Sqrt(math.Pow(dL/sL, 2) + termC*termC + termH*termH + rT*termC*termH)
}

// DeltaE は "#rrggbb" 2 つの色差。
func DeltaE(hexA, hexB string) float64 {
	return DeltaELab(LabOfHex(hexA), LabOfHex(hexB))
}
