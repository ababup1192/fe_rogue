/// CursorScene のシーン操作と `snapToPlayer` の動作を検証する。
///
/// `add` の最も重要な性質は「**初期位置 = プレイヤーのグリッド位置**」と
/// 「初期 hover 状態 = None」の 2 点。味方ターン開始時にカーソルが味方の上から
/// 始まることで、Z で即座に味方を選んで移動フェーズに入れる UX を保証する。
///
/// `snapToPlayer` は敵ターン終了 / キャンセルのたびに呼ばれ、カーソルを味方に
/// 引き戻す責務を持つ。ホバー状態 (lastHoveredEnemyId) もここでリセットされる。
///
/// `physicsProcess` 経由のキー入力 → 移動 → ホバー検知の経路は `GameEngine.Game`
/// （キー押下） + `BoardQuery` + `GameLogger` + `Tween.Scheduler` の 4 種類の
/// effect が絡む統合シナリオなので、ここでは扱わず実機での動作確認に委ねる。
mod TestCursorScene {

    // ════════════════════════════════════════════════════════
    // ヘルパー
    // ════════════════════════════════════════════════════════

    /// CursorScene.add の {GameEngine.Game, Fs.FileRead} effect を discharge して
    /// pure に見せる test 用ラッパ。`@Test` は `\ Assert` 限定のため unchecked_cast で
    /// IO effect を消す (Fs.FileRead は flix test の CWD = examples/fe_rogue から
    /// 実ファイルを読む)。
    def cursorAddPure(scene: Scene[NodeTag]): Scene[NodeTag] =
        unchecked_cast(
            (run {
                TestUnitFixtures.withMockGame(() -> CursorScene.add(scene))
            } with Fs.FileRead.runWithIO)
            as _ \ {})

