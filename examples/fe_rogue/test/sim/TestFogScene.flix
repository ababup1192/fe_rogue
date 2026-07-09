/// FogScene の純粋ロジックテスト（LWJGL / scene 構築非依存）。
///
/// - `moduleRect`: module の floorBounds(±edgePad)を world grid 矩形へ。
/// - `bandDecompose`: area から holes（明るい部屋）を除いた補集合の矩形分割。
/// - `litModulesIn`: hidden 除外 / 和集合 / 通路 / module 外無視。
///
/// プール再配置（applyFog の Scene 変換）は scene 構築が LDTK/LWJGL を要するため
/// 統合/手動確認に委ねる。
mod TestFogScene {

    // ModulePlacement 生成は本番の RoomLayout.placement を使う（テスト間の重複定義を廃止）。

    /// litModulesIn 用の最小ユニット record（gridPos + hidden）。
    def unit(x: Int32, y: Int32, hidden: Bool): {gridPos = {x = Int32, y = Int32}, hidden = Bool} =
        {gridPos = ({x = x, y = y}: {x = Int32, y = Int32}), hidden = hidden}


    // ── moduleRect ───────────────────────────────────────────

    /// offset(0,0)・床 8×8、edgePad=1 で grid (-1,-1)..(9,9)。
    @Test
    def testModuleRectAtOrigin(): Unit \ Assert =
        Assert.assertEq(expected = (-1, -1, 9, 9),
            TestUnitFixtures.rectT(FogScene.moduleRect(RoomLayout.placement(0, 0, 0, 8, 8))))

    /// offset(10,20)・床 5×3、edgePad=1 で grid (9,19)..(16,24)。
    @Test
    def testModuleRectWithOffset(): Unit \ Assert =
        Assert.assertEq(expected = (9, 19, 16, 24),
            TestUnitFixtures.rectT(FogScene.moduleRect(RoomLayout.placement(2, 10, 20, 5, 3))))

    // ── bandDecompose ────────────────────────────────────────

    /// 穴なし → area 全体を覆う 1 矩形。
    @Test
    def testBandDecomposeNoHoles(): Unit \ Assert =
        let area = ({x0 = 0, y0 = 0, x1 = 10, y1 = 10}: {x0 = Int32, y0 = Int32, x1 = Int32, y1 = Int32});
        let result = FogScene.bandDecompose(area, Nil) |> List.map(TestUnitFixtures.rectT);
        Assert.assertEq(expected = (0, 0, 10, 10) :: Nil, result)

    /// 中央の穴 (4,4)..(6,6) → 上/左/右/下の 4 矩形で補集合を覆う。
    @Test
    def testBandDecomposeCenterHole(): Unit \ Assert =
        let area = ({x0 = 0, y0 = 0, x1 = 10, y1 = 10}: {x0 = Int32, y0 = Int32, x1 = Int32, y1 = Int32});
        let hole   = ({x0 = 4, y0 = 4, x1 = 6,  y1 = 6 }: {x0 = Int32, y0 = Int32, x1 = Int32, y1 = Int32});
        let result = FogScene.bandDecompose(area, hole :: Nil) |> List.map(TestUnitFixtures.rectT);
        // バンド (0,4): 全幅 / (4,6): 左右 / (6,10): 全幅
        Assert.assertEq(
            expected = (0, 0, 10, 4) :: (0, 4, 4, 6) :: (6, 4, 10, 6) :: (0, 6, 10, 10) :: Nil,
            result)

    // ── holesFor ─────────────────────────────────────────────

    def holesT(rs: List[{x0 = Int32, y0 = Int32, x1 = Int32, y1 = Int32}]):
            List[(Int32, Int32, Int32, Int32)] = List.map(TestUnitFixtures.rectT, rs)

    /// 部屋(idx 0 < roomCount)にいる → 部屋全体（moduleRect）が穴。torch は無関係。
    @Test
    def testHolesRoomFull(): Unit \ Assert =
        let p0 = RoomLayout.placement(0, 0, 0, 8, 8);
        Assert.assertEq(expected = (-1, -1, 9, 9) :: Nil,
            holesT(FogScene.holesFor(unit(3, 4, false) :: Nil, p0 :: Nil, 1, true)))

