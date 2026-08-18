// Package style は焼いた PNG を測って「画風の軸がズレていないか」を言う検査。
package style

import (
	"fmt"
	"os"
	"sort"
	"strings"
)

// docHead は引数が無いときに出す 1 行の説明。
const docHead = "焼いた PNG を測って「画風の軸がズレていないか」を言う。"

// baseName は最後の / より後ろを返す（区切りで終わるなら空文字）。
// WhyNot: filepath.Base を使わないのは、末尾が区切りのときに "." や親の名前を返し、
// ディレクトリを絵のファイルと取り違えるため。
func baseName(path string) string {
	if i := strings.LastIndex(path, "/"); i >= 0 {
		return path[i+1:]
	}
	return path
}

func hexColor(col uint32) string {
	return fmt.Sprintf("#%02x%02x%02x", (col>>16)&255, (col>>8)&255, col&255)
}

// guessHand はファイル名から描き手を当てる。当たらなければ空文字。
func (r *Rules) guessHand(path string) string {
	name := strings.ToLower(baseName(path))
	for _, g := range r.HandGuess {
		for _, word := range g.Words {
			if strings.Contains(name, word) {
				return g.Hand
			}
		}
	}
	return ""
}

// gridText は格子適合率の表示（None なら「—」）。
func gridText(st *Stats) string {
	if !st.HasGrid {
		return "—"
	}
	return fmt.Sprintf("%.0f%%", 100*st.Grid)
}

func (r *Rules) describe(st *Stats, showRegions bool) []string {
	unit := fmt.Sprintf("unit=%d", st.Unit)
	if st.UnitAuto {
		unit += "(自動)"
	}
	lines := []string{
		fmt.Sprintf("%s  %dx%d  %s", baseName(st.Path), st.Width, st.Height, unit),
		fmt.Sprintf("  中間色 %.1f%%   格子適合 %s   楕円で説明できる面 %.1f%%",
			st.AA, gridText(st), st.Ellipse),
		fmt.Sprintf("  色数 %d (画面の 90%% を覆う色 %d)   平均輝度 %.0f",
			st.Colors, st.Cover90, st.Luma),
	}
	steps := make([]string, 4)
	for i := 0; i < 4; i++ {
		steps[i] = fmt.Sprintf("%s:%.0f%%", r.StepLabels[i], st.Steps[i])
	}
	lines = append(lines, "  隣の色の段: "+strings.Join(steps, "  "))
	lines = append(lines, fmt.Sprintf("  明度 3 段: 暗 %.0f%% / 中 %.0f%% / 明 %.0f%%",
		st.Luma3[0], st.Luma3[1], st.Luma3[2]))
	if showRegions && len(st.Regions) > 0 {
		top := st.Regions
		if len(top) > 5 {
			top = top[:5]
		}
		parts := make([]string, 0, len(top))
		for _, reg := range top {
			parts = append(parts, fmt.Sprintf("%s %.0f%%@%s", hexColor(reg.Col), reg.Area, reg.Pos))
		}
		lines = append(lines, "  大きい面: "+strings.Join(parts, "  "))
	}
	return lines
}

