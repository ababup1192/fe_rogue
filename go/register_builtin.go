package main

import "strings"

// 画素・波形を扱う 6 本の名乗り。仕様が外部で決まっていて動かない検査だけがここにいる。
//
// WhyNot: 新しいサブコマンドをこのファイルへ足さない。1 本につき cmd_<名前>.go を
// 新しく作って、そこで register する（同時に足す人どうしが衝突しないため）。
func init() {
	register("digest", "絵の差を数値で要約 (2 枚 or フォルダ)",
		func(out, _ *strings.Builder, rest []string, asJSON bool) int {
			return cmdDigest(out, rest, asJSON)
		})
	register("loop", "ループ GIF の継ぎ目 (最終コマ→0 コマ) が浮かないか",
		func(out, _ *strings.Builder, rest []string, asJSON bool) int {
			return cmdLoop(out, rest, asJSON)
		})
	register("sil", "ドット絵を目視用の PNG に描き出す",
		func(out, _ *strings.Builder, rest []string, asJSON bool) int {
			return cmdSil(out, rest, asJSON)
		})
	register("images", "git に入れる絵が増えすぎていないか",
		func(out, _ *strings.Builder, rest []string, asJSON bool) int {
			return runImages(out, rootArg(rest), asJSON)
		})
	register("audio", "音名が SfxRender・project.json・コードの 3 か所でそろっているか",
		func(out, _ *strings.Builder, rest []string, asJSON bool) int {
			return runAudio(out, rootArg(rest), asJSON)
		})
	register("palette", "ドット絵 legend の意味色キーが色票から解けるか",
		func(out, _ *strings.Builder, rest []string, asJSON bool) int {
			return runPalette(out, rootArg(rest), asJSON)
		})
}
