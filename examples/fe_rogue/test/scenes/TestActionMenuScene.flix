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
        consumables     = Nil,
        selectedItem    = None,
        moveStepsTaken  = 0,
        facing          = Staff.Direction.Down,
        hidden          = false,
        usedStairs          = false,
        level                   = 1,
        exp                     = 0,
        pendingLevelUp          = None
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
        let (_, after) = TestUnitFixtures.withMockPartyQuery(args#scene, () ->
            TestUnitFixtures.withMockRosterQuery(args#scene, () ->
                run {
                    ActionMenuScene.refreshItems(
                        Duration.seconds(0.0),
                        menuNode,
                        ActionMenuScene.menuPath(),
                        args#scene)
                } with handler SelectedPlayer.State {
                    def get(k)    = k({id = Some(args#selectedId), drafts = Nil})
                    def put(_, k) = k()
                } with handler TurnPhase.State {
                    def get(k)    = k(args#phase)
                    def put(_, k) = k()
                }));
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
                                        k({id = Some(args#selectedId), drafts = Nil})
                                    def put(_, k) = k()
                                } with handler TurnPhase.State {
                                    def get(k)         = k(Ref.get(phaseRef))
                                    def put(target, k) = {
                                        Ref.put(target, phaseRef);
                                        k()
                                    }
                                } with handler CustomEffects.FloorAdvanceRequest {
                                    // 既存の回帰テストは「かいだん」分岐を踏まないので no-op で十分。
                                    def advance(scene, k) = k(scene)
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
            let selRef = Ref.fresh(rc,
                ({id = Some(0), drafts = Nil}: SelectedPlayer.Selection));
            let pickupEntry: ItemEntry =
                { text = "ひろう", disabled = false, metadata = Some("pickup") };
            let after = TestUnitFixtures.withNoopTween(() ->
                TestUnitFixtures.withNoopAnim(() ->
                    TestUnitFixtures.withMockGameLogger(() ->
                        TestUnitFixtures.withMockEnemyTurnQueue(() ->
                            TestUnitFixtures.withMockPartyQuery(scene, () ->
                                TestUnitFixtures.withMockRosterQuery(scene, () ->
                                    run {
                                        let afterPick =
                                            ActionMenuScene.onActionConfirmed(pickupEntry, scene);
                                        PlayerScene.cancelSelection(afterPick)
                                    } with handler SelectedPlayer.State {
                                        def get(k)    = k(Ref.get(selRef))
                                        def put(s, k) = { Ref.put(s, selRef); k() }
                                    } with handler TurnPhase.State {
                                        def get(k)    = k(TurnPhase.Phase.ActionSelect)
                                        def put(_, k) = k()
                                    } with handler CustomEffects.FloorAdvanceRequest {
                                        def advance(s, k) = k(s)
                                    }))))));
            let groundItemBack =
                Option.nonEmpty(ItemScene.findAt({x = 1, y = 1}, after));
            // 期待: (床に戻った, 武器が 1 本に戻った)
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
        let selRef = Ref.fresh(rc,
            ({id = Some(0), drafts = drafts}: SelectedPlayer.Selection));
        TestUnitFixtures.withNoopTween(() ->
            TestUnitFixtures.withNoopAnim(() ->
                TestUnitFixtures.withMockPartyQuery(scene, () ->
                    run {
                        PlayerScene.cancelSelection(scene)
                    } with handler SelectedPlayer.State {
                        def get(k)    = k(Ref.get(selRef))
                        def put(s, k) = { Ref.put(s, selRef); k() }
                    } with handler TurnPhase.State {
                        def get(k)    = k(TurnPhase.Phase.ActionSelect)
                        def put(_, k) = k()
                    })))

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
                    ItemScene.GroundItemKind.WeaponItem(wB)) ::
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
                MoveDraft.DraftAction.Dropped(0, PlayerScene.ItemKind.Weapon(1),
                    ItemScene.GroundItemKind.WeaponItem(wB)) ::
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
    /// 「こうかん」エントリ (metadata = "exchange") がメニューに含まれる。
    @Test
    def testExchangeItemAppearsWhenAdjacentAllyExists(): Unit \ Assert =
        let scene = loadAdjacentPartyActionMenuScene();
        let after = runRefreshItems({
            phase          = TurnPhase.Phase.ActionSelect,
            selectedId     = 0,
            selectedOrigin = {x = 1, y = 1},
            scene          = scene
        });
        Assert.assertEq(
            expected = true,
            List.memberOf(Some("exchange"), itemsMetadata(after)))

    /// id=0 が (1,1)、id=1 が (3,3) の非隣接配置 (manhattan=4) なら「こうかん」は出ない。
    /// loadTwoPlayerActionMenuScene の標準フィクスチャを使う。
    @Test
    def testExchangeItemHiddenWhenNoAdjacentAlly(): Unit \ Assert =
        let scene = loadTwoPlayerActionMenuScene();
        let after = runRefreshItems({
            phase          = TurnPhase.Phase.ActionSelect,
            selectedId     = 0,
            selectedOrigin = {x = 1, y = 1},
            scene          = scene
        });
        Assert.assertEq(
            expected = false,
            List.memberOf(Some("exchange"), itemsMetadata(after)))

    // ════════════════════════════════════════════════════════
    // ローグ移動モードのメニュー (SelectedPlayer = None × 退避中の味方が居る)
    //   退避中の味方が居る = ローグ中 → 「ひろう(足元にアイテム時) / かいさん」を出す。
    // ════════════════════════════════════════════════════════

    /// World + ロード(id0, 表示, (1,1)) + 退避中の味方(id1, hidden) + ActionMenu。
    /// 「ローグ移動モード中」を表す最小フィクスチャ。
    def loadRogueActionMenuScene(): Scene[NodeTag] =
        let world = Marker2D.make(Vec2.zero());
        let m0 = Marker2D.make(Vec2.zero());
        let m1 = Marker2D.make(Vec2.zero());
        let lord = makePlayerData(0, {x = 1, y = 1});
        let ally = {hidden = true | makePlayerData(1, {x = 5, y = 5})};
        let withWorld = Scene.empty()
            |> Scene.addNode(MapScene.worldName(),
                EngineNode.Marker2DWithState(world, NodeTag.NoTag))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(0),
                EngineNode.Marker2DWithState(m0, NodeTag.Player(lord)))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(1),
                EngineNode.Marker2DWithState(m1, NodeTag.Player(ally)));
        actionMenuAddPure(withWorld)

    /// SelectedPlayer = None・ActionSelect で refreshItems を回すランナー
    /// (空マス / ローグメニューの項目構築を観測する用)。
    def runRefreshItemsNoSelection(scene: Scene[NodeTag]): Scene[NodeTag] =
        let menuNode = match Scene.getEngineNode(ActionMenuScene.menuPath(), scene) {
            case Some(node) => node
            case None       => bug!("ActionMenu ItemList not found")
        };
        let (_, after) = TestUnitFixtures.withMockPartyQuery(scene, () ->
            TestUnitFixtures.withMockRosterQuery(scene, () ->
                run {
                    ActionMenuScene.refreshItems(
                        Duration.seconds(0.0), menuNode,
                        ActionMenuScene.menuPath(), scene)
                } with handler SelectedPlayer.State {
                    def get(k)    = k({id = None, drafts = Nil})
                    def put(_, k) = k()
                } with handler TurnPhase.State {
                    def get(k)    = k(TurnPhase.Phase.ActionSelect)
                    def put(_, k) = k()
                }));
        after

    /// ローグ中・ロード足元にアイテムが無ければ、メニューは「かいさん」のみ。
    @Test
    def testRogueMenuShowsOnlyDisbandWithoutFloorItem(): Unit \ Assert =
        let after = runRefreshItemsNoSelection(loadRogueActionMenuScene());
        Assert.assertEq(
            expected = Some("disband") :: Nil,
            itemsMetadata(after))

    /// ローグ中・ロード足元((1,1))にアイテムがあれば、「ひろう → かいさん」の順で出る。
    @Test
    def testRogueMenuShowsPickupThenDisbandWithFloorItem(): Unit \ Assert =
        let scene = attachGroundItemAt({x = 1, y = 1},
            ItemScene.GroundItemKind.WeaponItem(TestUnitFixtures.testWeapon()),
            loadRogueActionMenuScene());
        let after = runRefreshItemsNoSelection(scene);
        Assert.assertEq(
            expected = Some("pickup") :: Some("disband") :: Nil,
            itemsMetadata(after))
}
