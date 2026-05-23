/// ActionMenuScene の `applyVisibility` が phase 切替で Panel / ItemList の visible を
/// 仕様どおりに反転することを観測する。
///
/// 検証する観点:
///   - `ActionSelect` 以外のフェーズでは Panel と ItemList のどちらも hidden
///   - `ActionSelect` のときだけ Panel = visible / ItemList = visible + focused
///
/// items の構築 (`buildItems` / `canAttackFrom` / `canWaitOn`) は private 関数なので
/// ここでは直接観測せず、R4 (Menu 基盤共通化) 後に refreshItems 経由で見る方が
/// 構築コストに対するリターンが良い。ここでは visibility 契約だけ pin する。
mod TestActionMenuScene {

    // ════════════════════════════════════════════════════════
    // ヘルパー
    // ════════════════════════════════════════════════════════

    /// `ActionMenuScene.add` の {GameEngine.Game, Fs.FileRead} effect を discharge して
    /// pure に見せる test 用ラッパ。`cursorAddPure` と同じ unchecked_cast パターン。
    def actionMenuAddPure(scene: Scene[NodeTag]): Scene[NodeTag] =
        unchecked_cast(
            (run {
                TestUnitFixtures.withMockGame(() -> ActionMenuScene.add(scene))
            } with Fs.FileRead.runWithIO)
            as _ \ {})

    /// Panel と ItemList の (visible, focused) を 1 タプルで観測する。
    /// 親 Panel が hidden になれば子の ItemList も実描画上は出ないが、ここでは
    /// `applyVisibility` が両方明示に setVisible しているかを直接確認する。
    def visibilityState(scene: Scene[NodeTag]): (Bool, Bool, Bool) =
        let panelVisible = match Scene.getEngineNode(ActionMenuScene.panelPath(), scene) {
            case Some(EngineNode.PanelWithState(p, _)) => CanvasItem.isVisible(p)
            case _                                       => bug!("ActionMenu panel not found")
        };
        let (menuVisible, menuFocused) =
            match Scene.getEngineNode(ActionMenuScene.menuPath(), scene) {
                case Some(EngineNode.ItemListWithState(l, _)) =>
                    (CanvasItem.isVisible(l), ItemList.isFocused(l))
                case _ => bug!("ActionMenu ItemList not found")
            };
        (panelVisible, menuVisible, menuFocused)

    // ════════════════════════════════════════════════════════
    // applyVisibility — phase に応じて panel/menu の表示を切り替える
    // ════════════════════════════════════════════════════════

    /// `ActionSelect` 以外のフェーズでは Panel = hidden / ItemList = hidden + 非フォーカス。
    /// PlayerCursor を代表として確認 (他フェーズも同じ「ActionSelect 以外」の集合に入る)。
    @Test
    def testApplyVisibilityHidesPanelOutsideActionSelect(): Unit \ Assert =
        let scene = actionMenuAddPure(Scene.empty());
        let after = ActionMenuScene.applyVisibility(TurnPhase.Phase.PlayerCursor, scene);
        Assert.assertEq(
            expected = (false, false, false),
            visibilityState(after))

    /// `ActionSelect` フェーズでは Panel = visible / ItemList = visible + focused。
    /// メニューに入力フォーカスが当たって engine の MenuEvent が Enter/Escape を拾える状態になる。
    @Test
    def testApplyVisibilityShowsAndFocusesInActionSelect(): Unit \ Assert =
        let scene = actionMenuAddPure(Scene.empty());
        let after = ActionMenuScene.applyVisibility(TurnPhase.Phase.ActionSelect, scene);
        Assert.assertEq(
            expected = (true, true, true),
            visibilityState(after))

    // ════════════════════════════════════════════════════════
    // onActionConfirmed 回帰テスト用フィクスチャ
    // ════════════════════════════════════════════════════════

