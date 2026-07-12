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

    /// 崖死亡: 下降する 3 音。穴へ消えた。
    def deathFall(): List[Float64] =
        SfxSynth.sequence(
            SfxSynth.fade(SfxSynth.tone(cfg(), 392.0, 0.1, 60)) ::
            SfxSynth.fade(SfxSynth.tone(cfg(), 261.63, 0.12, 60)) ::
            SfxSynth.fade(SfxSynth.tone(cfg(), 174.61, 0.2, 70)) :: Nil)

    /// 踏みつけ: 高→低の短い 2 音。ぷちっと潰した手応え。
    def stompSquish(): List[Float64] =
        SfxSynth.sequence(
            SfxSynth.fade(SfxSynth.tone(cfg(), 660.0, 0.04, 50)) ::
            SfxSynth.fade(SfxSynth.tone(cfg(), 330.0, 0.07, 55)) :: Nil)

    /// クリア: 上昇する 4 音の短いファンファーレ（C-E-G-C）。ゴール到達の一瞬。
    def clearFanfare(): List[Float64] =
        SfxSynth.sequence(
            SfxSynth.fade(SfxSynth.tone(cfg(), 523.25, 0.09, 55)) ::
            SfxSynth.fade(SfxSynth.tone(cfg(), 659.25, 0.09, 55)) ::
            SfxSynth.fade(SfxSynth.tone(cfg(), 783.99, 0.09, 55)) ::
            SfxSynth.fade(SfxSynth.tone(cfg(), 1046.5, 0.22, 60)) :: Nil)

    /// 中間地点: 上昇する 2 音の短いジングル。「ここまで来た」の刻印。
    def checkpointChime(): List[Float64] =
        SfxSynth.sequence(
            SfxSynth.fade(SfxSynth.tone(cfg(), 587.33, 0.07, 50)) ::
            SfxSynth.fade(SfxSynth.tone(cfg(), 880.0, 0.12, 55)) :: Nil)

    /// 花火: 短いノイズの破裂 + 低いドン。クリア後の夜空に 10 発鳴る。
    def fireworkPop(): List[Float64] =
        SfxSynth.blend(
            SfxSynth.fade(SfxSynth.noise(cfg(), 0.08, 55)),
            SfxSynth.fade(SfxSynth.tone(cfg(), 98.0, 0.15, 60)))

    /// キャラ切り替え: 上がる短い 2 音のブリップ。「乗り換えのポン」。
    def switchBlip(): List[Float64] =
        SfxSynth.sequence(
            SfxSynth.fade(SfxSynth.tone(cfg(), 523.25, 0.04, 45)) ::
            SfxSynth.fade(SfxSynth.tone(cfg(), 784.0, 0.06, 50)) :: Nil)

    /// ガード: 高い 2 音を重ねた金属的なチン。「弾いた」手応え。
    def guardTink(): List[Float64] =
        SfxSynth.blend(
            SfxSynth.fade(SfxSynth.tone(cfg(), 1318.5, 0.06, 40)),
            SfxSynth.fade(SfxSynth.tone(cfg(), 1975.5, 0.05, 30)))

    /// 10 音すべてを assets/sfx/ へ書き出す（Bake.all から呼ぶ）。
    pub def bakeAll(): Unit \ IO =
        SfxSynth.bakeSet(cfg(), "assets/sfx",
            ("jump", jumpRise()) :: ("land", landThud()) :: ("bump", bumpTick()) ::
            ("death", deathFall()) :: ("stomp", stompSquish()) :: ("clear", clearFanfare()) ::
            ("checkpoint", checkpointChime()) :: ("firework", fireworkPop()) ::
            ("switch", switchBlip()) :: ("guard", guardTink()) :: Nil)
}
