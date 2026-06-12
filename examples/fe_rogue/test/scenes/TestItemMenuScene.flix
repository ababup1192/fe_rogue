/// ItemMenuScene の表面 API を 3 観点で固定する:
///   1. `applyVisibility` が `ItemSelect` / `ItemActionSelect` でだけ panel/menu を表示する
///   2. `ItemSelect` フェーズで `refreshItems` が weapons + staves を 1 つの ItemList に
///      並べる（合計件数が一致する）
///   3. `ItemActionSelect` フェーズで選択中アイテム種別に応じてサブメニュー項目が出し分けされる
///      （武器 → 「装備 / 捨てる」、杖 → 「使う / 捨てる」）
mod TestItemMenuScene {

    use JsonCompat.PathTag.Root

    // ════════════════════════════════════════════════════════
    // フィクスチャ
    // ════════════════════════════════════════════════════════

    /// `ItemMenuScene.add` の {GameEngine.Game, Fs.FileRead} effect を discharge する。
    def loadItemMenu(scene: Scene[NodeTag]): Scene[NodeTag] \ Fs.FileRead =
        run {
            TestUnitFixtures.withMockGame(() -> ItemMenuScene.add(scene))
        } with handler GameEngine.Game {
            // unreachable: withMockGame が中で全部処理する。型を合わせるため定義だけ。
            def renderCommands(_, _, _, k)     = k(())
            def initTileBuffer(_, k)        = k((0i32, 0i32))
            def shouldClose(k)              = k(false)
            def getDeltaTime(k)             = k(Duration.seconds(0.016))
            def isKeyPressed(_, k)          = k(false)
            def getMousePosition(k)         = k({x = 0.0, y = 0.0})
            def isMouseButtonPressed(_, k)  = k(false)
            def consumeScrollDelta(k)       = k(0.0)
            def getFontAtlas(_, k)          = k(TestUnitFixtures.testFontAtlas())
            def getViewportRect(k)          = k({position = Vec2.zero(), size = {x = 128.0, y = 128.0}})
            def getTextureInfo(_, k)        = k(None)
            def setCursor(_, k)             = k(())
        }

    /// テスト用の杖 fixture（耐久 3 のライブの杖）。
    def testStaff(): Staff.StaffResource = {
        name       = "テスト杖",
        effect     = Staff.StaffEffect.Heal,
        durability = 3,
        sprite     = ({texture = "t", hframes = 1, vframes = 1, frame = 0,
                        offset = {x = 0.0, y = 0.0},
                        scale = {x = 1.0, y = 1.0}, flipForFacing = false}: Sprite.SpriteResource),
        description = ""
    }

