// Tests for Node2D default methods
//
// Sprite2D を具象型として使い、Node2D trait の
// デフォルト実装メソッドをテストする。
// getter/setter 自体のテストは除外し、
// 計算ロジックを持つメソッドのみ検証する。

mod TestNode2D {

    /// テスト用ヘルパー: 原点に配置したデフォルト Sprite2D を作る
    def mkSprite(): Sprite2D =
        Sprite2D.Sprite2D({
            position = {x = 0.0, y = 0.0},
            rotation = 0.0,
            scale = {x = 1.0, y = 1.0},
            skew = 0.0,
            visible = true,
            zIndex = 0,
            modulate = {r = 1.0f32, g = 1.0f32, b = 1.0f32},
            texture = "",
            centered = true,
            offset = {x = 0.0, y = 0.0},
            flipH = false,
            flipV = false
        })

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
        let s = mkSprite() |> Node2D.translate({x = 3.0, y = 4.0});
        let pos = Node2D.getPosition(s);
        Assert.assertTrue(approx(pos#x, 3.0) and approx(pos#y, 4.0))

    /// translate を連続で呼ぶと加算が累積する
    ///
    ///   (0,0) -- +（1,2） --> (1,2) -- +(3,4) --> (4,6)
    ///
    @Test
    def testTranslateAccumulates(): Unit \ Assert =
        let s = mkSprite()
            |> Node2D.translate({x = 1.0, y = 2.0})
            |> Node2D.translate({x = 3.0, y = 4.0});
        let pos = Node2D.getPosition(s);
        Assert.assertTrue(approx(pos#x, 4.0) and approx(pos#y, 6.0))

    // ========================================================================
    // rotate
    // ========================================================================

    /// rotate は現在の回転にラジアンを加算する
    @Test
    def testRotate(): Unit \ Assert =
        let s = mkSprite() |> Node2D.rotate(1.5);
        Assert.assertTrue(approx(Node2D.getRotation(s), 1.5))

    /// rotate を連続で呼ぶと加算が累積する
    ///
    ///   0.0 -- +1.0 --> 1.0 -- +0.5 --> 1.5
    ///
    @Test
    def testRotateAccumulates(): Unit \ Assert =
        let s = mkSprite()
            |> Node2D.rotate(1.0)
            |> Node2D.rotate(0.5);
        Assert.assertTrue(approx(Node2D.getRotation(s), 1.5))

    // ========================================================================
    // applyScale
    // ========================================================================

    /// applyScale は現在のスケールに比率を乗算する
    ///
    ///   scale(2,3) * ratio(0.5,2) = scale(1,6)
    ///
    @Test
    def testApplyScale(): Unit \ Assert =
        let s = mkSprite()
            |> Node2D.setScale({x = 2.0, y = 3.0})
            |> Node2D.applyScale({x = 0.5, y = 2.0});
        let sc = Node2D.getScale(s);
        Assert.assertTrue(approx(sc#x, 1.0) and approx(sc#y, 6.0))

    /// applyScale に (1,1) を渡すとスケールは変化しない
    @Test
    def testApplyScaleIdentity(): Unit \ Assert =
        let s = mkSprite()
            |> Node2D.setScale({x = 3.0, y = 5.0})
            |> Node2D.applyScale({x = 1.0, y = 1.0});
        let sc = Node2D.getScale(s);
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
        let angle = Node2D.getAngleTo({x = 1.0, y = 0.0}, mkSprite());
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
        let angle = Node2D.getAngleTo({x = 0.0, y = 1.0}, mkSprite());
        Assert.assertTrue(approx(angle, pi / 2.0))

    /// ノードが原点以外にいる場合、差分ベクトルで角度を計算する
    ///
    ///   node(1,1) -------> (2,1)   angle = 0  （差分 = (1,0)）
    ///
    @Test
    def testGetAngleToFromOffset(): Unit \ Assert =
        let s = mkSprite() |> Node2D.setPosition({x = 1.0, y = 1.0});
        let angle = Node2D.getAngleTo({x = 2.0, y = 1.0}, s);
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
        let s = mkSprite() |> Node2D.lookAt({x = 0.0, y = 1.0});
        Assert.assertTrue(approx(Node2D.getRotation(s), pi / 2.0))
}
