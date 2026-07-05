// Palette — View が使う色の番地: DB32（DawnBringer 32）から選んだ、役割名つきの色定数。
//
// 規約: 描画コードは色リテラルを直接書かない。ここで定義したロール名だけを参照する。
// 各 def は /255 で正規化した DB32 の正確な16進値を返す（目分量や近似は無し）。色を32色に
// 限ることで色選びの迷いを消す。ロール名はそれを最初に使う場面で足す。

mod Palette {

    // ── 背景 ──
    def background(): Color = {r = 0.133333f32, g = 0.125490f32, b = 0.203922f32}  // #222034

    // ── 壁（プレイフィールドの枠）──
    pub def wallFace(): Color = {r = 0.411765f32, g = 0.415686f32, b = 0.415686f32}  // #696a6a

    // ── パドル（プレイヤー）──
    // 面シェーディングの帯: 上端 = highlight、地 = body、下端 = shadow。
    // 中央セグメント = highlight（真上へ返る「安全地帯」が明るい）、
    // 端セグメント = edge のアクセント（鋭角に飛ぶ「攻めの帯」が目立つ）。
    pub def paddleBody(): Color = {r = 0.388235f32, g = 0.607843f32, b = 1.000000f32}       // #639bff
    pub def paddleHighlight(): Color = {r = 0.796078f32, g = 0.858824f32, b = 0.988235f32}  // #cbdbfc
    pub def paddleShadow(): Color = {r = 0.356863f32, g = 0.431373f32, b = 0.882353f32}     // #5b6ee1
    pub def paddleEdge(): Color = {r = 0.874510f32, g = 0.443137f32, b = 0.149020f32}       // #df7126

    // ── 壊れないブロック（金属）──
    // 面シェーディング（上端=明・地=中・下端=影）とリベットで「据え付け」を読ませる。
    pub def metalFace(): Color = {r = 0.517647f32, g = 0.494118f32, b = 0.529412f32}   // #847e87
    pub def metalTop(): Color = {r = 0.607843f32, g = 0.678431f32, b = 0.717647f32}    // #9badb7
    pub def metalShade(): Color = {r = 0.349020f32, g = 0.337255f32, b = 0.321569f32}  // #595652
    pub def rivet(): Color = {r = 0.796078f32, g = 0.858824f32, b = 0.988235f32}       // #cbdbfc

    // ── ボール ──
    pub def ball(): Color = {r = 0.984314f32, g = 0.949020f32, b = 0.211765f32}  // #fbf236

    // ── ボールの残像（速さで色が変わるランプ）──
    // 3 段の役割: 基準の速さ = 冷（淡い青白）、加速中 = 温（黄）、上限近く = 熱（橙）。
    pub def trailCool(): Color = {r = 0.796078f32, g = 0.858824f32, b = 0.988235f32}  // #cbdbfc
    pub def trailWarm(): Color = {r = 0.984314f32, g = 0.949020f32, b = 0.211765f32}  // #fbf236
    pub def trailHot(): Color = {r = 0.874510f32, g = 0.443137f32, b = 0.149020f32}   // #df7126

    /// 加速の道のり ratio（0=基準 … 1=上限）を残像の色へ写す 3 段ランプ。
    /// 3 分の 1 までは冷、4 分の 3 までは温、それより上は熱。
    pub def trailColor(ratio: Float64): Color =
        if (ratio < 0.3333) trailCool()
        else if (ratio < 0.75) trailWarm()
        else trailHot()

    // ── 通常ブロック（行ごとに色を変える）──
    /// 行 row の通常ブロック色。5 つの明るい DB32 ロールを行の並びに配る。
    pub def blockRow(row: Int32): Color = match Int32.modulo(row, 5) {
        case 0 => {r = 0.850980f32, g = 0.341176f32, b = 0.388235f32}  // #d95763 赤
        case 1 => {r = 0.874510f32, g = 0.443137f32, b = 0.149020f32}  // #df7126 橙
        case 2 => {r = 0.984314f32, g = 0.949020f32, b = 0.211765f32}  // #fbf236 黄
        case 3 => {r = 0.600000f32, g = 0.898039f32, b = 0.313725f32}  // #99e550 緑
        case _ => {r = 0.372549f32, g = 0.803922f32, b = 0.894118f32}  // #5fcde4 水
    }

    // ── ハードブロック（2発）──
    /// まだ2発耐えるハードブロックの色（明るい鋼）。
    pub def hardFull(): Color = {r = 0.796078f32, g = 0.858824f32, b = 0.988235f32}  // #cbdbfc
    /// 1発当たって残り1発のハードブロックの色（くすんだ鋼 = ひび割れて見える）。
    pub def hardChipped(): Color = {r = 0.607843f32, g = 0.678431f32, b = 0.717647f32}  // #9badb7

    // ── 破壊の破片 ──
    /// 破片 i の色: 明るい DB32 ロールをラウンドロビンで配る。
    pub def fragment(i: Int32): Color = match Int32.modulo(i, 4) {
        case 0 => {r = 0.984314f32, g = 0.949020f32, b = 0.211765f32}  // #fbf236
        case 1 => {r = 0.933333f32, g = 0.764706f32, b = 0.603922f32}  // #eec39a
        case 2 => {r = 0.796078f32, g = 0.858824f32, b = 0.988235f32}  // #cbdbfc
        case _ => {r = 1.000000f32, g = 1.000000f32, b = 1.000000f32}  // #ffffff
    }

    // ── テキスト ──
    pub def titleText(): Color = {r = 0.933333f32, g = 0.764706f32, b = 0.603922f32}  // #eec39a
    pub def scoreText(): Color = {r = 1.000000f32, g = 1.000000f32, b = 1.000000f32}  // #ffffff
    pub def clearText(): Color = {r = 0.600000f32, g = 0.898039f32, b = 0.313725f32}  // #99e550
    pub def overText(): Color  = {r = 0.850980f32, g = 0.341176f32, b = 0.388235f32}  // #d95763

    /// background は project.json の clearColor と等しい；これはコード側のアクセサ。
    pub def clearColor(): Color = background()
}
