package f32

// f32 — エンジンの公開 API に `Float32` が出ていないかを検査するゲート。
//
//	fge-go f32                       pub 面ぜんぶを検査
//	fge-go f32 --self-test           抽出が複数行の宣言と eff の op を拾えるかだけ見る
//	fge-go f32 --root DIR            リポジトリの根を差し替える
//	fge-go f32 [path/to/X.flix ...]  ファイルを名指しで検査する
//
// 規則は 1 本だけ: engine / engine_world / engine_tools の pub 面（型・関数・eff の op）に
// `Float32` を出さない。Float32 は GL / OpenAL / STB の境界の内側だけ。
//
// Flix のデフォルトの小数は Float64 で、Float32 のリテラルには `f32` サフィックスが要る。
// pub 面に Float32 が混ざっていると、ゲームを書く側は型が合わないコンパイルエラーで
// 初めてそれに気づき、`f32` を足して再コンパイルする往復を強いられる。
//
// 宣言の抽出は flixdecl に寄せてある（api-digest と同じ層）。二重管理しないためと、
// `pub type alias GradVertex = { ..., alpha = Float32 }` のような複数行の宣言や、
// `pub` の付かない eff の op を自前の正規表現で解き直さないため。

import (
	"fmt"
	"sort"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/ababup1192/flix_game_engine/go/internal/flixdecl"
)

// hit は pub 面に出ている Float32 1 件。
type hit struct {
	path string
	mod  string
	name string
	decl string
}

func (h hit) key() string { return h.mod + "." + h.name }

// hasFloat32 は語として独立した Float32 が含まれるかを見る。
// WhyNot: `\bFloat32\b` の正規表現をそのまま使わないのは、Go の `\b` が ASCII しか
// 語とみなさず、直前が漢字の Float32 を語として拾ってしまうため。
func hasFloat32(s string) bool {
	const word = "Float32"
	for i := 0; ; {
		j := strings.Index(s[i:], word)
		if j < 0 {
			return false
		}
		start := i + j
		end := start + len(word)
		if !isWordAt(s, start, true) && !isWordAt(s, end, false) {
			return true
		}
		i = start + 1
	}
}

// isWordAt は位置 i の（before なら手前の）文字が語の文字かを返す。
func isWordAt(s string, i int, before bool) bool {
	var r rune
	if before {
		if i <= 0 {
			return false
		}
		r, _ = utf8.DecodeLastRuneInString(s[:i])
	} else {
		if i >= len(s) {
			return false
		}
		r, _ = utf8.DecodeRuneInString(s[i:])
	}
	return r == '_' || unicode.IsLetter(r) || unicode.IsDigit(r)
}

// scanSource は .flix 1 本の pub 面から Float32 を拾う。rel は表示に使うパス。
func scanSource(path, rel string) ([]hit, error) {
	mods, err := flixdecl.ScanFile(path)
	if err != nil {
		return nil, err
	}
	return hitsOf(mods, rel), nil
}

func hitsOf(mods []flixdecl.ModDecls, rel string) []hit {
	var hits []hit
	for _, md := range mods {
		for _, d := range md.Decls {
			if hasFloat32(d.Text) {
				hits = append(hits, hit{path: rel, mod: md.Mod, name: flixdecl.DeclName(d.Text), decl: d.Text})
			}
		}
	}
	return hits
}

// allHits は 3 パッケージの pub 面ぜんぶを見る。
func allHits(root string) []hit {
	var hits []hit
	for _, pkg := range flixdecl.Packages {
		for _, file := range flixdecl.ScanPackage(root, pkg) {
			hits = append(hits, hitsOf(file.Mods, file.Rel)...)
		}
	}
	return hits
}

