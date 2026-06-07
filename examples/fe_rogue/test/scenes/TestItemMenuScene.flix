/// ItemMenuScene の表面 API を 3 観点で固定する:
///   1. `applyVisibility` が `ItemSelect` / `ItemActionSelect` でだけ panel/menu を表示する
///   2. `ItemSelect` フェーズで `refreshItems` が weapons + staves を 1 つの ItemList に
///      並べる（合計件数が一致する）
///   3. `ItemActionSelect` フェーズで選択中アイテム種別に応じてサブメニュー項目が出し分けされる
///      （武器 → 「そうび / すてる」、杖 → 「つかう / すてる」）
mod TestItemMenuScene {

    use Json.JsonError.JsonError
    use Json.Path.Path.Root

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
                        scale = {x = 1.0, y = 1.0}}: Sprite.SpriteResource)
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
            pendingLevelUp            = None
        };
        let withWorld = Scene.empty()
            |> Scene.addNode(MapScene.worldName(),
                EngineNode.Marker2DWithState(world, NodeTag.NoTag))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(0),
                EngineNode.Marker2DWithState(marker, NodeTag.Player(data)));
        loadItemMenu(withWorld)

    /// `SelectedPlayer.State` のスタブ handler（id=0 を返す）。
    def withSelectedZero(thunk: Unit -> a \ ef): a \ (ef - SelectedPlayer.State) =
        run { thunk() } with handler SelectedPlayer.State {
            def get(k)   = k({id = Some(0), drafts = Nil})
            def put(_, k) = k()
        }

    /// `TurnPhase.State` のスタブ handler（指定したフェーズを固定で返す）。
    def withFixedPhase(phase: TurnPhase.Phase, thunk: Unit -> a \ ef):
            a \ (ef - TurnPhase.State) =
        run { thunk() } with handler TurnPhase.State {
            def get(k)    = k(phase)
            def put(_, k) = k()
        }

    /// 現在の Panel + ItemList の visible 状態をタプルで取り出すヘルパー。
    def visibilityOf(scene: Scene[NodeTag]): (Bool, Bool) =
        let panelVisible = match Scene.getEngineNode(ItemMenuScene.panelPath(), scene) {
            case Some(EngineNode.PanelWithState(p, _)) => CanvasItem.isVisible(p)
            case _                                      => false
        };
        let menuVisible =
            match Scene.getEngineNode(ItemMenuScene.menuPath(), scene) {
                case Some(EngineNode.ItemListWithState(l, _)) => CanvasItem.isVisible(l)
                case _                                         => false
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
        let updated = withSelectedZero(() ->
            withFixedPhase(TurnPhase.Phase.ItemSelect, () ->
                match Scene.getEngineNode(menuPath, scene) {
                    case Some(node) =>
                        let (_, scnAfter) = ItemMenuScene.refreshItems(
                            Duration.seconds(0.016), node, menuPath, scene);
                        scnAfter
                    case None       => scene
                }));
        let count = match Scene.getEngineNode(menuPath, updated) {
            case Some(EngineNode.ItemListWithState(list, _)) =>
                List.length(ItemList.getItems(list))
            case _ => -1
        };
        Assert.assertEq(expected = 2, count)

    // ════════════════════════════════════════════════════════
    // ItemActionSelect: 武器/杖でサブメニュー項目が出し分けされる
    // ════════════════════════════════════════════════════════

    /// 選択中アイテムが武器（idx=0）→ サブメニュー項目は「そうび / すてる」の 2 件
    @Test
    def testActionMenuForWeapon(): Unit \ {Assert, Fs.FileRead} =
        let withSelection = sceneWithPlayer()
            |> PlayerScene.setSelectedItem(0, PlayerScene.ItemKind.Weapon(0));
        let menuPath = ItemMenuScene.menuPath();
        let updated = withSelectedZero(() ->
            withFixedPhase(TurnPhase.Phase.ItemActionSelect, () ->
                match Scene.getEngineNode(menuPath, withSelection) {
                    case Some(node) =>
                        let (_, scnAfter) = ItemMenuScene.refreshItems(
                            Duration.seconds(0.016), node, menuPath, withSelection);
                        scnAfter
                    case None       => withSelection
                }));
        let texts = match Scene.getEngineNode(menuPath, updated) {
            case Some(EngineNode.ItemListWithState(list, _)) =>
                List.map(entry -> entry#text, ItemList.getItems(list))
            case _ => Nil
        };
        Assert.assertEq(expected = "そうび" :: "すてる" :: Nil, texts)

    /// 選択中アイテムが杖（idx=0）→ サブメニュー項目は「つかう / すてる」の 2 件
    @Test
    def testActionMenuForStaff(): Unit \ {Assert, Fs.FileRead} =
        let withSelection = sceneWithPlayer()
            |> PlayerScene.setSelectedItem(0, PlayerScene.ItemKind.Staff(0));
        let menuPath = ItemMenuScene.menuPath();
        let updated = withSelectedZero(() ->
            withFixedPhase(TurnPhase.Phase.ItemActionSelect, () ->
                match Scene.getEngineNode(menuPath, withSelection) {
                    case Some(node) =>
                        let (_, scnAfter) = ItemMenuScene.refreshItems(
                            Duration.seconds(0.016), node, menuPath, withSelection);
                        scnAfter
                    case None       => withSelection
                }));
        let texts = match Scene.getEngineNode(menuPath, updated) {
            case Some(EngineNode.ItemListWithState(list, _)) =>
                List.map(entry -> entry#text, ItemList.getItems(list))
            case _ => Nil
        };
        Assert.assertEq(expected = "つかう" :: "すてる" :: Nil, texts)

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
        let after = withSelectedZero(() ->
            withFixedPhase(TurnPhase.Phase.ItemSelect, () ->
                ItemMenuScene.onItemConfirmed(entry, scene)));
        let idx = match Scene.getEngineNode(menuPath, after) {
            case Some(EngineNode.ItemListWithState(list, _)) => ItemList.getSelectedIndex(list)
            case _ => -1
        };
        Assert.assertEq(expected = 0, idx)
}
