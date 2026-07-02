/// PhaseTransitions の `enter*` 関数群が「フェーズ遷移時の overlay と cursor の状態」
/// を仕様どおりに整えるかを観測する。
///
/// 検証の枠組み:
///   - 4 種の range ノード (MoveRange / MoveAttackRange / PlayerAttackRange / EnemyRange)
///     と Cursor を **すべて** scene に手で挿入してから `enter*` を呼び、
///     どれが残ってどれが消えたか、cursor が visible か、TurnPhase が何になったかを
///     1 タプルで一気に観測する。
///   - 範囲計算（Board / WeaponRange）の正しさは別テスト（TestBoard / TestWeapon）が
///     担うので、ここでは「`enter*` がどの操作を呼んだか」だけを観測する。
///   - `enterPlayerCursorAt` は既存の `TestCursorScene.testEnterPlayerCursorAtBypassesPartyQuery`
///     でカバー済みなのでここでは扱わない。
mod TestPhaseTransitions {

    // ════════════════════════════════════════════════════════
    // ヘルパー
    // ════════════════════════════════════════════════════════

    /// テスト用ダミーセル（観測対象は「あるか／ないか」だけなので中身は重要でない）
    def dummyCell(): {x = Int32, y = Int32} = {x = 1, y = 1}

    def dummyCells(): List[{x = Int32, y = Int32}] =
        dummyCell() :: Nil

    /// 4 種の range ノードと Cursor を持つ scene を組む。
    /// 全 range は手で挿入する (refresh/show を呼ばずに観測対象の初期状態を作る)。
    /// Cursor は Marker2D.make でデフォルト visible=true。
    def sceneWithAllRangesAndCursor(): Scene[NodeTag] =
        let cursorMarker = Marker2D.make(Vec2.zero());
        let cursorData: CursorScene.Data = {
            gridPos            = dummyCell(),
            lastHoveredEnemyId = None,
            holdDir            = None,
            holdSteps          = 0
        };
        let moveData: MoveRangeScene.Data            = {reachable = dummyCells(), drawCells = dummyCells()};
        let moveAttackData: MoveAttackRangeScene.Data = {cells = dummyCells()};
        let playerAttackData: PlayerAttackRangeScene.Data = {cells = dummyCells()};
        let enemyData: EnemyRangeScene.Data          = {enemyId = 0, reachable = dummyCells()};
        let mkMarker = tag ->
            EngineNode.Marker2DWithState(Marker2D.make(Vec2.zero()), tag);
        Scene.empty()
            |> Scene.addNode("Cursor",
                EngineNode.Marker2DWithState(cursorMarker, NodeTag.Cursor(cursorData)))
            |> Scene.addNode("MoveRange",         mkMarker(NodeTag.MoveRange(moveData)))
            |> Scene.addNode("MoveAttackRange",   mkMarker(NodeTag.MoveAttackRange(moveAttackData)))
            |> Scene.addNode("PlayerAttackRange", mkMarker(NodeTag.PlayerAttackRange(playerAttackData)))
            |> Scene.addNode("EnemyRange",        mkMarker(NodeTag.EnemyRange(enemyData)))

    /// 観測タプル: (MoveRange あり, MoveAttackRange あり, PlayerAttackRange あり,
    ///                EnemyRange あり, Cursor visible, TurnPhase の値)
    def observe(scene: Scene[NodeTag]):
            (Bool, Bool, Bool, Bool, Bool, TurnPhase.Phase) \ TurnPhase.State =
        let hasNode = path -> Option.nonEmpty(Scene.getEngineNode(path, scene));
        let cursorVisible = match Scene.getEngineNode(CursorScene.cursorPath(), scene) {
            case Some(EngineNode.Marker2DWithState(m, _)) => CanvasItem.isVisible(m)
            case _                                          => bug!("Cursor node not found")
        };
        (hasNode(MoveRangeScene.moveRangePath()),
         hasNode(MoveAttackRangeScene.rangePath()),
         hasNode(PlayerAttackRangeScene.attackRangePath()),
         hasNode(EnemyRangeScene.enemyRangePath()),
         cursorVisible,
         TurnPhase.State.get())

    // ════════════════════════════════════════════════════════
    // enterPlayerCursor — 味方 3 range を消す / 敵 range は残す / cursor 表示
    // ════════════════════════════════════════════════════════

    /// PlayerCursor 進入で:
    ///   - Move / MoveAttack / PlayerAttack の 3 player range が全消去
    ///   - EnemyRange は残る（ホバー表示はカーソル操作中も生きる）
    ///   - Cursor は表示される
    ///   - TurnPhase は PlayerCursor
    /// SelectedPlayer = cleared() / PartyQuery 空 → snapToPlayer は fallback {0,0} で no-op 相当。
    @Test
    def testEnterPlayerCursorClearsPlayerRangesAndShowsCursor(): Unit \ Assert =
        region rc {
            let initial = sceneWithAllRangesAndCursor();
            let result = TestUnitFixtures.withNoopTween(() ->
                TestUnitFixtures.withNoopAnim(() ->
                    TestUnitFixtures.withMockPartyQuery(Scene.empty(), () ->
                        run {
                            // showAllActive 等が view 状態 Cmd を emit するため捨て handler で吸収。
                            let after = run { PhaseTransitions.enterPlayerCursor(initial) }
                                with handler World.Command { def emit(_c, k) = k() };
                            observe(after)
                        } with TurnPhase.withState(rc)
                          with SelectedPlayer.withState(rc))));
            Assert.assertEq(
                expected = (false, false, false, true, true, TurnPhase.Phase.PlayerCursor),
                result)
        }

