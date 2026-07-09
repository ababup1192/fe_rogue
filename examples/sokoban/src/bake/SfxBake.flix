// SfxBake — 4つの効果音は、ギャラリーと同様に生成されるアセットである: make bake
// （Bake.all）が assets/sfx/ へ素の16ビットモノラル PCM WAV ファイルとして書き出し、
// project.json のサウンドマニフェストが起動時にそれらを読み込む。サンプルパック
// も録音も無し —— SfxSynth の矩形波、ノイズバースト、フェードだけで、箱を押すロ
// ボットには十分な語彙になる。このファイルはサウンドデザインだけを保持し、合成
// と WAV エンコードは engine_tools にある。
mod SfxBake {

    /// 22050Hz モノラル: 小さいファイルで、この程度のブリップには十分。
    def cfg(): SfxSynth.Config = { sampleRate = 22050 }

    // ── 4つの音: それぞれが SfxSynth の語彙に対するデザイン ──

    /// 歩行: 短い中音のブリップ。
    def moveBlip(): List[Float64] = SfxSynth.fade(SfxSynth.tone(cfg(), 660.0, 0.22, 45))

    /// 押し: 鋭く減衰するノイズバーストの下に低い矩形波 —— 木が床を擦る音。ノイ
    /// ズは2回フェードするので、トーンより先に消える。
    def pushThud(): List[Float64] =
        SfxSynth.blend(
            SfxSynth.fade(SfxSynth.tone(cfg(), 98.0, 0.3, 90)),
            SfxSynth.fade(SfxSynth.fade(SfxSynth.noise(cfg(), 0.22, 90))))

    /// 巻き戻し: 巻き戻された1手につき高い音のチックが1つ、時計の声で。
    def undoTick(): List[Float64] = SfxSynth.fade(SfxSynth.tone(cfg(), 1568.0, 0.16, 22))

    /// CLEAR: 上昇する4つの矩形波の音 —— C5、E5、G5、C6。
    def clearFanfare(): List[Float64] =
        SfxSynth.sequence(
            SfxSynth.fade(SfxSynth.tone(cfg(), 523.25, 0.2, 90)) ::
            SfxSynth.fade(SfxSynth.tone(cfg(), 659.25, 0.2, 90)) ::
            SfxSynth.fade(SfxSynth.tone(cfg(), 783.99, 0.2, 90)) ::
            SfxSynth.fade(SfxSynth.tone(cfg(), 1046.5, 0.22, 240)) :: Nil)

    /// 4 音すべてを assets/sfx/ へ書き出す（Bake.all から呼ぶ）。
    pub def bakeAll(): Unit \ IO =
        SfxSynth.bakeSet(cfg(), "assets/sfx",
            ("move", moveBlip()) :: ("push", pushThud()) ::
            ("undo", undoTick()) :: ("clear", clearFanfare()) :: Nil)
}