// judge は (NG の並び, 注意の並び) を返す。
func (r *Rules) judge(st *Stats, hand string) (bad, warn []string) {
	name := baseName(st.Path)
	if t, ok := r.Hands[hand]; ok {
		switch {
		case st.AA > t.AaBad:
			bad = append(bad, fmt.Sprintf(
				"%s: 中間色が %.1f%% — ドット絵になっていません "+
					"(輪郭がなめらかに溶けている。%s 系は %.0f%% 以下)",
				name, st.AA, hand, t.AaWarn))
		case st.AA > t.AaWarn:
			warn = append(warn, fmt.Sprintf(
				"%s: 中間色が %.1f%% と多め (境目がぼけ始めている)", name, st.AA))
		}
		switch {
		case !st.HasGrid:
			warn = append(warn, fmt.Sprintf(
				"%s: 画素の目が見つかりません (unit=1) — "+
					"出力を等倍で焼いているか、段が格子に乗っていません", name))
		case st.Grid < t.GridBad:
			bad = append(bad, fmt.Sprintf(
				"%s: 格子適合 %.0f%% (unit=%d) — 輪郭の段が画素の目に"+
					"乗っていません (ベクター調の曲線)", name, 100*st.Grid, st.Unit))
		case st.Grid < t.GridWarn:
			warn = append(warn, fmt.Sprintf(
				"%s: 格子適合 %.0f%% (unit=%d) と甘い", name, 100*st.Grid, st.Unit))
		}
		switch {
		case st.Cover90 > t.CoverBad:
			bad = append(bad, fmt.Sprintf(
				"%s: 画面の 90%% を覆うのに %d 色 — パレットで塗っていません "+
					"(%s 系は %d 色まで)", name, st.Cover90, hand, t.CoverWarn))
		case st.Cover90 > t.CoverWarn:
			warn = append(warn, fmt.Sprintf(
				"%s: 画面の 90%% を覆うのに %d 色 (色を絞れていない)", name, st.Cover90))
		}
		switch {
		case st.Colors > t.ColorsBad:
			bad = append(bad, fmt.Sprintf(
				"%s: 全体の色数 %d — %s 系の色の予算 (%d 色) から桁で"+
					"外れています", name, st.Colors, hand, t.ColorsWarn))
		case st.Colors > t.ColorsWarn:
			warn = append(warn, fmt.Sprintf(
				"%s: 全体の色数 %d — %s 系の目安は %d 色", name, st.Colors, hand, t.ColorsWarn))
		}
		// 楕円の判定は画素で描く 2 本だけ。なめらかな絵では面を色で丸めて切り出す
		// ので、取れる面がそもそも本物の塊ではない (数字は出すが判定しない)。
		if st.Ellipse >= r.EllipseWarn {
			warn = append(warn, fmt.Sprintf(
				"%s: 画面の %.1f%% が楕円そのものの面 — 塊を楕円の"+
					"重ね合わせで作っています (目立ちます)", name, st.Ellipse))
		}
		return bad, warn
	}
	if hand == "smooth" {
		if st.AA < r.Smooth.AaMin {
			warn = append(warn, fmt.Sprintf(
				"%s: 中間色が %.1f%% しかない — なめらかさが出ていません "+
					"(段で塗っている)", name, st.AA))
		}
		if st.HasGrid && st.Grid >= r.Smooth.GridMax {
			warn = append(warn, fmt.Sprintf(
				"%s: 格子適合 %.0f%% (unit=%d) — 画素の目が見えています "+
					"(ドット絵側へ寄っている)", name, 100*st.Grid, st.Unit))
		}
		if st.Colors < r.Smooth.ColorsMin {
			warn = append(warn, fmt.Sprintf(
				"%s: 色数 %d と少なすぎ — 面が段になって見えます (banding)", name, st.Colors))
		}
	}
	return bad, warn
}

// compare は 2 枚の差を出す。「fine と smooth の差がほぼ無い」を機械に言わせる所。
func (r *Rules) compare(a, b *Stats, handA, handB string) (lines, bad []string) {
	lines = append(lines, fmt.Sprintf("%s <-> %s の差", baseName(a.Path), baseName(b.Path)))
	dAA := b.AA - a.AA
	// 色数は絵の大きさに比例して増えるので、1000 画素あたりに直してから比べる。
	ratio := (b.ColorsPerKpx + 0.01) / (a.ColorsPerKpx + 0.01)
	lines = append(lines, fmt.Sprintf("  中間色 %.1f%% -> %.1f%% (差 %+.1f ポイント)",
		a.AA, b.AA, dAA))
	lines = append(lines, fmt.Sprintf(
		"  色数 %d -> %d   1000 画素あたり %.1f -> %.1f (%.2f 倍)   90%% を覆う色 %d -> %d",
		a.Colors, b.Colors, a.ColorsPerKpx, b.ColorsPerKpx, ratio, a.Cover90, b.Cover90))
	lines = append(lines, fmt.Sprintf("  格子適合 %s (unit=%d) -> %s (unit=%d)",
		gridText(a), a.Unit, gridText(b), b.Unit))
	lines = append(lines, fmt.Sprintf("  楕円で説明できる面 %.1f%% -> %.1f%%", a.Ellipse, b.Ellipse))
	lines = append(lines, fmt.Sprintf("  明度 3 段 暗/中/明 %.0f/%.0f/%.0f -> %.0f/%.0f/%.0f",
		a.Luma3[0], a.Luma3[1], a.Luma3[2], b.Luma3[0], b.Luma3[1], b.Luma3[2]))

	sameAA := absFloat(dAA) < r.SameAa
	sameColor := (1.0/r.SameColorRatio) < ratio && ratio < r.SameColorRatio
	if handA != "" && handB != "" && handA != handB && sameAA && sameColor {
		bad = append(bad, fmt.Sprintf(
			"%s と %s の差がほぼありません "+
				"(中間色の差 %+.1f ポイント・色数 %.2f 倍) — "+
				"描き手を分けた意味が絵に出ていません", handA, handB, dAA, ratio))
	}
	return lines, bad
}

func absFloat(v float64) float64 {
	if v < 0 {
		return -v
	}
	return v
}

// parsed はコマンドラインから読み取った指定。
type parsed struct {
	strict      bool
	doCompare   bool
	showRegions bool
	hand        string
	unit        int
	hasUnit     bool
	files       []string
}

