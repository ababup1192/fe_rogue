// RadialGlow の画素計算を具体値で固定する。
//
// haloPixel（Addハロ用: rgb白固定・alpha落ち）と maskPixel（Multiply暗幕用: alpha固定・rgb落ち）は
// 呼び違えると効果が出ない事故になる 2 つの別規約なので、両方を独立に pin する。
// 契約テスト（末尾）は SoftRaster.blendPixel に通した結果まで確かめ、
// 「maskPixel の中心は本当に素通し・縁は本当に真っ暗になる」ことをコンパイル後も機械的に守る。
mod TestRadialGlow {

    /// ARGB int から (a, r, g, b) を取り出す（テストの比較用）。
    def channels(p: Int32): (Int32, Int32, Int32, Int32) =
        let c = shift -> Int32.bitwiseAnd(Int32.logicalRightShift(dist = shift, p), 255);
        (c(24), c(16), c(8), c(0))

    // ── haloPixel: rgb は常に白固定、alpha だけが curve で変わる ──

    // 中心（t=0）は curve が 1.0 を返す想定 → alpha=255・rgb=255 固定。
    @Test
    def testHaloPixelCenterIsFullAlpha(): Unit \ Assert =
        let out = RadialGlow.haloPixel(RadialGlow.linearCurve, 0.0);
        Assert.assertEq(expected = (255, 255, 255, 255), channels(out))

    // 縁（t=1）は curve が 0.0 を返す想定 → alpha=0（rgb は白のままで変わらない）。
    @Test
    def testHaloPixelEdgeIsZeroAlpha(): Unit \ Assert =
        let out = RadialGlow.haloPixel(RadialGlow.linearCurve, 1.0);
        Assert.assertEq(expected = (0, 255, 255, 255), channels(out))

    // 中間（t=0.5）は中心と縁のあいだで alpha が単調に下がる。
    @Test
    def testHaloPixelAlphaDecreasesMonotonically(): Unit \ Assert =
        let (a0, _, _, _) = channels(RadialGlow.haloPixel(RadialGlow.linearCurve, 0.0));
        let (aMid, _, _, _) = channels(RadialGlow.haloPixel(RadialGlow.linearCurve, 0.5));
        let (aEdge, _, _, _) = channels(RadialGlow.haloPixel(RadialGlow.linearCurve, 1.0));
        Assert.assertEq(expected = true, a0 > aMid and aMid > aEdge)

    // smoothstepCurve でも同じ端点（t=0→255, t=1→0）を通る。
    @Test
    def testHaloPixelSmoothstepEndpoints(): Unit \ Assert =
        let centerAlpha = RadialGlow.haloPixel(RadialGlow.smoothstepCurve, 0.0) |> channels |> fst4;
        let edgeAlpha = RadialGlow.haloPixel(RadialGlow.smoothstepCurve, 1.0) |> channels |> fst4;
        Assert.assertEq(expected = (255, 0), (centerAlpha, edgeAlpha))

    // ── maskPixel: alpha は常に不透明固定、rgb だけが curve で変わる ──

    // 中心（t=0）は curve が 1.0 → rgb=255 固定（穴。素通しを表す）・alpha=255。
    @Test
    def testMaskPixelCenterIsWhite(): Unit \ Assert =
        let out = RadialGlow.maskPixel(RadialGlow.linearCurve, 0.0);
        Assert.assertEq(expected = (255, 255, 255, 255), channels(out))

    // 縁（t=1）は curve が 0.0 → rgb=0（黒。暗く沈める）・alpha は不透明のまま 255。
    @Test
    def testMaskPixelEdgeIsBlack(): Unit \ Assert =
        let out = RadialGlow.maskPixel(RadialGlow.linearCurve, 1.0);
        Assert.assertEq(expected = (255, 0, 0, 0), channels(out))

    // 中間（t=0.5）は中心と縁のあいだで rgb が単調に下がる。alpha はどの t でも 255 固定。
    @Test
    def testMaskPixelRgbDecreasesMonotonicallyAndAlphaStaysOpaque(): Unit \ Assert =
        let (a0, r0, _, _) = channels(RadialGlow.maskPixel(RadialGlow.linearCurve, 0.0));
        let (aMid, rMid, _, _) = channels(RadialGlow.maskPixel(RadialGlow.linearCurve, 0.5));
        let (aEdge, rEdge, _, _) = channels(RadialGlow.maskPixel(RadialGlow.linearCurve, 1.0));
        Assert.assertEq(expected = (255, 255, 255, true),
            (a0, aMid, aEdge, r0 > rMid and rMid > rEdge))

