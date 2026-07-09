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

    /// 味方 1 体だけの World。`pendingLevelUp` が Some なら Cmd.SetPendingLevelUp で
    /// World へ seed する（pendingLevelUp は World 権威＝PlayerScene.anyPendingLevelUp が読む）。
    def worldWith(pendingLevelUp: Option[LevelSystem.Result]): World =
        let base = TestWorldFixtures.playerCmds(TestWorldFixtures.unitSpec(0, {x = 2, y = 2}));
        let cmds = match pendingLevelUp {
            case Some(r) => List.append(base, World.Cmd.SetPendingLevelUp(0, Some(r)) :: Nil)
            case None    => base
        };
        TestWorldFixtures.worldOf(cmds)

    /// commitWaitedAndAdvance を選択中 = Player(0) で 1 回呼び、終了時 phase を返す。
    def commitOnce(pendingLevelUp: Option[LevelSystem.Result]): TurnPhase.Phase =
        region rc {
            let ((_, phase), _world) =
                TestUnitFixtures.withWorldAppliedSeeded(rc, worldWith(pendingLevelUp), () ->
                TestUnitFixtures.withMockGameLogger(() ->
                TestUnitFixtures.withMockEnemyTurnQueue(() ->
                TestUnitFixtures.withPhaseRef(rc, TurnPhase.Phase.ActionSelect, () ->
                TestUnitFixtures.withSelectionRef(rc,
                    {id = Some(0), drafts = Nil, gatherActive = false}, () ->
                TestUnitFixtures.withCursorState(rc, () ->
                TestUnitFixtures.withRangeOverlay(rc, () ->
                    TurnFlow.commitWaitedAndAdvance())))))));
            phase
        }

    /// レベルアップ表示待ちの味方が居る間は、ターンを進めず LevelUpView へ割り込む。
    @Test
    def testCommitInterruptsForPendingLevelUp(): Unit \ Assert =
        let stats  = LevelSystem.statsOf(TestUnitFixtures.testResource(4, 10));
        let result = LevelSystem.buildResult("test", 1, stats, stats);
        Assert.assertEq(
            expected = TurnPhase.Phase.LevelUpView,
            commitOnce(Some(result)))

    /// 唯一の味方を waited にすると active が残らないので敵ターンへ進む。
    @Test
    def testCommitAdvancesToEnemyTurnWhenAllWaited(): Unit \ Assert =
        Assert.assertEq(
            expected = TurnPhase.Phase.EnemyTurn,
            commitOnce(None))
}
