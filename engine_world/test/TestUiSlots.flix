// TestUiSlots — 固定スロットへの流し込み（余りの畳み方・meta の付け外し・あふれ検知）と、
// UiMenu の applyItemLabels / scrollOffset を具体値で固定する。
// UiWorld は（既知のコンパイラ制約を避けるため）レコード直構築せず、必ず parse→spawnRoot で作る。
mod TestUiSlots {

    /// slot0..slot2 の 3 スロット（各スロットは label と mark の text 子を持つ行コンテナ）。
    /// meta は宣言せず、fill が付け外しする前提。
    def menuJson(): String =
        "{\"root\": {\"name\":\"Menu\",\"widget\":\"none\",\"children\":["
        + slotJson("slot0") + "," + slotJson("slot1") + "," + slotJson("slot2") + "]}}"

    def slotJson(name: String): String =
        "{\"name\":\"${name}\",\"widget\":\"none\",\"children\":["
        + "{\"name\":\"label\",\"widget\":\"text\",\"text\":\"\",\"fontSize\":8.0},"
        + "{\"name\":\"mark\",\"widget\":\"text\",\"text\":\"\",\"fontSize\":8.0}]}"

    /// JSON テキストを parse して空 UiWorld へ spawnRoot した結果（失敗時 None）。
    def spawnFrom(jsonText: String): Option[UiStore.UiWorld] =
        DocJson.parse(jsonText)
            |> Option.flatMap(json -> UiSpec.parse(json) |> Result.toOption)
            |> Option.map(spec -> let (_, ui) = UiSpec.spawnRoot(spec, UiStore.empty()); ui)

    /// テストで使うスロット規約（Menu 直下の slot0..slot2）。
    def spec(): UiSlots.SlotSpec =
        { slotPath = i -> "Menu/slot${i}", maxSlots = 3 }

    def entry(text: String, meta: String): UiSlots.Entry =
        { text = text, meta = Some(meta) }

    // ── fill: 流し込みと余りの畳み方 ──

    @Test
    def testFillWritesLabelMetaAndVisibility(): Unit \ Assert =
        // 2 項目を 3 スロットへ: slot0/1 は label + meta + 可視、余った slot2 は meta なし + 不可視。
        let got = spawnFrom(menuJson()) |> Option.map(ui -> {
            let ui1 = UiSlots.fill(spec(), entry("あお", "npc:0") :: entry("みどり", "npc:1") :: Nil, ui);
            (UiStore.textOf("Menu/slot0/label", ui1),
             UiStore.textOf("Menu/slot1/label", ui1),
             UiMenu.metas("Menu", ui1),
             UiStore.visibleOf("Menu/slot1", ui1),
             UiStore.visibleOf("Menu/slot2", ui1))
        });
        Assert.assertEq(
            expected = Some((Some("あお"), Some("みどり"), "npc:0" :: "npc:1" :: Nil, Some(true), Some(false))),
            got)

    @Test
    def testFillShrinksWhenItemsDecrease(): Unit \ Assert =
        // 2 項目 → 1 項目に減らして fill し直すと、slot1 が選択列から外れて不可視に戻る。
        let got = spawnFrom(menuJson()) |> Option.map(ui -> {
            let ui1 = UiSlots.fill(spec(), entry("あお", "npc:0") :: entry("みどり", "npc:1") :: Nil, ui);
            let ui2 = UiSlots.fill(spec(), entry("あか", "npc:2") :: Nil, ui1);
            (UiStore.textOf("Menu/slot0/label", ui2), UiMenu.metas("Menu", ui2),
             UiStore.visibleOf("Menu/slot1", ui2))
        });
        Assert.assertEq(expected = Some((Some("あか"), "npc:2" :: Nil, Some(false))), got)

    @Test
    def testFillMetaNoneIsVisibleButNotSelectable(): Unit \ Assert =
        // meta = None の項目（見出しなど）は見えるが UiMenu の項目列には載らない。
        let got = spawnFrom(menuJson()) |> Option.map(ui -> {
            let heading = ({ text = "なかまたち", meta = None }: UiSlots.Entry);
            let ui1 = UiSlots.fill(spec(), heading :: entry("あお", "npc:0") :: Nil, ui);
            (UiStore.visibleOf("Menu/slot0", ui1), UiMenu.metas("Menu", ui1))
        });
        Assert.assertEq(expected = Some((Some(true), "npc:0" :: Nil)), got)

    @Test
    def testOverflowsDetectsTooManyItems(): Unit \ Assert =
        // 3 スロットに 4 項目はあふれ、3 項目までは収まる。
        let four = entry("あ", "0") :: entry("い", "1") :: entry("う", "2") :: entry("え", "3") :: Nil;
        Assert.assertEq(expected = (true, false),
            (UiSlots.overflows(spec(), four), UiSlots.overflows(spec(), List.take(3, four))))

    // ── UiMenu.applyItemLabels: 行の子ノードへの文字差し ──

    @Test
    def testApplyItemLabelsWritesMarkColumn(): Unit \ Assert =
        // 項目列（meta 持ちスロット）の mark 子へ index に応じた文字を流し込む。
        let got = spawnFrom(menuJson()) |> Option.map(ui -> {
            let ui1 = UiSlots.fill(spec(), entry("あお", "npc:0") :: entry("みどり", "npc:1") :: Nil, ui);
            let ui2 = UiMenu.applyItemLabels("Menu", "mark", idx -> if (idx == 0) "○" else "・", ui1);
            (UiStore.textOf("Menu/slot0/mark", ui2), UiStore.textOf("Menu/slot1/mark", ui2))
        });
        Assert.assertEq(expected = Some((Some("○"), Some("・"))), got)

    // ── UiMenu.scrollOffset: スクロール範囲のクランプ ──

    @Test
    def testScrollOffsetPinsClampBehavior(): Unit \ Assert =
        // 7 項目を 3 行のビューポートで見るとき: 収まるなら 0 / 中央寄せ / 先頭 0 停止 / 末尾 4 停止。
        Assert.assertEq(expected = (0, 0, 2, 4),
            (UiMenu.scrollOffset(sel = 2, count = 3, slots = 3),
             UiMenu.scrollOffset(sel = 0, count = 7, slots = 3),
             UiMenu.scrollOffset(sel = 3, count = 7, slots = 3),
             UiMenu.scrollOffset(sel = 6, count = 7, slots = 3)))
}