// report は結果を書き出して終了コードを返す。
func report(out *strings.Builder, exempt map[string]string, hits []hit) int {
	keys := make([]string, 0, len(exempt))
	for key := range exempt {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	for _, key := range keys {
		fmt.Fprintf(out, "除外: %s — %s\n", key, exempt[key])
	}

	var bad []hit
	live := map[string]bool{}
	for _, h := range hits {
		live[h.key()] = true
		if _, ok := exempt[h.key()]; !ok {
			bad = append(bad, h)
		}
	}
	var stale []string
	for _, key := range keys {
		if !live[key] {
			stale = append(stale, key)
		}
	}
	if len(stale) > 0 {
		for _, key := range stale {
			fmt.Fprintf(out, "  %s は EXEMPT に載っていますが、そこに Float32 はもうありません\n", key)
		}
		fmt.Fprintf(out, "[lint-f32] 古い除外 %d 件。"+
			"宿題の一覧として読めなくなるので EXEMPT から消してください\n", len(stale))
		return 1
	}
	if len(bad) == 0 {
		fmt.Fprintf(out, "[lint-f32] OK (pub 面の Float32 %d 件 / 除外 %d 件)\n", len(hits), len(exempt))
		return 0
	}
	for _, h := range bad {
		fmt.Fprintf(out, "  %s: %s.%s の pub 面に Float32 があります\n", h.path, h.mod, h.name)
		fmt.Fprintf(out, "      %s\n", flixdecl.Truncate(h.decl, 110))
	}
	fmt.Fprintf(out, "[lint-f32] pub 面の Float32 %d 件。"+
		"\n  ゲームを書く側は Float64 と Int32 だけで済むのが決まりです。"+
		"型を Float64 にして、Float32 への変換は GL / OpenAL / STB を呼ぶ手前まで下げてください"+
		"\n  どうしても残すなら bin/lint-f32.py の EXEMPT へ"+
		" \"モジュール名.宣言名\" と理由 1 行を書いてください\n", len(bad))
	return 1
}

// sample は自己検査に使う見本（複数行の type alias と eff の op を含む）。
const sample = `
mod Demo {
    /// GL へ渡す値
    pub type alias GradVertex = {
        at = Vec2.Vec2,
        alpha = Float32
    }

    pub def clean(v: Float64): Float64 = v

    pub eff Audio {
        /// 音量
        def setVolume(name: String, volume: Float32): Unit
        def stopAudio(name: String): Unit
    }

    // Float32 とコメントに書いただけ
    pub def quiet(): String = "Float32"
}
`

func selfTest(out *strings.Builder, exempt map[string]string) (int, error) {
	hits := hitsOf(flixdecl.ScanText(sample), "self-test.flix")
	keys := make([]string, 0, len(hits))
	for _, h := range hits {
		keys = append(keys, h.key())
	}
	sort.Strings(keys)
	want := []string{"Demo.Audio.setVolume", "Demo.GradVertex"}
	if strings.Join(keys, ",") != strings.Join(want, ",") {
		return 2, fmt.Errorf("自己検査に失敗: 拾った宣言が %v (期待 %v)", keys, want)
	}
	for key, reason := range exempt {
		if !strings.Contains(key, ".") || strings.TrimSpace(reason) == "" {
			return 2, fmt.Errorf("自己検査に失敗: 除外 %q の形が違います", key)
		}
	}
	fmt.Fprintf(out, "[lint-f32] self-test OK "+
		"(複数行の type alias と eff の op を拾う / 除外 %d 件はすべて理由付き)\n", len(exempt))
	return 0, nil
}

// Options は呼ぶ側が差し替えられる所。Exempt が nil なら規約ファイルから読む。
type Options struct {
	Exempt map[string]string
}

// Run は検査を走らせて終了コードを返す。
// err が返ったとき呼ぶ側は必ず止まる（規約を読めないまま緑にしない）。
func Run(out, errOut *strings.Builder, root string, args []string, opts Options) (int, error) {
	exempt := opts.Exempt
	if exempt == nil {
		rules, err := LoadRules(root)
		if err != nil {
			return 2, err
		}
		exempt = rules.Exempt
	}

	selfTestMode := false
	var files []string
	for _, a := range args {
		switch {
		case a == "--self-test":
			selfTestMode = true
		case strings.HasPrefix(a, "--"):
			// WhyNot: 知らない旗を弾かないのは、--check を付けた呼び方でも黙って
			// 通常の検査を走らせるため（make check-docs-sync がそう呼ぶ）。
		default:
			files = append(files, a)
		}
	}

	if selfTestMode {
		return selfTest(out, exempt)
	}

	if len(files) > 0 {
		var hits []hit
		for _, path := range files {
			found, err := scanSource(path, flixdecl.RelTo(root, path))
			if err != nil {
				return 2, fmt.Errorf("読めません: %v", err)
			}
			hits = append(hits, found...)
		}
		return report(out, exempt, hits), nil
	}
	return report(out, exempt, allHits(root)), nil
}
