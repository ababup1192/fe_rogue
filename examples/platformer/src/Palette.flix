// Palette — View が使う色: DB32（DawnBringer 32）から選んだ、役割名つきの色定数。
//
// 規約: 描画コードは色リテラルを直接書かない。ここで定義したロール名だけを参照する。
// 各 def は /255 で正規化した DB32 の正確な16進値を返す。ロール名はそれを最初に使う場面で足す。

mod Palette {

    // ── 背景（project.json の clearColor と同じ値。ギャラリーの焼き込みが使う）──
    pub def clearColor(): Color = {r = 0.133333f32, g = 0.125490f32, b = 0.203922f32}  // #222034

    // ── 地形 ──
    pub def ground(): Color = {r = 0.411765f32, g = 0.415686f32, b = 0.415686f32}    // #696a6a
    pub def platform(): Color = {r = 0.607843f32, g = 0.678431f32, b = 0.717647f32}  // #9badb7
    pub def wall(): Color = {r = 0.349020f32, g = 0.337255f32, b = 0.321569f32}      // #595652

    // ── プレイヤー（球体）──
    pub def player(): Color = {r = 0.984314f32, g = 0.949020f32, b = 0.211765f32}    // #fbf236

    // ── HUD ──
    pub def hudText(): Color = {r = 1.000000f32, g = 1.000000f32, b = 1.000000f32}   // #ffffff
    pub def hintText(): Color = {r = 0.933333f32, g = 0.764706f32, b = 0.603922f32}  // #eec39a
}
