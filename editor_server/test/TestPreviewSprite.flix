// TestPreviewSprite — /preview/sprite の純粋な部分 (シートのセル並び・格子寸法・
// フォールバック色の決定性) を固定する。PNG の中身は curl + 目視検品と
// TestPxSpriteRaster (box 列 = クアッドの画素一致) に任せる。
mod TestPreviewSprite {

    def doc(): PxSpriteDoc.Doc =
        PxSpriteDoc.fromJson(String.unlines(
            "{" ::
            "  \"legend\": { \"a\": \"body\" }," ::
            "  \"sprites\": {" ::
            "    \"guy\": { \"frames\": { \"walk0\": [ \"aa\", \"aa\", \"aa\" ], \"walk1\": [ \"aa\" ] } }," ::
            "    \"berry\": { \"frames\": { \"idle\": [ \"aaa\" ] } }" ::
            "  }" ::
            "}" :: Nil))
            |> Option.getWithDefault(PxSpriteDoc.empty())

    /// 行 = スプライト (名前順)、列 = コマ×テーマ (コマ内でテーマ 0,1 が隣り合う)。
    @Test
    def testSheetCellsOrder(): Unit \ Assert =
        let rows = PreviewSprite.sheetCells(doc(), None, 2)
            |> List.map(row -> row |> List.map(c -> (c#sprite, c#frame, c#theme)));
        Assert.assertEq(expected =
            (("berry", "idle", 0) :: ("berry", "idle", 1) :: Nil) ::
            (("guy", "walk0", 0) :: ("guy", "walk0", 1) ::
             ("guy", "walk1", 0) :: ("guy", "walk1", 1) :: Nil) :: Nil,
            rows)

    /// sprite で絞ると 1 行だけ (クリップ再生の代替 = 静止コマ列)。
    @Test
    def testSheetCellsFilterBySprite(): Unit \ Assert =
        let rows = PreviewSprite.sheetCells(doc(), Some("guy"), 1);
        Assert.assertEq(expected = (1, Some(2)),
            (List.length(rows), List.head(rows) |> Option.map(List.length)))

    /// 格子寸法は (最長行, 行数)。無いコマは (0, 0)。
    @Test
    def testGridSize(): Unit \ Assert =
        Assert.assertEq(expected = ((2, 3), (3, 1), (0, 0)),
            (PreviewSprite.gridSize(doc(), "guy", "walk0"),
             PreviewSprite.gridSize(doc(), "berry", "idle"),
             PreviewSprite.gridSize(doc(), "guy", "nope")))

    /// フォールバック色は決定的 (同じキーは常に同じ色) で、0.25..0.85 に収まる。
    @Test
    def testFallbackColorDeterministicAndBounded(): Unit \ Assert =
        let a = PreviewSprite.fallbackColor("body");
        let b = PreviewSprite.fallbackColor("body");
        let inRange = v -> v >= 0.25f32 and v <= 0.85f32;
        Assert.assertEq(expected = (true, true),
            ((a#r, a#g, a#b) == (b#r, b#g, b#b),
             inRange(a#r) and inRange(a#g) and inRange(a#b)))
}
