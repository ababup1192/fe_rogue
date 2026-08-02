// TestUiMenu — メニューカーソルの移動（端の回り込み）とマウス同期（項目列基準の吸着）を固定する。
mod TestUiMenu {

    // ── moveCursor: 端の回り込みと count 0 ──

    @Test
    def testMoveCursorWrapsAtEdges(): Unit \ Assert =
        Assert.assertEq(
            expected = (1, 0, 2),
            (UiMenu.moveCursor(1, 3, 0),    // 前進
             UiMenu.moveCursor(1, 3, 2),    // 末尾から先頭へ
             UiMenu.moveCursor(-1, 3, 0)))  // 先頭から末尾へ

    @Test
    def testMoveCursorKeepsCursorWhenEmpty(): Unit \ Assert =
        // 項目が無いときは動かさない（カーソルはそのまま）。
        Assert.assertEq(expected = (5, 0), (UiMenu.moveCursor(1, 0, 5), UiMenu.moveCursor(-1, -2, 0)))

    // ── syncCursor: listPath の項目列（meta を持つ子）を基準に吸着する ──

    /// メニュー 1 枚（slot0/1/2 が項目、head は meta 無しなので項目に数えない）。
    def menuUi(): Option[UiStore.UiWorld] =
        let doc = "{\"root\": {\"name\":\"menu\",\"widget\":\"box\",\"color\":\"#000000\",\"width\":100,\"height\":100,\"dir\":\"column\","
                + "\"children\":["
                + "{\"name\":\"slot0\",\"widget\":\"box\",\"color\":\"#000000\",\"width\":10,\"height\":10,\"meta\":\"m/0\"},"
                + "{\"name\":\"slot1\",\"widget\":\"box\",\"color\":\"#000000\",\"width\":10,\"height\":10,\"meta\":\"m/1\"},"
                + "{\"name\":\"head\",\"widget\":\"box\",\"color\":\"#000000\",\"width\":10,\"height\":10},"
                + "{\"name\":\"slot2\",\"widget\":\"box\",\"color\":\"#000000\",\"width\":10,\"height\":10,\"meta\":\"m/2\"}]}}";
        DocJson.parse(doc)
            |> Option.flatMap(json -> UiSpec.parse(json) |> Result.toOption)
            |> Option.map(spec -> { let (_, ui) = UiSpec.spawnRoot(spec, UiStore.empty()); ui })

    @Test
    def testHitIndexInFindsItemOrder(): Unit \ Assert =
        // slot2 は（head を飛ばして）項目列の 2 番目。head 自体は項目でないので None。
        let got = menuUi() |> Option.map(ui ->
            (UiMenu.hitIndexIn("menu", UiStore.idOf("menu/slot2", ui), ui),
             UiMenu.hitIndexIn("menu", UiStore.idOf("menu/head", ui), ui),
             UiMenu.hitIndexIn("menu", None, ui)));
        Assert.assertEq(expected = Some((Some(2), None, None)), got)

    @Test
    def testCursorPathPointsAtItem(): Unit \ Assert =
        // カーソル 1 は slot1 のパス、範囲外は None。
        let got = menuUi() |> Option.map(ui ->
            (UiMenu.cursorPath("menu", 1, ui), UiMenu.cursorPath("menu", 5, ui)));
        Assert.assertEq(expected = Some((Some("menu/slot1"), None)), got)

    @Test
    def testSyncCursorSnapsWhenMouseMovedOntoItem(): Unit \ Assert =
        let got = menuUi() |> Option.map(ui -> {
            let r = UiMenu.syncCursor("menu",
                { mouseMoved = true, hit = UiStore.idOf("menu/slot2", ui) }, 0, ui);
            (r#cursor, r#hoverPath)
        });
        Assert.assertEq(expected = Some((2, Some("menu/slot2"))), got)

    @Test
    def testSyncCursorIgnoresHitWhenMouseStill(): Unit \ Assert =
        // マウスが静止しているフレームは hit を無視する（キーボード操作を上書きしない）。
        let got = menuUi() |> Option.map(ui -> {
            let r = UiMenu.syncCursor("menu",
                { mouseMoved = false, hit = UiStore.idOf("menu/slot2", ui) }, 1, ui);
            (r#cursor, r#hoverPath)
        });
        Assert.assertEq(expected = Some((1, Some("menu/slot1"))), got)

    @Test
    def testSyncCursorNonItemHitKeepsCursor(): Unit \ Assert =
        // 動いていても項目でない場所（head）に乗ったならカーソルはそのまま。
        let got = menuUi() |> Option.map(ui -> {
            let r = UiMenu.syncCursor("menu",
                { mouseMoved = true, hit = UiStore.idOf("menu/head", ui) }, 1, ui);
            (r#cursor, r#hoverPath)
        });
        Assert.assertEq(expected = Some((1, Some("menu/slot1"))), got)
}
