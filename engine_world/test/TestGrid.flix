// Grid のテスト。セル中心の座標・位置からセルへの逆変換・隣接セル・矩形内判定を固定する。
// Vec2 は構造レコード（Eq 非導出）なので、比較はスカラ成分で行う。

mod TestGrid {

    /// セル中心はセル左上から半タイルずらした位置：(2,3) は tile=10 で (25, 35)。
    @Test
    def testCellCenterValue(): Unit \ Assert =
        let center = Grid.cellCenter(10.0, (2, 3));
        Assert.assertEq(expected = (25.0, 35.0), (center#x, center#y))

    /// cellOf は cellCenter の逆：中心座標を渡すと元のセルに戻る（負のセルも floor で正しく戻る）。
    @Test
    def testCellRoundTrip(): Unit \ Assert =
        let tileSize = 24.0;
        let cells = (0, 0) :: (3, 2) :: (-1, 5) :: (7, -4) :: Nil;
        Assert.assertEq(expected = cells,
            List.map(cell -> Grid.cellOf(tileSize, Grid.cellCenter(tileSize, cell)), cells))

    /// neighbor は方向の単位ステップだけ進んだセル：(5,5) の Up は (5,4)、Right は (6,5)。
    @Test
    def testNeighbor(): Unit \ Assert =
        Assert.assertEq(expected = ((5, 4), (6, 5)),
            (Grid.neighbor((5, 5), Dir4.Up), Grid.neighbor((5, 5), Dir4.Right)))

    /// inRect は列 [0,cols)・行 [0,rows) の内側だけ true。境界と外側は false。
    @Test
    def testInRect(): Unit \ Assert =
        Assert.assertEq(
            expected = (true, false, false, false),
            (Grid.inRect((0, 0), 3, 3), Grid.inRect((3, 0), 3, 3),
             Grid.inRect((-1, 0), 3, 3), Grid.inRect((0, 3), 3, 3)))

    /// record 版 cellCenterOf は tuple 版 cellCenter と一致：{x=2,y=3} は tile=10 で (25,35)。
    @Test
    def testCellCenterOfMatchesTuple(): Unit \ Assert =
        let c = Grid.cellCenterOf(10.0, {x = 2, y = 3});
        Assert.assertEq(expected = (25.0, 35.0), (c#x, c#y))

    /// cellAt は cellCenterOf の逆：中心座標を渡すと元のセルへ戻る（負のセルも floor で戻る）。
    @Test
    def testCellAtIsInverseOfCellCenterOf(): Unit \ Assert =
        let ts = 24.0;
        let cell = {x = -1, y = 5};
        let back = Grid.cellAt(ts, Grid.cellCenterOf(ts, cell));
        Assert.assertEq(expected = (-1, 5), (back#x, back#y))

    /// neighborOf は neighbor と同じ結果を {x,y} で返す：(5,5) の Up は (5,4)。
    @Test
    def testNeighborOfMatchesTuple(): Unit \ Assert =
        let n = Grid.neighborOf({x = 5, y = 5}, Dir4.Up);
        Assert.assertEq(expected = Grid.neighbor((5, 5), Dir4.Up), (n#x, n#y))

    /// inRectOf は inRect と同じ内外判定：内側は true、右端の外は false。
    @Test
    def testInRectOfMatchesTuple(): Unit \ Assert =
        Assert.assertEq(
            expected = (true, false),
            (Grid.inRectOf({x = 0, y = 0}, 3, 3), Grid.inRectOf({x = 3, y = 0}, 3, 3)))

    /// cellAtCentered はセル中心が整数の座標系：セル (2,3) の中心 (2.0, 3.0) はそのセルに入る。
    @Test
    def testCellAtCenteredCenterPoint(): Unit \ Assert =
        let c = Grid.cellAtCentered({ x = 2.0, y = 3.0 });
        Assert.assertEq(expected = (2, 3), (c#x, c#y))

    /// 境界 ±0.5 ちょうどの点は + 側のマスに属する：(1.5, 2.5) はセル (2,3) に入る。
    @Test
    def testCellAtCenteredBoundaryBelongsToPlusSide(): Unit \ Assert =
        let c = Grid.cellAtCentered({ x = 1.5, y = 2.5 });
        Assert.assertEq(expected = (2, 3), (c#x, c#y))

    /// 負の座標も同じ規約：セル (-1,-2) の中心 (-1.0, -2.0) はそのセルに入り、
    /// 境界 -1.5 は + 側のセル -1 に入る（ゼロ向き丸めなら 0 / -1 になって崩れる）。
    @Test
    def testCellAtCenteredNegativeCoordinates(): Unit \ Assert =
        let center = Grid.cellAtCentered({ x = -1.0, y = -2.0 });
        let edge = Grid.cellAtCentered({ x = -1.5, y = -1.5 });
        Assert.assertEq(expected = ((-1, -2), (-1, -1)),
            ((center#x, center#y), (edge#x, edge#y)))

    /// 大きさは「一番長い行」で測る。短い行は右が空いているものとして扱うので、
    /// 末尾の空白を書き足さなくてよい。
    @Test
    def testDimsOfRowsUsesLongestRow(): Unit \ Assert =
        let d = Grid.dimsOfRows("###" :: "#" :: "#####" :: Nil);
        Assert.assertEq(expected = (5, 3), (d#cols, d#rows))

    /// 空の並びは 0×0（空リストで落ちない）。
    @Test
    def testDimsOfRowsHandlesEmpty(): Unit \ Assert =
        let d = Grid.dimsOfRows(Nil);
        Assert.assertEq(expected = (0, 0), (d#cols, d#rows))

    /// ほどく順は上の行から・行の中は左から。短い行はそこで終わる（空きは作らない）。
    @Test
    def testCellsOfRowsWalksTopLeftFirstAndStopsAtShortRow(): Unit \ Assert =
        let cells = Grid.cellsOfRows("ab" :: "c" :: Nil)
            |> List.map(pair -> { let (c, ch) = pair; (c#x, c#y, ch) });
        Assert.assertEq(expected = (0, 0, 'a') :: (1, 0, 'b') :: (0, 1, 'c') :: Nil, cells)
}
