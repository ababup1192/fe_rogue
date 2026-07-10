// SfxBake — 3 つの効果音も、ギャラリーと同様に生成されるアセットである: Bake.all が
// assets/sfx/ へ素の 16 ビットモノラル PCM WAV として書き出し、project.json のサウンド
// マニフェストが起動時にそれらを読み込む。SfxSynth の矩形波・ノイズ・フェードだけで、
// 跳ねる球体の語彙になる。
mod SfxBake {

    /// 22050Hz モノラル: 小さいファイルで、この程度のブリップには十分。
    def cfg(): SfxSynth.Config = { sampleRate = 22050 }

    /// ジャンプ: 上昇する 2 音のブリップ。飛び立ちの軽さ。
    def jumpRise(): List[Float64] =
        SfxSynth.sequence(
            SfxSynth.fade(SfxSynth.tone(cfg(), 440.0, 0.05, 45)) ::
            SfxSynth.fade(SfxSynth.tone(cfg(), 700.0, 0.07, 50)) :: Nil)

    /// 着地: 低い音と短いノイズ —— 地面を踏んだ手応え。
    def landThud(): List[Float64] =
        SfxSynth.blend(
            SfxSynth.fade(SfxSynth.tone(cfg(), 150.0, 0.09, 60)),
            SfxSynth.fade(SfxSynth.fade(SfxSynth.noise(cfg(), 0.05, 40))))

    /// 頭ぶつけ: 鈍く短いチック。天井に当たった。
    def bumpTick(): List[Float64] =
        SfxSynth.fade(SfxSynth.tone(cfg(), 260.0, 0.05, 45))

    /// 3 音すべてを assets/sfx/ へ書き出す（Bake.all から呼ぶ）。
    pub def bakeAll(): Unit \ IO =
        SfxSynth.bakeSet(cfg(), "assets/sfx",
            ("jump", jumpRise()) :: ("land", landThud()) :: ("bump", bumpTick()) :: Nil)
}
