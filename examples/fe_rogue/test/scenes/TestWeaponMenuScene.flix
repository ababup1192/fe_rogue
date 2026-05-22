/// WeaponMenuScene の表面 API を 3 観点で固定する:
///   1. `applyVisibility` が `WeaponSelect` 以外で panel/menu を hidden にする
///   2. `refreshItems` で生成される ItemList の件数 = 選択プレイヤーの装備武器数
///   3. `onWeaponConfirmed` が metadata の数字を `Data#selectedWeaponIdx` に保存する
///
/// この 3 観点は R4 (Menu 基盤共通化) で `MenuTemplate` に抽出するときに
/// 「何を保証すべきか」を明示する契約。
mod TestWeaponMenuScene {

    // ════════════════════════════════════════════════════════
    // ヘルパー
    // ════════════════════════════════════════════════════════

    /// `WeaponMenuScene.add` の {GameEngine.Game, Fs.FileRead} effect を discharge する。
    def weaponMenuAddPure(scene: Scene[NodeTag]): Scene[NodeTag] =
        unchecked_cast(
            (run {
                TestUnitFixtures.withMockGame(() -> WeaponMenuScene.add(scene))
            } with Fs.FileRead.runWithIO)
            as _ \ {})

    /// 指定数の武器を装備した Player(0) を World 配下に置いた scene を組む。
    /// PlayerScene.add の JSON ローダを経由せず Marker2D を直接生やす (テストの軽量化)。
    def sceneWithPlayerHavingWeapons(weaponCount: Int32): Scene[NodeTag] =
        let weapons = List.range(0, weaponCount)
            |> List.map(_ -> TestUnitFixtures.testWeapon());
        let world = Marker2D.make(Vec2.zero())
            |> CanvasItem.setYSortEnabled(true);
        let player = Marker2D.make(MapScene.cellCenter({x = 5, y = 5}));
        Scene.empty()
            |> Scene.addNode(MapScene.worldName(),
                EngineNode.Marker2DWithState(world, NodeTag.NoTag))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(0),
                EngineNode.Marker2DWithState(player,
                    NodeTag.Player({
                        id                = 0,
                        gridPos           = ({x = 5, y = 5}: {x = Int32, y = Int32}),
                        moveTiles         = 5,
                        hp                = 10,
                        waited            = false,
                        attackTargetId    = None,
                        resource          = TestUnitFixtures.testResource(5, 10),
                        weapons           = weapons,
                        selectedWeaponIdx = None,
                        moveStepsTaken    = 0
                    })))

    /// Panel と ItemList の (visible, focused) を 1 タプルで観測する。
    def visibilityState(scene: Scene[NodeTag]): (Bool, Bool, Bool) =
        let panelVisible = match Scene.getEngineNode(WeaponMenuScene.panelPath(), scene) {
            case Some(EngineNode.PanelWithState(p, _)) => CanvasItem.isVisible(p)
            case _                                       => bug!("WeaponMenu panel not found")
        };
        let (menuVisible, menuFocused) =
            match Scene.getEngineNode(WeaponMenuScene.menuPath(), scene) {
                case Some(EngineNode.ItemListWithState(l, _)) =>
                    (CanvasItem.isVisible(l), ItemList.isFocused(l))
                case _ => bug!("WeaponMenu ItemList not found")
            };
        (panelVisible, menuVisible, menuFocused)

    // ════════════════════════════════════════════════════════
    // applyVisibility — WeaponSelect 限定で表示
    // ════════════════════════════════════════════════════════

    /// `WeaponSelect` 以外の任意フェーズ (代表として PlayerAttack) では panel/menu とも hidden。
    @Test
    def testApplyVisibilityHidesPanelOutsideWeaponSelect(): Unit \ Assert =
        let scene = weaponMenuAddPure(Scene.empty());
        let after = WeaponMenuScene.applyVisibility(TurnPhase.Phase.PlayerAttack, scene);
        Assert.assertEq(
            expected = (false, false, false),
            visibilityState(after))

    // ════════════════════════════════════════════════════════
    // refreshItems — 選択プレイヤーの装備武器数だけ ItemEntry を生成する
    // ════════════════════════════════════════════════════════

    /// 選択中味方が 3 本武器を持っているとき、`refreshItems` 後の ItemList には 3 項目が並ぶ。
    /// 武器名やアイコンの一致は別問題なので、ここでは **項目数 1 つ** だけ assertEq する。
    @Test
    def testRefreshItemsMatchesPlayerWeaponsCount(): Unit \ Assert =
        region rc {
            let base = sceneWithPlayerHavingWeapons(3);
            let scene = weaponMenuAddPure(base);
            let menuPath = WeaponMenuScene.menuPath();
            let result = run {
                SelectedPlayer.State.put({
                    id     = Some(0),
                    origin = Some(({x = 5, y = 5}: {x = Int32, y = Int32}))
                });
                TurnPhase.State.put(TurnPhase.Phase.WeaponSelect);
                match Scene.getEngineNode(menuPath, scene) {
                    case Some(menuNode) =>
                        let (newNode, _) = WeaponMenuScene.refreshItems(
                            Duration.seconds(0.016), menuNode, menuPath, scene);
                        match newNode {
                            case EngineNode.ItemListWithState(list, _) =>
                                List.length(ItemList.getItems(list))
                            case _ => bug!("menu node is not ItemList after refresh")
                        }
                    case _ => bug!("WeaponMenu ItemList not found")
                }
            } with TurnPhase.withState(rc)
              with SelectedPlayer.withState(rc);
            Assert.assertEq(expected = 3, result)
        }

    // ════════════════════════════════════════════════════════
    // onWeaponConfirmed — metadata 数字を Data#selectedWeaponIdx に書き込む
    // ════════════════════════════════════════════════════════

    /// Enter で武器を確定すると、選択中味方の `Data#selectedWeaponIdx` に
    /// metadata の数字 (= 武器インデックス) が `Some(n)` で書き込まれる。
    /// AttackForecast への phase 遷移も同時に起きるが、後者は phase をタプル化して観測。
    @Test
    def testOnWeaponConfirmedSetsPlayerSelectedWeaponIdx(): Unit \ Assert =
        region rc {
            let scene = sceneWithPlayerHavingWeapons(2);
            let entry: ItemEntry = {
                text     = "test",
                disabled = false,
                metadata = Some("1")   // weapons[1] を選んだ想定
            };
            let result = run {
                SelectedPlayer.State.put({
                    id     = Some(0),
                    origin = Some(({x = 5, y = 5}: {x = Int32, y = Int32}))
                });
                TurnPhase.State.put(TurnPhase.Phase.WeaponSelect);
                let after = WeaponMenuScene.onWeaponConfirmed(entry, scene);
                let idx = match PlayerScene.get(0, after) {
                    case Some(d) => d#selectedWeaponIdx
                    case None    => bug!("Player(0) not found after onWeaponConfirmed")
                };
                (idx, TurnPhase.State.get())
            } with TurnPhase.withState(rc)
              with SelectedPlayer.withState(rc);
            Assert.assertEq(
                expected = (Some(1), TurnPhase.Phase.AttackForecast),
                result)
        }
}
