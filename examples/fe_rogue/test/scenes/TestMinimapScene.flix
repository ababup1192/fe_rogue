/// MinimapScene の純粋ロジックテスト（LWJGL / scene 構築非依存）。
///
/// - `visitedThisFrame`: hidden 除外 / module 外無視 / 部屋・通路の両方を捕捉。
/// - `accumulate`: 訪問記憶の核（離脱後も idx が残る）。
/// - `tightRegion`: margin なしの探索マップ bbox（moduleRect の union）。
/// - `fitTransform` + `mapCell` / `mapRect`: 一様スケール + レターボックスのセンタリング。
/// - `visitedRects`: idx < roomCount を部屋、それ以外を通路と判定。
///
/// プール再配置（renderMinimap の Scene 変換）は scene 構築が LDTK/LWJGL を要するため
/// 統合/手動確認に委ねる（`TestFogScene` と同方針）。
mod TestMinimapScene {

    /// TestFogScene と同じ placement 生成ヘルパー（gridSize 全体が床と仮定）。
    def placement(idx: Int32, ox: Int32, oy: Int32, w: Int32, h: Int32):
                  DungeonComposer.ModulePlacement =
        {
            idx              = idx,
            offset           = ({x = ox, y = oy}: {x = Int32, y = Int32}),
            gridSize         = ({x = w,  y = h }: {x = Int32, y = Int32}),
            floorBoundsMin   = ({x = 0,  y = 0 }: {x = Int32, y = Int32}),
            floorBoundsMaxEx = ({x = w,  y = h }: {x = Int32, y = Int32}),
            interiorCells    = (Nil: List[{x = Int32, y = Int32}])
        }

    def unit(x: Int32, y: Int32, hidden: Bool): {gridPos = {x = Int32, y = Int32}, hidden = Bool} =
        {gridPos = ({x = x, y = y}: {x = Int32, y = Int32}), hidden = hidden}