    /// id を指定して PlayerScene.Data を 1 体分作る。
    /// 武器を 1 本持たせ、まだ行動していない (waited = false) アクティブな駒。
    /// 検証の都合で id と gridPos だけ意味のある値、他はデフォルト値。
    def makePlayerData(id: Int32, gridPos: {x = Int32, y = Int32}):
            PlayerScene.Data = {
        id              = id,
        gridPos         = gridPos,
        moveTiles       = 4,
        hp              = 10,
        waited          = false,
        attackTargetId  = None,
        resource        = TestUnitFixtures.testResource(4, 10),
        weapons         = TestUnitFixtures.testWeapon() :: Nil,
        staves          = Nil,
        selectedItem    = None,
        moveStepsTaken  = 0
    }

    /// World + 2 人の Player + ActionMenu を組んだテスト scene。
    /// id=0 を (1,1) に、id=1 を (3,3) に置き、どちらもアクティブ (waited=false)。
    /// 回帰テストでは id=0 を選択中扱いにして、確定後に id=1 がアクティブのままか観測する。
    def loadTwoPlayerActionMenuScene(): Scene[NodeTag] =
        let world = Marker2D.make(Vec2.zero());
        let marker0 = Marker2D.make(Vec2.zero());
        let marker1 = Marker2D.make(Vec2.zero());
        let data0 = makePlayerData(0, {x = 1, y = 1});
        let data1 = makePlayerData(1, {x = 3, y = 3});
        let withWorld = Scene.empty()
            |> Scene.addNode(MapScene.worldName(),
                EngineNode.Marker2DWithState(world, NodeTag.NoTag))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(0),
                EngineNode.Marker2DWithState(marker0, NodeTag.Player(data0)))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(1),
                EngineNode.Marker2DWithState(marker1, NodeTag.Player(data1)));
        actionMenuAddPure(withWorld)

    /// 指定 id のプレイヤーの waited フラグを取り出す。居なければテストを潰す。
    def waitedOf(id: Int32, scene: Scene[NodeTag]): Bool =
        match PlayerScene.get(id, scene) {
            case Some(d) => d#waited
            case None    => bug!("player ${id} not found")
        }

    /// 指定 id のプレイヤーの所持武器本数を返す。居なければテストを潰す。
    def weaponCountOf(id: Int32, scene: Scene[NodeTag]): Int32 =
        match PlayerScene.get(id, scene) {
            case Some(d) => List.length(d#weapons)
            case None    => bug!("player ${id} not found")
        }

    /// テスト用 floor item を 1 個だけ scene に貼り付ける。
    /// World/Items の親ノードを (なければ) 作り、Item_0 として `cell` に置く。
    /// 視覚要素 (縁取り Sprite 等) は省き、`ItemScene.findAt` が見つけるのに必要な
    /// `NodeTag.GroundItem(Data)` だけを持たせる。
    def attachGroundItemAt(cell: {x = Int32, y = Int32},
                            kind: ItemScene.GroundItemKind,
                            scene: Scene[NodeTag]): Scene[NodeTag] =
        let parentNodeName = "Items";
        let parentMarker = Marker2D.make(Vec2.zero());
        let withParent = match Scene.getEngineNode(ItemScene.parentPath(), scene) {
            case Some(_) => scene
            case None    =>
                Scene.addChildAt(MapScene.worldPath(), parentNodeName,
                    EngineNode.Marker2DWithState(parentMarker, NodeTag.NoTag), scene)
        };
        let baseSprite = ItemScene.spriteOf(kind);
        let sprite = Sprite2D.make(baseSprite#texture, Vec2.zero(), Vec2.one());
        let data: ItemScene.Data = {
            gridPos = cell,
            itemKey = "test-ground-item",
            item    = kind,
            elapsed = Duration.seconds(0.0)
        };
        Scene.addChildAt(ItemScene.parentPath(), "Item_0",
            EngineNode.Sprite2DWithState(sprite, NodeTag.GroundItem(data)), withParent)

    /// `loadTwoPlayerActionMenuScene()` に「id=0 の足下 (1,1) に床武器 1 本」を足した scene。
    /// 「ひろう」確定の挙動を観測するための統合フィクスチャ。
    def loadActionMenuSceneWithFloorWeapon(): Scene[NodeTag] =
        attachGroundItemAt({x = 1, y = 1},
            ItemScene.GroundItemKind.WeaponItem(TestUnitFixtures.testWeapon()),
            loadTwoPlayerActionMenuScene())

    /// runOnActionConfirm に渡す入力一式。
    /// 引数が多いので record にまとめて named-parameter sugar で呼び出せるようにする。
    ///
    /// フィールドの意味:
    ///   - `initialPhase`   : 確定前のフェーズ (通常は ActionSelect)
    ///   - `selectedId`     : 選択中味方の id
    ///   - `selectedOrigin` : 選択中味方の origin (キャンセル時の戻り位置 / 通常は現在位置と同じ)
    ///   - `scene`          : テスト対象 scene
    ///   - `entry`          : 確定する ItemList のエントリ (metadata で分岐を決める)
    type alias ActionConfirmArgs = {
        initialPhase   = TurnPhase.Phase,
        selectedId     = Int32,
        selectedOrigin = {x = Int32, y = Int32},
        scene          = Scene[NodeTag],
        entry          = ItemEntry
    }

    /// `onActionConfirmed` の 8 effect を一括でスタブして実行し、
    /// 最終 scene と最終 phase をタプルで返すテストランナー。
    ///
    /// 各 effect の振る舞い:
    ///   - Tween / Anim: 完全 no-op (TestUnitFixtures の既存ヘルパー)
    ///   - GameLogger / EnemyTurn.Queue: 完全 no-op (同上)
    ///   - PartyQuery / RosterQuery: 受け取った scene からそのまま読み返す
    ///   - SelectedPlayer.State: get は指定 id+origin を返し、put は捨てる
    ///   - TurnPhase.State: Ref-backed で put を観測可能 (戻り値タプルの 2 番目)
    def runOnActionConfirm(rc: Region[r], args: ActionConfirmArgs):
            (Scene[NodeTag], TurnPhase.Phase) \ r =
        let phaseRef: Ref[TurnPhase.Phase, r] = Ref.fresh(rc, args#initialPhase);
        let result = TestUnitFixtures.withNoopTween(() ->
            TestUnitFixtures.withNoopAnim(() ->
                TestUnitFixtures.withMockGameLogger(() ->
                    TestUnitFixtures.withMockEnemyTurnQueue(() ->
                        TestUnitFixtures.withMockPartyQuery(args#scene, () ->
                            TestUnitFixtures.withMockRosterQuery(args#scene, () ->
                                run {
                                    ActionMenuScene.onActionConfirmed(args#entry,
                                                                       args#scene)
                                } with handler SelectedPlayer.State {
                                    def get(k)    =
                                        k({id = Some(args#selectedId),
                                           origin = Some(args#selectedOrigin)})
                                    def put(_, k) = k()
                                } with handler TurnPhase.State {
                                    def get(k)         = k(Ref.get(phaseRef))
                                    def put(target, k) = {
                                        Ref.put(target, phaseRef);
                                        k()
                                    }
                                }))))));
        (result, Ref.get(phaseRef))

    // ════════════════════════════════════════════════════════
    // 既存「行動終了」アクション回帰テスト
    //
    // applyPickup の挙動を Step 1-C で変更するに先立ち、変更しない他アクションが
    // 「これまで通り」動くことを pin する。Step 1-C のリファクタが万一
    // commitWaitedAndAdvance に副作用を与えた場合、ここのいずれかが赤になって気づける。
    // ════════════════════════════════════════════════════════

    /// たいき (`waitMeta`) を確定すると:
    ///   - 選択中プレイヤー (id=0) の `waited` が true になる
    ///   - もう 1 人 (id=1) はそのままアクティブ (waited=false)
    ///   - 残りアクティブが居るのでフェーズは `PlayerCursor` に戻る (次セレクトへ)
    @Test
    def testWaitMarksSelectedAndAdvancesToPlayerCursor(): Unit \ Assert =
        region rc {
            let scene = loadTwoPlayerActionMenuScene();
            let waitEntry: ItemEntry =
                { text = "たいき", disabled = false, metadata = Some("wait") };
            let (after, finalPhase) = runOnActionConfirm(rc, {
                initialPhase   = TurnPhase.Phase.ActionSelect,
                selectedId     = 0,
                selectedOrigin = {x = 1, y = 1},
                scene          = scene,
                entry          = waitEntry
            });
            Assert.assertEq(
                expected = (TurnPhase.Phase.PlayerCursor, true, false),
                (finalPhase, waitedOf(0, after), waitedOf(1, after)))
        }

    /// ターンエンド (`turnEndMeta`) を確定すると:
    ///   - アクティブだった全味方 (id=0, id=1) が `waited = true` になる
    ///   - フェーズは敵ターン (`EnemyTurn`) へ進む
    /// しゅうごう (`gatherMeta`) と並ぶ「空マスメニュー」用アクションで、
    /// 集合メニュー以外からは到達しないが、内部的には選択中プレイヤーが
    /// None でも全員 waited にする経路で `EnemyTurnDriverScene.beginTurn` を呼ぶ。
    @Test
    def testTurnEndMarksAllAndAdvancesToEnemyTurn(): Unit \ Assert =
        region rc {
            let scene = loadTwoPlayerActionMenuScene();
            let turnEndEntry: ItemEntry =
                { text = "ターンエンド", disabled = false, metadata = Some("turnEnd") };
            // SelectedPlayer = None (空マスメニュー扱い) で起動する
            let (after, finalPhase) = runOnActionConfirm(rc, {
                initialPhase   = TurnPhase.Phase.ActionSelect,
                selectedId     = -1,
                selectedOrigin = {x = 0, y = 0},
                scene          = scene,
                entry          = turnEndEntry
            });
            Assert.assertEq(
                expected = (TurnPhase.Phase.EnemyTurn, true, true),
                (finalPhase, waitedOf(0, after), waitedOf(1, after)))
        }

    // ════════════════════════════════════════════════════════
    // Step 1-B: 新規「ひろう = 行動継続」テスト
    //
    // Step 1-C で applyPickup を「行動継続」に書き換える前提のテスト。
    // 実装変更前は赤になることを確認 (フェーズが ActionSelect から外れる /
    // waited が立つため)。Step 1-C 適用後に緑に転じる。
    // ════════════════════════════════════════════════════════

    /// ひろう (`pickupMeta`) を確定すると:
    ///   - フェーズが `ActionSelect` のまま (行動継続: ActionMenu に戻る)
    ///   - 選択中プレイヤーの `waited` は **false** のまま (ターン消費しない)
    ///   - 床アイテムが消える (拾った)
    ///   - 選択中プレイヤーの所持武器が 1 → 2 本に増える (拾った武器が末尾追加)
    @Test
    def testPickupKeepsActionSelectAndAddsItemToInventory(): Unit \ Assert =
        region rc {
            let scene = loadActionMenuSceneWithFloorWeapon();
            let pickupEntry: ItemEntry =
                { text = "ひろう", disabled = false, metadata = Some("pickup") };
            let (after, finalPhase) = runOnActionConfirm(rc, {
                initialPhase   = TurnPhase.Phase.ActionSelect,
                selectedId     = 0,
                selectedOrigin = {x = 1, y = 1},
                scene          = scene,
                entry          = pickupEntry
            });
            let groundItemStillThere =
                Option.nonEmpty(ItemScene.findAt({x = 1, y = 1}, after));
            // 期待: (ActionSelect 維持, waited 立たず, 床から消えた, 武器2本)
            Assert.assertEq(
                expected = (TurnPhase.Phase.ActionSelect, false, false, 2),
                ( finalPhase
                , waitedOf(0, after)
                , groundItemStillThere
                , weaponCountOf(0, after) ))
        }
}
