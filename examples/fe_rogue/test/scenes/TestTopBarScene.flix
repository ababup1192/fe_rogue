/// TopBarScene の純粋ロジックを固定する:
///   - isEnemyPhase: EnemyTurn のみ敵軍、他は自軍
///   - isBusy: hold>0 の間だけ true（敵ターン開始の「間」）
///   - hasObservedEnemy: shown==Some(true) かワイプ目標が enemy のとき true（0 体敵ターンの取りこぼし防止）
mod TestTopBarScene {

    /// TopBar ノード（CanvasLayer + 状態）だけを持つ最小 scene を作る。
    def topBarScene(data: TopBarScene.Data): Scene[NodeTag] =
        Scene.empty()
            |> Scene.addNode("TopBar",
                EngineNode.CanvasLayerWithState(CanvasLayer.make(4), NodeTag.TopBar(data)))

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
        let scene = topBarScene(mkData(Some(true), None, Duration.millis(700)));
        Assert.assertEq(expected = true, TopBarScene.isBusy(scene))

    @Test
    def testIsBusyFalseWhenHoldZero(): Unit \ Assert =
        let scene = topBarScene(mkData(Some(true), None, Duration.zero()));
        Assert.assertEq(expected = false, TopBarScene.isBusy(scene))

    // ── hasObservedEnemy ──

    @Test
    def testHasObservedEnemyWhenShown(): Unit \ Assert =
        let scene = topBarScene(mkData(Some(true), None, Duration.zero()));
        Assert.assertEq(expected = true, TopBarScene.hasObservedEnemy(scene))

    @Test
    def testHasObservedEnemyWhenWipingToEnemy(): Unit \ Assert =
        // base はまだ player だが enemy へワイプ中なら観測済み扱い。
        let scene = topBarScene(mkData(Some(false), Some(true), Duration.millis(700)));
        Assert.assertEq(expected = true, TopBarScene.hasObservedEnemy(scene))

    @Test
    def testHasObservedEnemyFalseInitial(): Unit \ Assert =
        let scene = topBarScene(mkData(None, None, Duration.zero()));
        Assert.assertEq(expected = false, TopBarScene.hasObservedEnemy(scene))

    @Test
    def testHasObservedEnemyFalseWhenPlayer(): Unit \ Assert =
        let scene = topBarScene(mkData(Some(false), None, Duration.zero()));
        Assert.assertEq(expected = false, TopBarScene.hasObservedEnemy(scene))
}