    // ════════════════════════════════════════════════════════
    // enterPlayerMoving — EnemyRange 消去 / Move/MoveAttack を refresh / cursor 非表示
    // ════════════════════════════════════════════════════════

    /// PlayerMoving 進入で:
    ///   - EnemyRange は消える
    ///   - Move / MoveAttack は refresh される (SelectedPlayer = None なので「消して再構築なし」 = 消える)
    ///   - PlayerAttackRange は触らない (前 phase で消えているはずだが、ここでは残ると仮定)
    ///   - Cursor は隠れる
    ///   - TurnPhase は PlayerMoving
    @Test
    def testEnterPlayerMovingClearsEnemyAndMoveRangesHidesCursor(): Unit \ Assert =
        region rc {
            let initial = sceneWithAllRangesAndCursor();
            let result = run {
                let after = run { PhaseTransitions.enterPlayerMoving(initial) }
                    with handler World.WorldQuery { def get(k) = k(World.empty()) };
                observe(after)
            } with TurnPhase.withState(rc)
              with SelectedPlayer.withState(rc);
            Assert.assertEq(
                expected = (false, false, true, false, false, TurnPhase.Phase.PlayerMoving),
                result)
        }

    // ════════════════════════════════════════════════════════
    // enterPlayerAttack — Move/MoveAttack 消去 / PlayerAttackRange を show / EnemyRange 残す
    // ════════════════════════════════════════════════════════

    /// PlayerAttack 進入で:
    ///   - Move / MoveAttack の青系は消える
    ///   - PlayerAttackRange は show 経由で消されてから再構築の試みが入るが、SelectedPlayer = None
    ///     のため再構築せず消えたまま (= absent)
    ///   - EnemyRange は触らない (= present のまま)
    ///   - Cursor は表示される
    ///   - TurnPhase は PlayerAttack
    @Test
    def testEnterPlayerAttackClearsMoveRangesAndShowsCursor(): Unit \ Assert =
        region rc {
            let initial = sceneWithAllRangesAndCursor();
            let result = TestUnitFixtures.withNoopTween(() ->
                TestUnitFixtures.withNoopAnim(() ->
                    TestUnitFixtures.withMockPartyQuery(Scene.empty(), () ->
                        TestUnitFixtures.withMockRosterQuery(Scene.empty(), () ->
                            run {
                                let after = run { PhaseTransitions.enterPlayerAttack(initial) }
                                    with handler World.WorldQuery { def get(k) = k(World.empty()) };
                                observe(after)
                            } with TurnPhase.withState(rc)
                              with SelectedPlayer.withState(rc)))));
            Assert.assertEq(
                expected = (false, false, false, true, true, TurnPhase.Phase.PlayerAttack),
                result)
        }

    // ════════════════════════════════════════════════════════
    // enterGatherMove — 集合（行軍）の開始。MoveRange を refresh / 他の味方系・敵系は消す / cursor 非表示
    // ════════════════════════════════════════════════════════

    /// GatherMove 進入(=「集合」確定で行軍開始)で:
    ///   - MoveRange は refresh される (SelectedPlayer = None なので「消して再構築なし」 = 消える)
    ///   - MoveAttack / EnemyRange は消える
    ///   - PlayerAttackRange は触らない (前 phase で消えているはずだが、ここでは残ると仮定)
    ///   - Cursor は隠れる
    ///   - TurnPhase は GatherMove
    @Test
    def testEnterGatherMoveRefreshesMoveRangeHidesCursor(): Unit \ Assert =
        region rc {
            let initial = sceneWithAllRangesAndCursor();
            let result = run {
                let after = run { PhaseTransitions.enterGatherMove(initial) }
                    with handler World.WorldQuery { def get(k) = k(World.empty()) };
                observe(after)
            } with TurnPhase.withState(rc)
              with SelectedPlayer.withState(rc);
            Assert.assertEq(
                expected = (false, false, true, false, false, TurnPhase.Phase.GatherMove),
                result)
        }

    // ════════════════════════════════════════════════════════
    // enterEnemyTurn — 味方 3 range をすべて消す / EnemyRange と cursor 状態は触らない
    // ════════════════════════════════════════════════════════

    /// EnemyTurn 進入で:
    ///   - Move / MoveAttack / PlayerAttackRange の 3 味方 range が全消去
    ///   - EnemyRange は触らない
    ///   - Cursor の visible 状態は触らない (前 phase の値を引き継ぐ。
    ///     初期 Marker2D.make は default visible なので true)
    ///   - TurnPhase は EnemyTurn
    @Test
    def testEnterEnemyTurnClearsAllPlayerRanges(): Unit \ Assert =
        region rc {
            let initial = sceneWithAllRangesAndCursor();
            let result = run {
                // showAllActive 等が view 状態 Cmd を emit するため捨て handler で吸収。
                let after = run { PhaseTransitions.enterEnemyTurn(initial) }
                    with handler World.Command { def emit(_c, k) = k() };
                observe(after)
            } with TurnPhase.withState(rc);
            Assert.assertEq(
                expected = (false, false, false, true, true, TurnPhase.Phase.EnemyTurn),
                result)
        }
}
