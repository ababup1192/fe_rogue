/// TopBarScene の純粋ロジックを固定する:
///   - isEnemyPhase: EnemyTurn のみ敵軍、他は自軍
///   - isBusyOf: hold>0 の間だけ true（敵ターン開始の「間」）
///   - hasObservedEnemyOf: shown==Some(true) かワイプ目標が enemy のとき true（0 体敵ターンの取りこぼし防止）
/// 状態は resource が持つため、判定は scene 経由でなく Data 直の純関数を観測する。
mod TestTopBarScene {

    /// 状態レコードの簡易ビルダ。
    def mkData(shown: Option[Bool], animTarget: Option[Bool],
               hold: Duration.Duration): TopBarScene.Data =
        ({shown = shown, animTarget = animTarget, anim = Duration.zero(), hold = hold}: TopBarScene.Data)

    // ── isEnemyPhase ──

    @Test
    def testIsEnemyPhaseEnemyTurn(): Unit \ Assert =
        Assert.assertEq(expected = true, TopBarScene.isEnemyPhase(TurnPhase.Phase.EnemyTurn))

    @Test
    def testIsEnemyPhasePlayerCursor(): Unit \ Assert =
        Assert.assertEq(expected = false, TopBarScene.isEnemyPhase(TurnPhase.Phase.PlayerCursor))

    @Test
    def testIsEnemyPhaseActionSelect(): Unit \ Assert =
        Assert.assertEq(expected = false, TopBarScene.isEnemyPhase(TurnPhase.Phase.ActionSelect))

    // ── isBusy（敵ターン開始の「間」）──

    @Test
    def testIsBusyWhileHold(): Unit \ Assert =
        Assert.assertEq(expected = true, TopBarScene.isBusyOf(mkData(Some(true), None, Duration.millis(700))))

    @Test
    def testIsBusyFalseWhenHoldZero(): Unit \ Assert =
        Assert.assertEq(expected = false, TopBarScene.isBusyOf(mkData(Some(true), None, Duration.zero())))

    // ── hasObservedEnemy ──

    @Test
    def testHasObservedEnemyWhenShown(): Unit \ Assert =
        Assert.assertEq(expected = true, TopBarScene.hasObservedEnemyOf(mkData(Some(true), None, Duration.zero())))

    @Test
    def testHasObservedEnemyWhenWipingToEnemy(): Unit \ Assert =
        // base はまだ player だが enemy へワイプ中なら観測済み扱い。
        Assert.assertEq(expected = true, TopBarScene.hasObservedEnemyOf(mkData(Some(false), Some(true), Duration.millis(700))))

    @Test
    def testHasObservedEnemyFalseInitial(): Unit \ Assert =
        Assert.assertEq(expected = false, TopBarScene.hasObservedEnemyOf(mkData(None, None, Duration.zero())))

    @Test
    def testHasObservedEnemyFalseWhenPlayer(): Unit \ Assert =
        Assert.assertEq(expected = false, TopBarScene.hasObservedEnemyOf(mkData(Some(false), None, Duration.zero())))
}
