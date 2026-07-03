/// TopBarUi の純粋ロジックを固定する:
///   - isEnemyPhase: EnemyTurn のみ敵軍、他は自軍
///   - isBusyOf: hold>0 の間だけ true（敵ターン開始の「間」）
///   - hasObservedEnemyOf: shown==Some(true) かワイプ目標が enemy のとき true（0 体敵ターンの取りこぼし防止）
///   - advance: ワイプ状態機械（起動即確定 / 開始 / 進行中の sweep 幅 / 完了確定）
/// 状態は resource（TopBarState）が持つため、判定は scene 経由でなく Data 直の純関数を観測する。
mod TestTopBarUi {

    /// 状態レコードの簡易ビルダ（フロア表示は判定に無関係なので空）。
    def mkData(shown: Option[Bool], animTarget: Option[Bool],
               anim: Duration.Duration, hold: Duration.Duration): TopBarState.Data =
        ({shown = shown, animTarget = animTarget, anim = anim, hold = hold,
          floorLabel = "", floorName = ""}: TopBarState.Data)

    // ── isEnemyPhase ──

    @Test
    def testIsEnemyPhaseEnemyTurn(): Unit \ Assert =
        Assert.assertEq(expected = true, TopBarUi.isEnemyPhase(TurnPhase.Phase.EnemyTurn))

    @Test
    def testIsEnemyPhasePlayerCursor(): Unit \ Assert =
        Assert.assertEq(expected = false, TopBarUi.isEnemyPhase(TurnPhase.Phase.PlayerCursor))

    @Test
    def testIsEnemyPhaseActionSelect(): Unit \ Assert =
        Assert.assertEq(expected = false, TopBarUi.isEnemyPhase(TurnPhase.Phase.ActionSelect))

    // ── isBusy（敵ターン開始の「間」）──

    @Test
    def testIsBusyWhileHold(): Unit \ Assert =
        Assert.assertEq(expected = true,
            TopBarUi.isBusyOf(mkData(Some(true), None, Duration.zero(), Duration.millis(700))))

    @Test
    def testIsBusyFalseWhenHoldZero(): Unit \ Assert =
        Assert.assertEq(expected = false,
            TopBarUi.isBusyOf(mkData(Some(true), None, Duration.zero(), Duration.zero())))

    // ── hasObservedEnemy ──

    @Test
    def testHasObservedEnemyWhenShown(): Unit \ Assert =
        Assert.assertEq(expected = true,
            TopBarUi.hasObservedEnemyOf(mkData(Some(true), None, Duration.zero(), Duration.zero())))

    @Test
    def testHasObservedEnemyWhenWipingToEnemy(): Unit \ Assert =
        // base はまだ player だが enemy へワイプ中なら観測済み扱い。
        Assert.assertEq(expected = true,
            TopBarUi.hasObservedEnemyOf(mkData(Some(false), Some(true), Duration.zero(), Duration.millis(700))))

    @Test
    def testHasObservedEnemyFalseInitial(): Unit \ Assert =
        Assert.assertEq(expected = false,
            TopBarUi.hasObservedEnemyOf(mkData(None, None, Duration.zero(), Duration.zero())))

    @Test
    def testHasObservedEnemyFalseWhenPlayer(): Unit \ Assert =
        Assert.assertEq(expected = false,
            TopBarUi.hasObservedEnemyOf(mkData(Some(false), None, Duration.zero(), Duration.zero())))

    // ════════════════════════════════════════════════════════
    // advance: ワイプ状態機械（純粋コア）
    //   観測順: (次shown, 次animTarget, baseEnemy, sweepTarget, progress, startWipe)
    // ════════════════════════════════════════════════════════

    /// 起動直後（shown=None）に敵フェイズを観測 → ワイプ無しで即 base=敵に確定。sweep なし・無音。
    @Test
    def testAdvanceInitialConfirmsImmediately(): Unit \ Assert =
        let frame = TopBarUi.advance(Duration.millis(16), TurnPhase.Phase.EnemyTurn,
                                     mkData(None, None, Duration.zero(), Duration.zero()));
        Assert.assertEq(
            expected = (Some(true), None, true, (None: Option[Bool]), 0.0, false),
            (frame#data#shown, frame#data#animTarget, frame#baseEnemy, frame#sweepTarget, frame#progress, frame#startWipe))

    /// player 確定中に敵を観測 → ワイプ開始。base は player のまま、sweep 目標=敵、開始音トリガ。
    @Test
    def testAdvanceStartsWipe(): Unit \ Assert =
        let frame = TopBarUi.advance(Duration.millis(16), TurnPhase.Phase.EnemyTurn,
                                     mkData(Some(false), None, Duration.zero(), Duration.zero()));
        Assert.assertEq(
            expected = (Some(false), Some(true), false, Some(true), 0.0, true),
            (frame#data#shown, frame#data#animTarget, frame#baseEnemy, frame#sweepTarget, frame#progress, frame#startWipe))

    /// ワイプ進行中（残り 350ms から 100ms 経過 → 残り 250ms=半分）。base は player 維持・
    /// sweep 目標=敵・progress=0.5（1 - 250/500）。開始音は鳴らさない。
    @Test
    def testAdvanceMidWipeHalfProgress(): Unit \ Assert =
        let frame = TopBarUi.advance(Duration.millis(100), TurnPhase.Phase.EnemyTurn,
                                     mkData(Some(false), Some(true), Duration.millis(350), Duration.millis(700)));
        Assert.assertEq(
            expected = (Some(false), Some(true), false, Some(true), 0.5, false),
            (frame#data#shown, frame#data#animTarget, frame#baseEnemy, frame#sweepTarget, frame#progress, frame#startWipe))

    /// ワイプ完了（残り 50ms から 100ms 経過 → 0 以下）。新フェイズ=敵を base に確定し sweep を畳む。
    @Test
    def testAdvanceCompletesWipe(): Unit \ Assert =
        let frame = TopBarUi.advance(Duration.millis(100), TurnPhase.Phase.EnemyTurn,
                                     mkData(Some(false), Some(true), Duration.millis(50), Duration.millis(700)));
        Assert.assertEq(
            expected = (Some(true), None, true, (None: Option[Bool]), 0.0, false),
            (frame#data#shown, frame#data#animTarget, frame#baseEnemy, frame#sweepTarget, frame#progress, frame#startWipe))
}
