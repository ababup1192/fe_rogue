// SfxBake — 8 つの効果音も、ギャラリーと同様に生成されるアセットである: Bake.all（bin/flix run --entrypoint Bake.all）が
// assets/sfx/ へ素の 16 ビットモノラル PCM WAV として書き出し、project.json のサウンド
// マニフェストが起動時にそれらを読み込む。サンプルパックも録音も無し —— SfxSynth の
// 矩形波・ノイズバースト・フェードだけで、ボールと煉瓦の語彙になる。
// このファイルはサウンドデザインだけを保持し、合成と WAV エンコードは engine_tools に住む。
mod SfxBake {

    /// 22050Hz モノラル: 小さいファイルで、この程度のブリップには十分。
    def cfg(): SfxSynth.Config = { sampleRate = 22050 }

    // ── 8 つの音: それぞれが SfxSynth の語彙に対するデザイン ──

    /// パドル: 明るく短い高音のブリップ。ラリーの拍を刻む主役。
    def paddleBlip(): List[Float64] = SfxSynth.fade(SfxSynth.tone(cfg(), 880.0, 0.06, 50))

    /// 壁: パドルより低く小さいチック。往復のこだま。
    def wallTick(): List[Float64] = SfxSynth.fade(SfxSynth.tone(cfg(), 330.0, 0.05, 40))

    /// ハードが耐えた: 低い矩形波の上に鋭いノイズ —— 金属を叩いた手応え。
    def chipClang(): List[Float64] =
        SfxSynth.blend(
            SfxSynth.fade(SfxSynth.tone(cfg(), 180.0, 0.12, 70)),
            SfxSynth.fade(SfxSynth.fade(SfxSynth.noise(cfg(), 0.08, 60))))

    /// 破壊: 明るい音とノイズの弾け。煉瓦が砕ける。
    def breakPop(): List[Float64] =
        SfxSynth.blend(
            SfxSynth.fade(SfxSynth.tone(cfg(), 587.33, 0.1, 60)),
            SfxSynth.fade(SfxSynth.fade(SfxSynth.noise(cfg(), 0.06, 50))))

    /// サーブ: 上昇する 2 音。ボールが飛び立つ。
    def serveRise(): List[Float64] =
        SfxSynth.sequence(
            SfxSynth.fade(SfxSynth.tone(cfg(), 440.0, 0.07, 50)) ::
            SfxSynth.fade(SfxSynth.tone(cfg(), 660.0, 0.09, 55)) :: Nil)

    /// ミス: 下降する低い 2 音。ボールが底へ消えた。
    def missFall(): List[Float64] =
        SfxSynth.sequence(
            SfxSynth.fade(SfxSynth.tone(cfg(), 220.0, 0.15, 60)) ::
            SfxSynth.fade(SfxSynth.tone(cfg(), 146.83, 0.25, 60)) :: Nil)

    /// CLEAR: 上昇する 4 音のファンファーレ —— C5、E5、G5、C6。
    def clearFanfare(): List[Float64] =
        SfxSynth.sequence(
            SfxSynth.fade(SfxSynth.tone(cfg(), 523.25, 0.15, 90)) ::
            SfxSynth.fade(SfxSynth.tone(cfg(), 659.25, 0.15, 90)) ::
            SfxSynth.fade(SfxSynth.tone(cfg(), 783.99, 0.15, 90)) ::
            SfxSynth.fade(SfxSynth.tone(cfg(), 1046.5, 0.2, 240)) :: Nil)

    /// GAME OVER: 下降する 3 音 —— G4、Eb4、C4。
    def gameOverFall(): List[Float64] =
        SfxSynth.sequence(
            SfxSynth.fade(SfxSynth.tone(cfg(), 392.0, 0.18, 80)) ::
            SfxSynth.fade(SfxSynth.tone(cfg(), 311.13, 0.18, 80)) ::
            SfxSynth.fade(SfxSynth.tone(cfg(), 261.63, 0.3, 160)) :: Nil)

    /// 8 音すべてを assets/sfx/ へ書き出す（Bake.all から呼ぶ）。
    pub def bakeAll(): Unit \ IO =
        SfxSynth.bakeSet(cfg(), "assets/sfx",
            ("paddle", paddleBlip()) :: ("wall", wallTick()) :: ("chip", chipClang()) ::
            ("break", breakPop()) :: ("serve", serveRise()) :: ("miss", missFall()) ::
            ("clear", clearFanfare()) :: ("gameover", gameOverFall()) :: Nil)
}
