/// ItemList ノード（Godot ItemList 準拠）の挙動テスト。
/// 構築・カーソル移動（wrap / disabled スキップ）・focused 切替・キー入力差分検出を検証する。
mod TestItemList {

    /// 等幅 advance=10、ascent=8、descent=2、fontSize=16 のサンプル
    def sampleAtlas(): FontAtlas =
        let metrics: TextLayout.GlyphMetrics = {
            xOff = 0.0, yOff = 0.0, glyphW = 10.0, glyphH = 10.0,
            advance = 10.0, s0 = 0.0, t0 = 0.0, s1 = 1.0, t1 = 1.0
        };
        let glyphs = Map.empty()
            |> Map.insert(65, metrics)
            |> Map.insert(66, metrics)
            |> Map.insert(67, metrics);
        ({
            textureName = "atlas", fontSize = 16.0, textureSize = 256.0,
            ascent = 8.0, descent = 2.0, lineGap = 0.0, glyphs = glyphs
        }: FontAtlas)

    def entry(text: String): ItemEntry = {text = text, disabled = false}
    def disabledEntry(text: String): ItemEntry = {text = text, disabled = true}

    def threeItems(): List[ItemEntry] =
        entry("A") :: entry("B") :: entry("C") :: Nil

    def makeList(items: List[ItemEntry]): ItemList =
        ItemList.make(items, sampleAtlas(), 16.0, {x = 100.0, y = 100.0})

    // ── 初期値 ──

    @Test
    def testInitialSelectedIndex(): Unit \ Assert =
        Assert.assertEq(expected = 0, ItemList.getSelectedIndex(makeList(threeItems())))

    @Test
    def testInitialFocusedFalse(): Unit \ Assert =
        Assert.assertEq(expected = false, ItemList.isFocused(makeList(threeItems())))

    // ── カーソル移動 ──

    /// Down で次の項目へ進む
    @Test
    def testMoveCursorDown(): Unit \ Assert =
        let list = makeList(threeItems()) |> ItemList.moveCursorDown;
        Assert.assertEq(expected = 1, ItemList.getSelectedIndex(list))

    /// Up で前の項目へ戻る
    @Test
    def testMoveCursorUpWraps(): Unit \ Assert =
        // 初期 0 から Up → wrap して末尾 (idx 2) へ
        let list = makeList(threeItems()) |> ItemList.moveCursorUp;
        Assert.assertEq(expected = 2, ItemList.getSelectedIndex(list))

    /// 末尾で Down → wrap して先頭へ
    @Test
    def testMoveCursorDownWrapsAtEnd(): Unit \ Assert =
        let list = makeList(threeItems())
            |> ItemList.setSelectedIndex(2)
            |> ItemList.moveCursorDown;
        Assert.assertEq(expected = 0, ItemList.getSelectedIndex(list))

    /// wrap=false なら端で止まる
    @Test
    def testNoWrapStopsAtEnd(): Unit \ Assert =
        let list = makeList(threeItems())
            |> ItemList.setWrap(false)
            |> ItemList.setSelectedIndex(2)
            |> ItemList.moveCursorDown;
        Assert.assertEq(expected = 2, ItemList.getSelectedIndex(list))

    // ── disabled スキップ ──

    /// 真ん中の項目が disabled なら Down で 0 → 2 を飛ばす
    @Test
    def testMoveCursorDownSkipsDisabled(): Unit \ Assert =
        let items = entry("A") :: disabledEntry("B") :: entry("C") :: Nil;
        let list = makeList(items) |> ItemList.moveCursorDown;
        Assert.assertEq(expected = 2, ItemList.getSelectedIndex(list))

    /// 全項目 disabled なら index は据え置き
    @Test
    def testMoveCursorAllDisabled(): Unit \ Assert =
        let items = disabledEntry("A") :: disabledEntry("B") :: disabledEntry("C") :: Nil;
        let list = makeList(items) |> ItemList.moveCursorDown;
        Assert.assertEq(expected = 0, ItemList.getSelectedIndex(list))