    def rectT(r: GridRect): (Int32, Int32, Int32, Int32) = (r#x0, r#y0, r#x1, r#y1)

    def vecT(v: Vec2.Vec2): (Float64, Float64) = (v#x, v#y)

    // ── visitedThisFrame ─────────────────────────────────────

    /// 部屋(idx0)と通路(idx1)に居る非 hidden は捕捉、module 外(void)と hidden は除外。
    @Test
    def testVisitedThisFrame(): Unit \ Assert =
        let p0 = placement(0, 0,  0, 8, 8);   // セル (0..8, 0..8)
        let p1 = placement(1, 10, 0, 8, 8);   // セル (10..18, 0..8) 通路
        let units = unit(3, 4, false)      // p0
                 :: unit(12, 4, false)     // p1
                 :: unit(100, 100, false)  // void → 無視
                 :: unit(5, 5, true)       // hidden → 無視
                 :: Nil;
        Assert.assertEq(expected = Set#{0, 1},
            MinimapScene.visitedThisFrame(units, p0 :: p1 :: Nil))

    // ── accumulate（記憶の核） ───────────────────────────────

    /// 新フレーム分を足す。
    @Test
    def testAccumulateAddsNew(): Unit \ Assert =
        Assert.assertEq(expected = Set#{0, 1, 2},
            MinimapScene.accumulate(Set#{0, 1}, Set#{2}))

    /// 部屋を離れて今フレームに何も無くても、過去の訪問は残る（= 記憶）。
    @Test
    def testAccumulateRemembers(): Unit \ Assert =
        Assert.assertEq(expected = Set#{0, 1},
            MinimapScene.accumulate(Set#{0, 1}, Set.empty()))

    // ── tightRegion ──────────────────────────────────────────

    /// 単一 module: moduleRect(edgePad=1) そのもの。
    @Test
    def testTightRegionSingle(): Unit \ Assert =
        Assert.assertEq(expected = (-1, -1, 9, 9),
            rectT(MinimapScene.tightRegion(placement(0, 0, 0, 8, 8) :: Nil)))

    /// 複数 module: 各 moduleRect の union。p0→(-1,-1,9,9), p1→(9,-1,16,4)。
    @Test
    def testTightRegionUnion(): Unit \ Assert =
        let p0 = placement(0, 0,  0, 8, 8);
        let p1 = placement(1, 10, 0, 5, 3);
        Assert.assertEq(expected = (-1, -1, 16, 9),
            rectT(MinimapScene.tightRegion(p0 :: p1 :: Nil)))

    // ── fitTransform + mapCell ───────────────────────────────

    /// 正方リージョンを正方ターゲットへ: scale=10, オフセット 0。
    @Test
    def testFitSquare(): Unit \ Assert =
        let area = ({x0 = 0, y0 = 0, x1 = 10, y1 = 10}: GridRect);
        let target = ({x0 = 0, y0 = 0, x1 = 100, y1 = 100}: GridRect);
        let t = MinimapScene.fitTransform(area, target);
        Assert.assertEq(expected = (50.0, 50.0),
            vecT(MinimapScene.mapCell(({x = 5, y = 5}: {x = Int32, y = Int32}), t)))

    /// 横長リージョン → 縦にレターボックス。scale=min(5,10)=5, oy=(100-50)/2=25。
    @Test
    def testFitLetterbox(): Unit \ Assert =
        let area = ({x0 = 0, y0 = 0, x1 = 20, y1 = 10}: GridRect);
        let target = ({x0 = 0, y0 = 0, x1 = 100, y1 = 100}: GridRect);
        let t = MinimapScene.fitTransform(area, target);
        // 左上 (0,0) → (0,25)、右下 (20,10) → (100,75)
        Assert.assertEq(expected = (0.0, 25.0),
            vecT(MinimapScene.mapCell(({x = 0, y = 0}: {x = Int32, y = Int32}), t)))

    @Test
    def testFitLetterboxFarCorner(): Unit \ Assert =
        let area = ({x0 = 0, y0 = 0, x1 = 20, y1 = 10}: GridRect);
        let target = ({x0 = 0, y0 = 0, x1 = 100, y1 = 100}: GridRect);
        let t = MinimapScene.fitTransform(area, target);
        Assert.assertEq(expected = (100.0, 75.0),
            vecT(MinimapScene.mapCell(({x = 20, y = 10}: {x = Int32, y = Int32}), t)))

    // ── mapRect ──────────────────────────────────────────────

    /// scale=10 で grid 2×2 矩形 → 20×20 ピクセル、左上原点。
    @Test
    def testMapRect(): Unit \ Assert =
        let area = ({x0 = 0, y0 = 0, x1 = 10, y1 = 10}: GridRect);
        let target = ({x0 = 0, y0 = 0, x1 = 100, y1 = 100}: GridRect);
        let t = MinimapScene.fitTransform(area, target);
        let pr = MinimapScene.mapRect(({x0 = 0, y0 = 0, x1 = 2, y1 = 2}: GridRect), t);
        Assert.assertEq(expected = ((0.0, 0.0), (20.0, 20.0)), (vecT(pr#pos), vecT(pr#size)))

    // ── visitedRects ─────────────────────────────────────────

    def rectsT(rs: List[{idx = Int32, isRoom = Bool, rect = GridRect}]):
            List[(Int32, Bool)] = List.map(r -> (r#idx, r#isRoom), rs)

    /// 訪問 {0,1}・roomCount=1 → idx0=部屋, idx1=通路。
    @Test
    def testVisitedRectsRoomAndCorridor(): Unit \ Assert =
        let p0 = placement(0, 0,  0, 8, 8);
        let p1 = placement(1, 10, 0, 8, 8);
        Assert.assertEq(expected = (0, true) :: (1, false) :: Nil,
            rectsT(MinimapScene.visitedRects(Set#{0, 1}, p0 :: p1 :: Nil, 1)))

    /// 未訪問の module は出ない（visited に無い idx は除外）。
    @Test
    def testVisitedRectsFiltersUnvisited(): Unit \ Assert =
        let p0 = placement(0, 0,  0, 8, 8);
        let p1 = placement(1, 10, 0, 8, 8);
        Assert.assertEq(expected = (0, true) :: Nil,
            rectsT(MinimapScene.visitedRects(Set#{0}, p0 :: p1 :: Nil, 1)))

    // ── boundsOf / anchorBL（左下合わせ） ────────────────────

    @Test
    def testBoundsOfUnion(): Unit \ Assert =
        let rs = ({x0 = 0, y0 = 0, x1 = 4, y1 = 4}: GridRect)
              :: ({x0 = 10, y0 = 2, x1 = 14, y1 = 8}: GridRect) :: Nil;
        Assert.assertEq(expected = (0, 0, 14, 8), rectT(MinimapScene.boundsOf(rs)))

    /// content の左下が target の左下に来る（content がどこにあっても）。
    @Test
    def testAnchorBLBottomLeftRoom(): Unit \ Assert =
        let scaleArea = ({x0 = 0, y0 = 0, x1 = 20, y1 = 20}: GridRect);
        let target    = ({x0 = 0, y0 = 0, x1 = 100, y1 = 100}: GridRect);
        let content   = ({x0 = 0, y0 = 16, x1 = 4, y1 = 20}: GridRect);  // 左下の部屋
        let t = MinimapScene.anchorBL(scaleArea, content, target);
        // content 左下隅 (0,20) → target 左下 (0,100)
        Assert.assertEq(expected = (0.0, 100.0),
            vecT(MinimapScene.mapCell(({x = 0, y = 20}: {x = Int32, y = Int32}), t)))

    /// content が右上寄りでも、その左下隅が target 左下に合う（位置不変・スケールは scaleArea 基準）。
    @Test
    def testAnchorBLContentElsewhere(): Unit \ Assert =
        let scaleArea = ({x0 = 0, y0 = 0, x1 = 20, y1 = 20}: GridRect);
        let target    = ({x0 = 0, y0 = 0, x1 = 100, y1 = 100}: GridRect);
        let content   = ({x0 = 10, y0 = 0, x1 = 14, y1 = 4}: GridRect);
        let t = MinimapScene.anchorBL(scaleArea, content, target);
        Assert.assertEq(expected = (0.0, 100.0),
            vecT(MinimapScene.mapCell(({x = 10, y = 4}: {x = Int32, y = Int32}), t)))

    // ── corridorHints（出口ヒント） ──────────────────────────

    /// 訪問済み部屋に隣接する未訪問通路だけを出口ヒントとして出す。遠い通路は出さない。
    @Test
    def testCorridorHintsAdjacentOnly(): Unit \ Assert =
        let p0 = placement(0, 0,   0, 8, 8);  // 部屋(訪問済み)
        let p1 = placement(1, 8,   0, 4, 8);  // p0 に隣接する通路 → ヒント
        let p2 = placement(2, 100, 0, 4, 8);  // 遠い通路 → 出さない
        Assert.assertEq(expected = Set#{1},
            MinimapScene.corridorHints(Set#{0}, p0 :: p1 :: p2 :: Nil, 1))

    /// 既に訪問済みの通路はヒントに含めない（重複しない）。
    @Test
    def testCorridorHintsExcludesVisited(): Unit \ Assert =
        let p0 = placement(0, 0, 0, 8, 8);
        let p1 = placement(1, 8, 0, 4, 8);
        Assert.assertEq(expected = (Set.empty(): Set[Int32]),
            MinimapScene.corridorHints(Set#{0, 1}, p0 :: p1 :: Nil, 1))

    /// 訪問済みが無ければヒントも無い。
    @Test
    def testCorridorHintsEmptyWhenNothingVisited(): Unit \ Assert =
        let p0 = placement(0, 0, 0, 8, 8);
        let p1 = placement(1, 8, 0, 4, 8);
        Assert.assertEq(expected = (Set.empty(): Set[Int32]),
            MinimapScene.corridorHints(Set.empty(), p0 :: p1 :: Nil, 1))

    // ── unionBands（部屋・通路の一体化、重なり除去） ─────────

    def gridR(x0: Int32, y0: Int32, x1: Int32, y1: Int32): GridRect =
        ({x0 = x0, y0 = y0, x1 = x1, y1 = y1}: GridRect)

    /// 横に重なる 2 矩形 → 重なりを描かず 1 本に結合。
    @Test
    def testUnionBandsMergesOverlap(): Unit \ Assert =
        let rs = gridR(0, 0, 4, 4) :: gridR(2, 0, 6, 4) :: Nil;
        Assert.assertEq(expected = (0, 0, 6, 4) :: Nil,
            MinimapScene.unionBands(rs) |> List.map(rectT))

    /// 離れた 2 矩形 → そのまま 2 本（結合しない）。
    @Test
    def testUnionBandsKeepsSeparate(): Unit \ Assert =
        let rs = gridR(0, 0, 2, 2) :: gridR(4, 0, 6, 2) :: Nil;
        Assert.assertEq(expected = (0, 0, 2, 2) :: (4, 0, 6, 2) :: Nil,
            MinimapScene.unionBands(rs) |> List.map(rectT))

    /// 部屋＋下に伸びる通路（L 字）→ 互いに重ならない 2 矩形に分割。
    @Test
    def testUnionBandsLShapeDisjoint(): Unit \ Assert =
        let rs = gridR(0, 0, 4, 4) :: gridR(1, 4, 3, 8) :: Nil;
        Assert.assertEq(expected = (0, 0, 4, 4) :: (1, 4, 3, 8) :: Nil,
            MinimapScene.unionBands(rs) |> List.map(rectT))
}
