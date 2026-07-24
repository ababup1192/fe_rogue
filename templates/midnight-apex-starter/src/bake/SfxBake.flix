// SfxBake — MIDNIGHT APEX のオリジナル効果音とBGMを決定的にWAVへ焼く。
// 音の意匠だけを持ち、合成とファイル形式はエンジンの SfxSynth に任せる。
mod SfxBake {

    /// レトロな矩形波へ十分な音質と小さなファイルを両立する設定。
    def config(): SfxSynth.Config = { sampleRate = 22050 }

    /// 2本の駆動ループを含む全11音を project.json と同じ名前で書き出す。
    pub def bakeAll(): Unit \ IO =
        SfxSynth.bakeSet(
            config(),
            "assets/sfx",
            ("bgm", bgm()) ::
            ("engine_low", engineLow()) ::
            ("engine_high", engineHigh()) ::
            ("launch", launch()) ::
            ("accelerate", accelerate()) ::
            ("boost", boost()) ::
            ("brake", brake()) ::
            ("collision", collision()) ::
            ("wall", wall()) ::
            ("jump", jump()) ::
            ("explode", explode()) ::
            Nil)

    /// 低いベース、2部構成の分散和音、電子ドラムを重ねた8秒のループ。
    def bgm(): List[Float64] =
        let bass = SfxSynth.sequence(
            bassNote(55.0) :: bassNote(55.0) :: bassNote(65.41) :: bassNote(82.41) ::
            bassNote(55.0) :: bassNote(73.42) :: bassNote(65.41) :: bassNote(49.0) ::
            bassNote(55.0) :: bassNote(55.0) :: bassNote(65.41) :: bassNote(98.0) ::
            bassNote(82.41) :: bassNote(73.42) :: bassNote(65.41) :: bassNote(49.0) ::
            bassNote(55.0) :: bassNote(65.41) :: bassNote(73.42) :: bassNote(82.41) ::
            bassNote(55.0) :: bassNote(49.0) :: bassNote(65.41) :: bassNote(73.42) ::
            bassNote(55.0) :: bassNote(82.41) :: bassNote(98.0) :: bassNote(110.0) ::
            bassNote(82.41) :: bassNote(73.42) :: bassNote(65.41) :: bassNote(49.0) ::
            Nil);
        let lead = SfxSynth.sequence(
            leadNote(220.0) :: leadNote(261.63) :: leadNote(329.63) :: leadNote(392.0) ::
            leadNote(261.63) :: leadNote(329.63) :: leadNote(440.0) :: leadNote(329.63) ::
            leadNote(220.0) :: leadNote(293.66) :: leadNote(349.23) :: leadNote(440.0) ::
            leadNote(392.0) :: leadNote(329.63) :: leadNote(293.66) :: leadNote(246.94) ::
            leadNote(220.0) :: leadNote(329.63) :: leadNote(392.0) :: leadNote(493.88) ::
            leadNote(440.0) :: leadNote(392.0) :: leadNote(329.63) :: leadNote(293.66) ::
            leadNote(261.63) :: leadNote(349.23) :: leadNote(440.0) :: leadNote(523.25) ::
            leadNote(493.88) :: leadNote(392.0) :: leadNote(293.66) :: leadNote(246.94) ::
            Nil);
        let rhythm = List.range(0, 32)
            |> List.map(rhythmStep)
            |> SfxSynth.sequence;
        SfxSynth.blend(SfxSynth.blend(bass, lead), rhythm)

    /// BGMの低音1拍。
    def bassNote(frequency: Float64): List[Float64] =
        SfxSynth.tone(config(), frequency, 0.075, 250)

    /// BGMの高音1拍。ベースより小さくして効果音の場所を残す。
    def leadNote(frequency: Float64): List[Float64] =
        SfxSynth.tone(config(), frequency, 0.033, 250)

    /// 4拍ごとの低いキックと、その間を刻む短い金属音。
    def rhythmStep(index: Int32): List[Float64] =
        if (Int32.modulo(index, 4) == 0)
            SfxSynth.sequence(
                (SfxSynth.tone(config(), 52.0, 0.10, 90) |> SfxSynth.fade)
                :: silence(160) :: Nil)
        else
            SfxSynth.sequence(
                (SfxSynth.noise(config(), 0.028, 42)
                    |> SfxSynth.rasp
                    |> SfxSynth.fade)
                :: silence(208) :: Nil)

