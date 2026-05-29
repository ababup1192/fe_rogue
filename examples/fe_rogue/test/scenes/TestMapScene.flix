/// MapScene のヘルパー関数（純粋ロジック）テスト。
///
/// `moduleOfCellIn`: 配置済みモジュール一覧から「セル → idx」を逆引きする関数。
/// 部屋優先（先勝ち）と、bbox の包含判定（offset + gridSize の半開区間）を検証する。
mod TestMapScene {

    /// 簡単な ModulePlacement 生成ヘルパー。
    /// テストでは「gridSize 全体が床」を仮定して floorBounds を (0,0)..(w,h) で埋める。
    def placement(idx: Int32, ox: Int32, oy: Int32, w: Int32, h: Int32):
                  DungeonComposer.ModulePlacement =
        {
            idx              = idx,
            offset           = ({x = ox, y = oy}: {x = Int32, y = Int32}),
            gridSize         = ({x = w,  y = h }: {x = Int32, y = Int32}),
            floorBoundsMin   = ({x = 0,  y = 0 }: {x = Int32, y = Int32}),
            floorBoundsMaxEx = ({x = w,  y = h }: {x = Int32, y = Int32})
        }

    /// 単一モジュールの内部セル → そのモジュールの idx
    @Test
    def testModuleOfCellSingleInside(): Unit \ Assert =
        let p0 = placement(0, 0, 0, 8, 8);
        let result = MapScene.moduleOfCellIn(({x = 3, y = 4}: {x = Int32, y = Int32}), p0 :: Nil);
        Assert.assertEq(expected = Some(0), result)

    /// 範囲外セル → None
    @Test
    def testModuleOfCellOutsideAllModules(): Unit \ Assert =
        let p0 = placement(0, 0, 0, 8, 8);
        let result = MapScene.moduleOfCellIn(({x = 20, y = 20}: {x = Int32, y = Int32}), p0 :: Nil);
        Assert.assertEq(expected = None, result)

    /// bbox の右下端は半開区間（exclusive）。 (8,8) は p0 (0..8, 0..8) に含まれない
    @Test
    def testModuleOfCellExclusiveMax(): Unit \ Assert =
        let p0 = placement(0, 0, 0, 8, 8);
        let inside  = MapScene.moduleOfCellIn(({x = 7, y = 7}: {x = Int32, y = Int32}), p0 :: Nil);
        let outside = MapScene.moduleOfCellIn(({x = 8, y = 8}: {x = Int32, y = Int32}), p0 :: Nil);
        Assert.assertEq(expected = (Some(0), None), (inside, outside))

    /// 部屋（idx 0）と通路（idx 2）が重なる領域では idx 順で先勝ち = 部屋が勝つ。
    /// p0 = (0,0)..(8,8) 部屋, p1 = (10,0)..(18,8) 部屋, p2 = (6,2)..(12,6) 通路で
    /// p0 と p2 が重なる (7,3) は p0 を返すべき。
    @Test
    def testModuleOfCellRoomWinsOverPathway(): Unit \ Assert =
        let p0 = placement(0, 0, 0, 8, 8);
        let p1 = placement(1, 10, 0, 8, 8);
        let p2 = placement(2, 6, 2, 6, 4);   // 部屋 0 と通路が overlap
        let placements = p0 :: p1 :: p2 :: Nil;
        let result = MapScene.moduleOfCellIn(({x = 7, y = 3}: {x = Int32, y = Int32}), placements);
        Assert.assertEq(expected = Some(0), result)

    /// 通路だけが含むセルは通路の idx を返す（部屋に入っていない）。
    @Test
    def testModuleOfCellPathwayOnly(): Unit \ Assert =
        let p0 = placement(0, 0, 0, 8, 8);
        let p1 = placement(1, 10, 0, 8, 8);
        let p2 = placement(2, 6, 2, 6, 4);   // (8..10, 2..6) は p2 のみ
        let placements = p0 :: p1 :: p2 :: Nil;
        let result = MapScene.moduleOfCellIn(({x = 9, y = 4}: {x = Int32, y = Int32}), placements);
        Assert.assertEq(expected = Some(2), result)

    /// 空リスト → 常に None
    @Test
    def testModuleOfCellEmpty(): Unit \ Assert =
        let result = MapScene.moduleOfCellIn(({x = 0, y = 0}: {x = Int32, y = Int32}), Nil);
        Assert.assertEq(expected = None, result)
}