    /// 通路(idx 1 >= roomCount)＋torch → 周囲1マス(3×3)だけが穴。
    @Test
    def testHolesCorridorTorch(): Unit \ Assert =
        let p0 = RoomLayout.placement(0, 0,  0, 8, 8);
        let p1 = RoomLayout.placement(1, 10, 0, 8, 8);   // 通路
        // (12,4) は p1。torch=true → torchRect(12,4) = (11,3)..(14,6)
        Assert.assertEq(expected = (11, 3, 14, 6) :: Nil,
            holesT(FogScene.holesFor(unit(12, 4, false) :: Nil, p0 :: p1 :: Nil, 1, true)))

    /// 通路＋torch=false（通常モード）→ 通路全体（moduleRect）が穴。
    @Test
    def testHolesCorridorNoTorch(): Unit \ Assert =
        let p0 = RoomLayout.placement(0, 0,  0, 8, 8);
        let p1 = RoomLayout.placement(1, 10, 0, 8, 8);
        // moduleRect(p1) = (10-1, 0-1)..(18+1, 8+1) = (9,-1,19,9)
        Assert.assertEq(expected = (9, -1, 19, 9) :: Nil,
            holesT(FogScene.holesFor(unit(12, 4, false) :: Nil, p0 :: p1 :: Nil, 1, false)))

    /// hidden プレイヤーは除外される → 穴なし。
    @Test
    def testHolesHiddenExcluded(): Unit \ Assert =
        let p0 = RoomLayout.placement(0, 0, 0, 8, 8);
        Assert.assertEq(expected = (Nil: List[(Int32, Int32, Int32, Int32)]),
            holesT(FogScene.holesFor(unit(3, 4, true) :: Nil, p0 :: Nil, 1, false)))

    // ── holesForDraft（移動中は新規部屋だけ暗い） ───────────────

    /// holesForDraft 用ユニット（gridPos=現在位置 / origin=ターン開始位置）。
    def unitO(x: Int32, y: Int32, ox: Int32, oy: Int32, hidden: Bool):
            {gridPos = {x = Int32, y = Int32}, origin = {x = Int32, y = Int32}, hidden = Bool} =
        {gridPos = ({x = x, y = y}: {x = Int32, y = Int32}),
         origin  = ({x = ox, y = oy}: {x = Int32, y = Int32}), hidden = hidden}

    /// origin と live が同じ部屋(idx0) → 部屋全体が点灯（部屋内移動は従来どおり明るい）。
    @Test
    def testHolesDraftSameRoom(): Unit \ Assert =
        let p0 = RoomLayout.placement(0, 0, 0, 8, 8);
        Assert.assertEq(expected = (-1, -1, 9, 9) :: Nil,
            holesT(FogScene.holesForDraft(unitO(5, 5, 3, 4, false) :: Nil, p0 :: Nil, 1, false)))

    /// origin=部屋A(idx0)・live=新部屋B(idx1) → B は点灯せず holes 空（確定まで暗い）。
    @Test
    def testHolesDraftNewRoomDark(): Unit \ Assert =
        let p0 = RoomLayout.placement(0, 0,  0, 8, 8);
        let p1 = RoomLayout.placement(1, 20, 0, 8, 8);   // 部屋（roomCount=2）
        Assert.assertEq(expected = (Nil: List[(Int32, Int32, Int32, Int32)]),
            holesT(FogScene.holesForDraft(unitO(24, 4, 3, 4, false) :: Nil, p0 :: p1 :: Nil, 2, false)))

    /// live=通路(idx1>=roomCount)・torch=false → origin 無関係に通路全体が点灯（ライブ）。
    @Test
    def testHolesDraftCorridorLive(): Unit \ Assert =
        let p0 = RoomLayout.placement(0, 0,  0, 8, 8);
        let p1 = RoomLayout.placement(1, 10, 0, 8, 8);   // 通路（roomCount=1）
        Assert.assertEq(expected = (9, -1, 19, 9) :: Nil,
            holesT(FogScene.holesForDraft(unitO(12, 4, 3, 4, false) :: Nil, p0 :: p1 :: Nil, 1, false)))

