// SfxBake — BGM 実験用の音源も生成されるアセット: Bake.all が assets/sfx/ へ WAV を書き出し、
// project.json のサウンドマニフェスト（looping=true）が起動時に読み込む。
// このファイルはサウンドデザインだけを持ち、合成と WAV エンコードは engine_tools（SfxSynth）に住む。

mod SfxBake {

    /// 22050Hz モノラル: フェードの聴き比べには十分でファイルが小さい。
    def cfg(): SfxSynth.Config = { sampleRate = 22050 }

    /// BGM: 低めの 3 音を行って返るループ（A3 → C#4 → E4 → C#4）。
    /// 各音 500ms・控えめな振幅で、音量の変化（フェード・マスター）が耳で追いやすい。
    def bgmLoop(): List[Float64] =
        SfxSynth.sequence(
            SfxSynth.tone(cfg(), 220.0, 0.15, 500) ::
            SfxSynth.tone(cfg(), 277.18, 0.15, 500) ::
            SfxSynth.tone(cfg(), 329.63, 0.15, 500) ::
            SfxSynth.tone(cfg(), 277.18, 0.15, 500) :: Nil)

    pub def bakeAll(): Unit \ IO =
        SfxSynth.bakeSet(cfg(), "assets/sfx", ("bgm", bgmLoop()) :: Nil)
}
