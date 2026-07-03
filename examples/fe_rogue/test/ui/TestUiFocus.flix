/// UiFocus.hitTest（最前面優先）と UiWidget.selectionMove（回り込み）を固定する。
mod TestUiFocus {

    // ════════════════════════════════════════════════════════
    // フィクスチャ
    // ════════════════════════════════════════════════════════

    /// (0,0)-(10,10) の矩形。重ねて hit-test の前後関係を作る。
    def unitRect(): Rect2.Rect2 =
        {position = {x = 0.0, y = 0.0}, size = {x = 10.0, y = 10.0}}

    /// Map から Int32 を引くルックアップ（未登録は 0）。zOf / depthOf 用。
    def intLookup(m: Map[EntityId, Int32]): EntityId -> Int32 =
        id -> Option.getWithDefault(0, Map.get(id, m))

    // ════════════════════════════════════════════════════════
    // hitTest: zIndex 最前面優先
    // ════════════════════════════════════════════════════════

    /// 点(5,5) で 2 矩形が重なる。a(2,z=1)・b(3,z=5)。z 大の b が勝つ。
    @Test
    def testHitTestFrontmostByZIndex(): Unit \ Assert =
        let rects = Map#{2 => unitRect(), 3 => unitRect()};
        let vis = Map#{2 => true, 3 => true};
        let zOf = intLookup(Map#{2 => 1, 3 => 5});
        let depthOf = intLookup(Map#{2 => 0, 3 => 0});
        Assert.assertEq(expected = Some(3), UiFocus.hitTest(rects, vis, zOf, depthOf, {x = 5.0, y = 5.0}))

    // ════════════════════════════════════════════════════════
    // hitTest: z 同値は深い方
    // ════════════════════════════════════════════════════════

    /// z 同値(=2)。深さ a=1・b=3。深い b が勝つ。
    @Test
    def testHitTestZTieDeeperWins(): Unit \ Assert =
        let rects = Map#{2 => unitRect(), 3 => unitRect()};
        let vis = Map#{2 => true, 3 => true};
        let zOf = intLookup(Map#{2 => 2, 3 => 2});
        let depthOf = intLookup(Map#{2 => 1, 3 => 3});
        Assert.assertEq(expected = Some(3), UiFocus.hitTest(rects, vis, zOf, depthOf, {x = 5.0, y = 5.0}))

    // ════════════════════════════════════════════════════════
    // hitTest: 不可視は無視
    // ════════════════════════════════════════════════════════

    /// b(3) は z 大だが不可視。可視な a(2) が当たる。
    @Test
    def testHitTestSkipsInvisible(): Unit \ Assert =
        let rects = Map#{2 => unitRect(), 3 => unitRect()};
        let vis = Map#{2 => true, 3 => false};
        let zOf = intLookup(Map#{2 => 1, 3 => 5});
        let depthOf = intLookup(Map#{2 => 0, 3 => 0});
        Assert.assertEq(expected = Some(2), UiFocus.hitTest(rects, vis, zOf, depthOf, {x = 5.0, y = 5.0}))

    // ════════════════════════════════════════════════════════
    // selectionMove: 回り込み
    // ════════════════════════════════════════════════════════

    /// count=3: 2 から +1 で 0、0 から -1 で 2。count=0 は 0。
    @Test
    def testSelectionMoveWraps(): Unit \ Assert =
        Assert.assertEq(
            expected = (0, 2, 0),
            (UiWidget.selectionMove(3, 1, 2), UiWidget.selectionMove(3, -1, 0), UiWidget.selectionMove(0, 1, 0)))
}
