/// MapScene のヘルパー関数（純粋ロジック）テスト。
///
/// `moduleOfCellIn`: 配置済みモジュール一覧から「セル → idx」を逆引きする関数。
/// 部屋優先（先勝ち）と、bbox の包含判定（offset + gridSize の半開区間）を検証する。
mod TestMapScene {

    // ModulePlacement 生成は本番の RoomLayout.placement を使う（テスト間の重複定義を廃止）。

    /// 単一モジュールの内部セル → そのモジュールの idx
    @Test
    def testModuleOfCellSingleInside(): Unit \ Assert =
        let p0 = RoomLayout.placement(0, 0, 0, 8, 8);
        let result = MapSnapshot.moduleOfCellIn(({x = 3, y = 4}: {x = Int32, y = Int32}), p0 :: Nil);
        Assert.assertEq(expected = Some(0), result)

    /// 範囲外セル → None
    @Test
    def testModuleOfCellOutsideAllModules(): Unit \ Assert =
        let p0 = RoomLayout.placement(0, 0, 0, 8, 8);
        let result = MapSnapshot.moduleOfCellIn(({x = 20, y = 20}: {x = Int32, y = Int32}), p0 :: Nil);
        Assert.assertEq(expected = None, result)

    /// bbox の右下端は半開区間（exclusive）。 (8,8) は p0 (0..8, 0..8) に含まれない
    @Test
    def testModuleOfCellExclusiveMax(): Unit \ Assert =
        let p0 = RoomLayout.placement(0, 0, 0, 8, 8);
        let inside  = MapSnapshot.moduleOfCellIn(({x = 7, y = 7}: {x = Int32, y = Int32}), p0 :: Nil);
        let outside = MapSnapshot.moduleOfCellIn(({x = 8, y = 8}: {x = Int32, y = Int32}), p0 :: Nil);
        Assert.assertEq(expected = (Some(0), None), (inside, outside))

    /// 部屋（idx 0）と通路（idx 2）が重なる領域では idx 順で先勝ち = 部屋が勝つ。
    /// p0 = (0,0)..(8,8) 部屋, p1 = (10,0)..(18,8) 部屋, p2 = (6,2)..(12,6) 通路で
    /// p0 と p2 が重なる (7,3) は p0 を返すべき。
    @Test
    def testModuleOfCellRoomWinsOverPathway(): Unit \ Assert =
        let p0 = RoomLayout.placement(0, 0, 0, 8, 8);
        let p1 = RoomLayout.placement(1, 10, 0, 8, 8);
        let p2 = RoomLayout.placement(2, 6, 2, 6, 4);   // 部屋 0 と通路が overlap
        let placements = p0 :: p1 :: p2 :: Nil;
        let result = MapSnapshot.moduleOfCellIn(({x = 7, y = 3}: {x = Int32, y = Int32}), placements);
        Assert.assertEq(expected = Some(0), result)

    /// 通路だけが含むセルは通路の idx を返す（部屋に入っていない）。
    @Test
    def testModuleOfCellPathwayOnly(): Unit \ Assert =
        let p0 = RoomLayout.placement(0, 0, 0, 8, 8);
        let p1 = RoomLayout.placement(1, 10, 0, 8, 8);
        let p2 = RoomLayout.placement(2, 6, 2, 6, 4);   // (8..10, 2..6) は p2 のみ
        let placements = p0 :: p1 :: p2 :: Nil;
        let result = MapSnapshot.moduleOfCellIn(({x = 9, y = 4}: {x = Int32, y = Int32}), placements);
        Assert.assertEq(expected = Some(2), result)

    /// 空リスト → 常に None
    @Test
    def testModuleOfCellEmpty(): Unit \ Assert =
        let result = MapSnapshot.moduleOfCellIn(({x = 0, y = 0}: {x = Int32, y = Int32}), Nil);
        Assert.assertEq(expected = None, result)

    // ========================================================================
    // moduleCenter — 部屋(モジュール)の床範囲の中心セル（発見演出のカメラ寄せ用）
    // ========================================================================