    /// 武器 1 本 + 杖 1 本を持つプレイヤー 1 体を立てた scene を組む。
    /// id=0 に固定し SelectedPlayer を未設定で返す（テスト側で SelectedPlayer を上書きする）。
    def sceneWithPlayer(): Scene[NodeTag] \ Fs.FileRead =
        let world = Marker2D.make(Vec2.zero());
        let marker = Marker2D.make(Vec2.zero());
        let data: PlayerScene.Data = {
            id                = 0,
            gridPos           = {x = 1, y = 1},
            moveTiles         = 4,
            hp                = 10,
            waited            = false,
            attackTargetId    = None,
            resource          = TestUnitFixtures.testResource(4, 10),
            weapons           = TestUnitFixtures.testWeapon() :: Nil,
            staves            = testStaff() :: Nil,
            consumables       = Nil,
            selectedItem      = None,
            moveStepsTaken    = 0,
            facing            = Staff.Direction.Down,
            hidden            = false,
            usedStairs            = false,
            level                     = 1,
            exp                       = 0,
            pendingLevelUp            = None,
            statuses                  = Nil,
            rings          = Nil,
            ringEquipped          = false,
            followUpUsed   = false
        };
        let withWorld = Scene.empty()
            |> Scene.addNode(MapScene.worldName(),
                EngineNode.Marker2DWithState(world, NodeTag.NoTag))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(0),
                EngineNode.Marker2DWithState(marker, NodeTag.Player(data)));
        loadItemMenu(withWorld)

    /// path の ItemList ノードを取り出す（無ければ None）。Some のまま assert に使える。
    def itemListAt(path: NodePath, scene: Scene[NodeTag]): Option[ItemList] =
        match Scene.getEngineNode(path, scene) {
            case Some(EngineNode.ItemListWithState(list, _)) => Some(list)
            case _                                           => None
        }

    /// 現在の Panel + ItemList の visible 状態をタプルで取り出すヘルパー。
    def visibilityOf(scene: Scene[NodeTag]): (Bool, Bool) =
        let panelVisible = match Scene.getEngineNode(ItemMenuScene.panelPath(), scene) {
            case Some(EngineNode.PanelWithState(p, _)) => CanvasItem.isVisible(p)
            case _                                      => bug!("Panel node not found")
        };
        let menuVisible =
            match Scene.getEngineNode(ItemMenuScene.menuPath(), scene) {
                case Some(EngineNode.ItemListWithState(l, _)) => CanvasItem.isVisible(l)
                case _                                         => bug!("ItemList node not found")
            };
        (panelVisible, menuVisible)

    // ════════════════════════════════════════════════════════
    // applyVisibility — ItemSelect / ItemActionSelect でだけ表示
    // ════════════════════════════════════════════════════════

    /// `ItemSelect` フェーズで panel + menu の両方が visible になる
    @Test
    def testApplyVisibilityShowsOnItemSelect(): Unit \ {Assert, Fs.FileRead} =
        let scene = sceneWithPlayer();
        let after = ItemMenuScene.applyVisibility(TurnPhase.Phase.ItemSelect, scene);
        Assert.assertEq(expected = (true, true), visibilityOf(after))

    /// 関係ないフェーズ (代表として PlayerCursor) では両方 hidden
    @Test
    def testApplyVisibilityHidesOutsideMenuPhases(): Unit \ {Assert, Fs.FileRead} =
        let scene = sceneWithPlayer();
        let after = ItemMenuScene.applyVisibility(TurnPhase.Phase.PlayerCursor, scene);
        Assert.assertEq(expected = (false, false), visibilityOf(after))

    // ════════════════════════════════════════════════════════
    // ItemSelect: refreshItems が weapons + staves を 1 リストに並べる
    // ════════════════════════════════════════════════════════

    /// プレイヤー (weapons 1 + staves 1) → ItemList の項目数は 2
    @Test
    def testItemSelectListsWeaponsAndStaves(): Unit \ {Assert, Fs.FileRead} =
        let scene = sceneWithPlayer();
        let menuPath = ItemMenuScene.menuPath();
        let updated = TestUnitFixtures.withSelectedPlayer(0, () ->
            TestUnitFixtures.withFixedPhase(TurnPhase.Phase.ItemSelect, () ->
                TestUnitFixtures.withMockPartyQuery(scene, () ->
                match Scene.getEngineNode(menuPath, scene) {
                    case Some(node) =>
                        let (_, scnAfter) = ItemMenuScene.refreshItems(
                            Duration.seconds(0.016), node, menuPath, scene);
                        scnAfter
                    case None       => bug!("menu node not found at ${menuPath}")
                })));
        Assert.assertEq(expected = Some(2),
            itemListAt(menuPath, updated) |> Option.map(list -> List.length(ItemList.getItems(list))))

    // ════════════════════════════════════════════════════════
    // ItemActionSelect: 武器/杖でサブメニュー項目が出し分けされる
    // ════════════════════════════════════════════════════════

    /// 選択中アイテムが武器（idx=0）→ サブメニュー項目は「そうび / すてる」の 2 件
    @Test
    def testActionMenuForWeapon(): Unit \ {Assert, Fs.FileRead} =
        let withSelection = sceneWithPlayer()
            |> PlayerScene.setSelectedItem(0, PlayerData.ItemKind.Weapon(0));
        let menuPath = ItemMenuScene.menuPath();
        let updated = TestUnitFixtures.withSelectedPlayer(0, () ->
            TestUnitFixtures.withFixedPhase(TurnPhase.Phase.ItemActionSelect, () ->
                TestUnitFixtures.withMockPartyQuery(withSelection, () ->
                match Scene.getEngineNode(menuPath, withSelection) {
                    case Some(node) =>
                        let (_, scnAfter) = ItemMenuScene.refreshItems(
                            Duration.seconds(0.016), node, menuPath, withSelection);
                        scnAfter
                    case None       => withSelection
                })));
        let texts = match Scene.getEngineNode(menuPath, updated) {
            case Some(EngineNode.ItemListWithState(list, _)) =>
                List.map(entry -> entry#text, ItemList.getItems(list))
            case _ => Nil
        };
        Assert.assertEq(expected = "装備" :: "投げる" :: "捨てる" :: Nil, texts)

    /// 選択中アイテムが杖（idx=0）→ サブメニュー項目は「使う / 捨てる」の 2 件
    @Test
    def testActionMenuForStaff(): Unit \ {Assert, Fs.FileRead} =
        let withSelection = sceneWithPlayer()
            |> PlayerScene.setSelectedItem(0, PlayerData.ItemKind.Staff(0));
        let menuPath = ItemMenuScene.menuPath();
        let updated = TestUnitFixtures.withSelectedPlayer(0, () ->
            TestUnitFixtures.withFixedPhase(TurnPhase.Phase.ItemActionSelect, () ->
                TestUnitFixtures.withMockPartyQuery(withSelection, () ->
                match Scene.getEngineNode(menuPath, withSelection) {
                    case Some(node) =>
                        let (_, scnAfter) = ItemMenuScene.refreshItems(
                            Duration.seconds(0.016), node, menuPath, withSelection);
                        scnAfter
                    case None       => withSelection
                })));
        let texts = match Scene.getEngineNode(menuPath, updated) {
            case Some(EngineNode.ItemListWithState(list, _)) =>
                List.map(entry -> entry#text, ItemList.getItems(list))
            case _ => Nil
        };
        Assert.assertEq(expected = "使う" :: "投げる" :: "捨てる" :: Nil, texts)

    // ════════════════════════════════════════════════════════
    // カーソル位置: サブメニューに入ると必ず先頭(0)から始まる
    // ════════════════════════════════════════════════════════

    /// ItemSelect で 2 番目の項目にカーソルを置いた状態でアイテムを確定しても、
    /// サブメニュー(ItemActionSelect)に入った瞬間カーソルは先頭(index 0)に戻る。
    /// （回帰: 以前は ItemSelect の選択位置を引き継ぎ「すてる」に当たっていた）
    @Test
    def testEnteringActionSubmenuResetsCursorToFirst(): Unit \ {Assert, Fs.FileRead} =
        let menuPath = ItemMenuScene.menuPath();
        // ItemList に 2 項目入れて、カーソルを 2 番目(index 1)に動かした状態を再現する。
        let twoEntries =
            ({text = "a", disabled = false, metadata = Some("w:0")}: ItemEntry) ::
            ({text = "b", disabled = false, metadata = Some("s:0")}: ItemEntry) :: Nil;
        let scene = sceneWithPlayer()
            |> ItemList.mapAt(menuPath, list ->
                list |> ItemList.setItems(twoEntries) |> ItemList.setSelectedIndex(1));
        let entry = ({text = "a", disabled = false, metadata = Some("w:0")}: ItemEntry);
        let after = TestUnitFixtures.withSelectedPlayer(0, () ->
            TestUnitFixtures.withFixedPhase(TurnPhase.Phase.ItemSelect, () ->
                ItemMenuScene.onItemConfirmed(entry, scene)));
        Assert.assertEq(expected = Some(0),
            itemListAt(menuPath, after) |> Option.map(ItemList.getSelectedIndex))

    // ════════════════════════════════════════════════════════
    // ページング: ロード職など 8 個超の持ち物を 8 件ずつページ分けする
    // ════════════════════════════════════════════════════════

    /// 容量カウントに影響しないダミー sprite。
    def pageDummySprite(): Sprite.SpriteResource = {
        texture = "t", hframes = 1, vframes = 1, frame = 0,
        offset = {x = 0.0, y = 0.0}, scale = {x = 1.0, y = 1.0}, flipForFacing = false
    }

    /// 連番テキスト "0".."n-1" を持つ (表示エントリ, ダミー sprite) の組を n 個ぶん作る。
    /// スライス後に「どの組が並んだか」をテキストで追えるよう、入力データだけを用意する
    /// ヘルパー（期待値の計算はしない）。
    def numberedPairs(n: Int32): List[(ItemEntry, Sprite.SpriteResource)] =
        List.map(i ->
            (({text = "${i}", disabled = false, metadata = Some("${i}")}: ItemEntry),
             pageDummySprite()),
            List.range(0, n))

    /// 総ページ数: 8 個 = 1 ページ、9 個 = 2 ページ、16 個 = 2 ページ、0 個 = 1 ページ（最低 1）。
    @Test
    def testTotalPages(): Unit \ Assert =
        Assert.assertEq(
            expected = (1, 2, 2, 1),
            (ItemMenuScene.totalPages(8), ItemMenuScene.totalPages(9),
             ItemMenuScene.totalPages(16), ItemMenuScene.totalPages(0)))

    /// 持ち物 16 個・1 ページ目: 先頭 8 件が並び、先頭エントリは入力の 0 番、
    /// アイコンも 8 件ぶん（行 index 0..7 に振り直されている）。
    @Test
    def testPageSliceFirstPage(): Unit \ Assert =
        let (items, icons) = ItemMenuScene.pageSlice(numberedPairs(16), 0);
        match List.head(items) {
            case Some(entry) =>
                Assert.assertEq(
                    expected = (8, "0", 8),
                    (List.length(items), entry#text, Map.size(icons)))
            case None => bug!("1 ページ目には 8 件並ぶはず")
        }

    /// 持ち物 16 個・2 ページ目: 後半 8 件が並び、先頭エントリは入力の 8 番
    /// （ページ内は 0 起点にスライスされている）。
    @Test
    def testPageSliceSecondPage(): Unit \ Assert =
        let (items, _) = ItemMenuScene.pageSlice(numberedPairs(16), 1);
        match List.head(items) {
            case Some(entry) =>
                Assert.assertEq(expected = (8, "8"), (List.length(items), entry#text))
            case None => bug!("2 ページ目には 8 件並ぶはず")
        }

    /// 1 ページぶん（持ち物 2 個）のプレイヤーで → を押してもページは 0 のまま頭打ち
    /// （ループしないこと）。`sceneWithPlayer` は武器 1 + 杖 1 = 2 個 = 1 ページ。
    @Test
    def testPageRightClampsWhenSinglePage(): Unit \ {Assert, Fs.FileRead} =
        let scene = sceneWithPlayer();
        let after = TestUnitFixtures.withSelectedPlayer(0, () -> ItemMenuScene.pageRight(scene));
        let page = match Scene.getState(ItemMenuScene.menuPath(), after) {
            case Some(NodeTag.ItemMenu(currentPage, _)) => currentPage
            case _                                      => bug!("ItemMenu タグが無い")
        };
        Assert.assertEq(expected = 0, page)

    // ════════════════════════════════════════════════════════
    // actionItemsFor: 選択中アイテム種別 → サブメニュー項目（純粋）
    // ════════════════════════════════════════════════════════

    /// 武器選択中 → 「装備 / 捨てる」
    @Test
    def testActionItemsForWeapon(): Unit \ Assert =
        let items = ItemMenuScene.actionItemsFor(Some(PlayerData.ItemKind.Weapon(0)), false);
        Assert.assertEq(
            expected = "装備" :: "投げる" :: "捨てる" :: Nil,
            List.map(e -> e#text, items))

    /// 杖選択中 → 「使う / 捨てる」
    @Test
    def testActionItemsForStaff(): Unit \ Assert =
        let items = ItemMenuScene.actionItemsFor(Some(PlayerData.ItemKind.Staff(1)), false);
        Assert.assertEq(
            expected = "使う" :: "投げる" :: "捨てる" :: Nil,
            List.map(e -> e#text, items))

    /// 消費アイテム選択中 → 「使う / 捨てる」（杖と同じ）
    @Test
    def testActionItemsForConsumable(): Unit \ Assert =
        let items = ItemMenuScene.actionItemsFor(Some(PlayerData.ItemKind.Consumable(2)), false);
        Assert.assertEq(
            expected = "使う" :: "投げる" :: "捨てる" :: Nil,
            List.map(e -> e#text, items))

    /// 未装備の指輪を選択中 → 「装備 / 投げる / 捨てる」（拾っただけは装備されない）
    @Test
    def testActionItemsForRingUnequipped(): Unit \ Assert =
        let items = ItemMenuScene.actionItemsFor(Some(PlayerData.ItemKind.Ring(0)), false);
        Assert.assertEq(
            expected = "装備" :: "投げる" :: "捨てる" :: Nil,
            List.map(e -> e#text, items))

    /// 装備中の指輪（先頭 + ringEquipped=true）を選択中 → 「外す」に変わる
    @Test
    def testActionItemsForRingEquipped(): Unit \ Assert =
        let items = ItemMenuScene.actionItemsFor(Some(PlayerData.ItemKind.Ring(0)), true);
        Assert.assertEq(
            expected = "外す" :: "投げる" :: "捨てる" :: Nil,
            List.map(e -> e#text, items))

    /// ringEquipped=true でも先頭以外の指輪（idx=1）は装備中ではない → 「装備」のまま
    @Test
    def testActionItemsForRingNonHeadStillEquip(): Unit \ Assert =
        let items = ItemMenuScene.actionItemsFor(Some(PlayerData.ItemKind.Ring(1)), true);
        Assert.assertEq(
            expected = "装備" :: "投げる" :: "捨てる" :: Nil,
            List.map(e -> e#text, items))

    /// 未選択 → 空（サブメニューを出さない）
    @Test
    def testActionItemsForNone(): Unit \ Assert =
        let items = ItemMenuScene.actionItemsFor(None, false);
        Assert.assertEq(expected = 0, List.length(items))

    // ════════════════════════════════════════════════════════
    // parseItemKind: metadata 文字列 → ItemKind（純粋）
    // ════════════════════════════════════════════════════════

    @Test
    def testParseItemKindWeapon(): Unit \ Assert =
        Assert.assertEq(
            expected = Some(PlayerData.ItemKind.Weapon(1)),
            ItemMenuScene.parseItemKind("w:1"))

    @Test
    def testParseItemKindStaff(): Unit \ Assert =
        Assert.assertEq(
            expected = Some(PlayerData.ItemKind.Staff(0)),
            ItemMenuScene.parseItemKind("s:0"))

    @Test
    def testParseItemKindConsumable(): Unit \ Assert =
        Assert.assertEq(
            expected = Some(PlayerData.ItemKind.Consumable(2)),
            ItemMenuScene.parseItemKind("c:2"))

    /// 不明な prefix は None
    @Test
    def testParseItemKindUnknown(): Unit \ Assert =
        Assert.assertEq(
            expected = None,
            ItemMenuScene.parseItemKind("x:9"))

    // ════════════════════════════════════════════════════════
    // 詳細ウィンドウの性能 1 行（stats から自動生成・純粋）
    // ════════════════════════════════════════════════════════

    /// 武器の性能表記。攻撃 2 / 命中 80 / 射程 1-1（同値なので「射1」）/ 剣。
    /// テスト武器は attack 2・hit 80・range 1-1・Sword なのでこの 1 行になる。
    @Test
    def testWeaponStatLineSingleRange(): Unit \ Assert =
        Assert.assertEq(
            expected = "攻2 命80 射1 剣",
            ItemMenuScene.weaponStatLine(TestUnitFixtures.testWeapon()))

    /// 射程が min≠max のときは「射1-2」のように範囲表記になる。
    /// テスト武器の射程だけを 1-2 に差し替えて確認する。
    @Test
    def testWeaponStatLineRangeSpan(): Unit \ Assert =
        let javelin = {range = {min = 1, max = 2} | TestUnitFixtures.testWeapon()};
        Assert.assertEq(
            expected = "攻2 命80 射1-2 剣",
            ItemMenuScene.weaponStatLine(javelin))

    /// 杖の性能表記。効果（回復）と残り耐久を出す。テスト杖は Heal・耐久 3。
    @Test
    def testStaffStatLine(): Unit \ Assert =
        Assert.assertEq(
            expected = "効果:回復 耐久3",
            ItemMenuScene.staffStatLine(testStaff()))

    /// 消費アイテムの性能表記。回復量と残り使用回数を出す。
    @Test
    def testConsumableStatLine(): Unit \ Assert =
        let potion = ({name = "きずぐすり",
                        effect = Consumable.ConsumableEffect.Heal, magnitude = 10, duration = 0,
                        healAmount = 10, durability = 3,
                        sprite = testStaff()#sprite, description = ""}:
                        Consumable.ConsumableResource);
        Assert.assertEq(
            expected = "HP+10 耐久3",
            ItemMenuScene.consumableStatLine(potion))

    // ════════════════════════════════════════════════════════
    // wrapText: 説明文の手動折り返し（純粋）
    // ════════════════════════════════════════════════════════

    /// 幅 4 で 7 文字を折ると、先頭 4 文字と残り 3 文字が `\n` で 2 行に分かれる。
    @Test
    def testWrapTextSplitsAtWidth(): Unit \ Assert =
        Assert.assertEq(
            expected = "ABCD\nEFG",
            ItemMenuScene.wrapText(4, "ABCDEFG"))

    /// 幅より短いテキストはそのまま（改行を入れない）。
    @Test
    def testWrapTextShortStaysOneLine(): Unit \ Assert =
        Assert.assertEq(
            expected = "あいう",
            ItemMenuScene.wrapText(12, "あいう"))

    // ════════════════════════════════════════════════════════
    // 複数選択（マーク）の純粋ヘルパー
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
    /// まとめて捨てる/渡すとき大きい index から処理して小さい index がずれないことを支える並び。
    @Test
    def testMarksDescendingPerList(): Unit \ Assert =
        let marks = Set#{PlayerData.ItemKind.Weapon(0), PlayerData.ItemKind.Weapon(2),
                         PlayerData.ItemKind.Staff(1)};
        Assert.assertEq(
            expected = PlayerData.ItemKind.Weapon(2) :: PlayerData.ItemKind.Weapon(0)
                        :: PlayerData.ItemKind.Staff(1) :: Nil,
            PlayerData.marksDescendingPerList(marks))

    /// planBulkTransfer: 空きの数だけ index の大きい順に渡し、入りきらない分は残す。
    /// (渡す数, 残す数) で 3 ケース確認: 余裕あり全渡し / 空き0で全残し / 空き2で 2 渡し 2 残し。
    @Test
    def testPlanBulkTransferSplitsByFreeSlots(): Unit \ Assert =
        let two  = Set#{PlayerData.ItemKind.Weapon(0), PlayerData.ItemKind.Weapon(1)};
        let four = Set#{PlayerData.ItemKind.Weapon(0), PlayerData.ItemKind.Weapon(1),
                        PlayerData.ItemKind.Weapon(2), PlayerData.ItemKind.Weapon(3)};
        let (t5, l5) = PlayerData.planBulkTransfer(two, 5);
        let (t0, l0) = PlayerData.planBulkTransfer(two, 0);
        let (t2, l2) = PlayerData.planBulkTransfer(four, 2);
        Assert.assertEq(
            expected = ((2, 0), (0, 2), (2, 2)),
            ((List.length(t5), List.length(l5)),
             (List.length(t0), List.length(l0)),
             (List.length(t2), List.length(l2))))

    /// markedRowsOnPage: 印は種別+絶対 index なので、現在ページに表示される行だけを
    /// ページ内 0 起点の行 index に直す。10 個並びで w:0 と w:8 に印を付けると、
    /// 1 ページ目(先頭0)では w:0 が行0(w:8 は範囲外)、2 ページ目(先頭8)では w:8 が行0。
    @Test
    def testMarkedRowsOnPageMapsToCurrentPage(): Unit \ Assert =
        let pairs = List.map(i ->
            (({text = "${i}", disabled = false, metadata = Some("w:${i}")}: ItemEntry),
             pageDummySprite()), List.range(0, 10));
        let marks = Set#{PlayerData.ItemKind.Weapon(0), PlayerData.ItemKind.Weapon(8)};
        Assert.assertEq(
            expected = (0 :: Nil, 0 :: Nil),
            (ItemMenuScene.markedRowsOnPage(marks, 0, pairs),
             ItemMenuScene.markedRowsOnPage(marks, 8, pairs)))
}
