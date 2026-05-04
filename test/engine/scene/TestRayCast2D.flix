// RayCast2D のテスト
//
// 線分が静的衝突体（StaticBody2D / TileMapLayer の壁）と交差するかを判定する API を確認する。
// テストでは Game.flix の NodeTag を使い、StaticBody2D を設置したシーンに対して
// origin → target 線分のクエリを投げる。
//
// 衝突体の座標は中心ベース。例えば (50, 50) に 20×20 の矩形を置くと x∈[40, 60]、y∈[40, 60] の範囲を占める。

mod TestRayCast2D {

    // ========================================================================
    // ヘルパー — 衝突体を 1 つ置いたシーンを構築
    // ========================================================================

    /// 中心 (50, 50)、サイズ 20×20 の壁を 1 つ置いたシーンを作る。x∈[40, 60], y∈[40, 60]。
    def wallScene(): Scene[NodeTag] =
        let wall = StaticBody2D.make(
            {x = 50.0, y = 50.0},
            CollisionShape2D.RectShape2D({width = 20.0, height = 20.0}));
        Scene.empty() |> Scene.addNode("Wall",
            EngineNode.StaticBody2DWithState(wall, NodeTag.NoTag))

    /// 衝突体が一切ないシーン
    def emptyScene(): Scene[NodeTag] = Scene.empty()

    // ========================================================================
    // 矩形と交差するかどうか
    // ========================================================================

    /// 線分 (0, 50) → (100, 50) は壁 (中心 50, 半幅 10) を真横に貫く
    @Test
    def testHorizontalLineThroughRect(): Unit \ Assert =
        let hit = RayCast2D.isColliding(
            {x = 0.0, y = 50.0}, {x = 100.0, y = 50.0}, wallScene());
        Assert.assertEq(expected = true, hit)

    /// 線分 (0, 0) → (100, 0) は壁の外（y=0）を通るので当たらない
    @Test
    def testHorizontalLineMissesRect(): Unit \ Assert =
        let hit = RayCast2D.isColliding(
            {x = 0.0, y = 0.0}, {x = 100.0, y = 0.0}, wallScene());
        Assert.assertEq(expected = false, hit)

    /// 線分 (0, 0) → (30, 30) は壁の角 (40, 40) に届かないので当たらない
    /// （線分の終点 30 は範囲 40 まで届かない）
    @Test
    def testShortLineFallsBeforeRect(): Unit \ Assert =
        let hit = RayCast2D.isColliding(
            {x = 0.0, y = 0.0}, {x = 30.0, y = 30.0}, wallScene());
        Assert.assertEq(expected = false, hit)

    /// 線分の終点が壁の中 (50, 50) で完結する場合も衝突として扱う
    @Test
    def testLineEndingInsideRectHits(): Unit \ Assert =
        let hit = RayCast2D.isColliding(
            {x = 0.0, y = 50.0}, {x = 50.0, y = 50.0}, wallScene());
        Assert.assertEq(expected = true, hit)

    /// 衝突体のないシーンではどんな線分を投げても false
    @Test
    def testEmptySceneNeverCollides(): Unit \ Assert =
        let hit = RayCast2D.isColliding(
            {x = 0.0, y = 0.0}, {x = 100.0, y = 100.0}, emptyScene());
        Assert.assertEq(expected = false, hit)

    /// 縦方向の線分 (50, 0) → (50, 100) も中心が壁の x=50 を通るので当たる
    @Test
    def testVerticalLineThroughRect(): Unit \ Assert =
        let hit = RayCast2D.isColliding(
            {x = 50.0, y = 0.0}, {x = 50.0, y = 100.0}, wallScene());
        Assert.assertEq(expected = true, hit)

    /// 壁の真上 y=20 を平行に走る線分は当たらない（壁の上端 y=40 に届かない）
    @Test
    def testParallelLineAboveRect(): Unit \ Assert =
        let hit = RayCast2D.isColliding(
            {x = 0.0, y = 20.0}, {x = 100.0, y = 20.0}, wallScene());
        Assert.assertEq(expected = false, hit)
}
