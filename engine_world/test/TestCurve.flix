// Curve のテスト。各部品（loop / sine / spin / pieces）の値を、丸めの出ない
// 素直な入力で固定する。sine だけは三角関数ゆえ許容差で確かめる。

mod TestCurve {

    def near(a: Float64, b: Float64): Bool = Float64.abs(a - b) < 0.000000001

    /// loop: 端 span で折り返し [0, span) に収まる。10/4=2.5 の小数部 0.5 に span=4 を掛けて 2.0。
    @Test
    def testLoopWraps(): Unit \ Assert =
        Assert.assertEq(expected = (1.0, 2.0, 2.0),
            (Curve.loop(1.0, 4.0, 1.0),      // 0.25 の周回 → 1.0
             Curve.loop(1.0, 4.0, 10.0),     // 2.5 の周回 → 2.0（1 周目を折り返す）
             Curve.loop(3.0, 4.0, 10.0)))    // 7.5 の周回 → 2.0

    /// loop: 0 秒では起点 0。
    @Test
    def testLoopAtZero(): Unit \ Assert =
        Assert.assertEq(expected = 0.0, Curve.loop(5.0, 8.0, 0.0))

    /// sine: 位相 π/2・振幅 1・freq 0 は cos の頂点 → +1。振幅 2・位相 0 は 0 を通る。
    @Test
    def testSine(): Unit \ Assert =
        let halfPi = 1.5707963267948966;
        Assert.assertEq(expected = (true, true),
            (near(Curve.sine(1.0, 0.0, halfPi, 0.0), 1.0),
             near(Curve.sine(2.0, 3.0, 0.0, 0.0), 0.0)))

    /// spin: 角速度 × 経過秒。2.5 rad/s を 4 秒で 10.0 rad。
    @Test
    def testSpin(): Unit \ Assert =
        Assert.assertEq(expected = 10.0, Curve.spin(2.5, 4.0))

    /// pieces: 折れ線 (0,0)-(2,4)-(4,0)。区間内は線形、両端の外は平ら。
    @Test
    def testPiecesInterpolatesAndClamps(): Unit \ Assert =
        let kf = (0.0, 0.0) :: (2.0, 4.0) :: (4.0, 0.0) :: Nil;
        Assert.assertEq(expected = (0.0, 2.0, 4.0, 2.0, 0.0),
            (Curve.pieces(kf, -1.0),   // 先頭以前 → 先頭値
             Curve.pieces(kf, 1.0),    // 昇り区間の中点 → 2.0
             Curve.pieces(kf, 2.0),    // 頂点 → 4.0
             Curve.pieces(kf, 3.0),    // 降り区間の中点 → 2.0
             Curve.pieces(kf, 9.0)))   // 末尾以降 → 末尾値

    /// pieces: 空の折れ線は 0。
    @Test
    def testPiecesEmpty(): Unit \ Assert =
        Assert.assertEq(expected = 0.0, Curve.pieces(Nil, 3.0))

    /// tri: 周期 4 で 0→1→0。前半で直線に昇り (t=1 で 0.5)、中央 t=2 で山 1.0、後半で
    /// 直線に降り (t=3 で 0.5)、周期端 t=4 で 0 に戻る。すべて丸めの出ない値。
    @Test
    def testTriWave(): Unit \ Assert =
        Assert.assertEq(expected = (0.0, 0.5, 1.0, 0.5, 0.0),
            (Curve.tri(4.0, 0.0), Curve.tri(4.0, 1.0), Curve.tri(4.0, 2.0),
             Curve.tri(4.0, 3.0), Curve.tri(4.0, 4.0)))

    /// tri: 非正の周期は 0（0 除算を避けるためのガード）。
    @Test
    def testTriNonPositivePeriod(): Unit \ Assert =
        Assert.assertEq(expected = (0.0, 0.0), (Curve.tri(0.0, 1.0), Curve.tri(-2.0, 1.0)))

    /// triWave: 符号つき三角波 [-1,1]。四半期点 0 → +1 → 0 → -1 → 0（すべて丸めの出ない値）。
    @Test
    def testTriWaveQuarterPoints(): Unit \ Assert =
        Assert.assertEq(expected = (0.0, 1.0, 0.0, -1.0, 0.0),
            (Curve.triWave(0.0), Curve.triWave(0.25), Curve.triWave(0.5),
             Curve.triWave(0.75), Curve.triWave(1.0)))

    /// triWave: 1 周期で折り返し、負の入力も floor で同じ周期に畳む（-0.75 は 0.25 と同じ +1）。
    @Test
    def testTriWaveWrapsAndHandlesNegative(): Unit \ Assert =
        Assert.assertEq(expected = (1.0, 1.0),
            (Curve.triWave(2.25), Curve.triWave(-0.75)))
}
