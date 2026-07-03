/// ItemMenuUi（アイテム選択ウィンドウ・World-entity UI 版）の純粋部分を pin する。
///
/// 検証する観点:
///   - staffSubline / consumableSubline: 各行の 2 行目（効果 + 残り + 重さ）
///   - actionItemsFor: 選択中アイテム種別 → サブメニュー項目の出し分け（bulk / holdOnly 含む）
///   - parseItemKind: metadata "w:/s:/c:/r:<idx>" の往復
///   - nextCategoryIn: 在庫のあるカテゴリだけを左右で循環（空はスキップ）
///   - windowOffset: 3 行窓のスクロール offset（選択が窓に入るようクランプ）
///   - 実 asset の row 宣言数 ⇔ maxSlots() の一致
///   - 幾何: 武器/アイテムアイコンのチップが選択ハイライト箱に収まる（左はみ出しの回帰防止）
///
/// 可視同期（frameStep）・窓流し込みは UiWorldState を要する結線なので、ここでは行データ・
/// サブメニュー・スクロール計算などの純粋部分を直接観測する。
mod TestItemMenuUi {

    // ════════════════════════════════════════════════════════
    // フィクスチャ
    // ════════════════════════════════════════════════════════

    /// テスト用の杖 fixture（Heal・残 3・重 0.8）。
    def testStaff(): Staff.StaffResource = {
        name       = "テスト杖",
        effect     = Staff.StaffEffect.Heal,
        durability = 3,
        weight     = 0.75,
        sprite     = ({texture = "t", hframes = 1, vframes = 1, frame = 0,
                        offset = {x = 0.0, y = 0.0},
                        scale = {x = 1.0, y = 1.0}, flipForFacing = false}: Sprite.SpriteResource),
        description = "",
        effectRule = None
    }

    // ════════════════════════════════════════════════════════
    // カテゴリ別サブライン（各行の 2 行目・純粋）
    // ════════════════════════════════════════════════════════

    /// 杖のサブライン。効果（回復）+ 残り使用回数 + 重さ。テスト杖は Heal・残 3・重 0.8。
    @Test
    def testStaffSubline(): Unit \ Assert =
        Assert.assertEq(
            expected = "回復 ・残 3 ・重 0.8",
            ItemMenuUi.staffSubline(testStaff()))

