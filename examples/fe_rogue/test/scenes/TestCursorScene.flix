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
        let pos = MapScene.cellCenter(gridPos);
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
                        gridPos           = gridPos,
                        moveTiles         = 5,
                        hp                = 10,
                        waited            = false,
                        attackTargetId    = None,
                        resource          = TestUnitFixtures.testResource(5, 10),
                        weapons           = TestUnitFixtures.testWeapon() :: Nil,
                        selectedWeaponIdx = None,
                        moveStepsTaken    = 0
                    })))

    /// SelectedPlayer.State のスタブ handler（未選択を返す）。
    def withNoSelection(thunk: Unit -> a \ ef): a \ (ef - SelectedPlayer.State) =
        run { thunk() } with handler SelectedPlayer.State {
            def get(k) = k(SelectedPlayer.cleared())
            def put(_, k) = k()
        }

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
            EngineNode.Marker2DWithState(Marker2D.make(MapScene.cellCenter(pos)),
                NodeTag.Player({
                    id                = id,
                    gridPos           = pos,
                    moveTiles         = 5,
                    hp                = 10,
                    waited            = waited,
                    attackTargetId    = None,
                    resource          = TestUnitFixtures.testResource(5, 10),
                    weapons           = TestUnitFixtures.testWeapon() :: Nil,
                    selectedWeaponIdx = None,
                    moveStepsTaken    = 0
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
        let result = withNoSelection(() -> TestUnitFixtures.withNoopTween(() -> TestUnitFixtures.withNoopAnim(() ->
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
        let result = withNoSelection(() -> TestUnitFixtures.withNoopTween(() -> TestUnitFixtures.withNoopAnim(() ->
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
            let result = run {
                SelectedPlayer.State.put({
                    id     = Some(0),
                    origin = Some(p0Pos)
                });
                let scene = cursorAddPure(initial);
                let after = PlayerScene.commitWaitedAndAdvance(scene);
                cursorState(after)
            } with handler PlayerScene.PartyQuery {
                // 古い snapshot: setWaited 前の両方 active な状態を返し続ける
                def get(id, k)           = k(PlayerScene.get(id, initial))
                def getAll(k)            = k(PlayerScene.getAll(initial))
                def getGridPos(id, k)    = k(PlayerScene.getGridPos(id, initial))
                def getMoveTiles(id, k)  = k(PlayerScene.getMoveTiles(id, initial))
            }
              with Tween.withScheduler(rc)
              with AnimationPlayer.withScheduler(rc)
              with GameLogger.withLogger(rc)
              with EnemyTurn.withQueue(rc)
              with TurnPhase.withState(rc)
              with SelectedPlayer.withState(rc);
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
}
