// Palette — DB32（DawnBringer 32）、プロジェクト標準のパレットから選ばれた、役
// 割名付きの色定数。
//
// 規約: 描画コードは色リテラルを直接書かない。ここで定義されたロール名だけを参
// 照する。各 def は /255 で正規化された DB32 の正確な16進値を返す（目分量や近似
// は無し）。選択肢を32色に限ることで、色選びの迷いを取り除く。ロール名は、それ
// を最初に使う章で追加される。

mod Palette {

    // ── 背景 ──
    def background(): Color = {r = 0.133333f32, g = 0.125490f32, b = 0.203922f32}  // #222034

    // ── 木のクレート ──
    pub def cratePlank(): Color = {r = 0.560784f32, g = 0.337255f32, b = 0.231373f32}  // #8f563b
    pub def crateFrame(): Color = {r = 0.400000f32, g = 0.223529f32, b = 0.192157f32}  // #663931
    pub def crateSeam(): Color  = {r = 0.270588f32, g = 0.156863f32, b = 0.235294f32}  // #45283c
    pub def crateBrace(): Color = {r = 0.850980f32, g = 0.627451f32, b = 0.400000f32}  // #d9a066

    // ── ロボット（プレイヤー）──
    pub def robotBody(): Color = {r = 0.356863f32, g = 0.431373f32, b = 0.882353f32}  // #5b6ee1
    pub def robotTrim(): Color = {r = 0.388235f32, g = 0.607843f32, b = 1.000000f32}  // #639bff
    pub def robotEye(): Color  = {r = 0.796078f32, g = 0.858824f32, b = 0.988235f32}  // #cbdbfc
    pub def robotDark(): Color = {r = 0.133333f32, g = 0.125490f32, b = 0.203922f32}  // #222034
    pub def robotAccent(): Color = {r = 0.984314f32, g = 0.949020f32, b = 0.211765f32}  // #fbf236

    // ── ボードのタイル ──
    pub def wallFace(): Color  = {r = 0.411765f32, g = 0.415686f32, b = 0.415686f32}  // #696a6a
    pub def wallTop(): Color   = {r = 0.517647f32, g = 0.494118f32, b = 0.529412f32}  // #847e87
    pub def wallShade(): Color = {r = 0.349020f32, g = 0.337255f32, b = 0.321569f32}  // #595652
    pub def floorTile(): Color = {r = 0.196078f32, g = 0.235294f32, b = 0.223529f32}  // #323c39
    pub def goalMark(): Color  = {r = 0.600000f32, g = 0.898039f32, b = 0.313725f32}  // #99e550

    // ── 巻き戻し時計 ──
    pub def clockFace(): Color = {r = 1.000000f32, g = 1.000000f32, b = 1.000000f32}  // #ffffff
    pub def clockRim(): Color  = {r = 0.133333f32, g = 0.125490f32, b = 0.203922f32}  // #222034

    // ── テキスト ──
    pub def titleText(): Color = {r = 0.933333f32, g = 0.764706f32, b = 0.603922f32}  // #eec39a
    pub def clearText(): Color = {r = 0.984314f32, g = 0.949020f32, b = 0.211765f32}  // #fbf236

    // ── 紙吹雪 ──
    /// 切れ端 i の色: 5つの明るい DB32 ロールをラウンドロビンで配る。
    pub def confetti(i: Int32): Color = match Int32.modulo(i, 5) {
        case 0 => {r = 0.984314f32, g = 0.949020f32, b = 0.211765f32}  // #fbf236
        case 1 => {r = 0.600000f32, g = 0.898039f32, b = 0.313725f32}  // #99e550
        case 2 => {r = 0.388235f32, g = 0.607843f32, b = 1.000000f32}  // #639bff
        case 3 => {r = 0.933333f32, g = 0.764706f32, b = 0.603922f32}  // #eec39a
        case _ => {r = 0.796078f32, g = 0.858824f32, b = 0.988235f32}  // #cbdbfc
    }

    // background は project.json の clearColor と等しい；これはコード側のアク
    // セサである。
    pub def clearColor(): Color = background()
}
