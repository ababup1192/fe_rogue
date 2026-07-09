// Transform（位置・回転・スケール・せん断の値部品）の派生操作テスト。
// getter/setter そのものは除外し、計算ロジックを持つメソッドのみ検証する。

mod TestTransform {

    /// テスト用ヘルパー: 初期 Transform（原点・無回転・等倍）
    def mkT(): Transform = Transform.identity()

    /// Float64 の近似比較（許容誤差 0.001）
    def approx(a: Float64, b: Float64): Bool =
        let diff = a - b;
        let d = if (diff < 0.0) -1.0 * diff else diff;
        d < 0.001

    // ========================================================================
    // translate
    // ========================================================================

    /// translate は現在位置にオフセットを加算する
    ///
    ///   (0,0) -- translate(3,4) --> (3,4)
    ///
    @Test
    def testTranslate(): Unit \ Assert =
        let t = mkT() |> Transform.translate({x = 3.0, y = 4.0});
        let pos = Transform.getPosition(t);
        Assert.assertTrue(approx(pos#x, 3.0) and approx(pos#y, 4.0))

    /// translate を連続で呼ぶと加算が累積する
    ///
    ///   (0,0) -- +（1,2） --> (1,2) -- +(3,4) --> (4,6)
    ///
    @Test
    def testTranslateAccumulates(): Unit \ Assert =
        let t = mkT()
            |> Transform.translate({x = 1.0, y = 2.0})
            |> Transform.translate({x = 3.0, y = 4.0});
        let pos = Transform.getPosition(t);
        Assert.assertTrue(approx(pos#x, 4.0) and approx(pos#y, 6.0))

    // ========================================================================
    // rotate
    // ========================================================================

    /// rotate は現在の回転にラジアンを加算する
    @Test
    def testRotate(): Unit \ Assert =
        let t = mkT() |> Transform.rotate(1.5);
        Assert.assertTrue(approx(Transform.getRotation(t), 1.5))

    /// rotate を連続で呼ぶと加算が累積する
    ///
    ///   0.0 -- +1.0 --> 1.0 -- +0.5 --> 1.5
    ///
    @Test
    def testRotateAccumulates(): Unit \ Assert =
        let t = mkT()
            |> Transform.rotate(1.0)
            |> Transform.rotate(0.5);
        Assert.assertTrue(approx(Transform.getRotation(t), 1.5))

    // ========================================================================
    // applyScale
    // ========================================================================

    /// applyScale は現在のスケールに比率を乗算する
    ///
    ///   scale(2,3) * ratio(0.5,2) = scale(1,6)
    ///
    @Test
    def testApplyScale(): Unit \ Assert =
        let t = mkT()
            |> Transform.setScale({x = 2.0, y = 3.0})
            |> Transform.applyScale({x = 0.5, y = 2.0});
        let sc = Transform.getScale(t);
        Assert.assertTrue(approx(sc#x, 1.0) and approx(sc#y, 6.0))

    /// applyScale に (1,1) を渡すとスケールは変化しない
    @Test
    def testApplyScaleIdentity(): Unit \ Assert =
        let t = mkT()
            |> Transform.setScale({x = 3.0, y = 5.0})
            |> Transform.applyScale({x = 1.0, y = 1.0});
        let sc = Transform.getScale(t);
        Assert.assertTrue(approx(sc#x, 3.0) and approx(sc#y, 5.0))

    // ========================================================================
    // getAngleTo
    // ========================================================================

    /// 原点から +X 方向 (1,0) への角度は 0
    ///
    ///   node *-------> (1,0)   angle = 0
    ///
    @Test
    def testGetAngleToRight(): Unit \ Assert =
        let angle = Transform.getAngleTo({x = 1.0, y = 0.0}, mkT());
        Assert.assertTrue(approx(angle, 0.0))

    /// 原点から +Y 方向 (0,1) への角度は PI/2
    ///
    ///        (0,1)
    ///          |
    ///   node *    angle = PI/2
    ///
    @Test
    def testGetAngleToUp(): Unit \ Assert =
        let pi = 3.14159265;
        let angle = Transform.getAngleTo({x = 0.0, y = 1.0}, mkT());
        Assert.assertTrue(approx(angle, pi / 2.0))

    /// 原点以外を起点にする場合、差分ベクトルで角度を計算する
    ///
    ///   node(1,1) -------> (2,1)   angle = 0  （差分 = (1,0)）
    ///
    @Test
    def testGetAngleToFromOffset(): Unit \ Assert =
        let t = mkT() |> Transform.setPosition({x = 1.0, y = 1.0});
        let angle = Transform.getAngleTo({x = 2.0, y = 1.0}, t);
        Assert.assertTrue(approx(angle, 0.0))

    // ========================================================================
    // lookAt
    // ========================================================================

    /// lookAt は指定した点への角度に rotation をセットする
    ///
    ///   before:           after:
    ///       (0,1)            (0,1)
    ///                      /
    ///   node *--->    node *   rotation = PI/2
    ///
    @Test
    def testLookAt(): Unit \ Assert =
        let pi = 3.14159265;
        let t = mkT() |> Transform.lookAt({x = 0.0, y = 1.0});
        Assert.assertTrue(approx(Transform.getRotation(t), pi / 2.0))
}