// parseArgs の第 2 の返り値が false なら、出すべき文言を out へ書いた上で 1 で終わる。
func parseArgs(out *strings.Builder, argv []string) (parsed, bool) {
	p := parsed{}
	for _, a := range argv {
		switch a {
		case "--strict":
			p.strict = true
		case "--compare":
			p.doCompare = true
		case "--regions":
			p.showRegions = true
		}
	}
	var args []string
	for _, a := range argv {
		if a != "--strict" && a != "--compare" && a != "--regions" {
			args = append(args, a)
		}
	}
	for i := 0; i < len(args); {
		a := args[i]
		if a == "--hand" && i+1 < len(args) {
			p.hand = args[i+1]
			i += 2
			continue
		}
		if a == "--unit" && i+1 < len(args) {
			n, ok := pyInt(args[i+1])
			if !ok {
				fmt.Fprintf(out, "--unit には数を渡してください: %s\n", args[i+1])
				return p, false
			}
			p.unit, p.hasUnit = n, true
			i += 2
			continue
		}
		if strings.HasPrefix(a, "--") {
			fmt.Fprintf(out, "知らないオプション: %s\n", a)
			return p, false
		}
		p.files = append(p.files, a)
		i++
	}
	return p, true
}

// Run は検査を走らせて終了コードを返す。
// err が返ったとき呼ぶ側は必ず止まる（規約を読めないまま緑にしない）。
func Run(out, errOut *strings.Builder, root string, args []string) (int, error) {
	rules, err := LoadRules(root)
	if err != nil {
		return 2, err
	}

	p, ok := parseArgs(out, args)
	if !ok {
		return 1, nil
	}
	if len(p.files) == 0 {
		fmt.Fprintln(out, docHead)
		fmt.Fprintln(out, "使い方: bin/fge style --hand fine --unit 2 debug/style/*.png")
		fmt.Fprintln(out, "        bin/fge style --compare a.png b.png")
		return 1, nil
	}
	if p.hand != "" && !rules.isHandName(p.hand) {
		fmt.Fprintf(out, "--hand は coarse / fine / smooth のどれか: %s\n", p.hand)
		return 1, nil
	}
	if p.doCompare && len(p.files) != 2 {
		fmt.Fprintln(out, "--compare は PNG を 2 枚だけ渡してください")
		return 1, nil
	}

	var stats []*Stats
	var hands []string
	for _, path := range p.files {
		if !isFile(path) {
			fmt.Fprintf(out, "見つからない: %s\n", path)
			return 1, nil
		}
		st, err := rules.Measure(path, p.unit, p.hasUnit)
		if err != nil {
			fmt.Fprintf(out, "測れない: %s (%v)\n", path, err)
			return 1, nil
		}
		stats = append(stats, st)
		if p.hand != "" {
			hands = append(hands, p.hand)
		} else {
			hands = append(hands, rules.guessHand(path))
		}
	}

	var badTotal, warnTotal []string
	if p.doCompare {
		lines, bad := rules.compare(stats[0], stats[1], hands[0], hands[1])
		for _, st := range stats {
			for _, line := range rules.describe(st, p.showRegions) {
				fmt.Fprintln(out, line)
			}
		}
		for _, line := range lines {
			fmt.Fprintln(out, line)
		}
		badTotal = append(badTotal, bad...)
	} else {
		for i, st := range stats {
			for _, line := range rules.describe(st, p.showRegions) {
				fmt.Fprintln(out, line)
			}
			if hands[i] == "" {
				warnTotal = append(warnTotal, fmt.Sprintf(
					"%s: 描き手が分かりません — --hand を渡すと判定します", baseName(st.Path)))
				continue
			}
			b, w := rules.judge(st, hands[i])
			badTotal = append(badTotal, b...)
			warnTotal = append(warnTotal, w...)
		}
	}

	for _, w := range warnTotal {
		fmt.Fprintf(out, "注意: %s\n", w)
	}
	if len(badTotal) == 0 {
		fmt.Fprintf(out, "OK: 画風の軸ズレはありません（注意 %d 件）\n", len(warnTotal))
		if p.strict && len(warnTotal) > 0 {
			return 1, nil
		}
		return 0, nil
	}

	fmt.Fprintln(errOut, "")
	for _, b := range badTotal {
		fmt.Fprintf(errOut, "NG: %s\n", b)
	}
	seen := map[string]bool{}
	var tips []string
	for _, h := range hands {
		hint, ok := rules.HandHints[h]
		if !ok || seen[hint] {
			continue
		}
		seen[hint] = true
		tips = append(tips, hint)
	}
	sort.Strings(tips)
	if len(tips) > 0 {
		fmt.Fprintln(errOut, "")
		fmt.Fprintln(errOut, "手つきの在り処: "+strings.Join(tips, " / "))
	}
	return 1, nil
}

func isFile(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.Mode().IsRegular()
}