    // ── findNextEnabled の境界 ──

    @Test
    def testFindNextEnabledSkipsDisabled(): Unit \ Assert =
        let items = entry("A") :: disabledEntry("B") :: entry("C") :: Nil;
        Assert.assertEq(expected = 2, ItemList.findNextEnabled(0, 1, true, items))

    @Test
    def testFindNextEnabledEmptyReturnsZero(): Unit \ Assert =
        Assert.assertEq(expected = 0, ItemList.findNextEnabled(0, 1, true, Nil))

    // ── focused 切替 ──

    @Test
    def testSetFocusedRoundtrip(): Unit \ Assert =
        let list = makeList(threeItems()) |> ItemList.setFocused(true);
        Assert.assertEq(expected = true, ItemList.isFocused(list))

    // ── キー入力差分検出 (updateInputState) ──

    /// focused=false なら入力を受けても何も変わらない
    @Test
    def testUpdateInputIgnoredWhenNotFocused(): Unit \ Assert =
        let list = makeList(threeItems())
            |> ItemList.updateInputState(false, true, false, false);
        Assert.assertEq(expected = 0, ItemList.getSelectedIndex(list))

    /// focused=true で Down キー押下瞬間 → idx 0 → 1
    @Test
    def testUpdateInputDownMovesCursor(): Unit \ Assert =
        let list = makeList(threeItems())
            |> ItemList.setFocused(true)
            |> ItemList.updateInputState(false, true, false, false);
        Assert.assertEq(expected = 1, ItemList.getSelectedIndex(list))

    /// 同じキー押しっぱなしでは 2 回目以降は移動しない（前フレーム差分が無くなる）
    @Test
    def testUpdateInputHeldKeyDoesNotRepeat(): Unit \ Assert =
        let list = makeList(threeItems())
            |> ItemList.setFocused(true)
            |> ItemList.updateInputState(false, true, false, false)
            |> ItemList.updateInputState(false, true, false, false);
        Assert.assertEq(expected = 1, ItemList.getSelectedIndex(list))

    /// 確定キー押下瞬間で pendingConfirm が true になる
    @Test
    def testUpdateInputEnterSetsPendingConfirm(): Unit \ Assert =
        let list = makeList(threeItems())
            |> ItemList.setFocused(true)
            |> ItemList.updateInputState(false, false, true, false);
        Assert.assertEq(expected = true, ItemList.isPendingConfirm(list))

    /// キャンセルキー押下瞬間で pendingCancel が true
    @Test
    def testUpdateInputEscapeSetsPendingCancel(): Unit \ Assert =
        let list = makeList(threeItems())
            |> ItemList.setFocused(true)
            |> ItemList.updateInputState(false, false, false, true);
        Assert.assertEq(expected = true, ItemList.isPendingCancel(list))

    /// clearPending で両フラグがリセットされる
    @Test
    def testClearPendingResetsFlags(): Unit \ Assert =
        let list = makeList(threeItems())
            |> ItemList.setFocused(true)
            |> ItemList.updateInputState(false, false, true, true)
            |> ItemList.clearPending;
        Assert.assertEq(expected = false, ItemList.isPendingConfirm(list));
        Assert.assertEq(expected = false, ItemList.isPendingCancel(list))

    // ── 構造 ──

    @Test
    def testSetItemsClampsIndex(): Unit \ Assert =
        // 選択 idx=2 の状態で 1 項目に setItems → idx 0 にクランプ
        let list = makeList(threeItems())
            |> ItemList.setSelectedIndex(2)
            |> ItemList.setItems(entry("X") :: Nil);
        Assert.assertEq(expected = 0, ItemList.getSelectedIndex(list))

    @Test
    def testGetSelectedReturnsEntry(): Unit \ Assert =
        let list = makeList(threeItems()) |> ItemList.setSelectedIndex(1);
        match ItemList.getSelected(list) {
            case Some(entry) => Assert.assertEq(expected = "B", entry#text)
            case None        => Assert.assertTrue(false)
        }
}
