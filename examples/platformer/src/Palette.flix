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

    // ── 地形（役割ごとの色分け。同じ 16 進値でも意味が違う場所は別ロール名にする）──
    pub def grassTop(): Color = {r = 0.415686f32, g = 0.745098f32, b = 0.188235f32}    // #6abe30
    pub def dirtBody(): Color = {r = 0.560784f32, g = 0.337255f32, b = 0.231373f32}    // #8f563b
    pub def stoneWall(): Color = {r = 0.411765f32, g = 0.415686f32, b = 0.415686f32}   // #696a6a
    pub def plankOneWay(): Color = {r = 0.850980f32, g = 0.627451f32, b = 0.400000f32} // #d9a066
    pub def plankShadow(): Color = {r = 0.560784f32, g = 0.337255f32, b = 0.231373f32} // #8f563b
    pub def moverPlate(): Color = {r = 0.372549f32, g = 0.803922f32, b = 0.894118f32}  // #5fcde4
    pub def slopeGrass(): Color = {r = 0.415686f32, g = 0.745098f32, b = 0.188235f32}  // #6abe30
    pub def goalFlag(): Color = {r = 0.600000f32, g = 0.898039f32, b = 0.313725f32}    // #99e550

    // ── プレイヤー（球体）──
    pub def player(): Color = {r = 0.984314f32, g = 0.949020f32, b = 0.211765f32}    // #fbf236
    pub def playerDash(): Color = {r = 0.874510f32, g = 0.443137f32, b = 0.149020f32} // #df7126
    pub def playerMax(): Color = {r = 1.000000f32, g = 1.000000f32, b = 1.000000f32}  // #ffffff
    pub def ballSpin(): Color = {r = 0.541176f32, g = 0.435294f32, b = 0.188235f32}   // #8a6f30

    // ── 敵 ──
    pub def walkerBody(): Color = {r = 0.674510f32, g = 0.196078f32, b = 0.196078f32}  // #ac3232
    pub def flyerBody(): Color = {r = 0.843137f32, g = 0.482353f32, b = 0.729412f32}   // #d77bba
    pub def flyerWing(): Color = {r = 0.796078f32, g = 0.858824f32, b = 0.988235f32}   // #cbdbfc
    pub def spikyBody(): Color = {r = 0.462745f32, g = 0.266667f32, b = 0.384314f32}   // #764462
    pub def spikeTip(): Color = {r = 0.796078f32, g = 0.858824f32, b = 0.988235f32}    // #cbdbfc
    pub def eyeWhite(): Color = {r = 1.000000f32, g = 1.000000f32, b = 1.000000f32}    // #ffffff
    pub def eyePupil(): Color = {r = 0.133333f32, g = 0.125490f32, b = 0.203922f32}    // #222034

    // ── 花火（クリア演出・DB32 の 4 色を発ごとに巡回）──
    pub def fireworkA(): Color = {r = 0.984314f32, g = 0.949020f32, b = 0.211765f32}   // #fbf236
    pub def fireworkB(): Color = {r = 0.600000f32, g = 0.898039f32, b = 0.313725f32}   // #99e550
    pub def fireworkC(): Color = {r = 0.372549f32, g = 0.803922f32, b = 0.894118f32}   // #5fcde4
    pub def fireworkD(): Color = {r = 0.843137f32, g = 0.482353f32, b = 0.729412f32}   // #d77bba

    /// 花火の色を発番号（seed）から選ぶ: A→B→C→D の巡回。
    pub def fireworkColor(seed: Int32): Color =
        let m = Int32.modulo(seed, 4);
        if (m == 0) fireworkA() else if (m == 1) fireworkB() else if (m == 2) fireworkC() else fireworkD()

    // ── 演出の粒（ダッシュの土埃・ジャンプの噴射）──
    pub def dustPuff(): Color = {r = 0.850980f32, g = 0.627451f32, b = 0.400000f32}   // #d9a066
    pub def jetPuff(): Color = {r = 0.796078f32, g = 0.858824f32, b = 0.988235f32}    // #cbdbfc

    // ── HUD ──
    pub def hudText(): Color = {r = 1.000000f32, g = 1.000000f32, b = 1.000000f32}   // #ffffff
    pub def hintText(): Color = {r = 0.933333f32, g = 0.764706f32, b = 0.603922f32}  // #eec39a
}
