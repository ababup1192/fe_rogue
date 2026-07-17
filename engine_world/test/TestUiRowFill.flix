// TestUiRowFill — 項目列を行スロットへ流し込む窓（offset）付けと、余った行の畳み方を固定する。
mod TestUiRowFill {

    /// row0..row2 の 3 行スロット（各行は label text 子を持つ）。
    def rowsJson(): String =
        "{\"root\": {\"name\":\"Rows\",\"widget\":\"none\",\"children\":["
        + rowJson("row0") + "," + rowJson("row1") + "," + rowJson("row2") + "]}}"

    def rowJson(name: String): String =
        "{\"name\":\"${name}\",\"widget\":\"none\",\"children\":["
        + "{\"name\":\"label\",\"widget\":\"text\",\"text\":\"\",\"fontSize\":8.0}]}"

    def spawnFrom(jsonText: String): Option[UiStore.UiWorld] =
        JsonCompat.parse(jsonText)
            |> Option.flatMap(json -> UiSpec.parse(json) |> Result.toOption)
            |> Option.map(spec -> let (_, ui) = UiSpec.spawnRoot(spec, UiStore.empty()); ui)

    def spec(offset: Int32): UiRowFill.Spec =
        { rowPath = i -> "Rows/row${i}", maxSlots = 3, offset = offset }

    /// テスト用の項目型（text と meta だけの最小形）。
    type alias Entry = { text = String, meta = String }

    def entry(text: String, meta: String): Entry = { text = text, meta = meta }

    def applyLabel(i: Int32, e: Entry, ui: UiStore.UiWorld): UiStore.UiWorld =
        UiStore.setText("Rows/row${i}/label", e#text, ui)

    // ── fill: 項目のある行は可視+meta、窓外は不可視+meta なし ──

    @Test
    def testFillWritesLabelAndMetaWithinWindow(): Unit \ Assert =
        // offset=0 で 2 項目を 3 行窓へ: row0/1 は label+meta+可視、余った row2 は不可視。
        let got = spawnFrom(rowsJson()) |> Option.map(ui -> {
            let items = entry("あか", "0") :: entry("あお", "1") :: Nil;
            let ui1 = UiRowFill.fill(spec(0), items, e -> Some(e#meta), applyLabel, ui);
            (UiStore.textOf("Rows/row0/label", ui1), UiMenu.metas("Rows", ui1),
             UiStore.visibleOf("Rows/row2", ui1))
        });
        Assert.assertEq(expected = Some((Some("あか"), "0" :: "1" :: Nil, Some(false))), got)

    @Test
    def testFillWithOffsetSkipsLeadingItems(): Unit \ Assert =
        // offset=1 で先頭項目を飛ばし、2 番目以降を row0 から詰める（スクロール窓の挙動）。
        let got = spawnFrom(rowsJson()) |> Option.map(ui -> {
            let items = entry("あか", "0") :: entry("あお", "1") :: entry("みどり", "2") :: Nil;
            let ui1 = UiRowFill.fill(spec(1), items, e -> Some(e#meta), applyLabel, ui);
            UiStore.textOf("Rows/row0/label", ui1)
        });
        Assert.assertEq(expected = Some(Some("あお")), got)

    @Test
    def testHideAllClearsVisibilityAndMeta(): Unit \ Assert =
        // 流し込み後に hideAll すると全行が不可視になり、項目列（meta 持ち）も空になる。
        let got = spawnFrom(rowsJson()) |> Option.map(ui -> {
            let items = entry("あか", "0") :: Nil;
            let ui1 = UiRowFill.fill(spec(0), items, e -> Some(e#meta), applyLabel, ui);
            let ui2 = UiRowFill.hideAll(spec(0), ui1);
            (UiStore.visibleOf("Rows/row0", ui2), UiMenu.metas("Rows", ui2))
        });
        Assert.assertEq(expected = Some((Some(false), Nil)), got)
}
