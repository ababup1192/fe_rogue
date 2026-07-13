/// CursorDriver の初期化・スナップ・`step`/`stepOnBoard` 入力処理を検証する。
///
/// `add` の最も重要な性質は「**初期位置 = プレイヤーのグリッド位置**」と
/// 「初期 hover 状態 = None」の 2 点。味方ターン開始時にカーソルが味方の上から
/// 始まることで、Z で即座に味方を選んで移動フェーズに入れる UX を保証する。
///
/// `snapToPlayer` は敵ターン終了 / キャンセルのたびに呼ばれ、カーソルを味方に
/// 引き戻す責務を持つ。ホバー状態 (lastHoveredEnemyId) もここでリセットされる。
///
/// `step` 経由のキー入力 → 移動 → ホバー検知の経路も `runPhysics` /
/// `runPhysicsTween` / `runPhysicsThenVisual` ヘルパーが `GameEngine.Game`
/// （キー押下） + `BoardQuery` + `GameLogger` 等の effect を mock/withState で
/// 束ねて直接 pin する（下記「step」節）。
///
/// 駒は scene ノードでなく World（`TestWorldFixtures`）で組む。カーソル論理状態は
/// `CursorState.State` resource が権威。
mod TestCursorDriver {

    use World.Cmd
    use World.EntityRef

    // ════════════════════════════════════════════════════════
    // ヘルパー
    // ════════════════════════════════════════════════════════