    /// 消費アイテムのサブライン。効果要約 + 残り使用回数 + 重さ。
    @Test
    def testConsumableSubline(): Unit \ Assert =
        let potion = ({name = "きずぐすり",
                        effect = Consumable.ConsumableEffect.Heal, magnitude = 10, duration = 0,
                        healAmount = 10, durability = 3, weight = 0.5,
                        sprite = testStaff()#sprite, description = "", effectRule = None}:
                        Consumable.ConsumableResource);
        Assert.assertEq(
            expected = "HP+10 ・残 3 ・重 0.5",
            ItemMenuUi.consumableSubline(potion))

    // ════════════════════════════════════════════════════════
    // actionItemsFor: 選択中アイテム種別 → サブメニュー項目（純粋）
    // ════════════════════════════════════════════════════════

    /// 武器選択中 → 「装備 / 投げる / 捨てる」
    @Test
    def testActionItemsForWeapon(): Unit \ Assert =
        let items = ItemMenuUi.actionItemsFor(Some(PlayerData.ItemKind.Weapon(0)), false, false, false);
        Assert.assertEq(
            expected = "装備" :: "投げる" :: "捨てる" :: Nil,
            List.map(e -> e#text, items))

    /// 杖選択中 → 「使う / 投げる / 捨てる」
    @Test
    def testActionItemsForStaff(): Unit \ Assert =
        let items = ItemMenuUi.actionItemsFor(Some(PlayerData.ItemKind.Staff(1)), false, false, false);
        Assert.assertEq(
            expected = "使う" :: "投げる" :: "捨てる" :: Nil,
            List.map(e -> e#text, items))

    /// 消費アイテム選択中 → 「使う / 投げる / 捨てる」（杖と同じ）
    @Test
    def testActionItemsForConsumable(): Unit \ Assert =
        let items = ItemMenuUi.actionItemsFor(Some(PlayerData.ItemKind.Consumable(2)), false, false, false);
        Assert.assertEq(
            expected = "使う" :: "投げる" :: "捨てる" :: Nil,
            List.map(e -> e#text, items))

    /// 未装備の指輪を選択中 → 「装備 / 投げる / 捨てる」
    @Test
    def testActionItemsForRingUnequipped(): Unit \ Assert =
        let items = ItemMenuUi.actionItemsFor(Some(PlayerData.ItemKind.Ring(0)), false, false, false);
        Assert.assertEq(
            expected = "装備" :: "投げる" :: "捨てる" :: Nil,
            List.map(e -> e#text, items))

    /// 装備中の指輪（先頭 + ringEquipped=true）を選択中 → 「外す」に変わる
    @Test
    def testActionItemsForRingEquipped(): Unit \ Assert =
        let items = ItemMenuUi.actionItemsFor(Some(PlayerData.ItemKind.Ring(0)), true, false, false);
        Assert.assertEq(
            expected = "外す" :: "投げる" :: "捨てる" :: Nil,
            List.map(e -> e#text, items))

    /// ringEquipped=true でも先頭以外の指輪（idx=1）は装備中ではない → 「装備」のまま
    @Test
    def testActionItemsForRingNonHeadStillEquip(): Unit \ Assert =
        let items = ItemMenuUi.actionItemsFor(Some(PlayerData.ItemKind.Ring(1)), true, false, false);
        Assert.assertEq(
            expected = "装備" :: "投げる" :: "捨てる" :: Nil,
            List.map(e -> e#text, items))

    /// 未選択 → 空（サブメニューを出さない）
    @Test
    def testActionItemsForNone(): Unit \ Assert =
        Assert.assertEq(expected = 0, List.length(ItemMenuUi.actionItemsFor(None, false, false, false)))

    /// 複数選択（bulkMode=true）中は「捨てる」だけ有効、他は disabled。
    @Test
    def testActionItemsForBulkOnlyDropEnabled(): Unit \ Assert =
        let items = ItemMenuUi.actionItemsFor(Some(PlayerData.ItemKind.Weapon(0)), false, true, false);
        Assert.assertEq(
            expected = ("装備", true) :: ("投げる", true) :: ("捨てる", false) :: Nil,
            List.map(e -> (e#text, e#disabled), items))

    /// 「持つだけ」系（浮雲 = holdOnly）の指輪は装備も投げるも出ず「捨てる」だけ。
    @Test
    def testActionItemsForHoldOnly(): Unit \ Assert =
        let items = ItemMenuUi.actionItemsFor(Some(PlayerData.ItemKind.Ring(0)), false, false, true);
        Assert.assertEq(expected = "捨てる" :: Nil, List.map(e -> e#text, items))

    // ════════════════════════════════════════════════════════
    // parseItemKind: metadata 文字列 → ItemKind（純粋）
    // ════════════════════════════════════════════════════════

    @Test
    def testParseItemKindWeapon(): Unit \ Assert =
        Assert.assertEq(expected = Some(PlayerData.ItemKind.Weapon(1)), ItemMenuUi.parseItemKind("w:1"))

    @Test
    def testParseItemKindStaff(): Unit \ Assert =
        Assert.assertEq(expected = Some(PlayerData.ItemKind.Staff(0)), ItemMenuUi.parseItemKind("s:0"))

    @Test
    def testParseItemKindConsumable(): Unit \ Assert =
        Assert.assertEq(expected = Some(PlayerData.ItemKind.Consumable(2)), ItemMenuUi.parseItemKind("c:2"))

    @Test
    def testParseItemKindRing(): Unit \ Assert =
        Assert.assertEq(expected = Some(PlayerData.ItemKind.Ring(3)), ItemMenuUi.parseItemKind("r:3"))

    /// 不明な prefix は None
    @Test
    def testParseItemKindUnknown(): Unit \ Assert =
        Assert.assertEq(expected = None, ItemMenuUi.parseItemKind("x:9"))

    // ════════════════════════════════════════════════════════
    // nextCategoryIn: 在庫のあるカテゴリだけを循環（純粋）
    // ════════════════════════════════════════════════════════

    /// 在庫のあるカテゴリ [武器(0), 杖(2), 指輪(3)] を循環する。
    ///   武器→次=杖、指輪→次=武器（ループ）、武器→前=指輪（ループ）。空カテゴリ(消費=1)はスキップ。
    @Test
    def testNextCategoryInCyclesNonEmpty(): Unit \ Assert =
        let cats = 0 :: 2 :: 3 :: Nil;
        Assert.assertEq(
            expected = (2, 0, 3),
            (ItemMenuUi.nextCategoryIn(cats, 0, 1),
             ItemMenuUi.nextCategoryIn(cats, 3, 1),
             ItemMenuUi.nextCategoryIn(cats, 0, -1)))

    /// 在庫が 1 カテゴリだけなら左右で動かない（その 1 つのまま）。
    @Test
    def testNextCategoryInSingleStays(): Unit \ Assert =
        Assert.assertEq(
            expected = (1, 1),
            (ItemMenuUi.nextCategoryIn(1 :: Nil, 1, 1),
             ItemMenuUi.nextCategoryIn(1 :: Nil, 1, -1)))

    // ════════════════════════════════════════════════════════
    // windowOffset: 3 行窓のスクロール offset（選択が窓に入るようクランプ）
    //   maxSlots()=3。centerOff=(3-1)/2=1 なので選択を上から 1 行目に保つ。
    //     count<=3      : 0 固定（スクロール不要）
    //     count=5, sel  : 0→0, 1→0, 2→1, 3→2, 4→2（末尾で下停止）
    // ════════════════════════════════════════════════════════

    /// count が窓（3）以下ならスクロールせず offset=0（末尾 sel でも 0）。
    @Test
    def testWindowOffsetNoScrollWhenFits(): Unit \ Assert =
        Assert.assertEq(
            expected = (0, 0),
            (ItemMenuUi.windowOffset(0, 3, 3), ItemMenuUi.windowOffset(2, 3, 3)))

    /// count=5 での offset 列。選択を上から 1 行目に保ちつつ末尾で下停止する。
    @Test
    def testWindowOffsetScrolls(): Unit \ Assert =
        let offs = List.map(sel -> ItemMenuUi.windowOffset(sel, 5, 3), 0 :: 1 :: 2 :: 3 :: 4 :: Nil);
        Assert.assertEq(expected = 0 :: 0 :: 1 :: 2 :: 2 :: Nil, offs)

    // ════════════════════════════════════════════════════════
    // 複数選択（マーク）の純粋ヘルパー（PlayerData 側だが ItemMenu の Shift 操作を支える）
    // ════════════════════════════════════════════════════════

    /// toggleMark: 印が無いアイテムに付け、付いているアイテムからは外す。
    @Test
    def testToggleMarkAddsThenRemoves(): Unit \ Assert =
        let w0 = PlayerData.ItemKind.Weapon(0);
        let added   = PlayerData.toggleMark(w0, Set#{});    // 無 → 付く
        let removed = PlayerData.toggleMark(w0, added);     // 有 → 外れる
        Assert.assertEq(
            expected = (true, false),
            (Set.memberOf(w0, added), Set.memberOf(w0, removed)))

    /// marksDescendingPerList: 各リスト内で index の大きい順に並べる（武器は 2→0、杖は 1）。
    @Test
    def testMarksDescendingPerList(): Unit \ Assert =
        let marks = Set#{PlayerData.ItemKind.Weapon(0), PlayerData.ItemKind.Weapon(2),
                         PlayerData.ItemKind.Staff(1)};
        Assert.assertEq(
            expected = PlayerData.ItemKind.Weapon(2) :: PlayerData.ItemKind.Weapon(0)
                        :: PlayerData.ItemKind.Staff(1) :: Nil,
            PlayerData.marksDescendingPerList(marks))

    // ════════════════════════════════════════════════════════
    // 実 asset の行宣言数 ⇔ maxSlots() の一致（窓の行数を pin）
    //   ui.json は row0..row{maxSlots-1} を宣言し、row{maxSlots} は宣言しない。
    // ════════════════════════════════════════════════════════

    /// 実 asset（ItemMenu.ui.json）を parse し、menu 直下の "row" 名の子の数を数える。
    def itemMenuRowCount(): Int32 \ Fs.FileRead =
        match UiSpec.load(ItemMenuUi.specPath()) {
            case Ok(root) => UiSpec.countPrefixedChildren("panel" :: "menu" :: Nil, "row", root)
            case Err(_)   => bug!("ItemMenu.ui.json load failed")
        }

    /// 実 asset の row 宣言数が `ItemMenuUi.maxSlots()` と一致する（窓の行数の宣言過不足を弾く）。
    @Test
    def testRowDeclarationCountMatchesMaxSlots(): Unit \ {Assert, Fs.FileRead} =
        Assert.assertEq(expected = ItemMenuUi.maxSlots(), itemMenuRowCount())

    // ════════════════════════════════════════════════════════
    // 幾何: アイテムアイコンのチップが選択ハイライト箱に収まる（左はみ出しの回帰防止）
    //   実 asset を parse→spawn し、row0 を可視にして computeLayout を掛け、iconBg（チップ）と
    //   highlight（青枠）の実 rect を突き合わせる。行テンプレの左 pad 1.5 でチップをハイライト内へ収める。
    //   UiWorld は spawnRoot（ライブラリ側）が組む（@Test 内の UiWorld リテラル構築は避ける）。
    // ════════════════════════════════════════════════════════

    /// design 空間の rootRect（170×128）。panel は abs で内側に置かれる。
    def designRect(): Rect2.Rect2 =
        {position = {x = 0.0, y = 0.0}, size = {x = 170.0, y = 128.0}}

    /// 実 asset を spawn し、row0 を可視にして computeLayout を掛けた結果（UiWorld 同梱）。
    def itemMenuLayout(): (UiStore.UiWorld, Map[EntityId, Rect2.Rect2]) \ Fs.FileRead =
        match UiSpec.load(ItemMenuUi.specPath()) {
            case Err(_)   => bug!("ItemMenu.ui.json load failed")
            case Ok(spec) =>
                let (rootId, ui0) = UiSpec.spawnRoot(spec, UiStore.empty());
                let ui = UiStore.setVisible("ItemMenu/panel/menu/row0", true, ui0);
                let layout = UiLayout.computeLayout(
                    {styles = ui#styles, parents = ui#parents, order = ui#order,
                     measures = Map.empty(), visible = ui#visible},
                    rootId, designRect());
                (ui, layout)
        }

    /// 名前パスの rect を (x, y, w, h) tuple で引く。未確定は None。
    def rectAt(path: String, ui: UiStore.UiWorld, layout: Map[EntityId, Rect2.Rect2]):
            Option[(Float64, Float64, Float64, Float64)] =
        UiStore.idOf(path, ui)
            |> Option.flatMap(id -> Map.get(id, layout))
            |> Option.map(r -> (r#position#x, r#position#y, r#size#x, r#size#y))

    /// rect tuple の (x, width) だけ取り出す（横方向の突き合わせ用）。
    def xw(t: (Float64, Float64, Float64, Float64)): (Float64, Float64) =
        let (x, _y, w, _h) = t; (x, w)

    /// inner が outer に 4 辺とも収まるか（左右上下）。
    def contains(outer: (Float64, Float64, Float64, Float64), inner: (Float64, Float64, Float64, Float64)): Bool =
        let (ox, oy, ow, oh) = outer;
        let (ix, iy, iw, ih) = inner;
        ix >= ox and iy >= oy and (ix + iw) <= (ox + ow) and (iy + ih) <= (oy + oh)

    /// 横方向の実 rect を pin する。panel abs(28,40)+pad2 で menu 原点 x=30。
    /// highlight は inset 0.5 で x=30.5・幅47（内側 30.5..77.5）。行の左 pad 1.5 で
    /// チップ(iconBg 7幅)は x=31.5 から始まり、ハイライトの左内側に 1px 入る。
    @Test
    def testChipXFitsInsideHighlight(): Unit \ {Assert, Fs.FileRead} =
        let (ui, layout) = itemMenuLayout();
        let chip = rectAt("ItemMenu/panel/menu/row0/iconBg", ui, layout) |> Option.map(xw);
        let hl   = rectAt("ItemMenu/panel/menu/highlight", ui, layout) |> Option.map(xw);
        Assert.assertEq(
            expected = (Some((31.5, 7.0)), Some((30.5, 47.0))),
            (chip, hl))

    /// チップの箱がハイライトの箱に上下左右とも完全収容される（左はみ出しの回帰防止）。
    @Test
    def testChipFullyContainedInHighlight(): Unit \ {Assert, Fs.FileRead} =
        let (ui, layout) = itemMenuLayout();
        let chip = rectAt("ItemMenu/panel/menu/row0/iconBg", ui, layout);
        let hl   = rectAt("ItemMenu/panel/menu/highlight", ui, layout);
        Assert.assertEq(
            expected = Some(true),
            forM (h <- hl; c <- chip) yield contains(h, c))
}
