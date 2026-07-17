/// UiToggle — ON/OFF 2 状態を切り替える行の純粋ヘルパ。
/// 見た目の出し分けは「マーク欄の文言を差し替える」を第一候補にする
/// （UiBinding が担う bind 機構をそのまま使えるので、ヘルパは文言を決めるだけの薄さで足りる）。
/// ピル型スイッチ（track+knob）で見せたいときは pillApply が track 色と knob 位置も書き込む
/// （UiSlider.projectTo/apply と同じ「純粋計算 → 書き込み」の分業）。
mod UiToggle {

    /// on/off を切り替えた次の状態。
    pub def toggled(on: Bool): Bool = not on

    /// on/off をマーク欄の文言へ変換する。onText/offText は ui.json 側の色・記号に
    /// 合わせてゲームが決める（例: "ON"/"OFF"、"✓"/" "）。
    pub def markText(on: Bool, onText: String, offText: String): String =
        if (on) onText else offText

    /// namePath 配下の `${namePath}/mark` へマーク文言を書き込む。
    pub def apply(namePath: String, on: Bool, onText: String, offText: String, ui: UiStore.UiWorld): UiStore.UiWorld =
        UiStore.setText("${namePath}/mark", markText(on, onText, offText), ui)

    /// ピルの見た目（track 色・knob のトラック内 x）を on/off から導く。
    /// knobX は track 左端基準のつまみ中心 x（OFF=左端寄り、ON=右端寄り）。
    /// knobDiameter ぶん内側へ収めるのは、knob の中心を端に置くと半分が track からはみ出るため。
    pub def pillProjectTo(on: Bool, trackWidth: Float64, knobDiameter: Float64,
                          onColor: Color, offColor: Color): { trackColor = Color, knobX = Float64 } =
        let inset = knobDiameter / 2.0;
        let knobX = if (on) trackWidth - inset else inset;
        { trackColor = (if (on) onColor else offColor), knobX = clamp(knobX, inset, trackWidth - inset) }

    /// namePath 配下の `${namePath}/track` の色と `${namePath}/track/knob` の位置を書き込む
    /// （knob は track の子 — スライダーの knob と同じ「track 基準の子」規約に揃える）。
    /// knobY は track 高さの中心などトラック基準の固定 y（呼び側が渡す。UiSlider.apply と同じ分業）。
    pub def pillApply(namePath: String, on: Bool, trackWidth: Float64, knobDiameter: Float64, knobY: Float64,
                      onColor: Color, offColor: Color, ui: UiStore.UiWorld): UiStore.UiWorld =
        let proj = pillProjectTo(on, trackWidth, knobDiameter, onColor, offColor);
        ui
            |> UiStore.setBoxColor("${namePath}/track", proj#trackColor)
            |> UiStore.setAbs("${namePath}/track/knob", { x = proj#knobX - knobDiameter / 2.0, y = knobY })

    def clamp(v: Float64, lo: Float64, hi: Float64): Float64 =
        Float64.max(lo, Float64.min(hi, v))
}
