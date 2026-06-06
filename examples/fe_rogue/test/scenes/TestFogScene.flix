/// FogScene の純粋ロジックテスト（LWJGL / scene 構築非依存）。
///
/// - `moduleRect`: module の floorBounds(±edgePad)を world grid 矩形へ。
/// - `bandDecompose`: area から holes（明るい部屋）を除いた補集合の矩形分割。
/// - `litModulesIn`: hidden 除外 / 和集合 / 通路 / module 外無視。
///
/// プール再配置（applyFog の Scene 変換）は scene 構築が LDTK/LWJGL を要するため
/// 統合/手動確認に委ねる。
mod TestFogScene {

    /// TestMapScene と同じ placement 生成ヘルパー（gridSize 全体が床と仮定）。
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

    /// litModulesIn 用の最小ユニット record（gridPos + hidden）。
    def unit(x: Int32, y: Int32, hidden: Bool): {gridPos = {x = Int32, y = Int32}, hidden = Bool} =
        {gridPos = ({x = x, y = y}: {x = Int32, y = Int32}), hidden = hidden}

    def rectT(r: {x0 = Int32, y0 = Int32, x1 = Int32, y1 = Int32}): (Int32, Int32, Int32, Int32) =
        (r#x0, r#y0, r#x1, r#y1)

    // ── moduleRect ───────────────────────────────────────────

    /// offset(0,0)・床 8×8、edgePad=1 で grid (-1,-1)..(9,9)。
    @Test
    def testModuleRectAtOrigin(): Unit \ Assert =
        Assert.assertEq(expected = (-1, -1, 9, 9),
            rectT(FogScene.moduleRect(placement(0, 0, 0, 8, 8))))

    /// offset(10,20)・床 5×3、edgePad=1 で grid (9,19)..(16,24)。
    @Test
    def testModuleRectWithOffset(): Unit \ Assert =
        Assert.assertEq(expected = (9, 19, 16, 24),
            rectT(FogScene.moduleRect(placement(2, 10, 20, 5, 3))))

    // ── bandDecompose ────────────────────────────────────────

    /// 穴なし → area 全体を覆う 1 矩形。
    @Test
    def testBandDecomposeNoHoles(): Unit \ Assert =
        let area = ({x0 = 0, y0 = 0, x1 = 10, y1 = 10}: {x0 = Int32, y0 = Int32, x1 = Int32, y1 = Int32});
        let result = FogScene.bandDecompose(area, Nil) |> List.map(rectT);
        Assert.assertEq(expected = (0, 0, 10, 10) :: Nil, result)

    /// 中央の穴 (4,4)..(6,6) → 上/左/右/下の 4 矩形で補集合を覆う。
    @Test
    def testBandDecomposeCenterHole(): Unit \ Assert =
        let area = ({x0 = 0, y0 = 0, x1 = 10, y1 = 10}: {x0 = Int32, y0 = Int32, x1 = Int32, y1 = Int32});
        let hole   = ({x0 = 4, y0 = 4, x1 = 6,  y1 = 6 }: {x0 = Int32, y0 = Int32, x1 = Int32, y1 = Int32});
        let result = FogScene.bandDecompose(area, hole :: Nil) |> List.map(rectT);
        // バンド (0,4): 全幅 / (4,6): 左右 / (6,10): 全幅
        Assert.assertEq(
            expected = (0, 0, 10, 4) :: (0, 4, 4, 6) :: (6, 4, 10, 6) :: (0, 6, 10, 10) :: Nil,
            result)

    // ── holesFor ─────────────────────────────────────────────

    def holesT(rs: List[{x0 = Int32, y0 = Int32, x1 = Int32, y1 = Int32}]):
            List[(Int32, Int32, Int32, Int32)] = List.map(rectT, rs)

    /// 部屋(idx 0 < roomCount)にいる → 部屋全体（moduleRect）が穴。torch は無関係。
    @Test
    def testHolesRoomFull(): Unit \ Assert =
        let p0 = placement(0, 0, 0, 8, 8);
        Assert.assertEq(expected = (-1, -1, 9, 9) :: Nil,
            holesT(FogScene.holesFor(unit(3, 4, false) :: Nil, p0 :: Nil, 1, true)))

    /// 通路(idx 1 >= roomCount)＋torch → 周囲1マス(3×3)だけが穴。
    @Test
    def testHolesCorridorTorch(): Unit \ Assert =
        let p0 = placement(0, 0,  0, 8, 8);
        let p1 = placement(1, 10, 0, 8, 8);   // 通路
        // (12,4) は p1。torch=true → torchRect(12,4) = (11,3)..(14,6)
        Assert.assertEq(expected = (11, 3, 14, 6) :: Nil,
            holesT(FogScene.holesFor(unit(12, 4, false) :: Nil, p0 :: p1 :: Nil, 1, true)))

    /// 通路＋torch=false（通常モード）→ 通路全体（moduleRect）が穴。
    @Test
    def testHolesCorridorNoTorch(): Unit \ Assert =
        let p0 = placement(0, 0,  0, 8, 8);
        let p1 = placement(1, 10, 0, 8, 8);
        // moduleRect(p1) = (10-1, 0-1)..(18+1, 8+1) = (9,-1,19,9)
        Assert.assertEq(expected = (9, -1, 19, 9) :: Nil,
            holesT(FogScene.holesFor(unit(12, 4, false) :: Nil, p0 :: p1 :: Nil, 1, false)))

    /// hidden プレイヤーは除外される → 穴なし。
    @Test
    def testHolesHiddenExcluded(): Unit \ Assert =
        let p0 = placement(0, 0, 0, 8, 8);
        Assert.assertEq(expected = (Nil: List[(Int32, Int32, Int32, Int32)]),
            holesT(FogScene.holesFor(unit(3, 4, true) :: Nil, p0 :: Nil, 1, false)))
}
