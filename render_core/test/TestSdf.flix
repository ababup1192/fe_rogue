// RenderSdf.roundedBox の境界値テスト。
// シェーダ (GLSL) に同式を転記するため、ここで数式の正しさを固定する。

mod TestSdf {

    def approx(a: Float64, b: Float64): Bool =
        Float64.abs(a - b) < 0.001

    /// 中心は内側 (負)。half=(50,30), r=10 → inner=-20, outer=0 → -20-10=-30。
    @Test
    def testCenterInside(): Unit \ Assert =
        Assert.assertTrue(approx(RenderSdf.roundedBox(0.0, 0.0, 50.0, 30.0, 10.0), -30.0))

    /// 直線辺の中点はちょうど境界 (0)。x=50,y=0, half=(50,30), r=10。
    @Test
    def testFlatEdgeIsZero(): Unit \ Assert =
        Assert.assertTrue(approx(RenderSdf.roundedBox(50.0, 0.0, 50.0, 30.0, 10.0), 0.0))

    /// 角の外側 (正)。x=50,y=30, half=(50,30), r=10 → q=(10,10) → sqrt(200)-10≈4.142。
    @Test
    def testCornerOutsidePositive(): Unit \ Assert =
        Assert.assertTrue(approx(RenderSdf.roundedBox(50.0, 30.0, 50.0, 30.0, 10.0),
                                  RenderUtil.sqrtF(200.0) - 10.0))

    /// 角丸の弧上 (境界=0)。角中心 (40,20) から半径10の点 (40+10cos45, 20+10sin45)。
    @Test
    def testRoundedCornerArcIsZero(): Unit \ Assert =
        let d = 10.0 / RenderUtil.sqrtF(2.0);
        Assert.assertTrue(approx(RenderSdf.roundedBox(40.0 + d, 20.0 + d, 50.0, 30.0, 10.0), 0.0))

    /// r=0 は通常の矩形 SDF と一致。中心 → -min(half)=-30、辺上 → 0。
    @Test
    def testZeroRadiusIsBox(): Unit \ Assert =
        Assert.assertTrue(
            approx(RenderSdf.roundedBox(0.0, 0.0, 50.0, 30.0, 0.0), -30.0)
            and approx(RenderSdf.roundedBox(50.0, 0.0, 50.0, 30.0, 0.0), 0.0))

}