    /// プレイヤー id=0 1 体だけを (gridPos) に置いた scene を組む。
    /// JSON ロードを介さず Marker2D を直接構築する（PlayerScene.playerPath は
    /// World 配下を指すため、ここでも World Marker2D を挟む）。
    def sceneWithPlayer(gridPos: {x = Int32, y = Int32}): Scene[NodeTag] =
        let pos = MapSnapshot.cellCenter(gridPos);
        let marker = Marker2D.make(pos);
        let world = Marker2D.make(Vec2.zero())
            |> CanvasItem.setYSortEnabled(true);
        Scene.empty()
            |> Scene.addNode(MapScene.worldName(),
                EngineNode.Marker2DWithState(world, NodeTag.NoTag))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(0),
                EngineNode.Marker2DWithState(marker,
                    NodeTag.Player({
                        id                = 0,
                        classId           = "test_player",
                        gridPos           = gridPos,
                        moveTiles         = 5,
                        hp                = 10,
                        waited            = false,
                        attackTargetId    = None,
                        resource          = TestUnitFixtures.testResource(5, 10),
                        weapons           = TestUnitFixtures.testWeapon() :: Nil,
                        staves            = Nil,
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
                    })))

    /// `add` 後の (gridPos, lastHoveredEnemyId) を 1 タプルにまとめて取り出す
    def cursorState(scene: Scene[NodeTag]): (Int32, Int32, Option[Int32]) =
        let d = CursorScene.getCursorData(scene);
        (d#gridPos#x, d#gridPos#y, d#lastHoveredEnemyId)

    /// 味方を 2 体置いた scene を組む。`waited` を個別に指定できる。
    /// commit 後の「アクティブな次の味方にカーソルがスナップ」テスト用。
    /// 引数: p0 = (gridPos, waited), p1 = (gridPos, waited)
    def sceneWithTwoPlayers(p0: ({x = Int32, y = Int32}, Bool),
                              p1: ({x = Int32, y = Int32}, Bool)): Scene[NodeTag] =
        let (p0Pos, p0Waited) = p0;
        let (p1Pos, p1Waited) = p1;
        let world = Marker2D.make(Vec2.zero())
            |> CanvasItem.setYSortEnabled(true);
        let mk = (id, pos, waited) ->
            EngineNode.Marker2DWithState(Marker2D.make(MapSnapshot.cellCenter(pos)),
                NodeTag.Player({
                    id                = id,
                    classId           = "test_player",
                    gridPos           = pos,
                    moveTiles         = 5,
                    hp                = 10,
                    waited            = waited,
                    attackTargetId    = None,
                    resource          = TestUnitFixtures.testResource(5, 10),
                    weapons           = TestUnitFixtures.testWeapon() :: Nil,
                    staves            = Nil,
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
                }));
        Scene.empty()
            |> Scene.addNode(MapScene.worldName(),
                EngineNode.Marker2DWithState(world, NodeTag.NoTag))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(0),
                mk(0, p0Pos, p0Waited))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(1),
                mk(1, p1Pos, p1Waited))

    // ════════════════════════════════════════════════════════
    // add: 初期位置はプレイヤーと同じ、ホバー状態は空
    // ════════════════════════════════════════════════════════

    /// add 直後のカーソルは「プレイヤーと同じグリッド」にあり、
    /// lastHoveredEnemyId は None（味方マスにはどの敵も乗っていない）
    @Test
    def testAddPlacesCursorAtPlayerGrid(): Unit \ Assert =
        let player: {x = Int32, y = Int32} = {x = 5, y = 5};
        let scene = cursorAddPure(sceneWithPlayer(player));
        Assert.assertEq(expected = (5, 5, (None: Option[Int32])),
            cursorState(scene))

    /// add でプレイヤーが (3, 7) にいれば、カーソルも (3, 7) にスポーンする
    /// （プレイヤーの初期セルが 5,5 でない場合の追従を確認）
    @Test
    def testAddFollowsPlayerSpawnPosition(): Unit \ Assert =
        let player: {x = Int32, y = Int32} = {x = 3, y = 7};
        let scene = cursorAddPure(sceneWithPlayer(player));
        Assert.assertEq(expected = (3, 7, (None: Option[Int32])),
            cursorState(scene))

    // ════════════════════════════════════════════════════════
    // snapToPlayer: どこに居ても味方位置に戻り、ホバーもリセット
    // ════════════════════════════════════════════════════════

    /// ホバー対象を持っていたカーソルが、snapToPlayer で味方位置に引き戻される。
    /// ホバー履歴 (lastHoveredEnemyId) も None にリセットされる
    /// （敵ターン明けに「カーソルは味方の上から再開・赤レンジは無し」を保証する）
    @Test
    def testSnapToPlayerResetsCursorAndHover(): Unit \ Assert =
        let player: {x = Int32, y = Int32} = {x = 4, y = 4};
        let initial = sceneWithPlayer(player);
        let result = TestUnitFixtures.withNoSelection(() -> TestUnitFixtures.withNoopTween(() -> TestUnitFixtures.withNoopAnim(() ->
            TestUnitFixtures.withMockPartyQuery(initial, () ->
                let scene = cursorAddPure(initial);
                // カーソルを (10, 10) に移し、ホバー履歴も Some(99) に偽装
                let drifted = scene |> CursorScene.mapCursor((m, d) ->
                    (m, {gridPos = ({x = 10, y = 10}: {x = Int32, y = Int32}),
                         lastHoveredEnemyId = Some(99) | d}));
                let snapped = CursorScene.snapToPlayer(drifted);
                cursorState(snapped)))));
        Assert.assertEq(expected = (4, 4, (None: Option[Int32])), result)

    /// commit 後の「行動済みじゃない味方にカーソルが飛ぶ」フォールバックを検証する。
    /// 状況: SelectedPlayer は cleared() (`commitWaitedAndAdvance` でクリア済み)、
    /// 味方 0 が waited (たった今攻撃を確定した駒)、味方 1 が waited でない (次に動ける駒)。
    /// 期待: snapToPlayer が味方 1 (= アクティブな最初の味方) の位置にスナップする。
    /// 実装は `CursorScene.snapTargetPos → fallbackPos` (`CursorScene.flix:449-470`)。
    @Test
    def testSnapToPlayerJumpsToActiveAllyWhenSelectedCleared(): Unit \ Assert =
        let waitedPos: {x = Int32, y = Int32}  = {x = 2, y = 2};
        let activePos: {x = Int32, y = Int32}  = {x = 5, y = 5};
        let initial = sceneWithTwoPlayers((waitedPos, true), (activePos, false));
        let result = TestUnitFixtures.withNoSelection(() -> TestUnitFixtures.withNoopTween(() -> TestUnitFixtures.withNoopAnim(() ->
            TestUnitFixtures.withMockPartyQuery(initial, () ->
                let scene = cursorAddPure(initial);
                let snapped = CursorScene.snapToPlayer(scene);
                cursorState(snapped)))));
        Assert.assertEq(expected = (5, 5, (None: Option[Int32])), result)

    /// 統合テスト: `commitWaitedAndAdvance` を **古い PartyQuery snapshot** ありの状態で呼んでも、
    /// カーソルが「いま waited にした駒」(Player(0)) ではなく「次のアクティブ味方」(Player(1)) に飛ぶ。
    /// 連打バグ修正後の「待機すると次のキャラにカーソルが当たる」体験を担保する回帰防止テスト。
    /// PartyQuery は両方 active のままの snapshot を返すので、修正前なら fallback で
    /// Player(0) を「最初の active」と判定してカーソルが (2,2) に残ったはず。
    @Test
    def testCommitWaitedAndAdvanceMovesCursorToNextActive(): Unit \ Assert =
        region rc {
            let p0Pos: {x = Int32, y = Int32} = {x = 2, y = 2};
            let p1Pos: {x = Int32, y = Int32} = {x = 5, y = 5};
            let initial = sceneWithTwoPlayers((p0Pos, false), (p1Pos, false));
            let result = TestUnitFixtures.withWorldCommand(rc, () -> run {
                SelectedPlayer.State.put({
                    id     = Some(0),
                    drafts = Nil,
                    gatherActive = false
                });
                let scene = cursorAddPure(initial);
                let after = TurnFlow.commitWaitedAndAdvance(scene);
                cursorState(after)
            } with handler PlayerData.PartyQuery {
                // 古い snapshot: setWaited 前の両方 active な状態を返し続ける
                def get(id, k)           = k(PlayerScene.get(id, initial))
                def getAll(k)            = k(PlayerScene.getAll(initial))
            }
              with Tween.withScheduler(rc)
              with AnimationPlayer.withScheduler(rc)
              with GameLogger.withLogger(rc)
              with EnemyTurn.withQueue(rc)
              with TurnPhase.withState(rc)
              with SelectedPlayer.withState(rc));
            Assert.assertEq(expected = (5, 5, (None: Option[Int32])), result)
        }

    /// `enterPlayerCursorAt` (target 直指定版) は PartyQuery を一切経由せず、
    /// 渡された座標にカーソルをスナップする。`commitWaitedAndAdvance` のように
    /// フレーム内で setWaited した直後の経路で、PartyQuery (= frame 冒頭の snapshot) を
    /// 介さずに「次のアクティブ味方の位置」を確実にカーソルに反映するための関数。
    /// 古い snapshot を握った PartyQuery を渡しても、target が直接効くことを担保する。
    @Test
    def testEnterPlayerCursorAtBypassesPartyQuery(): Unit \ Assert =
        region rc {
            let p0Pos: {x = Int32, y = Int32} = {x = 2, y = 2};
            let p1Pos: {x = Int32, y = Int32} = {x = 5, y = 5};
            // 古い snapshot: 両方 active
            let staleSnapshot = sceneWithTwoPlayers((p0Pos, false), (p1Pos, false));
            // 新 scene: Player(0) が setWaited されたばかり (commitWaitedAndAdvance 内のローカル変数)
            let freshScene = sceneWithTwoPlayers((p0Pos, true), (p1Pos, false));
            let result = TestUnitFixtures.withMockPartyQuery(staleSnapshot, () -> run {
                let scene = cursorAddPure(freshScene);
                // 呼び出し側が新 scene から計算した「次のアクティブ味方の gridPos」
                let snapped = PhaseTransitions.enterPlayerCursorAt(p1Pos, scene);
                cursorState(snapped)
            } with Tween.withScheduler(rc)
              with AnimationPlayer.withScheduler(rc)
              with TurnPhase.withState(rc));
            Assert.assertEq(expected = (5, 5, (None: Option[Int32])), result)
        }

    // ════════════════════════════════════════════════════════
    // physicsProcess — PlayerCursor フェーズの方向入力 / hold / 入力捨て
    // ════════════════════════════════════════════════════════

    /// 手で Cursor ノードを scene に挿入する。`cursorAddPure` (= scene.json + GameEngine.Game) を
    /// 経由しないので任意の `gridPos` / `holdDir` / `holdSteps` で初期化できる。
    def cursorSceneAt(gridPos: {x = Int32, y = Int32},
                       holdDir: Option[{x = Int32, y = Int32}],
                       holdSteps: Int32): Scene[NodeTag] =
        let marker = Marker2D.make(MapSnapshot.cellCenter(gridPos));
        let data: CursorScene.Data = {
            gridPos            = gridPos,
            lastHoveredEnemyId = None,
            holdDir            = holdDir,
            holdSteps          = holdSteps
        };
        Scene.empty()
            |> Scene.addNode("Cursor",
                EngineNode.Marker2DWithState(marker, NodeTag.Cursor(data)))

    /// 13×13 床のみ・駒なしのテスト用 Board。`clampToMap` で端マスを判定できる範囲。
    def testBoard(): Board =
        let map: MapSnapshot = {
            tileSize    = 16.0,
            usedRect    = {position = {x = 0, y = 0}, size = ({x = 13, y = 13}: {x = Int32, y = Int32})},
            wallCells   = (Set#{}: Set[(Int32, Int32)]),
            mapGlobal   = {x = 0.0, y = 0.0},
            placements  = Nil
        };
        {map = map, pieces = Nil}

    /// 指定フェーズで `physicsProcess` を 1 フレーム回し、Cursor の Data を取り出す。
    /// R3 で physicsProcess が phase 分岐するようになったため、テスト側でも phase を
    /// 立ててから呼ぶ。`PlayerAttack` 用テストも同じ runner を使う (旧 runPhysicsAttack 廃止)。
    def runPhysics(phase: TurnPhase.Phase, scene: Scene[NodeTag]): CursorScene.Data
            \ {GameEngine.Game, BoardQuery,
                Tween.Scheduler, AnimationPlayer.Scheduler,
                GameLogger.GameLogger,
                EnemyData.RosterQuery, TurnPhase.State} =
        TurnPhase.State.put(phase);
        let path = CursorScene.cursorPath();
        match Scene.getEngineNode(path, scene) {
            case Some(node) =>
                // physicsProcess は WeaponSelect 分岐用に SelectedPlayer.State を要求するので、
                // ここで discharge する（PlayerCursor / PlayerAttack 分岐では未使用なので値は任意）。
                let (newNode, newScene) =
                    TestUnitFixtures.withSelectedPlayer(0, () ->
                        CursorScene.physicsProcess(Duration.seconds(0.016), node, path, scene));
                let updated = Scene.setEngineNode(path, newNode, newScene);
                CursorScene.getCursorData(updated)
            case _ => bug!("Cursor not found at cursorPath()")
        }

    /// Up キーを押下した 1 フレーム後、cursor が y 方向に 1 マス分減ったセルに進む
    /// (Vec2i.up() = {x=0, y=-1} を gridPos に足す)。端でなければ (5,5) → (5,4)。
    @Test
    def testPhysicsProcessMovesCursorUpOnUpKey(): Unit \ Assert =
        region rc {
            let scene = cursorSceneAt({x = 5, y = 5}, None, 0);
            let data = run {
                TestUnitFixtures.withMockGameKeys(k -> k == GameEngine.Key.Up, () ->
                    TestUnitFixtures.withMockBoard(testBoard(), () ->
                        TestUnitFixtures.withNoopTween(() ->
                            TestUnitFixtures.withNoopAnim(() ->
                                TestUnitFixtures.withMockRosterQuery(Scene.empty(), () ->
                                    runPhysics(TurnPhase.Phase.PlayerCursor, scene))))))
            } with GameLogger.withLogger(rc)
              with TurnPhase.withState(rc);
            Assert.assertEq(expected = (5, 4), (data#gridPos#x, data#gridPos#y))
        }

    /// snag アニメ再生中 (isPlaying = true) は方向キーを完全無視する。
    /// Up を押しても gridPos は (5,5) のまま動かない。
    @Test
    def testPhysicsProcessNoopsWhilePlayingAnimation(): Unit \ Assert =
        region rc {
            let scene = cursorSceneAt({x = 5, y = 5}, None, 0);
            let data = run {
                TestUnitFixtures.withMockGameKeys(k -> k == GameEngine.Key.Up, () ->
                    TestUnitFixtures.withMockBoard(testBoard(), () ->
                        TestUnitFixtures.withNoopTween(() ->
                            TestUnitFixtures.withPlayingAnim(() ->
                                TestUnitFixtures.withMockRosterQuery(Scene.empty(), () ->
                                    runPhysics(TurnPhase.Phase.PlayerCursor, scene))))))
            } with GameLogger.withLogger(rc)
              with TurnPhase.withState(rc);
            Assert.assertEq(expected = (5, 5), (data#gridPos#x, data#gridPos#y))
        }

    /// 方向キーが離れたフレームでは hold 状態 (holdDir / holdSteps) がリセットされる。
    /// (再度押したときに「初速」から再加速できるように)。gridPos は変わらない。
    /// holdDir record は Eq 未定義なので Option.isEmpty で Bool 化して比較する。
    @Test
    def testPhysicsProcessClearsHoldWhenNoKeyPressed(): Unit \ Assert =
        region rc {
            let scene = cursorSceneAt({x = 5, y = 5}, Some(Vec2i.up()), 3);
            let data = run {
                TestUnitFixtures.withMockGameKeys(_ -> false, () ->
                    TestUnitFixtures.withMockBoard(testBoard(), () ->
                        TestUnitFixtures.withNoopTween(() ->
                            TestUnitFixtures.withNoopAnim(() ->
                                TestUnitFixtures.withMockRosterQuery(Scene.empty(), () ->
                                    runPhysics(TurnPhase.Phase.PlayerCursor, scene))))))
            } with GameLogger.withLogger(rc)
              with TurnPhase.withState(rc);
            Assert.assertEq(
                expected = (5, 5, true, 0),
                (data#gridPos#x, data#gridPos#y,
                 Option.isEmpty(data#holdDir), data#holdSteps))
        }

    // ════════════════════════════════════════════════════════
    // physicsProcess (PlayerAttack フェーズ) — ターゲットサイクル
    // ════════════════════════════════════════════════════════

    /// 攻撃フェーズで PlayerAttackRange ノードが scene に居ない (= 射程内に敵候補が居ない)
    /// 状態で Down を「押下開始」したフレーム → 内部の cycleToTarget は targets = Nil を受けて
    /// gridPos を動かさない (X キャンセル待ち)。
    @Test
    def testPhysicsProcessAttackNoopsWhenNoTargetsInRange(): Unit \ Assert =
        region rc {
            let scene = cursorSceneAt({x = 3, y = 3}, None, 0);
            let data = run {
                TestUnitFixtures.withMockGameKeys(k -> k == GameEngine.Key.Down, () ->
                    TestUnitFixtures.withMockBoard(testBoard(), () ->
                        TestUnitFixtures.withNoopTween(() ->
                            TestUnitFixtures.withNoopAnim(() ->
                                TestUnitFixtures.withMockRosterQuery(Scene.empty(), () ->
                                    runPhysics(TurnPhase.Phase.PlayerAttack, scene))))))
            } with GameLogger.withLogger(rc)
              with TurnPhase.withState(rc);
            Assert.assertEq(expected = (3, 3), (data#gridPos#x, data#gridPos#y))
        }

    /// 攻撃フェーズで snag アニメ再生中はターゲット切替も走らない。
    /// Down を押しても gridPos は (3,3) のまま。
    @Test
    def testPhysicsProcessAttackNoopsWhilePlayingAnimation(): Unit \ Assert =
        region rc {
            let scene = cursorSceneAt({x = 3, y = 3}, None, 0);
            let data = run {
                TestUnitFixtures.withMockGameKeys(k -> k == GameEngine.Key.Down, () ->
                    TestUnitFixtures.withMockBoard(testBoard(), () ->
                        TestUnitFixtures.withNoopTween(() ->
                            TestUnitFixtures.withPlayingAnim(() ->
                                TestUnitFixtures.withMockRosterQuery(Scene.empty(), () ->
                                    runPhysics(TurnPhase.Phase.PlayerAttack, scene))))))
            } with GameLogger.withLogger(rc)
              with TurnPhase.withState(rc);
            Assert.assertEq(expected = (3, 3), (data#gridPos#x, data#gridPos#y))
        }

    // ════════════════════════════════════════════════════════
    // snapToFirstTradeCellOrPlayer — 「こうかん」確定時の初期スナップ
    //
    // 検証する観点:
    //   - 隣接味方が複数いるとき、reading order (y → x) の先頭にスナップする
    //     (= 北 > 西 > 東 > 南 の優先順位、最も若い y、同 y では最も若い x)
    //   - 隣接味方が 1 人だけならその人の位置にスナップする
    // ════════════════════════════════════════════════════════

    /// テスト用に id と gridPos だけ意味を持つ最小限の PlayerScene.Data。
    def makePartyMember(id: Int32, gridPos: {x = Int32, y = Int32}):
            PlayerScene.Data = {
        id              = id,
        classId         = "test_player",
        gridPos         = gridPos,
        moveTiles       = 5,
        hp              = 10,
        waited          = false,
        attackTargetId  = None,
        resource        = TestUnitFixtures.testResource(5, 10),
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

    /// World + 与えた party の Marker2D を直接組み立てた scene。
    /// cursorAddPure を後付けで挟むと Cursor も入る (CursorScene.add は id=0 の
    /// 位置を初期セルとして読む)。
    def sceneWithParty(party: List[PlayerScene.Data]): Scene[NodeTag] =
        let world = Marker2D.make(Vec2.zero())
            |> CanvasItem.setYSortEnabled(true);
        let withWorld = Scene.empty()
            |> Scene.addNode(MapScene.worldName(),
                EngineNode.Marker2DWithState(world, NodeTag.NoTag));
        List.foldLeft((acc, data) -> {
            let marker = Marker2D.make(MapSnapshot.cellCenter(data#gridPos));
            Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(data#id),
                EngineNode.Marker2DWithState(marker, NodeTag.Player(data)), acc)
        }, withWorld, party)

    /// 4 effect (SelectedPlayer / PartyQuery / Tween / Anim) を一度に剥がすラッパ。
    /// TradeRangeScene.show + snapToFirstTradeCellOrPlayer を続けて実行する用途。
    def runWithTradeSnapMocks(scene: Scene[NodeTag], selectedId: Int32,
                                _selectedPos: {x = Int32, y = Int32},
                                thunk: Unit -> a \ ef):
            a \ (ef - SelectedPlayer.State - PlayerData.PartyQuery
                  - Tween.Scheduler - AnimationPlayer.Scheduler) =
        TestUnitFixtures.withSelectedPlayer(selectedId, () ->
            TestUnitFixtures.withMockPartyQuery(scene, () ->
                TestUnitFixtures.withNoopTween(() ->
                    TestUnitFixtures.withNoopAnim(thunk))))

    /// cursor の現在 gridPos を (x, y) タプルで取り出す。
    def cursorPosOf(scene: Scene[NodeTag]): (Int32, Int32) =
        let d = CursorScene.getCursorData(scene);
        (d#gridPos#x, d#gridPos#y)

    /// 配置 (id=0 self at (5,5)):
    ///       (5,4) id=1 north
    /// (4,5) (5,5) (6,5)
    ///  id=2  self  id=3
    ///  west       east
    ///       (5,6) id=4 south
    ///
    /// reading order (y → x) では (5,4) (= 北) が先頭。
    /// 「こうかん」確定時に北の味方にカーソルがスナップする。
    @Test
    def testSnapToFirstTradeCellPicksNorthAmongFourNeighbors(): Unit \ Assert =
        let self     = makePartyMember(0, {x = 5, y = 5});
        let northern = makePartyMember(1, {x = 5, y = 4});
        let western  = makePartyMember(2, {x = 4, y = 5});
        let eastern  = makePartyMember(3, {x = 6, y = 5});
        let southern = makePartyMember(4, {x = 5, y = 6});
        let baseScene = cursorAddPure(
            sceneWithParty(self :: northern :: western :: eastern :: southern :: Nil));
        let after = runWithTradeSnapMocks(baseScene, 0, {x = 5, y = 5}, () -> {
            let withRange = TradeRangeScene.show(baseScene);
            CursorScene.snapToFirstTradeCellOrPlayer(withRange)
        });
        Assert.assertEq(expected = (5, 4), cursorPosOf(after))

    /// 隣接味方が 1 人だけ (東に id=1) のとき、その人の位置に直接スナップする。
    /// 複数考慮の特殊ケースとして単一ケースも pin。
    @Test
    def testSnapToFirstTradeCellPicksTheOnlyAdjacentAlly(): Unit \ Assert =
        let self    = makePartyMember(0, {x = 5, y = 5});
        let eastern = makePartyMember(1, {x = 6, y = 5});
        let baseScene = cursorAddPure(
            sceneWithParty(self :: eastern :: Nil));
        let after = runWithTradeSnapMocks(baseScene, 0, {x = 5, y = 5}, () -> {
            let withRange = TradeRangeScene.show(baseScene);
            CursorScene.snapToFirstTradeCellOrPlayer(withRange)
        });
        Assert.assertEq(expected = (6, 5), cursorPosOf(after))

    // ════════════════════════════════════════════════════════
    // cursorVisibleForPhase — フェーズ→カーソル可視の単一の真理表
    // ════════════════════════════════════════════════════════

    /// 「ゲームプレイ復帰フェーズ」の通常カーソル可視を 1 タプルで pin する純粋テスト。
    /// この表は各 `enter*` の `setVisible` が直接参照する単一の真理点なので、表が
    /// 崩れると「カーソルが出ない／消えない」半端状態に直結する。表示=PlayerCursor /
    /// PlayerAttack、非表示=PlayerMoving / GatherMove / ItemSelect / LevelUpView /
    /// StairsExit。非対象フェーズ（矢印カーソル・交換メニュー・Keep 系）はこの関数を
    /// 呼ばないので対象外（呼べば bug! で落ちる）。
    @Test
    def testCursorVisibleForPhaseMatrix(): Unit \ Assert =
        Assert.assertEq(
            expected = (true, true, false, false, false, false, false),
            (CursorScene.cursorVisibleForPhase(TurnPhase.Phase.PlayerCursor),
             CursorScene.cursorVisibleForPhase(TurnPhase.Phase.PlayerAttack),
             CursorScene.cursorVisibleForPhase(TurnPhase.Phase.PlayerMoving),
             CursorScene.cursorVisibleForPhase(TurnPhase.Phase.GatherMove),
             CursorScene.cursorVisibleForPhase(TurnPhase.Phase.ItemSelect),
             CursorScene.cursorVisibleForPhase(TurnPhase.Phase.LevelUpView),
             CursorScene.cursorVisibleForPhase(TurnPhase.Phase.StairsExit)))
}