    /// Option[{x,y}] を assertEq 用タプルに変換 ((None → (false,0,0))。
    def centerToTuple(o: Option[{x = Int32, y = Int32}]): (Bool, Int32, Int32) =
        match o {
            case Some(c) => (true, c#x, c#y)
            case None    => (false, 0, 0)
        }

    /// offset(0,0)・床 8×8 の部屋0 の中心は (3,3)。
    /// floorBoundsMaxEx は排他なので最終床セルは 7、中心 = (0+7)/2 = 3。
    @Test
    def testModuleCenterAtOrigin(): Unit \ Assert =
        let p0 = RoomLayout.placement(0, 0, 0, 8, 8);
        Assert.assertEq(expected = (true, 3, 3),
            centerToTuple(RoomLayout.moduleCenter(0, p0 :: Nil)))

    /// offset(10,20)・床 5×3 の部屋2 の中心は (12,21)。
    /// x: (10 + 14)/2 = 12（14 = 10+5-1）、y: (20 + 22)/2 = 21（22 = 20+3-1）。
    @Test
    def testModuleCenterWithOffset(): Unit \ Assert =
        let p2 = RoomLayout.placement(2, 10, 20, 5, 3);
        Assert.assertEq(expected = (true, 12, 21),
            centerToTuple(RoomLayout.moduleCenter(2, p2 :: Nil)))

    /// 未配置の idx は None。
    @Test
    def testModuleCenterUnknownIdx(): Unit \ Assert =
        let p0 = RoomLayout.placement(0, 0, 0, 8, 8);
        Assert.assertEq(expected = (false, 0, 0),
            centerToTuple(RoomLayout.moduleCenter(9, p0 :: Nil)))

    // ════════════════════════════════════════════════════════
    // MapSnapshot の純関数層
    //   地形は wallCells / placements の純粋データから計算する。
    //   座標系（mapToLocal / gridToWorld 等）の pin をここで担う。
    // ════════════════════════════════════════════════════════

    /// 壁/床判定: wallCells のセルは壁、範囲内の他セルは床、範囲外（size の外）は床でない。
    @Test
    def testIsWallAndIsFloorFromData(): Unit \ Assert =
        let m: MapSnapshot = {tileSize = 26.0,
            usedRect = {position = {x = 0, y = 0}, size = ({x = 5, y = 3}: {x = Int32, y = Int32})},
            wallCells = Set#{(2, 1)}, mapGlobal = {x = 0.0, y = 0.0}, placements = Nil};
        Assert.assertEq(
            expected = (true, false, true, false),
            (MapSnapshot.isWall({x = 2, y = 1}, m),     // 壁セル
             MapSnapshot.isFloor({x = 2, y = 1}, m),    // 壁なので床でない
             MapSnapshot.isFloor({x = 0, y = 0}, m),    // 範囲内の床
             MapSnapshot.isFloor({x = 5, y = 0}, m)))   // x=5 は size 5 の外 → 床でない

    /// mapToLocal: tileSize 26 のセル中心。(1,1) → (1*26+13, 1*26+13) = (39, 39)。
    @Test
    def testMapToLocalCellCenter(): Unit \ Assert =
        let m: MapSnapshot = {tileSize = 26.0,
            usedRect = {position = {x = 0, y = 0}, size = ({x = 5, y = 5}: {x = Int32, y = Int32})},
            wallCells = (Set#{}: Set[(Int32, Int32)]), mapGlobal = {x = 0.0, y = 0.0}, placements = Nil};
        let p = MapSnapshot.mapToLocal({x = 1, y = 1}, m);
        Assert.assertEq(expected = (39.0, 39.0), (p#x, p#y))

    /// gridToWorld: mapToLocal に mapGlobal を加算する。mapGlobal=(10,20) で (1,1) → (49, 59)。
    @Test
    def testGridToWorldAddsMapGlobal(): Unit \ Assert =
        let m: MapSnapshot = {tileSize = 26.0,
            usedRect = {position = {x = 0, y = 0}, size = ({x = 5, y = 5}: {x = Int32, y = Int32})},
            wallCells = (Set#{}: Set[(Int32, Int32)]), mapGlobal = {x = 10.0, y = 20.0}, placements = Nil};
        let p = MapSnapshot.gridToWorld({x = 1, y = 1}, m);
        Assert.assertEq(expected = (49.0, 59.0), (p#x, p#y))   // (39+10, 39+20)

    /// singleRoom: 全床 5×3 が単一モジュール 0。範囲外は None。
    @Test
    def testSingleRoomModuleOfCell(): Unit \ Assert =
        let ps = RoomLayout.singleRoom(5, 3);
        Assert.assertEq(
            expected = (Some(0), Some(0), None),
            (MapSnapshot.moduleOfCellIn({x = 0, y = 0}, ps),
             MapSnapshot.moduleOfCellIn({x = 4, y = 2}, ps),
             MapSnapshot.moduleOfCellIn({x = 5, y = 0}, ps)))   // 範囲外

    /// twoRoom: 10×5 を縦半分。左 (x<5)=module0、右 (x>=5)=module1（half=5 の境界）。
    @Test
    def testTwoRoomModuleBoundary(): Unit \ Assert =
        let ps = RoomLayout.twoRoom(10, 5);
        Assert.assertEq(
            expected = (Some(0), Some(1)),
            (MapSnapshot.moduleOfCellIn({x = 4, y = 2}, ps),    // 左半分
             MapSnapshot.moduleOfCellIn({x = 5, y = 2}, ps)))   // 右半分
}
