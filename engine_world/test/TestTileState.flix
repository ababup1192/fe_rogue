// TileState（マスごとの状態の表）— 置く・引く・消す、一斉更新、セーブとの往復。
mod TestTileState {

    def cell(x: Int32, y: Int32): Grid.Cell = { x = x, y = y }

    @Test
    def testPutAndGetRoundTrip(): Unit \ Assert =
        let table = TileState.empty() |> TileState.put(cell(3, 4), 7);
        Assert.assertEq(expected = (Some(7), None), (TileState.get(cell(3, 4), table),
                                                     TileState.get(cell(4, 3), table)))

    @Test
    def testOnlyFilledCellsAreHeld(): Unit \ Assert =
        // 疎な表 — 値を置いたマスの数しか持たない。
        let table = TileState.empty()
            |> TileState.put(cell(0, 0), 1)
            |> TileState.put(cell(9, 9), 1);
        Assert.assertEq(expected = 2, TileState.size(table))

    @Test
    def testRemoveDropsTheCell(): Unit \ Assert =
        let table = TileState.empty() |> TileState.put(cell(1, 1), 5) |> TileState.remove(cell(1, 1));
        Assert.assertEq(expected = false, TileState.has(cell(1, 1), table))

    @Test
    def testUpdateCanCreateAndErase(): Unit \ Assert =
        let made = TileState.update(cell(2, 2), _ -> Some(1), TileState.empty());
        let erased = TileState.update(cell(2, 2), _ -> (None: Option[Int32]), made);
        Assert.assertEq(expected = (1, 0), (TileState.size(made), TileState.size(erased)))

    @Test
    def testMapValuesUpdatesEveryCellAtOnce(): Unit \ Assert =
        // 「日が変わったら畑を一斉に更新する」の形。
        let table = TileState.empty()
            |> TileState.put(cell(0, 0), 1)
            |> TileState.put(cell(1, 0), 2)
            |> TileState.mapValues(v -> v * 10);
        Assert.assertEq(expected = (Some(10), Some(20)),
            (TileState.get(cell(0, 0), table), TileState.get(cell(1, 0), table)))

    @Test
    def testSaveRoundTripKeepsCellsAndValues(): Unit \ Assert =
        let table = TileState.empty()
            |> TileState.put(cell(3, 7), 42)
            |> TileState.put(cell(-2, 5), 1);
        let json = TileState.toJson(v -> Util.Json.Json.JNumber(JsonCodec.intToBd(v)), table);
        let back = TileState.fromJson(JsonCodec.expectInt, json);
        Assert.assertEq(expected = (2, Some(42), Some(1)),
            (TileState.size(back), TileState.get(cell(3, 7), back), TileState.get(cell(-2, 5), back)))

    @Test
    def testBrokenSaveFallsBackToEmpty(): Unit \ Assert =
        // 読めないセーブは黙って空になる（遊びは続く）。
        let back: TileState.Table[Int32] =
            TileState.fromJson(JsonCodec.expectInt, Util.Json.Json.JString("こわれている"));
        Assert.assertEq(expected = 0, TileState.size(back))
}