    // ── normalizedRadius: 画素座標 → 0(中心)..1(縁) ──

    // size=256 の正方形で中心画素 (128,128) はほぼ 0、四隅は 1 にクランプされる。
    @Test
    def testNormalizedRadiusCenterAndCorner(): Unit \ Assert =
        let center = RadialGlow.normalizedRadius(256, 128, 128);
        let corner = RadialGlow.normalizedRadius(256, 0, 0);
        Assert.assertEq(expected = (true, 1.0), (center < 0.01, corner))

    // ── 契約テスト: maskPixel を SoftRaster.blendPixel(Multiply) に通した結果 ──
    // 「穴あき暗幕」という設計の核心（中心は景色そのまま・縁は真っ暗）を、
    // 実際に使われる合成式まで通して機械的に守る。

    def dstArgb(): Int32 =
        Int32.leftShift(255, 24)
            |> Int32.bitwiseOr(Int32.leftShift(200, 16))
            |> Int32.bitwiseOr(Int32.leftShift(120, 8))
            |> Int32.bitwiseOr(60)

    // 中心の maskPixel は Multiply で dst と同じ値に戻る（穴 = 景色がそのまま見える）。
    @Test
    def testMaskCenterThroughMultiplyIsIdentity(): Unit \ Assert =
        let mask = RadialGlow.maskPixel(RadialGlow.linearCurve, 0.0);
        let out = SoftRaster.blendPixel(DrawCmd.BlendMode.Multiply, mask, dstArgb());
        Assert.assertEq(expected = dstArgb(), out)

    // 縁の maskPixel は Multiply で 0（alpha だけ dst のまま・rgb は真っ暗）になる。
    @Test
    def testMaskEdgeThroughMultiplyIsBlack(): Unit \ Assert =
        let mask = RadialGlow.maskPixel(RadialGlow.linearCurve, 1.0);
        let out = SoftRaster.blendPixel(DrawCmd.BlendMode.Multiply, mask, dstArgb());
        let (a, r, g, b) = channels(out);
        Assert.assertEq(expected = (255, 0, 0, 0), (a, r, g, b))

    def fst4(t: (Int32, Int32, Int32, Int32)): Int32 = let (a, _, _, _) = t; a

    // ── maskCurveWithHole: 平坦な穴を持たせたカーブ（Light.singleLightItems のスケール
    // 計算が「穴の実寸半径 = light#radius」を逆算する前提の土台）──

    // holeFrac 以下は完全に 1.0（素通し）— 平坦部の内側であることを固定する。
    @Test
    def testMaskCurveWithHoleIsFlatInsideHoleFrac(): Unit \ Assert =
        let atZero = RadialGlow.maskCurveWithHole(0.2, RadialGlow.linearCurve, 0.0);
        let atHoleFrac = RadialGlow.maskCurveWithHole(0.2, RadialGlow.linearCurve, 0.2);
        Assert.assertEq(expected = (1.0, 1.0), (atZero, atHoleFrac))

    // holeFrac を過ぎた直後は curve(0.0) から始まる（残り区間へ 0..1 に再マップされるため、
    // 平坦部を出た瞬間は元カーブの中心と同じ値になる）。
    @Test
    def testMaskCurveWithHoleResumesCurveJustPastHoleFrac(): Unit \ Assert =
        let justPast = RadialGlow.maskCurveWithHole(0.2, RadialGlow.linearCurve, 0.2 + 0.0001);
        Assert.assertEq(expected = true, justPast > 0.99)

    // t=1.0（縁）は holeFrac に依らず curve(1.0)=0.0 に落ちる。
    @Test
    def testMaskCurveWithHoleReachesZeroAtEdge(): Unit \ Assert =
        let out = RadialGlow.maskCurveWithHole(0.2, RadialGlow.linearCurve, 1.0);
        Assert.assertEq(expected = 0.0, out)
}
