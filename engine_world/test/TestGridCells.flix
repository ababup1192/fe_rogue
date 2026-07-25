// Grid.cellsIn（見えている矩形に重なるマス）— 盤の外へはみ出さない・余分を足せる。
mod TestGridCells {

    def area(x: Float64, y: Float64, w: Float64, h: Float64):
            { position = Vec2.Vec2, size = Vec2.Vec2 } =
        { position = { x = x, y = y }, size = { x = w, y = h } }

    @Test
    def testStaysInsideTheBoard(): Unit \ Assert =
        // 盤の左上より外を見ても、負のマスは出てこない。
        let cells = Grid.cellsIn({ tileSize = 10.0, area = area(-50.0, -50.0, 30.0, 30.0),
                                   cols = 4, rows = 4, margin = Grid.noMargin() });
        Assert.assertEq(expected = true,
            cells |> List.forAll(c -> c#x >= 0 and c#y >= 0 and c#x < 4 and c#y < 4))

    @Test
    def testCoversExactlyTheOverlappingCells(): Unit \ Assert =
        // 10px のマスで (0,0)-(20,10) を見ると、横 3 列 × 縦 2 行に重なる。
        let cells = Grid.cellsIn({ tileSize = 10.0, area = area(0.0, 0.0, 20.0, 10.0),
                                   cols = 8, rows = 8, margin = Grid.noMargin() });
        Assert.assertEq(expected = 6, List.length(cells))

    @Test
    def testMarginAddsCellsOutsideTheView(): Unit \ Assert =
        // 下へ 2 マスぶん余分に見る（画面の外に立つ木の葉が中へ差し込むため）。
        let plain = Grid.cellsIn({ tileSize = 10.0, area = area(0.0, 0.0, 10.0, 10.0),
                                   cols = 8, rows = 8, margin = Grid.noMargin() });
        let wide = Grid.cellsIn({ tileSize = 10.0, area = area(0.0, 0.0, 10.0, 10.0),
                                  cols = 8, rows = 8,
                                  margin = { left = 0, top = 0, right = 0, bottom = 2 } });
        // 2×2 の 4 マスが、下に 2 行増えて 2×4 の 8 マスになる。
        Assert.assertEq(expected = (4, 8), (List.length(plain), List.length(wide)))

    @Test
    def testBrokenTileSizeYieldsNothing(): Unit \ Assert =
        // 0 や負のマス目は割れないので、黙って何も返さない（fail-open）。
        Assert.assertEq(expected = 0,
            Grid.cellsIn({ tileSize = 0.0, area = area(0.0, 0.0, 10.0, 10.0),
                           cols = 4, rows = 4, margin = Grid.noMargin() }) |> List.length)
}
