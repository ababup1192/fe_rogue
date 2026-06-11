/// MapLoader の自動壁計算（純粋ロジック）テスト。
///
/// `.map.json` の床マスから「自動壁セル」「タイル選択キー」「IntGrid」を導出する純粋関数群。
/// 全マップの壁描画 + 当たり判定の土台で、`DungeonComposer.buildWallsLayer` も再利用する。
/// 引数は `Set[(Int32, Int32)]` と Int32 のみ＝scene/engine 非依存で純粋値だけで検証できる。
mod TestMapLoader {

    // ── computeWallCells: 床に隣接する非床セルが自動壁になる ──

    /// 単一床 (1,1) の周囲 8 セルがすべて壁になる（床自身は壁にしない）。
    @Test
    def testWallCellsRingAroundSingleFloor(): Unit \ Assert =
        let walls = MapLoader.computeWallCells(Set#{(1, 1)}, 3, 3);
        Assert.assertEq(
            expected = (8, false, true),
            (Set.size(walls),
             Set.memberOf((1, 1), walls),     // 床自身は壁でない
             Set.memberOf((0, 0), walls)))    // 周囲は壁

    /// 床が 1 つも無ければ自動壁も無い（境界）。
    @Test
    def testWallCellsNoFloorIsEmpty(): Unit \ Assert =
        let walls = MapLoader.computeWallCells((Set#{}: Set[(Int32, Int32)]), 3, 3);
        Assert.assertEq(expected = true, Set.isEmpty(walls))

    // ── trblTritKeyAt: 上右下左の壁/床/空キー（オートタイル選択の要） ──

    /// 部屋の上辺中央 (1,0) のキー: 上=空(E) 右=壁(W) 下=床(F) 左=壁(W) → "EWFW"。
    /// floorMask=(1,1) のとき computeWallCells で周囲8セルが壁になる構成で trit 順を pin。
    @Test
    def testTritKeyTopEdgeOfRoom(): Unit \ Assert =
        let floorMask = Set#{(1, 1)};
        let wallCells = MapLoader.computeWallCells(floorMask, 3, 3);
        Assert.assertEq(
            expected = "EWFW",
            MapLoader.trblTritKeyAt(wallCells, floorMask, 1, 0))

    // ── buildIntGrid: 0=空 / 1=床 / 2=壁（AutoRule 入力） ──

    /// 床セル=1・自動壁セル=2 でエンコードされる。index = row*width + col。
    /// (1,1)=床 → index 4 が 1、(0,0)=壁 → index 0 が 2。
    @Test
    def testIntGridEncoding(): Unit \ Assert =
        let floorMask = Set#{(1, 1)};
        let wallCells = MapLoader.computeWallCells(floorMask, 3, 3);
        let grid = MapLoader.buildIntGrid(floorMask, wallCells, 3, 3);
        Assert.assertEq(
            expected = (1, 2),
            (Vector.get(4, grid), Vector.get(0, grid)))

}
