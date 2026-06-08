/// PhaseBannerScene の純粋な状態更新 `step` を検証する。
///
/// `step` は「今のフェーズが敵ターンか」と前フレームの状態から、(1) 見せたいターンを控える、
/// (2) 演出していないときだけ控えを取り出してバナーを開始する、(3) スライド演出の段階を時間で
/// 進める、を担う。帯の描画・色差し替え・オフセット反映は scene 副作用なので、ここでは扱わず
/// 実機確認に委ねる。
///
/// 段階の長さ: 滑り込み 440ms / 静止 1520ms / 滑り抜け 440ms。
/// 「段階が終わる」系のテストは、どの段階の長さ(最大 1520ms)も確実に超える 2 秒(2000ms)を
/// 1 回だけ進めて、次の段階へ移ることを確認する。
mod TestPhaseBannerScene {

    use PhaseBannerScene.Stage

    // ════════════════════════════════════════════════════════
    // トリガー: 演出していない(Idle)ときはターンに合わせて即座にバナーを出す
    // ════════════════════════════════════════════════════════

    /// 起動直後（wasEnemy = None）の最初のフレームは、味方ターンとして味方バナーを出し始める。
    /// triggered = Some(false)（= 敵ではない = 味方）、段階は滑り込み開始。
    @Test
    def testFirstFrameTriggersPlayerBanner(): Unit \ Assert =
        let result = PhaseBannerScene.step(
            {stage = Stage.Idle, elapsed = Duration.zero(), wasEnemy = None, pending = None},
            false,
            Duration.millis(50));
        Assert.assertEq(expected = (Some(false), Stage.SlideIn),
                        (result#triggered, result#data#stage))

    /// 非表示(Idle)中に味方→敵へ切り替わると、その場で敵バナーを出し始める。
    /// triggered = Some(true)、段階は滑り込み。
    @Test
    def testTurnChangeWhileIdleTriggersEnemyBanner(): Unit \ Assert =
        let result = PhaseBannerScene.step(
            {stage = Stage.Idle, elapsed = Duration.zero(),
             wasEnemy = Some(false), pending = None},
            true,
            Duration.millis(50));
        Assert.assertEq(expected = (Some(true), Stage.SlideIn),
                        (result#triggered, result#data#stage))

    // ════════════════════════════════════════════════════════
    // 上書きしない: 演出中にターンが変わっても今の帯を最後まで出し、次は控える
    // ════════════════════════════════════════════════════════

    /// 味方バナーの静止中に敵ターンへ切り替わっても、味方バナーは上書きしない。
    /// triggered は出さず（None）、段階は静止のまま、敵ターンは控え(pending)に積む。
    /// これが「敵が一瞬で行動を終えても順番に最後まで見せる」ための核心。
    @Test
    def testBusyBannerDefersTurnChangeToPending(): Unit \ Assert =
        let result = PhaseBannerScene.step(
            {stage = Stage.Hold, elapsed = Duration.zero(),
             wasEnemy = Some(false), pending = None},
            true,
            Duration.millis(50));
        Assert.assertEq(expected = (None, Stage.Hold, Some(true)),
                        (result#triggered, result#data#stage, result#data#pending))

    /// 同じターンが続くフレームでは何も出さない（triggered = None、段階も控えも変わらない）。
    /// 味方ターン中のサブフェーズ移動でバナーが何度も走らないことの保証。
    @Test
    def testSameTurnDoesNotRetrigger(): Unit \ Assert =
        let result = PhaseBannerScene.step(
            {stage = Stage.Hold, elapsed = Duration.millis(100),
             wasEnemy = Some(false), pending = None},
            false,
            Duration.millis(50));
        Assert.assertEq(expected = (None, Stage.Hold, None),
                        (result#triggered, result#data#stage, result#data#pending))

    /// 帯が出終わって非表示(Idle)に戻ったフレームで、控えていたターンのバナーを出し始める。
    /// triggered = Some(true)、段階は滑り込み、控えは空に戻る。
    @Test
    def testIdleStartsPendingBanner(): Unit \ Assert =
        let result = PhaseBannerScene.step(
            {stage = Stage.Idle, elapsed = Duration.zero(),
             wasEnemy = Some(true), pending = Some(true)},
            true,
            Duration.millis(50));
        Assert.assertEq(expected = (Some(true), Stage.SlideIn, None),
                        (result#triggered, result#data#stage, result#data#pending))

    // ════════════════════════════════════════════════════════
    // 段階遷移: 滑り込み → 静止 → 滑り抜け → 非表示
    // ════════════════════════════════════════════════════════

    /// 滑り込み(440ms)が終わると静止段階へ移り、帯は中央(offsetX = 0)に収まる。
    @Test
    def testSlideInEndsAtCenter(): Unit \ Assert =
        let result = PhaseBannerScene.step(
            {stage = Stage.SlideIn, elapsed = Duration.zero(),
             wasEnemy = Some(false), pending = None},
            false,
            Duration.millis(2000));
        Assert.assertEq(expected = (Stage.Hold, 0.0),
                        (result#data#stage, result#offsetX))

    /// 静止(1520ms)が終わると滑り抜け段階へ移る。抜け始めなので帯はまだ中央(offsetX = 0)。
    @Test
    def testHoldEndsStartsSlideOut(): Unit \ Assert =
        let result = PhaseBannerScene.step(
            {stage = Stage.Hold, elapsed = Duration.zero(),
             wasEnemy = Some(false), pending = None},
            false,
            Duration.millis(2000));
        Assert.assertEq(expected = (Stage.SlideOut, 0.0),
                        (result#data#stage, result#offsetX))

    /// 滑り抜け(440ms)が終わると非表示(Idle)になり、帯は画面右外(offsetX = 140)へ退避する。
    @Test
    def testSlideOutEndsParksOffScreen(): Unit \ Assert =
        let result = PhaseBannerScene.step(
            {stage = Stage.SlideOut, elapsed = Duration.zero(),
             wasEnemy = Some(false), pending = None},
            false,
            Duration.millis(2000));
        Assert.assertEq(expected = (Stage.Idle, 140.0),
                        (result#data#stage, result#offsetX))

    // ════════════════════════════════════════════════════════
    // perceivedIsEnemy: LevelUpView 中はターン認識を据え置く
    // ════════════════════════════════════════════════════════

    /// 通常フェーズはそのまま敵ターン判定: EnemyTurn は true、それ以外は false。
    @Test
    def testPerceivedIsEnemyNormalPhases(): Unit \ Assert =
        Assert.assertEq(
            expected = (true, false, false),
            (PhaseBannerScene.perceivedIsEnemy(TurnPhase.Phase.EnemyTurn, Some(false)),
             PhaseBannerScene.perceivedIsEnemy(TurnPhase.Phase.PlayerCursor, Some(true)),
             PhaseBannerScene.perceivedIsEnemy(TurnPhase.Phase.PlayerAttack, None)))

    /// LevelUpView 中は実フェーズが EnemyTurn を外れても直前の認識(wasEnemy)を返す。
    /// 敵ターン由来なら true 据え置き、味方ターン由来なら false 据え置き。
    @Test
    def testPerceivedIsEnemyHoldsDuringLevelUpView(): Unit \ Assert =
        Assert.assertEq(
            expected = (true, false),
            (PhaseBannerScene.perceivedIsEnemy(TurnPhase.Phase.LevelUpView, Some(true)),
             PhaseBannerScene.perceivedIsEnemy(TurnPhase.Phase.LevelUpView, Some(false))))

    /// 回帰: 敵ターン中(wasEnemy = Some(true))の反撃でレベルアップして LevelUpView に
    /// 入っても、据え置きの isEnemy(= true) を step に渡せば帯は新規に出ない(triggered = None)。
    /// これが「レベルアップパネルにプレイヤーフェーズ帯が被る」不具合の回帰防止。
    @Test
    def testLevelUpViewDoesNotTriggerBannerDuringEnemyTurn(): Unit \ Assert =
        let data = {stage = Stage.Idle, elapsed = Duration.zero(),
                    wasEnemy = Some(true), pending = None};
        let isEnemy = PhaseBannerScene.perceivedIsEnemy(TurnPhase.Phase.LevelUpView, data#wasEnemy);
        let result = PhaseBannerScene.step(data, isEnemy, Duration.millis(50));
        Assert.assertEq(expected = (None, Stage.Idle),
                        (result#triggered, result#data#stage))
}
