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
}