    def silence(ms: Int32): List[Float64] =
        SfxSynth.tone(config(), 1.0, 0.0, ms)

    /// 低回転域の太い駆動ループ。高回転と同じ1秒にそろえて継ぎ目を合わせる。
    def engineLow(): List[Float64] =
        SfxSynth.blend(
            SfxSynth.tone(config(), 58.0, 0.10, 1000),
            SfxSynth.tone(config(), 116.0, 0.035, 1000))

    /// 速度が上がるほど前へ出る、同じ長さの高回転ループ。
    def engineHigh(): List[Float64] =
        SfxSynth.blend(
            SfxSynth.tone(config(), 132.0, 0.075, 1000),
            SfxSynth.tone(config(), 264.0, 0.030, 1000))

    /// レース開始を告げる短い上昇音。
    def launch(): List[Float64] =
        SfxSynth.sequence(
            SfxSynth.tone(config(), 220.0, 0.10, 80) ::
            SfxSynth.tone(config(), 329.63, 0.12, 80) ::
            SfxSynth.tone(config(), 440.0, 0.14, 130) ::
            Nil)
            |> SfxSynth.fade

    /// アクセルを踏み込んだ時の三段階の駆動音。
    def accelerate(): List[Float64] =
        SfxSynth.sequence(
            SfxSynth.tone(config(), 110.0, 0.11, 90) ::
            SfxSynth.tone(config(), 165.0, 0.10, 90) ::
            SfxSynth.tone(config(), 220.0, 0.08, 130) ::
            Nil)
            |> SfxSynth.fade

    /// 加速帯と手動ブーストに共通する、雑音と低音の噴射。
    def boost(): List[Float64] =
        SfxSynth.blend(
            SfxSynth.noise(config(), 0.13, 340) |> SfxSynth.rasp,
            SfxSynth.tone(config(), 92.5, 0.12, 340))
            |> SfxSynth.fade

    /// ブレーキの擦過音と下降する電子音。
    def brake(): List[Float64] =
        SfxSynth.blend(
            SfxSynth.noise(config(), 0.10, 300) |> SfxSynth.rasp,
            SfxSynth.sequence(
                SfxSynth.tone(config(), 190.0, 0.07, 100) ::
                SfxSynth.tone(config(), 140.0, 0.07, 100) ::
                SfxSynth.tone(config(), 90.0, 0.06, 100) ::
                Nil))
            |> SfxSynth.fade

    /// 接触を伝える低い打音。長く鳴らして操作音を隠さない。
    def collision(): List[Float64] =
        SfxSynth.blend(
            SfxSynth.noise(config(), 0.16, 190),
            SfxSynth.tone(config(), 55.0, 0.16, 190))
            |> SfxSynth.fade

    /// 電磁壁から弾かれる、短い上昇音と硬い雑音。
    def wall(): List[Float64] =
        SfxSynth.blend(
            SfxSynth.noise(config(), 0.12, 220) |> SfxSynth.rasp,
            SfxSynth.sequence(
                SfxSynth.tone(config(), 120.0, 0.10, 90) ::
                SfxSynth.tone(config(), 240.0, 0.08, 130) ::
                Nil))
            |> SfxSynth.fade

    /// 台を離れる瞬間の軽い上昇音。
    def jump(): List[Float64] =
        SfxSynth.sequence(
            SfxSynth.tone(config(), 180.0, 0.08, 80) ::
            SfxSynth.tone(config(), 270.0, 0.09, 90) ::
            SfxSynth.tone(config(), 405.0, 0.07, 120) ::
            Nil)
            |> SfxSynth.fade

    /// 機体喪失を伝える低い爆発。雑音を二段にし、通常接触より長く残す。
    def explode(): List[Float64] =
        SfxSynth.blend(
            SfxSynth.sequence(
                SfxSynth.noise(config(), 0.22, 260) ::
                SfxSynth.noise(config(), 0.13, 360) :: Nil)
                |> SfxSynth.fade,
            SfxSynth.tone(config(), 42.0, 0.18, 620)
                |> SfxSynth.fade)
}
