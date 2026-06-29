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
        classId         = "test_player",
        gridPos         = gridPos,
        moveTiles       = 4,
        hp              = 10,
        waited          = false,
        attackTargetId  = None,
        resource        = TestUnitFixtures.testResource(4, 10),
        weapons         = TestUnitFixtures.testWeapon() :: Nil,
        staves          = Nil,
        consumables     = Nil,
        selectedItem    = None,
        moveStepsTaken  = 0,
        facing          = Staff.Direction.Down,
        hidden          = false,
        usedStairs          = false,
        level                   = 1,
        exp                     = 0,
        pendingLevelUp          = None,
        statuses                = Nil,
        rings          = Nil,
        ringEquipped          = false,
        followUpUsed   = false
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
                            kind: ItemData.GroundItemKind,
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
            ItemData.GroundItemKind.WeaponItem(TestUnitFixtures.testWeapon()),
            loadTwoPlayerActionMenuScene())

    /// 「こうかん」項目の出現確認用フィクスチャ。id=0 を (1,1)、id=1 を (2,1) に置き、
    /// 上下左右で隣接する 2 人パーティ + ActionMenu を組む (manhattan=1)。
    def loadAdjacentPartyActionMenuScene(): Scene[NodeTag] =
        let world = Marker2D.make(Vec2.zero());
        let marker0 = Marker2D.make(Vec2.zero());
        let marker1 = Marker2D.make(Vec2.zero());
        let data0 = makePlayerData(0, {x = 1, y = 1});
        let data1 = makePlayerData(1, {x = 2, y = 1});
        let withWorld = Scene.empty()
            |> Scene.addNode(MapScene.worldName(),
                EngineNode.Marker2DWithState(world, NodeTag.NoTag))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(0),
                EngineNode.Marker2DWithState(marker0, NodeTag.Player(data0)))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(1),
                EngineNode.Marker2DWithState(marker1, NodeTag.Player(data1)));
        actionMenuAddPure(withWorld)

    /// runRefreshItems に渡す入力一式。
    /// 引数が多いので record にまとめて named-parameter sugar で呼び出せるようにする。
    ///
    /// フィールドの意味:
    ///   - `phase`          : refreshItems 中に観測させるフェーズ
    ///   - `selectedId`     : 選択中味方の id (refreshItems 内 buildItems から参照される)
    ///   - `selectedOrigin` : 選択中味方の origin (使われないが Selection を埋めるため)
    ///   - `scene`          : テスト対象 scene
    type alias RefreshArgs = {
        phase          = TurnPhase.Phase,
        selectedId     = Int32,
        selectedOrigin = {x = Int32, y = Int32},
        scene          = Scene[NodeTag]
    }

    /// `refreshItems` を 4 effect (SelectedPlayer / TurnPhase / PartyQuery / RosterQuery)
    /// 込みで実行し、更新後の scene を返す。
    /// `TurnPhase.State.put` は refreshItems からは呼ばれない前提で fixed 値固定。
    def runRefreshItems(args: RefreshArgs): Scene[NodeTag] =
        let menuNode = match Scene.getEngineNode(ActionMenuScene.menuPath(), args#scene) {
            case Some(node) => node
            case None       => bug!("ActionMenu ItemList not found")
        };
        let (_, after) = TestUnitFixtures.withMenuReadMocks(
            args#phase, args#selectedId, args#scene, () ->
                ActionMenuScene.refreshItems(
                    Duration.seconds(0.0),
                    menuNode,
                    ActionMenuScene.menuPath(),
                    args#scene));
        after

    /// scene 内 ActionMenu の ItemList から各エントリの metadata を順に取り出す。
    /// 「項目に X が含まれるか」を 1 タプルで pin するために使う。
    def itemsMetadata(scene: Scene[NodeTag]): List[Option[String]] =
        match Scene.getEngineNode(ActionMenuScene.menuPath(), scene) {
            case Some(EngineNode.ItemListWithState(list, _)) =>
                List.map(entry -> entry#metadata, ItemList.getItems(list))
            case _ => bug!("ActionMenu ItemList not found")
        }

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

    /// `onActionConfirmed` の 9 effect を一括でスタブして実行し、
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
        TestUnitFixtures.withWorldCommand(rc, () ->
        // P1a: 確定経路（gatherStairs→StairsExit.begin）が BoardQuery を読むので mock board を供給。
        TestUnitFixtures.withMockBoard(BoardSnapshot.fromScene(args#scene), () ->
        TestUnitFixtures.withPhaseRef(rc, args#initialPhase, () ->
            TestUnitFixtures.withNoopTween(() ->
                TestUnitFixtures.withNoopAnim(() ->
                    TestUnitFixtures.withMockGameLogger(() ->
                        TestUnitFixtures.withMockEnemyTurnQueue(() ->
                            TestUnitFixtures.withMockPartyQuery(args#scene, () ->
                                TestUnitFixtures.withMockRosterQuery(args#scene, () ->
                                  TestUnitFixtures.withMockAudio(() ->
                                    TestUnitFixtures.withNoopFloorAdvance(() ->
                                      TestUnitFixtures.withMockGatherResume(() ->
                                        TestUnitFixtures.withSelectedPlayer(args#selectedId, () ->
                                          ActionMenuScene.onActionConfirmed(args#entry,
                                                                            args#scene))))))))))))))

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

    /// 「ひろう」で拾った後に選択解除キャンセル (cancelSelection) すると拾得が巻き戻る:
    ///   - 床アイテムが (1,1) に戻る
    ///   - 仮取得した武器が在庫から取り消され 2 → 1 本に戻る
    /// SelectedPlayer を Ref で持ち、pickup が立てた picked ドラフトが cancel まで残る
    /// 実プレイ経路を再現する (runOnActionConfirm は put を捨てるのでここは専用ランナー)。
    @Test
    def testPickupThenCancelSelectionRevertsPickup(): Unit \ Assert =
        region rc {
            let scene = loadActionMenuSceneWithFloorWeapon();
            let pickupEntry: ItemEntry =
                { text = "ひろう", disabled = false, metadata = Some("pickup") };
            let after = TestUnitFixtures.withWorldCommand(rc, () ->
                TestUnitFixtures.withMockBoard(BoardSnapshot.fromScene(scene), () ->
                TestUnitFixtures.withNoopTween(() ->
                TestUnitFixtures.withNoopAnim(() ->
                    TestUnitFixtures.withMockGameLogger(() ->
                        TestUnitFixtures.withMockEnemyTurnQueue(() ->
                            TestUnitFixtures.withMockPartyQuery(scene, () ->
                                TestUnitFixtures.withMockRosterQuery(scene, () ->
                                  TestUnitFixtures.withMockAudio(() ->
                                    TestUnitFixtures.withFixedPhase(TurnPhase.Phase.ActionSelect, () ->
                                      TestUnitFixtures.withNoopFloorAdvance(() ->
                                        TestUnitFixtures.withMockGatherResume(() ->
                                          TestUnitFixtures.withSelectionRef(rc,
                                            {id = Some(0), drafts = Nil, gatherActive = false}, () -> {
                                                let afterPick =
                                                    ActionMenuScene.onActionConfirmed(pickupEntry, scene);
                                                PlayerScene.cancelSelection(afterPick)
                                            })))))))))))));
            let groundItemBack =
                Option.nonEmpty(ItemScene.findAt({x = 1, y = 1}, after));
            // 期待: (床に戻った, 武器が 1 本に戻った)
            Assert.assertEq(
                expected = (true, 1),
                (groundItemBack, weaponCountOf(0, after)))
        }

    // ════════════════════════════════════════════════════════
    // 移動着地の自動取得（PlayerMovementScene.autoPickupOrLog）
    //   「乗るだけ」でなく重量が許す限り基本拾う。過多になるなら拾わず床に残す。
    //   ここの床アイテム/武器数フィクスチャ（loadActionMenuSceneWithFloorWeapon 他）を再利用。
    // ════════════════════════════════════════════════════════

    /// scene から id のプレイヤー Data を取り出す（居なければテストを潰す）。
    def playerDataOf(id: Int32, scene: Scene[NodeTag]): PlayerScene.Data =
        match PlayerScene.get(id, scene) {
            case Some(d) => d
            case None    => bug!("player ${id} not found")
        }

    /// 着地マス (1,1) の床武器を、重量が許すので **自動で拾う**:
    ///   - 床アイテムが消える
    ///   - id=0 の所持武器が 1 → 2 本（積載 8.6 に対し剣 2 本=3.8 で余裕）
    /// 「乗っただけで拾わない」旧仕様からの変更点を固定する。
    @Test
    def testAutoPickupPicksUpWhenWeightAllows(): Unit \ Assert =
        let scene = loadActionMenuSceneWithFloorWeapon();
        let data  = playerDataOf(0, scene);
        let after = TestUnitFixtures.withMockGameLogger(() ->
            TestUnitFixtures.withSelectedPlayer(0, () ->
                TestUnitFixtures.dischargeWorldCommand(() ->
                    PlayerMovementScene.autoPickupOrLog(data, {x = 1, y = 1}, scene))));
        let floorEmpty = Option.isEmpty(ItemScene.findAt({x = 1, y = 1}, after));
        Assert.assertEq(
            expected = (true, 2),
            (floorEmpty, weaponCountOf(0, after)))

    /// 拾うと積載過多（移動不可）になるなら、着地しても **拾わず床に残す**:
    ///   id=0 に剣を 3 本足して計 4 本（積載 7.6 / 容量 8.6）。床の 5 本目(1.9)を拾うと
    ///   9.5 = 110%+ で Immobile になるため自動取得しない。床アイテムは残り、武器は 4 本のまま。
    @Test
    def testAutoPickupSkipsWhenWouldOverload(): Unit \ Assert =
        let w    = TestUnitFixtures.testWeapon();
        let heavy = TestUnitFixtures.dischargeWorldCommand(() ->
            loadActionMenuSceneWithFloorWeapon()
                |> PlayerScene.addWeapon(0, w)
                |> PlayerScene.addWeapon(0, w)
                |> PlayerScene.addWeapon(0, w));
        let data  = playerDataOf(0, heavy);
        let after = TestUnitFixtures.withMockGameLogger(() ->
            TestUnitFixtures.withSelectedPlayer(0, () ->
                TestUnitFixtures.dischargeWorldCommand(() ->
                    PlayerMovementScene.autoPickupOrLog(data, {x = 1, y = 1}, heavy))));
        let floorStillThere = Option.nonEmpty(ItemScene.findAt({x = 1, y = 1}, after));
        Assert.assertEq(
            expected = (true, 4),
            (floorStillThere, weaponCountOf(0, after)))

    /// 着地の自動取得は移動キャンセルで巻き戻せる（`pickupFloorItem` が `PickedUp` ドラフトを
    /// 積むこと）を pin する。**Ref-backed の `withSelectionRef`** で drafts を保持し、
    /// autoPickupOrLog → `cancelSelection` 後に床アイテムが (1,1) に戻り武器が 2 → 1 本に戻る。
    /// （put を捨てる `withSelectedPlayer` だと pushDraft が消えてこの巻き戻しを検証できない＝
    ///  pushDraft 行を消してもグリーンになってしまうので、ここは Ref で本経路を再現する。）
    @Test
    def testAutoPickupThenCancelSelectionRevertsPickup(): Unit \ Assert =
        region rc {
            let scene = loadActionMenuSceneWithFloorWeapon();
            let data  = playerDataOf(0, scene);
            let after = TestUnitFixtures.withNoopTween(() ->
                TestUnitFixtures.withNoopAnim(() ->
                    TestUnitFixtures.withMockGameLogger(() ->
                        TestUnitFixtures.withMockPartyQuery(scene, () ->
                            TestUnitFixtures.withFixedPhase(TurnPhase.Phase.PlayerMoving, () ->
                                TestUnitFixtures.withSelectionRef(rc,
                                    {id = Some(0), drafts = Nil, gatherActive = false}, () ->
                                        TestUnitFixtures.dischargeWorldCommand(() -> {
                                            let picked =
                                                PlayerMovementScene.autoPickupOrLog(data, {x = 1, y = 1}, scene);
                                            PlayerScene.cancelSelection(picked)
                                        })))))));
            let groundItemBack = Option.nonEmpty(ItemScene.findAt({x = 1, y = 1}, after));
            Assert.assertEq(
                expected = (true, 1),
                (groundItemBack, weaponCountOf(0, after)))
        }

    // ════════════════════════════════════════════════════════
    // 装備 / 捨てる の巻き戻し（移動中の仮アクションを逆順 revert）
    //   各アクションを積み、cancelSelection が新しい順に逆操作することを検証する。
    // ════════════════════════════════════════════════════════

    /// World + 単一プレイヤー(id0) で weapons を指定した最小 scene（巻き戻し検証用）。
    def loadPlayerWithWeapons(pos: {x = Int32, y = Int32},
                                weapons: List[UnitCatalog.WeaponResource]): Scene[NodeTag] =
        let world = Marker2D.make(Vec2.zero());
        let data  = {weapons = weapons | makePlayerData(0, pos)};
        Scene.empty()
            |> Scene.addNode(MapScene.worldName(),
                EngineNode.Marker2DWithState(world, NodeTag.NoTag))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(0),
                EngineNode.Marker2DWithState(Marker2D.make(Vec2.zero()), NodeTag.Player(data)))

    /// 与えた drafts を SelectedPlayer に載せて `cancelSelection` を実行するランナー。
    /// cancelSelection の 5 effect (Tween/Anim/TurnPhase/SelectedPlayer/PartyQuery) をスタブ。
    def runCancelWithDrafts(rc: Region[r], scene: Scene[NodeTag],
                              drafts: List[MoveDraft.DraftAction]):
            Scene[NodeTag] \ r =
        TestUnitFixtures.withSelectionRef(rc,
            {id = Some(0), drafts = drafts, gatherActive = false}, () ->
                TestUnitFixtures.withNoopTween(() ->
                    TestUnitFixtures.withNoopAnim(() ->
                        TestUnitFixtures.withMockPartyQuery(scene, () ->
                            TestUnitFixtures.withFixedPhase(TurnPhase.Phase.ActionSelect, () ->
                                TestUnitFixtures.dischargeWorldCommand(() ->
                                    PlayerScene.cancelSelection(scene)))))))

    /// 報告バグの回帰: 拾得 → 装備 → 選択解除キャンセル で、装備の並び替えも拾得も
    /// 正しく巻き戻る（元の武器 A が残り、拾った B は床へ復活）。逆順 revert により
    /// 装備を先に戻すので `PickedUp` の末尾削除も正しい物（B）を消す。
    @Test
    def testEquipAfterPickupThenCancelRevertsBoth(): Unit \ Assert =
        region rc {
            let wA = TestUnitFixtures.testWeaponFull(5, 10);    // 元々持っていた武器
            let wB = TestUnitFixtures.testWeaponFull(99, 10);   // 拾って装備した武器
            // 拾得+装備後の状態: weapons=[B, A]（B を先頭に装備）、床アイテムは取得済みで無し
            let scene = loadPlayerWithWeapons({x = 1, y = 1}, wB :: wA :: Nil);
            // 積んだ順(古→新): MovedFrom, PickedUp, Equipped。drafts は新しい順で保持。
            let drafts =
                MoveDraft.DraftAction.Equipped(0, 1) ::
                MoveDraft.DraftAction.PickedUp(0, {x = 1, y = 1}, "wB",
                    ItemData.GroundItemKind.WeaponItem(wB)) ::
                MoveDraft.DraftAction.MovedFrom(0, {x = 1, y = 1}) :: Nil;
            let after   = runCancelWithDrafts(rc, scene, drafts);
            let attacks = List.map(w -> w#attack, PlayerScene.getWeapons(0, after));
            let floorB  = Option.nonEmpty(ItemScene.findAt({x = 1, y = 1}, after));
            // 期待: weapons=[A](attack 5) のみ・B が床に復活
            Assert.assertEq(expected = (5 :: Nil, true), (attacks, floorB))
        }

    /// 中央の武器を捨ててからキャンセルすると、元の idx に正確に戻る（順序保持）。
    @Test
    def testDropThenCancelRestoresItemAtIndex(): Unit \ Assert =
        region rc {
            let wA = TestUnitFixtures.testWeaponFull(1, 10);
            let wB = TestUnitFixtures.testWeaponFull(2, 10);
            let wC = TestUnitFixtures.testWeaponFull(3, 10);
            // B(idx1) を捨てた後の状態: weapons=[A, C]
            let scene = loadPlayerWithWeapons({x = 2, y = 2}, wA :: wC :: Nil);
            let drafts =
                MoveDraft.DraftAction.Dropped(0, PlayerData.ItemKind.Weapon(1),
                    ItemData.GroundItemKind.WeaponItem(wB)) ::
                MoveDraft.DraftAction.MovedFrom(0, {x = 2, y = 2}) :: Nil;
            let after   = runCancelWithDrafts(rc, scene, drafts);
            let attacks = List.map(w -> w#attack, PlayerScene.getWeapons(0, after));
            // 期待: [A, B, C]（attack 1,2,3）に元 idx で復元
            Assert.assertEq(expected = 1 :: 2 :: 3 :: Nil, attacks)
        }

    // ════════════════════════════════════════════════════════
    // Phase 2: 「こうかん」項目の表示制御
    //
    // 隣接味方が居る × ActionSelect 中 → ActionMenu に「こうかん」が出る。
    // 隣接味方が居なければ「こうかん」は出ない。
    // ════════════════════════════════════════════════════════

    /// id=0 が (1,1)、id=1 が (2,1) の隣接配置のとき、ActionSelect 中の refreshItems で
    /// 「こうかん」エントリ (metadata = "exchange") が**選択可能**で出る。
    @Test
    def testExchangeItemEnabledWhenAdjacentAllyExists(): Unit \ Assert =
        let scene = loadAdjacentPartyActionMenuScene();
        let after = runRefreshItems({
            phase          = TurnPhase.Phase.ActionSelect,
            selectedId     = 0,
            selectedOrigin = {x = 1, y = 1},
            scene          = scene
        });
        // 出現する（Some）かつ選択可能（false）= Some(false)。
        Assert.assertEq(expected = Some(false), entryDisabledOf("exchange", after))

    /// id=0 が (1,1)、id=1 が (3,3) の非隣接配置 (manhattan=4) でも「こうかん」は**常に出る**が、
    /// 隣接味方が居ないので disabled=true（敵にだけ隣接していても同様）。
    @Test
    def testExchangeItemDisabledWhenNoAdjacentAlly(): Unit \ Assert =
        let scene = loadTwoPlayerActionMenuScene();
        let after = runRefreshItems({
            phase          = TurnPhase.Phase.ActionSelect,
            selectedId     = 0,
            selectedOrigin = {x = 1, y = 1},
            scene          = scene
        });
        // 出現する（Some）かつ選択不可（true）= Some(true)。
        Assert.assertEq(expected = Some(true), entryDisabledOf("exchange", after))

    /// 指定 metadata のエントリの disabled フラグを返す（見つからなければ None）。
    def entryDisabledOf(meta: String, scene: Scene[NodeTag]): Option[Bool] =
        match Scene.getEngineNode(ActionMenuScene.menuPath(), scene) {
            case Some(EngineNode.ItemListWithState(list, _)) =>
                ItemList.getItems(list)
                    |> List.findLeft(e -> e#metadata == Some(meta))
                    |> Option.map(e -> e#disabled)
            case _ => None
        }

    /// 「攻撃」は敵が射程外でも常にメニューに出る。ただし射程内に敵が居ないので disabled=true。
    /// loadTwoPlayerActionMenuScene は敵が居ない（id=0,1 のみ）ので canAttackFrom=false。
    @Test
    def testAttackAlwaysShownDisabledWhenNoTarget(): Unit \ Assert =
        let scene = loadTwoPlayerActionMenuScene();
        let after = runRefreshItems({
            phase          = TurnPhase.Phase.ActionSelect,
            selectedId     = 0,
            selectedOrigin = {x = 1, y = 1},
            scene          = scene
        });
        // 出現する（Some）かつ選択不可（true）= Some(true)。
        Assert.assertEq(expected = Some(true), entryDisabledOf("attack", after))

    /// SelectedPlayer なし（空マスメニュー）で refreshItems を回すランナー。
    def runRefreshItemsNoSel(scene: Scene[NodeTag]): Scene[NodeTag] =
        let menuNode = match Scene.getEngineNode(ActionMenuScene.menuPath(), scene) {
            case Some(node) => node
            case None       => bug!("ActionMenu ItemList not found")
        };
        let (_, after) = TestUnitFixtures.withMenuReadMocksNoSel(
            TurnPhase.Phase.ActionSelect, scene, () ->
                ActionMenuScene.refreshItems(
                    Duration.seconds(0.0), menuNode, ActionMenuScene.menuPath(), scene));
        after

    /// loadTwoPlayerActionMenuScene と同じだが主人公(id=0)を行動済み(waited=true)にした scene。
    def loadWaitedLordScene(): Scene[NodeTag] =
        let world = Marker2D.make(Vec2.zero());
        let marker0 = Marker2D.make(Vec2.zero());
        let marker1 = Marker2D.make(Vec2.zero());
        let lord = { waited = true | makePlayerData(0, {x = 1, y = 1}) };
        let ally = makePlayerData(1, {x = 3, y = 3});
        let withWorld = Scene.empty()
            |> Scene.addNode(MapScene.worldName(),
                EngineNode.Marker2DWithState(world, NodeTag.NoTag))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(0),
                EngineNode.Marker2DWithState(marker0, NodeTag.Player(lord)))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(1),
                EngineNode.Marker2DWithState(marker1, NodeTag.Player(ally)));
        actionMenuAddPure(withWorld)

    /// 空マスメニュー: 主人公が未行動 + 別の生存味方が居れば「集合」は選択可能。
    @Test
    def testGatherEnabledWhenLordActiveWithAlly(): Unit \ Assert =
        let after = runRefreshItemsNoSel(loadTwoPlayerActionMenuScene());
        Assert.assertEq(expected = Some(false), entryDisabledOf("gather", after))

    /// 空マスメニュー: 主人公が行動済み(waited)なら「集合」は出るが disabled。
    @Test
    def testGatherDisabledWhenLordWaited(): Unit \ Assert =
        let after = runRefreshItemsNoSel(loadWaitedLordScene());
        Assert.assertEq(expected = Some(true), entryDisabledOf("gather", after))

    // ════════════════════════════════════════════════════════
    // 集合（行軍）の隣接メニュー (gatherActive=true × 主人公選択中)
    //   主人公に隣接する味方が居れば「交換」、常に「全員待機」。
    //   隣接味方が居なければ「交換」は出さない（仕様 6）。
    // ════════════════════════════════════════════════════════

    /// World + 主人公(id0, (1,1)) + 味方(id1, allyPos) + ActionMenu。
    /// allyPos を主人公の隣 ((2,1)) にすれば「隣接味方あり」、離せば「なし」を表す。
    def loadGatherMenuScene(allyPos: {x = Int32, y = Int32}): Scene[NodeTag] =
        let world = Marker2D.make(Vec2.zero());
        let m0 = Marker2D.make(Vec2.zero());
        let m1 = Marker2D.make(Vec2.zero());
        let lord = makePlayerData(0, {x = 1, y = 1});
        let ally = makePlayerData(1, allyPos);
        let withWorld = Scene.empty()
            |> Scene.addNode(MapScene.worldName(),
                EngineNode.Marker2DWithState(world, NodeTag.NoTag))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(0),
                EngineNode.Marker2DWithState(m0, NodeTag.Player(lord)))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(1),
                EngineNode.Marker2DWithState(m1, NodeTag.Player(ally)));
        actionMenuAddPure(withWorld)

    /// gatherActive=true・主人公選択中・ActionSelect で refreshItems を回すランナー
    /// (集合の隣接メニューの項目構築を観測する用)。
    def runRefreshItemsGather(scene: Scene[NodeTag]): Scene[NodeTag] =
        let menuNode = match Scene.getEngineNode(ActionMenuScene.menuPath(), scene) {
            case Some(node) => node
            case None       => bug!("ActionMenu ItemList not found")
        };
        let (_, after) = TestUnitFixtures.withMenuReadMocksGather(scene, () ->
            ActionMenuScene.refreshItems(
                Duration.seconds(0.0), menuNode,
                ActionMenuScene.menuPath(), scene));
        after

    /// 主人公に隣接する味方((2,1)) が居れば、隣接メニューは「交換 → 全員待機」。
    @Test
    def testGatherAdjacentMenuShowsTradeWithAdjacentAlly(): Unit \ Assert =
        let after = runRefreshItemsGather(loadGatherMenuScene({x = 2, y = 1}));
        Assert.assertEq(
            expected = Some("gatherTrade") :: Some("waitAll") :: Nil,
            itemsMetadata(after))

    /// 隣接する味方が居なければ((5,5))、「交換」は出さず「全員待機」だけ（仕様 6）。
    @Test
    def testGatherAdjacentMenuHidesTradeWithoutAdjacentAlly(): Unit \ Assert =
        let after = runRefreshItemsGather(loadGatherMenuScene({x = 5, y = 5}));
        Assert.assertEq(
            expected = Some("waitAll") :: Nil,
            itemsMetadata(after))

    /// 配置済み(placed)の階段ノードを `cell` に置いたシーンを返す（JSON ロードを介さず直接構築）。
    def withStairsAt(cell: {x = Int32, y = Int32}, scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
            |> Scene.addNode("Stairs",
                EngineNode.Marker2DWithState(Marker2D.make(Vec2.zero()),
                    NodeTag.Stairs(({gridPos = cell, placed = true}: StairsScene.Data))))

    /// 主人公(1,1)の足元に床アイテムがあると、集合メニューの先頭に「拾う」が出る
    /// （非隣接味方(5,5)なので交換は無し）。
    @Test
    def testGatherMenuShowsPickupWhenItemUnderLord(): Unit \ Assert =
        let after = runRefreshItemsGather(
            attachGroundItemAt({x = 1, y = 1},
                ItemData.GroundItemKind.WeaponItem(TestUnitFixtures.testWeapon()),
                loadGatherMenuScene({x = 5, y = 5})));
        Assert.assertEq(
            expected = Some("pickup") :: Some("waitAll") :: Nil,
            itemsMetadata(after))

    /// 主人公(1,1)が階段マスに立っているときだけ集合メニューに「階段」が出る。
    @Test
    def testGatherMenuShowsStairsWhenLordOnStairs(): Unit \ Assert =
        let after = runRefreshItemsGather(
            withStairsAt({x = 1, y = 1}, loadGatherMenuScene({x = 5, y = 5})));
        Assert.assertEq(
            expected = Some("gatherStairs") :: Some("waitAll") :: Nil,
            itemsMetadata(after))

    /// 階段が別マス(5,5)にあっても主人公(1,1)が乗っていなければ「階段」は出さない
    /// （canExit の到達判定ではなく足元判定であることを固定する）。
    @Test
    def testGatherMenuHidesStairsWhenLordOffStairs(): Unit \ Assert =
        let after = runRefreshItemsGather(
            withStairsAt({x = 5, y = 5}, loadGatherMenuScene({x = 5, y = 5})));
        Assert.assertEq(
            expected = Some("waitAll") :: Nil,
            itemsMetadata(after))

    /// 足元アイテム + 階段上 + 隣接味方が揃うと固定順「拾う → 階段 → 交換 → 全員待機」。
    @Test
    def testGatherMenuFullOrder(): Unit \ Assert =
        let after = runRefreshItemsGather(
            loadGatherMenuScene({x = 2, y = 1})
                |> attachGroundItemAt({x = 1, y = 1},
                    ItemData.GroundItemKind.WeaponItem(TestUnitFixtures.testWeapon()))
                |> withStairsAt({x = 1, y = 1}));
        Assert.assertEq(
            expected = Some("pickup") :: Some("gatherStairs") :: Some("gatherTrade")
                        :: Some("waitAll") :: Nil,
            itemsMetadata(after))

    // ════════════════════════════════════════════════════════
    // 「集合」確定のリーダー行動済みガード（仕様3）
    // ════════════════════════════════════════════════════════

    /// World + 主人公(id0,(1,1)) + 味方(id1,(3,3))。lordWaited で主人公の waited を切り替える。
    def loadGatherStartScene(lordWaited: Bool): Scene[NodeTag] =
        let world = Marker2D.make(Vec2.zero());
        let m0 = Marker2D.make(Vec2.zero());
        let m1 = Marker2D.make(Vec2.zero());
        let lord = {waited = lordWaited | makePlayerData(0, {x = 1, y = 1})};
        let ally = makePlayerData(1, {x = 3, y = 3});
        let withWorld = Scene.empty()
            |> Scene.addNode(MapScene.worldName(),
                EngineNode.Marker2DWithState(world, NodeTag.NoTag))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(0),
                EngineNode.Marker2DWithState(m0, NodeTag.Player(lord)))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(1),
                EngineNode.Marker2DWithState(m1, NodeTag.Player(ally)));
        actionMenuAddPure(withWorld)

    /// 「集合」確定: 主人公(リーダー)が既に行動済み(waited)なら開始せず ActionSelect に留まる
    /// （ログ「リーダーは既に行動済みです。」を出すが、ここでは遷移しないことを確認）。
    /// （アクティブ時の GatherMove 遷移は overlay/cursor/map ノードを要する統合経路なので実機側で確認）。
    @Test
    def testGatherBlockedWhenLeaderWaited(): Unit \ Assert =
        region rc {
            let gatherEntry: ItemEntry =
                { text = "集合", disabled = false, metadata = Some("gather") };
            let (_, finalPhase) = runOnActionConfirm(rc, {
                initialPhase   = TurnPhase.Phase.ActionSelect,
                selectedId     = 0,
                selectedOrigin = {x = 1, y = 1},
                scene          = loadGatherStartScene(true),
                entry          = gatherEntry
            });
            Assert.assertEq(expected = TurnPhase.Phase.ActionSelect, finalPhase)
        }

    // ════════════════════════════════════════════════════════
    // 再スキン: 幾何結合の pin（menu pos.y == menuHeaderPadding 真理値 8.0）
    // ════════════════════════════════════════════════════════

    /// scene.json をロードした後の menu pos.y が menuHeaderPadding の真理値 8.0 と一致する。
    /// fontSize 変更でヘッダ高が変わったら scene.json の menu pos.y と menuHeaderPadding の
    /// 両方を直す必要があり、片方だけ直すと赤になる。
    @Test
    def testMenuOriginMatchesHeaderPadding(): Unit \ Assert =
        let scene = actionMenuAddPure(Scene.empty());
        let menuPosY = ItemList.getAt(ActionMenuScene.menuPath(), scene)
            |> Option.map(l -> Node2D.getPosition(l)#y);
        Assert.assertEq(expected = Some(8.0), menuPosY)

    // ════════════════════════════════════════════════════════
    // 再スキン: 色二重管理の enforcement（scene.json 実ロード値 == UITheme）
    // ════════════════════════════════════════════════════════

    /// Color を比較可能な (Float32, Float32, Float32) タプルに開く（Color には ToString が無い）。
    def rgbOf(c: {r = Float32, g = Float32, b = Float32}): (Float32, Float32, Float32) =
        (c#r, c#g, c#b)

    /// scene.json をロードし parse 後の Color を UITheme と突き合わせる。
    /// 真理点は UITheme。片方だけ変えると赤になる。
    @Test
    def testSceneJsonColorsMatchTheme(): Unit \ Assert =
        let scene = actionMenuAddPure(Scene.empty());
        let panelBg = Panel.getAt(ActionMenuScene.panelPath(), scene)
            |> Option.map(p -> rgbOf(Panel.getBackgroundColor(p)));
        // パネル枠（暗いスレート）も pin。
        let panelBorder = Panel.getAt(ActionMenuScene.panelPath(), scene)
            |> Option.map(p -> rgbOf(Panel.getBorderColor(p)));
        // header の見出し色（淡い青 #9cc0ff）を pin。白等へ戻ると赤になる。
        let headerColor = Label2D.getAt(ActionMenuScene.headerPath(), scene)
            |> Option.map(h -> rgbOf(CanvasItem.getModulate(h)));
        // 選択ハイライトの fillColor（暗藍 #16314f）と borderColor（allyBlue）を両方 pin。
        let selFill = ItemList.getAt(ActionMenuScene.menuPath(), scene)
            |> Option.flatMap(l -> ItemList.getSelectedHighlight(l)#fillColor)
            |> Option.map(rgbOf);
        let selBorder = ItemList.getAt(ActionMenuScene.menuPath(), scene)
            |> Option.map(l -> rgbOf(ItemList.getSelectedHighlight(l)#borderColor));
        // 全行チップ（rowHighlight）の塗り #0e1626 と枠 #1c2533 も pin。
        let rowFill = ItemList.getAt(ActionMenuScene.menuPath(), scene)
            |> Option.flatMap(l -> ItemList.getRowHighlight(l)#fillColor)
            |> Option.map(rgbOf);
        let rowBorder = ItemList.getAt(ActionMenuScene.menuPath(), scene)
            |> Option.map(l -> rgbOf(ItemList.getRowHighlight(l)#borderColor));
        Assert.assertEq(
            expected = (Some(rgbOf(UITheme.panel())), Some(rgbOf(UITheme.panelBorder())),
                        Some(rgbOf(UITheme.headerText())),
                        Some(rgbOf(UITheme.selectBg())), Some(rgbOf(UITheme.allyBlue())),
                        Some(rgbOf(UITheme.rowBg())), Some(rgbOf(UITheme.rowBorder()))),
            (panelBg, panelBorder, headerColor, selFill, selBorder, rowFill, rowBorder))

    // ════════════════════════════════════════════════════════
    // onActionCancelled — メニューを閉じる X が戻り先フェーズの cursor を必ず確立する
    //   （武器/アイテム/交換でカーソルを隠したまま戻ると操作不能になる既知バグの回帰防止）
    // ════════════════════════════════════════════════════════

    /// Cursor ノード 1 個だけを持つ最小 scene（visible を指定）。
    /// `onActionCancelled` が委譲する `enter*` はレンジ消去・showAllActive・snap など
    /// 不在ノードに対しては no-op なので、cursor の visible 観測にはこれで十分。
    def sceneWithCursor(visible: Bool): Scene[NodeTag] =
        let cursorData: CursorScene.Data = {
            gridPos            = {x = 1, y = 1},
            lastHoveredEnemyId = None,
            holdDir            = None,
            holdSteps          = 0
        };
        Scene.empty()
            |> Scene.addNode("Cursor",
                EngineNode.Marker2DWithState(Marker2D.make(Vec2.zero()), NodeTag.Cursor(cursorData)))
            |> CursorScene.setVisible(visible)

    /// 空マスメニュー由来（SelectedPlayer = None）でメニューに入り、武器/アイテム/交換が
    /// カーソルを隠した状態（initial = hidden）で X を押す回帰テスト。
    /// 修正前は `onActionCancelled` が `put(PlayerCursor)` だけして scene を素通しするため
    /// カーソルが隠れたまま＝「カーソル消失・操作不能」状態になった（このテストは失敗する）。
    /// 修正後は `enterPlayerCursor` へ委譲し、PlayerCursor かつカーソル **再表示** になる。
    @Test
    def testActionCancelFromEmptyCellRestoresCursor(): Unit \ Assert =
        let initial = sceneWithCursor(false);   // 交換/アイテムでカーソルが隠れた状態を再現
        let (after, finalPhase) =
            TestUnitFixtures.withCancelTransitionMocks(SelectedPlayer.cleared(), () ->
                ActionMenuScene.onActionCancelled(initial));
        Assert.assertEq(
            expected = (TurnPhase.Phase.PlayerCursor, true),
            (finalPhase, TestUnitFixtures.readCursorVisible(after)))

    /// 駒選択中（SelectedPlayer = Some(0)）でメニューに入って X を押すと PlayerMoving へ
    /// 戻る。PlayerMoving のカーソルは設計上 **非表示**（駒を WASD で動かす＝青マスが操作面）
    /// なので、これは半端状態ではない。`enterPlayerMoving` 経由で visible=false に確立される
    /// ことを pin する（put 素通しなら initial の true が残って崩れる）。
    @Test
    def testActionCancelWithSelectionReturnsToMovingHidden(): Unit \ Assert =
        let initial = sceneWithCursor(true);
        let (after, finalPhase) =
            TestUnitFixtures.withCancelTransitionMocks(
                {id = Some(0), drafts = Nil, gatherActive = false}, () ->
                ActionMenuScene.onActionCancelled(initial));
        Assert.assertEq(
            expected = (TurnPhase.Phase.PlayerMoving, false),
            (finalPhase, TestUnitFixtures.readCursorVisible(after)))

    /// 集合（行軍）の隣接メニュー（gatherActive=true）で X を押すと GatherMove へ戻る。
    /// GatherMove のカーソルも設計上 **非表示**（主人公は自分の physicsProcess で動く）。
    /// `enterGatherMove` 経由で phase=GatherMove / cursor=false に確立されることを pin。
    @Test
    def testActionCancelGatherReturnsToGatherMoveHidden(): Unit \ Assert =
        let initial = sceneWithCursor(true);
        let (after, finalPhase) =
            TestUnitFixtures.withCancelTransitionMocks(
                {id = Some(0), drafts = Nil, gatherActive = true}, () ->
                ActionMenuScene.onActionCancelled(initial));
        Assert.assertEq(
            expected = (TurnPhase.Phase.GatherMove, false),
            (finalPhase, TestUnitFixtures.readCursorVisible(after)))
}
