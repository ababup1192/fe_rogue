// SfxBake — 6 つの効果音は生成されるアセット: make bake（Bake.all）が assets/sfx/ へ
// 16 ビットモノラル PCM WAV として書き出し、project.json のサウンドマニフェストが
// 起動時に読み込む。サンプルも録音も無し — SfxSynth の矩形波・ノイズ・フェードだけ。
// このファイルはサウンドデザインだけを持ち、合成と WAV エンコードは engine_tools にある。
mod SfxBake {

    /// 22050Hz モノラル: この程度のブリップには十分。
    def cfg(): SfxSynth.Config = { sampleRate = 22050 }

    // ── 6 つの音: それぞれが SfxSynth の語彙に対するデザイン ──

    /// 歩行: 靴音。「カツッ」— 低いトーンの芯に短いノイズの粒をかぶせ、強くフェードさせる。
    def moveStep(): List[Float64] =
        SfxSynth.blend(
            SfxSynth.fade(SfxSynth.fade(SfxSynth.noise(cfg(), 0.16, 26))),
            SfxSynth.fade(SfxSynth.tone(cfg(), 196.0, 0.14, 22)))

    /// 話しかけ: 昔の RPG の会話ふうの「ど・ど・ど・ど・ど」。同じ音を 5 回連続で鳴らす。
    /// pitch で声の高さを変えられる（1.0 = ふつうの人。高い人・低い人を作り分ける）。
    def talkPop(pitch: Float64): List[Float64] =
        let blip = talkBlip(261.63 * pitch);
        SfxSynth.sequence(blip :: blip :: blip :: blip :: blip :: Nil)

    /// 会話の 1 音: 控えめな矩形波 + ひと呼吸の間。
    def talkBlip(freq: Float64): List[Float64] =
        SfxSynth.sequence(
            SfxSynth.fade(SfxSynth.tone(cfg(), freq, 0.12, 60)) ::
            silence(70) :: Nil)

    /// 確認メニュー: 短い高音のチック（選択が確定に近づく緊張）。
    def confirmTick(): List[Float64] = SfxSynth.fade(SfxSynth.tone(cfg(), 1318.5, 0.15, 30))

    /// 不正解: クイズ番組の「ブブー」。低い矩形波の短いブと長いブーの 2 連。
    def wrongBuzz(): List[Float64] =
        SfxSynth.sequence(
            SfxSynth.tone(cfg(), 110.0, 0.3, 150) ::
            silence(60) ::
            SfxSynth.fade(SfxSynth.tone(cfg(), 110.0, 0.32, 420)) :: Nil)

    /// 正解: 上昇する 4 音のファンファーレ — C5、E5、G5、C6。
    def clearFanfare(): List[Float64] =
        SfxSynth.sequence(
            SfxSynth.fade(SfxSynth.tone(cfg(), 523.25, 0.2, 90)) ::
            SfxSynth.fade(SfxSynth.tone(cfg(), 659.25, 0.2, 90)) ::
            SfxSynth.fade(SfxSynth.tone(cfg(), 783.99, 0.2, 90)) ::
            SfxSynth.fade(SfxSynth.tone(cfg(), 1046.5, 0.22, 240)) :: Nil)

    /// メモの書き込み: 羽ペンで走り書きする「シャッシャッ」。ノイズを rasp（差分フィルタ）で
    /// かすれさせ、太い低音を落とした高い擦過音を 2 筆（2 筆目は少し長く・弱く引く）。
    def memoScratch(): List[Float64] =
        SfxSynth.sequence(
            SfxSynth.fade(SfxSynth.rasp(SfxSynth.noise(cfg(), 0.35, 90))) ::
            silence(50) ::
            SfxSynth.fade(SfxSynth.fade(SfxSynth.rasp(SfxSynth.noise(cfg(), 0.3, 130)))) :: Nil)

    /// BGM: 木製の柱時計の針。「コチ・・カチ・・・」の 2 打 + 間を 1 ループにした静かな音
    /// （project.json 側で looping = true にして鳴らしっぱなしにする）。
    def clockTickLoop(): List[Float64] =
        SfxSynth.sequence(
            tickClick(523.25) ::
            silence(1100) ::
            tickClick(392.0) ::
            silence(1400) :: Nil)

    /// コチ 1 打: 低めの短い芯（木を叩いた「コッ」）にノイズの粒。音量は BGM なので控えめ。
    def tickClick(freq: Float64): List[Float64] =
        SfxSynth.blend(
            SfxSynth.fade(SfxSynth.fade(SfxSynth.tone(cfg(), freq, 0.09, 16))),
            SfxSynth.fade(SfxSynth.fade(SfxSynth.noise(cfg(), 0.04, 8))))

    /// 無音（振幅 0 のトーン）。ループの「間」を作る。
    def silence(ms: Int32): List[Float64] =
        SfxSynth.tone(cfg(), 100.0, 0.0, ms)

    /// 6 音すべてを assets/sfx/ へ書き出す（Bake.all から呼ぶ）。
    pub def bakeAll(): Unit \ IO =
        SfxSynth.bakeSet(cfg(), "assets/sfx",
            ("move", moveStep()) :: ("talk_mid", talkPop(1.0)) :: ("talk_high", talkPop(1.4)) ::
            ("talk_low", talkPop(0.72)) :: ("confirm", confirmTick()) :: ("wrong", wrongBuzz()) ::
            ("clear", clearFanfare()) :: ("memo", memoScratch()) :: ("bgm_tick", clockTickLoop()) :: Nil)
}
