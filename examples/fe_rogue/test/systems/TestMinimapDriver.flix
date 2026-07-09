/// MinimapDriver の純粋ロジックテスト（LWJGL / scene 構築非依存）。
///
/// - `visitedThisFrame`: hidden 除外 / module 外無視 / 部屋・通路の両方を捕捉。
/// - `accumulate`: 訪問記憶の核（離脱後も idx が残る）。
/// - `tightRegion`: margin なしの探索マップ bbox（moduleRect の union）。
/// - `fitTransform` + `mapCell` / `mapRect`: 一様スケール + レターボックスのセンタリング。
/// - `visitedRects`: idx < roomCount を部屋、それ以外を通路と判定。
///
/// プール再配置（renderMinimap の Scene 変換）は scene 構築が LDTK/LWJGL を要するため
/// 統合/手動確認に委ねる（`TestFog` と同方針）。
mod TestMinimapDriver {

    // ModulePlacement 生成は本番の RoomLayout.placement を使う（テスト間の重複定義を廃止）。

    def unit(x: Int32, y: Int32, hidden: Bool): {gridPos = {x = Int32, y = Int32}, hidden = Bool} =
        {gridPos = ({x = x, y = y}: {x = Int32, y = Int32}), hidden = hidden}


    def vecT(v: Vec2.Vec2): (Float64, Float64) = (v#x, v#y)

    // ── visitedThisFrame ─────────────────────────────────────

    /// 部屋(idx0)と通路(idx1)に居る非 hidden は捕捉、module 外(void)と hidden は除外。
    @Test
    def testVisitedThisFrame(): Unit \ Assert =
        let p0 = RoomLayout.placement(0, 0,  0, 8, 8);   // セル (0..8, 0..8)
        let p1 = RoomLayout.placement(1, 10, 0, 8, 8);   // セル (10..18, 0..8) 通路
        let units = unit(3, 4, false)      // p0
                 :: unit(12, 4, false)     // p1
                 :: unit(100, 100, false)  // void → 無視
                 :: unit(5, 5, true)       // hidden → 無視
                 :: Nil;
        Assert.assertEq(expected = Set#{0, 1},
            MinimapDriver.visitedThisFrame(units, p0 :: p1 :: Nil))

    // ── visitedThisFrameDrafted / litRoomsDrafted（新規部屋は確定まで記録しない） ──

    def unitO(x: Int32, y: Int32, ox: Int32, oy: Int32, hidden: Bool):
            {gridPos = {x = Int32, y = Int32}, origin = {x = Int32, y = Int32}, hidden = Bool} =
        {gridPos = ({x = x, y = y}: {x = Int32, y = Int32}),
         origin  = ({x = ox, y = oy}: {x = Int32, y = Int32}), hidden = hidden}

    /// origin=部屋A(idx0)・live=新部屋B(idx1) → B は訪問記録しない（A も live に居ないので空）。
    @Test
    def testVisitedDraftNewRoomExcluded(): Unit \ Assert =
        let p0 = RoomLayout.placement(0, 0,  0, 8, 8);
        let p1 = RoomLayout.placement(1, 20, 0, 8, 8);   // 部屋（roomCount=2）
        Assert.assertEq(expected = (Set.empty(): Set[Int32]),
            MinimapDriver.visitedThisFrameDrafted(unitO(24, 4, 3, 4, false) :: Nil, p0 :: p1 :: Nil, 2))

    /// 通路(idx1>=roomCount)はライブで記録、origin 一致の部屋A(idx0)も記録。
    @Test
    def testVisitedDraftCorridorAndOriginRoom(): Unit \ Assert =
        let p0 = RoomLayout.placement(0, 0,  0, 8, 8);   // 部屋
        let p1 = RoomLayout.placement(1, 10, 0, 8, 8);   // 通路（roomCount=1）
        let units = unitO(3, 4, 3, 4, false)      // 部屋A: origin==live → 記録
                 :: unitO(12, 4, 12, 4, false)    // 通路: ライブ記録
                 :: Nil;
        Assert.assertEq(expected = Set#{0, 1},
            MinimapDriver.visitedThisFrameDrafted(units, p0 :: p1 :: Nil, 1))

    /// 点灯部屋集合: origin 一致の部屋A(idx0)だけ。新部屋B(idx1)と通路(idx2)は入らない。
    @Test
    def testLitRoomsDrafted(): Unit \ Assert =
        let p0 = RoomLayout.placement(0, 0,  0, 8, 8);   // 部屋 idx0
        let p1 = RoomLayout.placement(1, 20, 0, 8, 8);   // 部屋 idx1
        let p2 = RoomLayout.placement(2, 40, 0, 8, 8);   // 通路 idx2 (roomCount=2)
        let units = unitO(3, 4, 3, 4, false)       // 部屋A origin一致 → lit
                 :: unitO(24, 4, 3, 4, false)      // 新部屋B origin不一致 → 暗い
                 :: unitO(44, 4, 44, 4, false)     // 通路 → room ではないので除外
                 :: Nil;
        Assert.assertEq(expected = Set#{0},
            MinimapDriver.litRoomsDrafted(units, p0 :: p1 :: p2 :: Nil, 2))

    // ── accumulate（記憶の核） ───────────────────────────────

    /// 新フレーム分を足す。
    @Test
    def testAccumulateAddsNew(): Unit \ Assert =
        Assert.assertEq(expected = Set#{0, 1, 2},
            MinimapDriver.accumulate(Set#{0, 1}, Set#{2}))

    /// 部屋を離れて今フレームに何も無くても、過去の訪問は残る（= 記憶）。
    @Test
    def testAccumulateRemembers(): Unit \ Assert =
        Assert.assertEq(expected = Set#{0, 1},
            MinimapDriver.accumulate(Set#{0, 1}, Set.empty()))

    // ── tightRegion ──────────────────────────────────────────

    /// 単一 module: moduleRect(edgePad=1) そのもの。
    @Test
    def testTightRegionSingle(): Unit \ Assert =
        Assert.assertEq(expected = (-1, -1, 9, 9),
            TestUnitFixtures.rectT(MinimapDriver.tightRegion(RoomLayout.placement(0, 0, 0, 8, 8) :: Nil)))

    /// 複数 module: 各 moduleRect の union。p0→(-1,-1,9,9), p1→(9,-1,16,4)。
    @Test
    def testTightRegionUnion(): Unit \ Assert =
        let p0 = RoomLayout.placement(0, 0,  0, 8, 8);
        let p1 = RoomLayout.placement(1, 10, 0, 5, 3);
        Assert.assertEq(expected = (-1, -1, 16, 9),
            TestUnitFixtures.rectT(MinimapDriver.tightRegion(p0 :: p1 :: Nil)))

    // ── fitTransform + mapCell ───────────────────────────────

    /// 正方リージョンを正方ターゲットへ: scale=10, オフセット 0。
    @Test
    def testFitSquare(): Unit \ Assert =
        let area = ({x0 = 0, y0 = 0, x1 = 10, y1 = 10}: GridRect);
        let target = ({x0 = 0, y0 = 0, x1 = 100, y1 = 100}: GridRect);
        let t = MinimapDriver.fitTransform(area, target);
        Assert.assertEq(expected = (50.0, 50.0),
            vecT(MinimapDriver.mapCell(({x = 5, y = 5}: {x = Int32, y = Int32}), t)))

    /// 横長リージョン → 縦にレターボックス。scale=min(5,10)=5, oy=(100-50)/2=25。
    @Test
    def testFitLetterbox(): Unit \ Assert =
        let area = ({x0 = 0, y0 = 0, x1 = 20, y1 = 10}: GridRect);
        let target = ({x0 = 0, y0 = 0, x1 = 100, y1 = 100}: GridRect);
        let t = MinimapDriver.fitTransform(area, target);
        // 左上 (0,0) → (0,25)、右下 (20,10) → (100,75)
        Assert.assertEq(expected = (0.0, 25.0),
            vecT(MinimapDriver.mapCell(({x = 0, y = 0}: {x = Int32, y = Int32}), t)))

    @Test
    def testFitLetterboxFarCorner(): Unit \ Assert =
        let area = ({x0 = 0, y0 = 0, x1 = 20, y1 = 10}: GridRect);
        let target = ({x0 = 0, y0 = 0, x1 = 100, y1 = 100}: GridRect);
        let t = MinimapDriver.fitTransform(area, target);
        Assert.assertEq(expected = (100.0, 75.0),
            vecT(MinimapDriver.mapCell(({x = 20, y = 10}: {x = Int32, y = Int32}), t)))

    // ── mapRect ──────────────────────────────────────────────

    /// scale=10 で grid 2×2 矩形 → 20×20 ピクセル、左上原点。
    @Test
    def testMapRect(): Unit \ Assert =
        let area = ({x0 = 0, y0 = 0, x1 = 10, y1 = 10}: GridRect);
        let target = ({x0 = 0, y0 = 0, x1 = 100, y1 = 100}: GridRect);
        let t = MinimapDriver.fitTransform(area, target);
        let pr = MinimapDriver.mapRect(({x0 = 0, y0 = 0, x1 = 2, y1 = 2}: GridRect), t);
        Assert.assertEq(expected = ((0.0, 0.0), (20.0, 20.0)), (vecT(pr#pos), vecT(pr#size)))

    // ── visitedRects ─────────────────────────────────────────

    def rectsT(rs: List[{idx = Int32, isRoom = Bool, rect = GridRect}]):
            List[(Int32, Bool)] = List.map(r -> (r#idx, r#isRoom), rs)

    /// 訪問 {0,1}・roomCount=1 → idx0=部屋, idx1=通路。
    @Test
    def testVisitedRectsRoomAndCorridor(): Unit \ Assert =
        let p0 = RoomLayout.placement(0, 0,  0, 8, 8);
        let p1 = RoomLayout.placement(1, 10, 0, 8, 8);
        Assert.assertEq(expected = (0, true) :: (1, false) :: Nil,
            rectsT(MinimapDriver.visitedRects(Set#{0, 1}, p0 :: p1 :: Nil, 1)))

    /// 未訪問の module は出ない（visited に無い idx は除外）。
    @Test
    def testVisitedRectsFiltersUnvisited(): Unit \ Assert =
        let p0 = RoomLayout.placement(0, 0,  0, 8, 8);
        let p1 = RoomLayout.placement(1, 10, 0, 8, 8);
        Assert.assertEq(expected = (0, true) :: Nil,
            rectsT(MinimapDriver.visitedRects(Set#{0}, p0 :: p1 :: Nil, 1)))

    // ── boundsOf / anchorBL（左下合わせ） ────────────────────

    @Test
    def testBoundsOfUnion(): Unit \ Assert =
        let rs = ({x0 = 0, y0 = 0, x1 = 4, y1 = 4}: GridRect)
              :: ({x0 = 10, y0 = 2, x1 = 14, y1 = 8}: GridRect) :: Nil;
        Assert.assertEq(expected = (0, 0, 14, 8), TestUnitFixtures.rectT(MinimapDriver.boundsOf(rs)))

    /// content の左下が target の左下に来る（content がどこにあっても）。
    @Test
    def testAnchorBLBottomLeftRoom(): Unit \ Assert =
        let scaleArea = ({x0 = 0, y0 = 0, x1 = 20, y1 = 20}: GridRect);
        let target    = ({x0 = 0, y0 = 0, x1 = 100, y1 = 100}: GridRect);
        let content   = ({x0 = 0, y0 = 16, x1 = 4, y1 = 20}: GridRect);  // 左下の部屋
        let t = MinimapDriver.anchorBL(scaleArea, content, target);
        // content 左下隅 (0,20) → target 左下 (0,100)
        Assert.assertEq(expected = (0.0, 100.0),
            vecT(MinimapDriver.mapCell(({x = 0, y = 20}: {x = Int32, y = Int32}), t)))

    /// content が右上寄りでも、その左下隅が target 左下に合う（位置不変・スケールは scaleArea 基準）。
    @Test
    def testAnchorBLContentElsewhere(): Unit \ Assert =
        let scaleArea = ({x0 = 0, y0 = 0, x1 = 20, y1 = 20}: GridRect);
        let target    = ({x0 = 0, y0 = 0, x1 = 100, y1 = 100}: GridRect);
        let content   = ({x0 = 10, y0 = 0, x1 = 14, y1 = 4}: GridRect);
        let t = MinimapDriver.anchorBL(scaleArea, content, target);
        Assert.assertEq(expected = (0.0, 100.0),
            vecT(MinimapDriver.mapCell(({x = 10, y = 4}: {x = Int32, y = Int32}), t)))

    // ── anchorBLWithScale / 縮尺一定（フロア間統一） ─────────────

    /// 与えた scale をそのまま使い、content 左下を target 左下へ合わせる。
    @Test
    def testAnchorBLWithScaleUsesGivenScale(): Unit \ Assert =
        let target  = ({x0 = 0, y0 = 0, x1 = 100, y1 = 100}: GridRect);
        let content = ({x0 = 10, y0 = 0, x1 = 14, y1 = 4}: GridRect);
        let t = MinimapDriver.anchorBLWithScale(3.0, content, target);
        let pos = MinimapDriver.mapCell(({x = 10, y = 4}: {x = Int32, y = Int32}), t);
        Assert.assertEq(expected = (3.0, 0.0, 100.0), (t#scale, pos#x, pos#y))

    /// 参照内に収まる 2 つの異なるフロア寸法でも、適用される縮尺は同一（referenceScale）。
    /// = フロアの実寸に依らずミニマップのズーム率が一定になることの回帰テスト。
    @Test
    def testMinimapScaleConstantAcrossFloorSizes(): Unit \ Assert =
        let target = MinimapDriver.targetRect();
        let small  = ({x0 = 0, y0 = 0, x1 = 23, y1 = 12}: GridRect);   // 小フロア (rc2 相当)
        let mid    = ({x0 = 0, y0 = 0, x1 = 35, y1 = 38}: GridRect);   // 大きめ (rc6 相当)
        let ref    = MinimapDriver.referenceScale();
        let sSmall = Float64.min(ref, MinimapDriver.fitTransform(small, target)#scale);
        let sMid   = Float64.min(ref, MinimapDriver.fitTransform(mid, target)#scale);
        Assert.assertEq(expected = (ref, ref), (sSmall, sMid))

    /// 参照より大きい巨大フロアは、はみ出し防止のため fit 倍率にクランプ（縮小）される。
    @Test
    def testMinimapScaleClampedForHugeFloor(): Unit \ Assert =
        let target = MinimapDriver.targetRect();
        let huge   = ({x0 = 0, y0 = 0, x1 = 70, y1 = 51}: GridRect);   // 参照(47×51)より広い
        let ref    = MinimapDriver.referenceScale();
        let fit    = MinimapDriver.fitTransform(huge, target)#scale;
        Assert.assertEq(expected = true, Float64.min(ref, fit) < ref)

    // ── corridorHints（出口ヒント） ──────────────────────────

    /// 訪問済み部屋に隣接する未訪問通路だけを出口ヒントとして出す。遠い通路は出さない。
    @Test
    def testCorridorHintsAdjacentOnly(): Unit \ Assert =
        let p0 = RoomLayout.placement(0, 0,   0, 8, 8);  // 部屋(訪問済み)
        let p1 = RoomLayout.placement(1, 8,   0, 4, 8);  // p0 に隣接する通路 → ヒント
        let p2 = RoomLayout.placement(2, 100, 0, 4, 8);  // 遠い通路 → 出さない
        Assert.assertEq(expected = Set#{1},
            MinimapDriver.corridorHints(Set#{0}, p0 :: p1 :: p2 :: Nil, 1))

    /// 既に訪問済みの通路はヒントに含めない（重複しない）。
    @Test
    def testCorridorHintsExcludesVisited(): Unit \ Assert =
        let p0 = RoomLayout.placement(0, 0, 0, 8, 8);
        let p1 = RoomLayout.placement(1, 8, 0, 4, 8);
        Assert.assertEq(expected = (Set.empty(): Set[Int32]),
            MinimapDriver.corridorHints(Set#{0, 1}, p0 :: p1 :: Nil, 1))

    /// 訪問済みが無ければヒントも無い。
    @Test
    def testCorridorHintsEmptyWhenNothingVisited(): Unit \ Assert =
        let p0 = RoomLayout.placement(0, 0, 0, 8, 8);
        let p1 = RoomLayout.placement(1, 8, 0, 4, 8);
        Assert.assertEq(expected = (Set.empty(): Set[Int32]),
            MinimapDriver.corridorHints(Set.empty(), p0 :: p1 :: Nil, 1))

    // ── unionBands（部屋・通路の一体化、重なり除去） ─────────

    def gridR(x0: Int32, y0: Int32, x1: Int32, y1: Int32): GridRect =
        ({x0 = x0, y0 = y0, x1 = x1, y1 = y1}: GridRect)

    /// 横に重なる 2 矩形 → 重なりを描かず 1 本に結合。
    @Test
    def testUnionBandsMergesOverlap(): Unit \ Assert =
        let rs = gridR(0, 0, 4, 4) :: gridR(2, 0, 6, 4) :: Nil;
        Assert.assertEq(expected = (0, 0, 6, 4) :: Nil,
            MinimapDriver.unionBands(rs) |> List.map(TestUnitFixtures.rectT))

    /// 離れた 2 矩形 → そのまま 2 本（結合しない）。
    @Test
    def testUnionBandsKeepsSeparate(): Unit \ Assert =
        let rs = gridR(0, 0, 2, 2) :: gridR(4, 0, 6, 2) :: Nil;
        Assert.assertEq(expected = (0, 0, 2, 2) :: (4, 0, 6, 2) :: Nil,
            MinimapDriver.unionBands(rs) |> List.map(TestUnitFixtures.rectT))

    /// 部屋＋下に伸びる通路（L 字）→ 互いに重ならない 2 矩形に分割。
    @Test
    def testUnionBandsLShapeDisjoint(): Unit \ Assert =
        let rs = gridR(0, 0, 4, 4) :: gridR(1, 4, 3, 8) :: Nil;
        Assert.assertEq(expected = (0, 0, 4, 4) :: (1, 4, 3, 8) :: Nil,
            MinimapDriver.unionBands(rs) |> List.map(TestUnitFixtures.rectT))
}