    /// live=通路・torch=true → 周囲1マス（松明）。新規部屋デファーは通路には掛からない。
    @Test
    def testHolesDraftCorridorTorch(): Unit \ Assert =
        let p0 = RoomLayout.placement(0, 0,  0, 8, 8);
        let p1 = RoomLayout.placement(1, 10, 0, 8, 8);
        Assert.assertEq(expected = (11, 3, 14, 6) :: Nil,
            holesT(FogScene.holesForDraft(unitO(12, 4, 3, 4, false) :: Nil, p0 :: p1 :: Nil, 1, true)))

    // ── cursorRangeRects ─────────────────────────────────────

    /// 明るい部屋だけ（visited 空）→ moduleRect(p0)=(-1,-1,9,9) を radius=5 拡張した
    /// (-6,-6,14,14) 1 枚。既訪 module の矩形は付かない。
    @Test
    def testCursorRangeLitOnly(): Unit \ Assert =
        let p0 = RoomLayout.placement(0, 0,  0, 8, 8);
        let p1 = RoomLayout.placement(1, 20, 0, 8, 8);
        Assert.assertEq(expected = (-6, -6, 14, 14) :: Nil,
            holesT(FogScene.cursorRangeRects(unit(3, 4, false) :: Nil,
                                              p0 :: p1 :: Nil, 2, Set.empty(), 5)))

    /// 既訪 module(idx 1) があれば、明るい部屋の拡張矩形に加えて moduleRect(p1)
    /// （余白なし、(19,-1,29,9)）が和に入る。
    @Test
    def testCursorRangeVisitedAdded(): Unit \ Assert =
        let p0 = RoomLayout.placement(0, 0,  0, 8, 8);
        let p1 = RoomLayout.placement(1, 20, 0, 8, 8);
        Assert.assertEq(
            expected = (-6, -6, 14, 14) :: (19, -1, 29, 9) :: Nil,
            holesT(FogScene.cursorRangeRects(unit(3, 4, false) :: Nil,
                                              p0 :: p1 :: Nil, 2,
                                              Set.insert(1, Set.empty()), 5)))

    /// radius=5 の境界: moduleRect(p0) の右端 x1=9（=床 x≤8）から 5 マス先 x=13 は内側、
    /// x=14 は外側。
    @Test
    def testCursorRangeRadiusBoundary(): Unit \ Assert =
        let p0    = RoomLayout.placement(0, 0, 0, 8, 8);
        let rects = FogScene.cursorRangeRects(unit(3, 4, false) :: Nil,
                                               p0 :: Nil, 1, Set.empty(), 5);
        Assert.assertEq(expected = true,
            FogScene.insideAny(({x = 13, y = 4}: {x = Int32, y = Int32}), rects));
        Assert.assertEq(expected = false,
            FogScene.insideAny(({x = 14, y = 4}: {x = Int32, y = Int32}), rects))

    /// 未踏（visited に無い）遠方 module のセルは可動域外。visited に入れると可動域内。
    @Test
    def testCursorRangeUnvisitedExcluded(): Unit \ Assert =
        let p0   = RoomLayout.placement(0, 0,  0, 8, 8);
        let p1   = RoomLayout.placement(1, 20, 0, 8, 8);
        let cell = ({x = 24, y = 4}: {x = Int32, y = Int32});   // p1 内
        let units = unit(3, 4, false) :: Nil;
        Assert.assertEq(expected = false,
            FogScene.insideAny(cell,
                FogScene.cursorRangeRects(units, p0 :: p1 :: Nil, 2, Set.empty(), 5)));
        Assert.assertEq(expected = true,
            FogScene.insideAny(cell,
                FogScene.cursorRangeRects(units, p0 :: p1 :: Nil, 2,
                                           Set.insert(1, Set.empty()), 5)))
}
