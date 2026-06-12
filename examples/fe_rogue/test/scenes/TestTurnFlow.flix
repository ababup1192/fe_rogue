// TurnFlow.commitWaitedAndAdvance のフェーズ前進判定の検証。
//
// 検証する観点:
//   - pendingLevelUp 保留中はターンを進めず LevelUpView へ割り込む
//   - active な味方が残っていなければ敵ターン (EnemyTurn) へ進む
//
// 「次の active 味方へカーソルが飛ぶ」経路は TestCursorScene の統合テスト
// (testCommitWaitedAndAdvanceMovesCursorToNextActive) が stale PartyQuery 回帰込みで
// 担保しているので、ここでは重複させない。

mod TestTurnFlow {

    /// 指定 id の味方 1 体。`pendingLevelUp` を作り分ける。
    def playerData(id: Int32,
                    pendingLevelUp: Option[LevelSystem.Result]): PlayerScene.Data = {
        id                = id,
        gridPos           = {x = 2, y = 2},
        moveTiles         = 4,
        hp                = 10,
        waited            = false,
        attackTargetId    = None,
        resource          = TestUnitFixtures.testResource(4, 10),
        weapons           = TestUnitFixtures.testWeapon() :: Nil,
        staves            = Nil,
        consumables       = Nil,
        selectedItem      = None,
        moveStepsTaken    = 0,
        facing            = Staff.Direction.Down,
        hidden            = false,
        usedStairs        = false,
        level             = 1,
        exp               = 0,
        pendingLevelUp    = pendingLevelUp,
        statuses          = Nil,
        rings          = Nil,
        ringEquipped          = false,
        followUpUsed   = false
    }

    /// World 配下に味方 1 体だけの最小シーン。
    def soloScene(pendingLevelUp: Option[LevelSystem.Result]): Scene[NodeTag] =
        let world = Marker2D.make(Vec2.zero()) |> CanvasItem.setYSortEnabled(true);
        Scene.empty()
            |> Scene.addNode(MapScene.worldName(),
                EngineNode.Marker2DWithState(world, NodeTag.NoTag))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(0),
                EngineNode.Marker2DWithState(Marker2D.make(Vec2.zero()),
                    NodeTag.Player(playerData(0, pendingLevelUp))))

    /// commitWaitedAndAdvance を選択中 = Player(0) で 1 回呼び、終了時 phase を返す。
    def commitOnce(scene: Scene[NodeTag]): TurnPhase.Phase =
        region rc {
            TestUnitFixtures.withMockGameLogger(() ->
            TestUnitFixtures.withMockEnemyTurnQueue(() ->
            TestUnitFixtures.withNoopTween(() ->
            TestUnitFixtures.withNoopAnim(() ->
                run {
                    SelectedPlayer.State.put({id = Some(0), drafts = Nil});
                    let _ = TurnFlow.commitWaitedAndAdvance(scene);
                    TurnPhase.State.get()
                } with TurnPhase.withState(rc)
                  with SelectedPlayer.withState(rc)))))
        }

    /// レベルアップ表示待ちの味方が居る間は、ターンを進めず LevelUpView へ割り込む。
    @Test
    def testCommitInterruptsForPendingLevelUp(): Unit \ Assert =
        let stats  = LevelSystem.statsOf(TestUnitFixtures.testResource(4, 10));
        let result = LevelSystem.buildResult("test", 1, stats, stats);
        Assert.assertEq(
            expected = TurnPhase.Phase.LevelUpView,
            commitOnce(soloScene(Some(result))))

    /// 唯一の味方を waited にすると active が残らないので敵ターンへ進む。
    @Test
    def testCommitAdvancesToEnemyTurnWhenAllWaited(): Unit \ Assert =
        Assert.assertEq(
            expected = TurnPhase.Phase.EnemyTurn,
            commitOnce(soloScene(None)))
}