    /// カーソル resource の (gridPos, lastHoveredEnemyId) を 1 タプルにまとめて取り出す
    def cursorState(): (Int32, Int32, Option[Int32]) \ CursorState.State =
        let d = CursorDriver.getCursorData();
        (d#gridPos#x, d#gridPos#y, d#lastHoveredEnemyId)

    // ════════════════════════════════════════════════════════
    // add: 初期位置はプレイヤーと同じ、ホバー状態は空
    // ════════════════════════════════════════════════════════

    /// add 直後のカーソルは「プレイヤーと同じグリッド」にあり、
    /// lastHoveredEnemyId は None（味方マスにはどの敵も乗っていない）
    @Test
    def testAddPlacesCursorAtPlayerGrid(): Unit \ Assert =
        region rc {
            let player: {x = Int32, y = Int32} = {x = 5, y = 5};
            let world = TestWorldFixtures.worldOf(TestWorldFixtures.playerCmds(TestWorldFixtures.unitSpec(0, player)));
            let result = TestUnitFixtures.withWorldQuery(world, () -> run {
                CursorDriver.add();
                cursorState()
            } with CursorState.withState(rc));
            Assert.assertEq(expected = (5, 5, (None: Option[Int32])), result)
        }

    /// add でプレイヤーが (3, 7) にいれば、カーソルも (3, 7) にスポーンする
    /// （プレイヤーの初期セルが 5,5 でない場合の追従を確認）
    @Test
    def testAddFollowsPlayerSpawnPosition(): Unit \ Assert =
        region rc {
            let player: {x = Int32, y = Int32} = {x = 3, y = 7};
            let world = TestWorldFixtures.worldOf(TestWorldFixtures.playerCmds(TestWorldFixtures.unitSpec(0, player)));
            let result = TestUnitFixtures.withWorldQuery(world, () -> run {
                CursorDriver.add();
                cursorState()
            } with CursorState.withState(rc));
            Assert.assertEq(expected = (3, 7, (None: Option[Int32])), result)
        }

    // ════════════════════════════════════════════════════════
    // snapToPlayer: どこに居ても味方位置に戻り、ホバーもリセット
    // ════════════════════════════════════════════════════════

    /// ホバー対象を持っていたカーソルが、snapToPlayer で味方位置に引き戻される。
    /// ホバー履歴 (lastHoveredEnemyId) も None にリセットされる
    /// （敵ターン明けに「カーソルは味方の上から再開・赤レンジは無し」を保証する）
    @Test
    def testSnapToPlayerResetsCursorAndHover(): Unit \ Assert =
        region rc {
            let player: {x = Int32, y = Int32} = {x = 4, y = 4};
            let world = TestWorldFixtures.worldOf(TestWorldFixtures.playerCmds(TestWorldFixtures.unitSpec(0, player)));
            let result = TestUnitFixtures.withNoSelection(() ->
                TestUnitFixtures.withMockPartyQuery(TestUnitFixtures.worldPlayers(world), () ->
                    TestUnitFixtures.withWorldQuery(world, () ->
                        run {
                            CursorDriver.add();
                            // カーソルを (10, 10) に移し、ホバー履歴も Some(99) に偽装
                            CursorState.State.put({gridPos = {x = 10, y = 10},
                                                   lastHoveredEnemyId = Some(99)
                                                   | CursorState.State.get()});
                            CursorDriver.snapToPlayer();
                            cursorState()
                        } with CursorState.withState(rc))));
            Assert.assertEq(expected = (4, 4, (None: Option[Int32])), result)
        }

    /// snapToPlayer の「行動済みじゃない味方にカーソルが飛ぶ」フォールバックを検証する。
    /// 状況: SelectedPlayer は cleared()、味方 0 が waited (行動済み)、味方 1 が waited でない
    /// (次に動ける駒)。期待: snapToPlayer が味方 1 (= アクティブな最初の味方) の位置にスナップする。
    /// 実装は `CursorDriver.snapTargetPos → fallbackPos` (`CursorDriver.flix:449-470` 相当)。
    @Test
    def testSnapToPlayerJumpsToActiveAllyWhenSelectedCleared(): Unit \ Assert =
        region rc {
            let waitedPos: {x = Int32, y = Int32} = {x = 2, y = 2};
            let activePos: {x = Int32, y = Int32} = {x = 5, y = 5};
            let world = TestWorldFixtures.worldOf(List.flatten(
                TestWorldFixtures.playerCmds(TestWorldFixtures.unitSpec(0, waitedPos))
                    :: (Cmd.SetWaited(EntityRef.Player(0), true) :: Nil)
                    :: TestWorldFixtures.playerCmds(TestWorldFixtures.unitSpec(1, activePos))
                    :: Nil));
            let result = TestUnitFixtures.withNoSelection(() ->
                TestUnitFixtures.withMockPartyQuery(TestUnitFixtures.worldPlayers(world), () ->
                    TestUnitFixtures.withWorldQuery(world, () ->
                        run {
                            CursorDriver.add();
                            CursorDriver.snapToPlayer();
                            cursorState()
                        } with CursorState.withState(rc))));
            Assert.assertEq(expected = (5, 5, (None: Option[Int32])), result)
        }

    /// 統合テスト: `commitWaitedAndAdvance` を呼ぶと、カーソルが「いま waited にした駒」
    /// (Player(0)) ではなく「次のアクティブ味方」(Player(1)) に飛ぶ。
    /// `commitWaitedAndAdvance` は次のスナップ先を `PlayerDriver.firstActiveExcluding` (World 直読み)
    /// で計算してから `PhaseTransitions.enterPlayerCursorAt` に明示的に渡すため、setWaited 直後の
    /// フレームでも正しい駒を拾う（連打すると待機した駒にカーソルが残るバグの回帰防止）。
    /// World は単一 Ref (`withWorldAppliedSeeded`) で seed し、setWaited の書き込みが同フレーム内で
    /// 即座に読み返せる (read-after-write) ようにする。
    @Test
    def testCommitWaitedAndAdvanceMovesCursorToNextActive(): Unit \ Assert =
        region rc {
            let p0Pos: {x = Int32, y = Int32} = {x = 2, y = 2};
            let p1Pos: {x = Int32, y = Int32} = {x = 5, y = 5};
            let world0 = TestWorldFixtures.worldOf(List.flatten(
                TestWorldFixtures.playerCmds(TestWorldFixtures.unitSpec(0, p0Pos))
                    :: TestWorldFixtures.playerCmds(TestWorldFixtures.unitSpec(1, p1Pos))
                    :: Nil));
            let (result, _) = TestUnitFixtures.withWorldAppliedSeeded(rc, world0, () -> run {
                SelectedPlayer.State.put({
                    id     = Some(0),
                    drafts = Nil,
                    gatherActive = false
                });
                CursorDriver.add();
                TurnFlow.commitWaitedAndAdvance();
                cursorState()
            } with GameLogger.withLogger(rc)
              with EnemyTurn.withQueue(rc)
              with TurnPhase.withState(rc)
              with SelectedPlayer.withState(rc)
              with CursorState.withState(rc)
              with RangeOverlayState.withState(rc));
            Assert.assertEq(expected = (5, 5, (None: Option[Int32])), result)
        }

    /// `enterPlayerCursorAt` (target 直指定版) は World の駒位置を一切読まず、渡された座標に
    /// カーソルをスナップする。世界に別の位置で存在する駒 (id=1 は (9,9)) がいても、
    /// 引数 `target` (= (5,5)) がそのまま採用されることを担保する。フレーム内で `setWaited`
    /// した直後の経路 (`commitWaitedAndAdvance`) が「呼び出し側が計算した次のアクティブ味方位置」を
    /// 確実にカーソルへ反映するための性質。
    @Test
    def testEnterPlayerCursorAtSnapsDirectlyToTarget(): Unit \ Assert =
        region rc {
            let p0Pos: {x = Int32, y = Int32} = {x = 2, y = 2};
            let otherPos: {x = Int32, y = Int32} = {x = 9, y = 9};
            let target: {x = Int32, y = Int32} = {x = 5, y = 5};
            let world = TestWorldFixtures.worldOf(List.flatten(
                TestWorldFixtures.playerCmds(TestWorldFixtures.unitSpec(0, p0Pos))
                    :: TestWorldFixtures.playerCmds(TestWorldFixtures.unitSpec(1, otherPos))
                    :: Nil));
            let result = TestUnitFixtures.withWorldQuery(world, () -> run {
                CursorDriver.add();
                PhaseTransitions.enterPlayerCursorAt(target);
                cursorState()
            } with TurnPhase.withState(rc)
              with CursorState.withState(rc)
              with RangeOverlayState.withState(rc)
              with handler World.Command { def emit(_c, k) = k() });
            Assert.assertEq(expected = (5, 5, (None: Option[Int32])), result)
        }

    // ════════════════════════════════════════════════════════
    // step — PlayerCursor フェーズの方向入力 / hold / 入力捨て
    // ════════════════════════════════════════════════════════

    /// カーソル論理状態の初期 Data を任意の `gridPos` / `holdDir` / `holdSteps` /
    /// `snagRemaining` で組む。ノードは持たず（カーソルは resource 権威）、視覚系フィールド
    /// （renderPos / tweens / visible）は `CursorState.initial()` の既定を継ぐ。
    /// `snagRemaining > 0` は「駒に乗った直後の入力捨て」区間（`isSnagging`）を表す。
    def cursorDataAt(gridPos: {x = Int32, y = Int32},
                      holdDir: Option[{x = Int32, y = Int32}],
                      holdSteps: Int32, snagRemaining: Float64): CursorDriver.Data =
        {gridPos = gridPos, holdDir = holdDir, holdSteps = holdSteps,
         snagRemaining = snagRemaining | CursorState.initial()}

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

    /// 指定フェーズで `step` を 1 フレーム回し、Cursor の Data を取り出す。
    /// step は phase 分岐するので、テスト側でも phase を立ててから呼ぶ。
    /// `PlayerAttack` 用テストも同じ runner を使う。カーソルは resource 権威で、
    /// 位置・hold・snag は `CursorState` に seed してから回す（ノード/パスは不要）。
    /// PlayerAttack の `targetsInRange` が範囲 resource を読むため `RangeOverlayState` も供給する。
    def runPhysics(phase: TurnPhase.Phase, initial: CursorDriver.Data, held: Set[GameEngine.Key]): CursorDriver.Data
            \ {BoardQuery,
                GameLogger.GameLogger,
                EnemyData.RosterQuery, TurnPhase.State, CursorState.State} =
        // 押下キーは Frame 値で渡す（本番 gameLoop と同じ入力モデル）。カーソル polling は down のみ読む。
        let frame = ({down = held, justPressed = Set.empty(), dt = 0.016, viewport = {x = 240.0, y = 128.0}}: App.Frame);
        // カーソル論理状態は resource 権威。初期 gridPos / hold / snag をここで seed する。
        CursorState.State.put(initial);
        TurnPhase.State.put(phase);
        // step は WeaponSelect 分岐用に SelectedPlayer.State / UiWorldState.State を
        // 要求するので、ここで discharge する（PlayerCursor / PlayerAttack 分岐では未使用なので
        // 値は任意）。step が World 位置を読む（空 World なら未登録扱い）。
        region rc {
            let _ =
                TestUnitFixtures.withSelectedPlayer(0, () ->
                    TestUnitFixtures.withRangeOverlay(rc, () ->
                        run { CursorDriver.step(frame, Duration.seconds(0.016)) }
                            with handler World.WorldQuery { def get(k) = k(World.empty()) }
                            with handler UiWorldState.State {
                                def get(k)      = k(UiStore.empty())
                                def put(_ui, k) = k()
                            }));
            CursorDriver.getCursorData()
        }

    /// 盤面レス World で `stepOnBoard` を 1 フレーム回す runner。BoardQuery は本番
    /// （`WorldDriver.withWorld`）と同じく「要求されたとき地形を読む」遅延 handler にする —
    /// ゲートが無ければ盤面未 seed の `BoardQuery.board` が bug! で落ちるため、
    /// 「board() が要求されないこと」まで含めて pin できる。
    def runStepOnBoardNoMap(initial: CursorDriver.Data, held: Set[GameEngine.Key]): CursorDriver.Data
            \ {GameLogger.GameLogger,
                EnemyData.RosterQuery, TurnPhase.State, CursorState.State} =
        let frame = ({down = held, justPressed = Set.empty(), dt = 0.016, viewport = {x = 240.0, y = 128.0}}: App.Frame);
        CursorState.State.put(initial);
        TurnPhase.State.put(TurnPhase.Phase.PlayerCursor);
        region rc {
            let _ =
                TestUnitFixtures.withSelectedPlayer(0, () ->
                    TestUnitFixtures.withRangeOverlay(rc, () ->
                        run { CursorDriver.stepOnBoard(frame, Duration.seconds(0.016)) }
                            with handler BoardQuery {
                                def board(k) = k(({map = TestWorldFixtures.floorSnapshot({w = 13, h = 13}),
                                                   pieces = Nil}: Board))
                            }
                            with handler World.WorldQuery { def get(k) = k(World.empty()) }
                            with handler UiWorldState.State {
                                def get(k)      = k(UiStore.empty())
                                def put(_ui, k) = k()
                            }));
            CursorDriver.getCursorData()
        }

    /// PlayerCursor で 1 フレーム `step` を回した直後の
    /// (gridPos, `isTweening`) を取り出す（stepVisual は回さない）。
    /// 移動で張った補間が同フレームの論理 put で clobber されず残るかを pin する用途。
    def runPhysicsTween(initial: CursorDriver.Data, held: Set[GameEngine.Key]): (Int32, Int32, Bool)
            \ {BoardQuery,
                GameLogger.GameLogger,
                EnemyData.RosterQuery, TurnPhase.State, CursorState.State} =
        let frame = ({down = held, justPressed = Set.empty(), dt = 0.016, viewport = {x = 240.0, y = 128.0}}: App.Frame);
        CursorState.State.put(initial);
        TurnPhase.State.put(TurnPhase.Phase.PlayerCursor);
        region rc {
            TestUnitFixtures.withSelectedPlayer(0, () ->
                TestUnitFixtures.withRangeOverlay(rc, () ->
                    run {
                        CursorDriver.step(frame, Duration.seconds(0.016));
                        let d = CursorState.State.get();
                        (d#gridPos#x, d#gridPos#y, CursorState.isTweening())
                    }
                        with handler World.WorldQuery { def get(k) = k(World.empty()) }
                        with handler UiWorldState.State {
                            def get(k)      = k(UiStore.empty())
                            def put(_ui, k) = k()
                        }))
        }

    /// PlayerCursor で 1 マス移動 → `stepVisual(visualDt)` を 1 回回し、
    /// (gridPos, `isTweening`, renderPos) を取り出す。補間完了後の視覚追従と
    /// 入力凍結解除を pin する用途。
    def runPhysicsThenVisual(initial: CursorDriver.Data, visualDt: Float64, held: Set[GameEngine.Key]):
            (Int32, Int32, Bool, Float64, Float64)
            \ {BoardQuery,
                GameLogger.GameLogger,
                EnemyData.RosterQuery, TurnPhase.State, CursorState.State} =
        let frame = ({down = held, justPressed = Set.empty(), dt = 0.016, viewport = {x = 240.0, y = 128.0}}: App.Frame);
        CursorState.State.put(initial);
        TurnPhase.State.put(TurnPhase.Phase.PlayerCursor);
        region rc {
            TestUnitFixtures.withSelectedPlayer(0, () ->
                TestUnitFixtures.withRangeOverlay(rc, () ->
                    run {
                        CursorDriver.step(frame, Duration.seconds(0.016));
                        CursorDriver.stepVisual(Duration.seconds(visualDt));
                        let d = CursorState.State.get();
                        (d#gridPos#x, d#gridPos#y, CursorState.isTweening(),
                         d#renderPos#x, d#renderPos#y)
                    }
                        with handler World.WorldQuery { def get(k) = k(World.empty()) }
                        with handler UiWorldState.State {
                            def get(k)      = k(UiStore.empty())
                            def put(_ui, k) = k()
                        }))
        }

    /// 盤面（Map）が無い画面（Title 等）では `stepOnBoard` が polling ごと no-op する。
    /// TurnPhase が起動時デフォルトの `PlayerCursor` のまま盤面レス画面で方向キーを保持しても、
    /// カーソルは動かず BoardQuery（Map 不在で bug!）にも触れない（実機の起動時クラッシュの pin）。
    @Test
    def testStepOnBoardNoopsWithoutMap(): Unit \ Assert =
        region rc {
            let initial = cursorDataAt({x = 5, y = 5}, None, 0, 0.0);
            let data = run {
                TestUnitFixtures.withMockRosterQuery(Nil, () ->
                    runStepOnBoardNoMap(initial, Set#{GameEngine.Key.Up}))
            } with GameLogger.withLogger(rc)
              with TurnPhase.withState(rc)
              with CursorState.withState(rc);
            Assert.assertEq(expected = (5, 5), (data#gridPos#x, data#gridPos#y))
        }

    /// Up キーを押下した 1 フレーム後、cursor が y 方向に 1 マス分減ったセルに進む
    /// (Vec2i.up() = {x=0, y=-1} を gridPos に足す)。端でなければ (5,5) → (5,4)。
    @Test
    def testPhysicsProcessMovesCursorUpOnUpKey(): Unit \ Assert =
        region rc {
            let initial = cursorDataAt({x = 5, y = 5}, None, 0, 0.0);
            let data = run {
                TestUnitFixtures.withMockBoard(testBoard(), () ->
                    TestUnitFixtures.withMockRosterQuery(Nil, () ->
                        runPhysics(TurnPhase.Phase.PlayerCursor, initial, Set#{GameEngine.Key.Up})))
            } with GameLogger.withLogger(rc)
              with TurnPhase.withState(rc)
              with CursorState.withState(rc);
            Assert.assertEq(expected = (5, 4), (data#gridPos#x, data#gridPos#y))
        }

    /// 【回帰】1 マス移動で張ったスライド補間が、同フレームの論理 put で消えない。
    /// 修正前は `stepFreeMovement` の最終 put がフレーム冒頭スナップショット（tweens 空）
    /// を丸ごと書き戻し、`moveStep`→`startMove` が張った tween を即上書きしていた。
    /// 結果 `isTweening` が常に false のまま → `stepVisual` が renderPos を進めず視覚カーソルが
    /// 固まる一方 gridPos だけ先行し、実機の「カーソルが動かない」「味方に乗せて Enter しても
    /// 確定メニューが出る」両症状の根になっていた。ここでは移動直後に補間が生存する
    /// （`isTweening == true`）ことを pin する。
    @Test
    def testPhysicsProcessStartsTweenThatSurvivesLogicalPut(): Unit \ Assert =
        region rc {
            let initial = cursorDataAt({x = 5, y = 5}, None, 0, 0.0);
            let (gx, gy, tweening) = run {
                TestUnitFixtures.withMockBoard(testBoard(), () ->
                    TestUnitFixtures.withMockRosterQuery(Nil, () ->
                        runPhysicsTween(initial, Set#{GameEngine.Key.Up})))
            } with GameLogger.withLogger(rc)
              with TurnPhase.withState(rc)
              with CursorState.withState(rc);
            Assert.assertEq(expected = (5, 4, true), (gx, gy, tweening))
        }

    /// 【回帰】移動後に視覚 tick を十分な dt で回すと補間が完了し、
    /// (1) `isTweening` が false に戻って再入力を受け付ける（凍結解除 = 症状2）、
    /// (2) renderPos が移動先セル中心へ追従して gridPos と一致する（視覚と論理の同期 =
    ///     症状1 の「見た目は味方の上・実際は別セル」誤爆の解消）。
    /// 修正前は補間が clobber され renderPos が始点に固定されたままだった。
    @Test
    def testVisualTickCatchesRenderPosUpToGridAndUnfreezes(): Unit \ Assert =
        region rc {
            let initial = cursorDataAt({x = 5, y = 5}, None, 0, 0.0);
            let (gx, gy, tweening, rpx, rpy) = run {
                TestUnitFixtures.withMockBoard(testBoard(), () ->
                    TestUnitFixtures.withMockRosterQuery(Nil, () ->
                        runPhysicsThenVisual(initial, 1.0, Set#{GameEngine.Key.Up})))
            } with GameLogger.withLogger(rc)
              with TurnPhase.withState(rc)
              with CursorState.withState(rc);
            let target = MapSnapshot.cellCenter({x = 5, y = 4});
            Assert.assertEq(
                expected = (5, 4, false, target#x, target#y),
                (gx, gy, tweening, rpx, rpy))
        }

    /// snag 区間中 (snagRemaining > 0 = isSnagging) は方向キーを完全無視する。
    /// Up を押しても gridPos は (5,5) のまま動かない。
    @Test
    def testPhysicsProcessNoopsWhileSnagging(): Unit \ Assert =
        region rc {
            let initial = cursorDataAt({x = 5, y = 5}, None, 0, 1.0);
            let data = run {
                TestUnitFixtures.withMockBoard(testBoard(), () ->
                    TestUnitFixtures.withMockRosterQuery(Nil, () ->
                        runPhysics(TurnPhase.Phase.PlayerCursor, initial, Set#{GameEngine.Key.Up})))
            } with GameLogger.withLogger(rc)
              with TurnPhase.withState(rc)
              with CursorState.withState(rc);
            Assert.assertEq(expected = (5, 5), (data#gridPos#x, data#gridPos#y))
        }

    /// 方向キーが離れたフレームでは hold 状態 (holdDir / holdSteps) がリセットされる。
    /// (再度押したときに「初速」から再加速できるように)。gridPos は変わらない。
    /// holdDir record は Eq 未定義なので Option.isEmpty で Bool 化して比較する。
    @Test
    def testPhysicsProcessClearsHoldWhenNoKeyPressed(): Unit \ Assert =
        region rc {
            let initial = cursorDataAt({x = 5, y = 5}, Some(Vec2i.up()), 3, 0.0);
            let data = run {
                TestUnitFixtures.withMockBoard(testBoard(), () ->
                    TestUnitFixtures.withMockRosterQuery(Nil, () ->
                        runPhysics(TurnPhase.Phase.PlayerCursor, initial, Set.empty())))
            } with GameLogger.withLogger(rc)
              with TurnPhase.withState(rc)
              with CursorState.withState(rc);
            Assert.assertEq(
                expected = (5, 5, true, 0),
                (data#gridPos#x, data#gridPos#y,
                 Option.isEmpty(data#holdDir), data#holdSteps))
        }

    // ════════════════════════════════════════════════════════
    // step (PlayerAttack フェーズ) — ターゲットサイクル
    // ════════════════════════════════════════════════════════

    /// 攻撃フェーズで射程内に敵候補が居ない状態で Down を「押下開始」したフレーム →
    /// 内部の cycleToTarget は targets = Nil を受けて gridPos を動かさない (X キャンセル待ち)。
    @Test
    def testPhysicsProcessAttackNoopsWhenNoTargetsInRange(): Unit \ Assert =
        region rc {
            let initial = cursorDataAt({x = 3, y = 3}, None, 0, 0.0);
            let data = run {
                TestUnitFixtures.withMockBoard(testBoard(), () ->
                    TestUnitFixtures.withMockRosterQuery(Nil, () ->
                        runPhysics(TurnPhase.Phase.PlayerAttack, initial, Set#{GameEngine.Key.Down})))
            } with GameLogger.withLogger(rc)
              with TurnPhase.withState(rc)
              with CursorState.withState(rc);
            Assert.assertEq(expected = (3, 3), (data#gridPos#x, data#gridPos#y))
        }

    /// 攻撃フェーズで snag 区間中 (snagRemaining > 0) はターゲット切替も走らない。
    /// Down を押しても gridPos は (3,3) のまま。
    @Test
    def testPhysicsProcessAttackNoopsWhileSnagging(): Unit \ Assert =
        region rc {
            let initial = cursorDataAt({x = 3, y = 3}, None, 0, 1.0);
            let data = run {
                TestUnitFixtures.withMockBoard(testBoard(), () ->
                    TestUnitFixtures.withMockRosterQuery(Nil, () ->
                        runPhysics(TurnPhase.Phase.PlayerAttack, initial, Set#{GameEngine.Key.Down})))
            } with GameLogger.withLogger(rc)
              with TurnPhase.withState(rc)
              with CursorState.withState(rc);
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

    /// SelectedPlayer / PartyQuery / World.WorldQuery を一度に剥がすラッパ。
    /// `TradeRange.show` + `snapToFirstTradeCellOrPlayer` を続けて実行する用途。
    def runWithTradeSnapMocks(world: World, selectedId: Int32, thunk: Unit -> a \ ef):
            a \ (ef - SelectedPlayer.State - PlayerData.PartyQuery - World.WorldQuery) =
        TestUnitFixtures.withSelectedPlayer(selectedId, () ->
            TestUnitFixtures.withMockPartyQuery(TestUnitFixtures.worldPlayers(world), () ->
                TestUnitFixtures.withWorldQuery(world, thunk)))

    /// cursor resource の現在 gridPos を (x, y) タプルで取り出す。
    def cursorPosOf(): (Int32, Int32) \ CursorState.State =
        let d = CursorDriver.getCursorData();
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
        region rc {
            let world = TestWorldFixtures.worldOf(List.flatten(
                TestWorldFixtures.playerCmds(TestWorldFixtures.unitSpec(0, {x = 5, y = 5}))
                    :: TestWorldFixtures.playerCmds(TestWorldFixtures.unitSpec(1, {x = 5, y = 4}))
                    :: TestWorldFixtures.playerCmds(TestWorldFixtures.unitSpec(2, {x = 4, y = 5}))
                    :: TestWorldFixtures.playerCmds(TestWorldFixtures.unitSpec(3, {x = 6, y = 5}))
                    :: TestWorldFixtures.playerCmds(TestWorldFixtures.unitSpec(4, {x = 5, y = 6}))
                    :: Nil));
            let result = runWithTradeSnapMocks(world, 0, () -> run {
                CursorDriver.add();
                TradeRange.show();
                CursorDriver.snapToFirstTradeCellOrPlayer();
                cursorPosOf()
            } with CursorState.withState(rc)
              with RangeOverlayState.withState(rc));
            Assert.assertEq(expected = (5, 4), result)
        }

    /// 隣接味方が 1 人だけ (東に id=1) のとき、その人の位置に直接スナップする。
    /// 複数考慮の特殊ケースとして単一ケースも pin。
    @Test
    def testSnapToFirstTradeCellPicksTheOnlyAdjacentAlly(): Unit \ Assert =
        region rc {
            let world = TestWorldFixtures.worldOf(List.flatten(
                TestWorldFixtures.playerCmds(TestWorldFixtures.unitSpec(0, {x = 5, y = 5}))
                    :: TestWorldFixtures.playerCmds(TestWorldFixtures.unitSpec(1, {x = 6, y = 5}))
                    :: Nil));
            let result = runWithTradeSnapMocks(world, 0, () -> run {
                CursorDriver.add();
                TradeRange.show();
                CursorDriver.snapToFirstTradeCellOrPlayer();
                cursorPosOf()
            } with CursorState.withState(rc)
              with RangeOverlayState.withState(rc));
            Assert.assertEq(expected = (6, 5), result)
        }

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
            (CursorDriver.cursorVisibleForPhase(TurnPhase.Phase.PlayerCursor),
             CursorDriver.cursorVisibleForPhase(TurnPhase.Phase.PlayerAttack),
             CursorDriver.cursorVisibleForPhase(TurnPhase.Phase.PlayerMoving),
             CursorDriver.cursorVisibleForPhase(TurnPhase.Phase.GatherMove),
             CursorDriver.cursorVisibleForPhase(TurnPhase.Phase.ItemSelect),
             CursorDriver.cursorVisibleForPhase(TurnPhase.Phase.LevelUpView),
             CursorDriver.cursorVisibleForPhase(TurnPhase.Phase.StairsExit)))
}
