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

    def entry(text: String): ItemEntry = {text = text, disabled = false, metadata = None}
    def disabledEntry(text: String): ItemEntry = {text = text, disabled = true, metadata = None}

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

    /// focused=true で Down キー押下瞬間 → idx 0 → 1。
    /// setFocused(true) 直後は prev*Down が全 true なので、まず 1 フレーム「全離す」を入れる。
    @Test
    def testUpdateInputDownMovesCursor(): Unit \ Assert =
        let list = makeList(threeItems())
            |> ItemList.setFocused(true)
            |> ItemList.updateInputState(false, false, false, false)
            |> ItemList.updateInputState(false, true, false, false);
        Assert.assertEq(expected = 1, ItemList.getSelectedIndex(list))

    /// 同じキー押しっぱなしでは 2 回目以降は移動しない（前フレーム差分が無くなる）
    @Test
    def testUpdateInputHeldKeyDoesNotRepeat(): Unit \ Assert =
        let list = makeList(threeItems())
            |> ItemList.setFocused(true)
            |> ItemList.updateInputState(false, false, false, false)
            |> ItemList.updateInputState(false, true, false, false)
            |> ItemList.updateInputState(false, true, false, false);
        Assert.assertEq(expected = 1, ItemList.getSelectedIndex(list))

    /// 確定キー押下瞬間で pendingConfirm が true になる
    @Test
    def testUpdateInputEnterSetsPendingConfirm(): Unit \ Assert =
        let list = makeList(threeItems())
            |> ItemList.setFocused(true)
            |> ItemList.updateInputState(false, false, false, false)
            |> ItemList.updateInputState(false, false, true, false);
        Assert.assertEq(expected = true, ItemList.isPendingConfirm(list))

    /// キャンセルキー押下瞬間で pendingCancel が true
    @Test
    def testUpdateInputEscapeSetsPendingCancel(): Unit \ Assert =
        let list = makeList(threeItems())
            |> ItemList.setFocused(true)
            |> ItemList.updateInputState(false, false, false, false)
            |> ItemList.updateInputState(false, false, false, true);
        Assert.assertEq(expected = true, ItemList.isPendingCancel(list))

    /// clearPending で両フラグがリセットされる
    @Test
    def testClearPendingResetsFlags(): Unit \ Assert =
        let list = makeList(threeItems())
            |> ItemList.setFocused(true)
            |> ItemList.updateInputState(false, false, false, false)
            |> ItemList.updateInputState(false, false, true, true)
            |> ItemList.clearPending;
        Assert.assertEq(expected = false, ItemList.isPendingConfirm(list));
        Assert.assertEq(expected = false, ItemList.isPendingCancel(list))

    /// setFocused(false→true) 直後は前フレームを「全押下中」と仮定するため、
    /// 連鎖した押下を消費して何も起きない（フェーズ遷移時の入力連鎖を防ぐ）
    @Test
    def testSetFocusedConsumesPriorInput(): Unit \ Assert =
        let list = makeList(threeItems())
            |> ItemList.setFocused(true)
            |> ItemList.updateInputState(false, false, true, false);  // Enter まだ押されたまま
        Assert.assertEq(expected = false, ItemList.isPendingConfirm(list))

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

    // ── アイコン ──

    /// 初期状態は iconSize=0、itemIcons は空
    @Test
    def testDefaultsHaveNoIcons(): Unit \ Assert =
        let list = makeList(threeItems());
        Assert.assertEq(expected = 0.0, ItemList.getIconSize(list));
        Assert.assertEq(expected = 0, Map.size(ItemList.getItemIcons(list)))

    /// setIconSize の roundtrip。負値は 0 にクランプ。
    @Test
    def testSetIconSizeRoundtrip(): Unit \ Assert =
        let list = makeList(threeItems())
            |> ItemList.setIconSize(8.0);
        Assert.assertEq(expected = 8.0, ItemList.getIconSize(list))

    @Test
    def testSetIconSizeClampsNegative(): Unit \ Assert =
        let list = makeList(threeItems())
            |> ItemList.setIconSize(-5.0);
        Assert.assertEq(expected = 0.0, ItemList.getIconSize(list))

    /// setIconAt で 1 行ごとにアイコンを登録できる
    @Test
    def testSetIconAtRegistersEntry(): Unit \ Assert =
        let icon: ItemIcon = {texture = "weapons", hframes = 4, vframes = 4, frame = 7};
        let list = makeList(threeItems())
            |> ItemList.setIconAt(1, icon);
        let icons = ItemList.getItemIcons(list);
        Assert.assertEq(expected = 1, Map.size(icons));
        match Map.get(1, icons) {
            case Some(got) => Assert.assertEq(expected = 7, got#frame)
            case None      => Assert.assertTrue(false)
        }

    /// setItemIcons でマップ全体差し替え
    @Test
    def testSetItemIconsReplacesMap(): Unit \ Assert =
        let icon0: ItemIcon = {texture = "w", hframes = 1, vframes = 1, frame = 0};
        let icon2: ItemIcon = {texture = "w", hframes = 1, vframes = 1, frame = 2};
        let icons = Map.empty()
            |> Map.insert(0, icon0)
            |> Map.insert(2, icon2);
        let list = makeList(threeItems())
            |> ItemList.setItemIcons(icons);
        Assert.assertEq(expected = 2, Map.size(ItemList.getItemIcons(list)))

    /// iconTextGap roundtrip
    @Test
    def testSetIconTextGapRoundtrip(): Unit \ Assert =
        let list = makeList(threeItems())
            |> ItemList.setIconTextGap(3.5);
        Assert.assertEq(expected = 3.5, ItemList.getIconTextGap(list))

    // ── サブラベル / 選択ハイライト描画（toDrawables、Game effect は stub）──

    def blue(): Color = {r = 0.18f32, g = 0.43f32, b = 0.94f32}

    /// toDrawables を最小 GameEngine.Game stub 下で実行して Drawable 列を得る。
    /// アイコン無しなので getTextureInfo は呼ばれない（全 op は形式的に埋める）。
    def renderList(list: ItemList): List[GameEngine.Drawable] =
        run {
            ItemList.toDrawables(list, Vec2.zero())
        } with handler GameEngine.Game {
            def renderCommands(_, _, _, k) = k(())
            def initTileBuffer(_, k) = k((0i32, 0i32))
            def shouldClose(k) = k(false)
            def getDeltaTime(k) = k(16 |> Duration.millis)
            def isKeyPressed(_, k) = k(false)
            def getMousePosition(k) = k(Vec2.zero())
            def isMouseButtonPressed(_, k) = k(false)
            def consumeScrollDelta(k) = k(0.0)
            def getFontAtlas(_, _) = bug!("font not used")
            def getViewportRect(k) = k({position = Vec2.zero(), size = {x = 480.0, y = 720.0}})
            def getTextureInfo(_, k) = k(None)
            def setCursor(_, k) = k(())
        }

    def styledCount(drawables: List[GameEngine.Drawable]): Int32 =
        List.count(d -> Option.nonEmpty(d#style), drawables)

    /// fillColor=Some のハイライト設定（cornerRadius 指定）。
    def highlight(radius: Float64): SelectedHighlight =
        {fillColor = Some(blue()), fillAlpha = 0.5f32,
         borderColor = blue(), borderAlpha = 1.0f32, borderWidth = 1.0,
         cornerRadius = radius, inset = 0.0}

    /// styled Drawable（選択ハイライト）の cornerRadius を取り出す（無ければ -1）。
    def styledRadius(drawables: List[GameEngine.Drawable]): Float64 =
        match List.filter(d -> Option.nonEmpty(d#style), drawables) {
            case d :: _ => Option.getWithDefault(-1.0, Option.map(s -> s#cornerRadius, d#style))
            case Nil    => -1.0
        }

    /// focused かつ fillColor=Some なら選択行に style=Some の Drawable が1枚出る。
    @Test
    def testSelectedHighlightEmitsStyledDrawable(): Unit \ Assert =
        let list = makeList(threeItems())
            |> ItemList.setFocused(true)
            |> ItemList.setSelectedHighlight(highlight(4.0));
        Assert.assertEq(expected = 1, styledCount(renderList(list)))

    /// ハイライト Drawable の cornerRadius が設定値と一致する。
    @Test
    def testSelectedHighlightCornerRadius(): Unit \ Assert =
        let list = makeList(threeItems())
            |> ItemList.setFocused(true)
            |> ItemList.setSelectedHighlight(highlight(4.0));
        Assert.assertEq(expected = 4.0, styledRadius(renderList(list)))

    /// fillColor=None（既定）ならハイライト無し＝style付き Drawable は 0（後方互換）。
    @Test
    def testNoHighlightWhenFillNone(): Unit \ Assert =
        let list = makeList(threeItems()) |> ItemList.setFocused(true);
        Assert.assertEq(expected = 0, styledCount(renderList(list)))

    /// focused=false なら fillColor=Some でもハイライトを出さない。
    @Test
    def testNoHighlightWhenNotFocused(): Unit \ Assert =
        let list = makeList(threeItems()) |> ItemList.setSelectedHighlight(highlight(4.0));
        Assert.assertEq(expected = 0, styledCount(renderList(list)))

    /// itemSubtexts 登録行のぶんだけ Drawable が増える（"AB"=2 グリフ）。未登録時との差で検証。
    @Test
    def testSubtextEmitsExtraDrawables(): Unit \ Assert =
        let base = makeList(threeItems());
        let withSub = base |> ItemList.setItemSubtexts(Map.empty() |> Map.insert(0, "AB"));
        let diff = List.length(renderList(withSub)) - List.length(renderList(base));
        Assert.assertEq(expected = 2, diff)
}
