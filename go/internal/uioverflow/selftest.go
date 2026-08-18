package uioverflow

// この検査自身の検査。判定 1 つずつに見本を当て、出るはずの物が出るかを見る。

import (
	"fmt"
	"strings"
)

// obj は見本を組み立てる小物。
func obj(pairs ...any) map[string]any {
	m := make(map[string]any, len(pairs)/2)
	for i := 0; i+1 < len(pairs); i += 2 {
		m[pairs[i].(string)] = pairs[i+1]
	}
	return m
}

// with は元を変えずに鍵を足した写しを返す。
func with(base map[string]any, pairs ...any) map[string]any {
	m := make(map[string]any, len(base)+len(pairs)/2)
	for k, v := range base {
		m[k] = v
	}
	for i := 0; i+1 < len(pairs); i += 2 {
		m[pairs[i].(string)] = pairs[i+1]
	}
	return m
}

func rooted(root map[string]any) map[string]any {
	return obj("version", float64(1), "root", root)
}

func (r *Rules) selfTest(out *strings.Builder) int {
	text := obj("name", "label", "widget", "text", "text", "ながいながい文言")
	var lines []string
	bad := 0
	check := func(name string, doc map[string]any, needle string) {
		notes := r.CheckDoc(doc, &stats{})
		hit := len(notes) == 0
		if needle != "" {
			hit = false
			for _, n := range notes {
				if strings.Contains(n, needle) {
					hit = true
					break
				}
			}
		}
		if hit {
			lines = append(lines, "OK  "+name)
			return
		}
		bad++
		lines = append(lines, fmt.Sprintf("NG  %s: %s", name, pyReprList(notes)))
	}

	check("固定幅パネル内の宣言なし text は注意",
		rooted(obj("name", "panel", "width", float64(120), "children", []any{with(text)})),
		"宣言していない")
	check("wrap: \"auto\" 宣言があれば合格",
		rooted(obj("name", "panel", "width", float64(120),
			"children", []any{with(text, "wrap", "auto")})), "")
	check("wrap: 数値(px) 宣言があれば合格",
		rooted(obj("name", "panel", "width", float64(120),
			"children", []any{with(text, "wrap", float64(96))})), "")
	check("fit: true 宣言があれば合格",
		rooted(obj("name", "panel", "width", float64(120),
			"children", []any{with(text, "fit", true)})), "")
	check("真偽値 wrap は flex wrap で別物 — 宣言と数えず注意",
		rooted(obj("name", "panel", "width", float64(120),
			"children", []any{with(text, "wrap", true)})), "宣言していない")
	check("auto-size の枠 (width 未指定) は構造上はみ出せないので対象外",
		rooted(obj("name", "panel", "children", []any{with(text)})), "")
	check("grow は素通しして更に上の固定幅を見る",
		rooted(obj("name", "outer", "width", float64(200), "children", []any{
			obj("name", "inner", "width", "grow", "children", []any{with(text)})})),
		"固定幅 200px")
	check("grow の上が auto なら見逃す側を選んで対象外",
		rooted(obj("name", "outer", "children", []any{
			obj("name", "inner", "width", "grow", "children", []any{with(text)})})), "")
	check("text 自身の固定幅も枠として見る",
		rooted(obj("name", "panel", "children", []any{with(text, "width", float64(80))})),
		"固定幅 80px")
	check("理由付き lint-ui 宣言で除外できる",
		rooted(obj("name", "panel", "width", float64(120),
			"children", []any{with(text, "lint-ui", "対象外 — スコア表示は桁固定")})), "")
	check("instance ノードは対象外 (UiDoc が唯一のパーサ)",
		rooted(obj("name", "panel", "width", float64(120), "children", []any{
			obj("name", "sub", "instance", "assets/ui/sub.ui.json")})), "")
	check("use テンプレの width もノードに重ねて見る",
		obj("version", float64(1),
			"templates", obj("fixed", obj("width", float64(150))),
			"root", obj("name", "panel", "use", "fixed", "children", []any{with(text)})),
		"固定幅 150px")

	for _, line := range lines {
		fmt.Fprintf(out, "%s\n", line)
	}
	fmt.Fprintf(out, "\n%d/%d 件 OK\n", len(lines)-bad, len(lines))
	if bad > 0 {
		return 1
	}
	return 0
}
