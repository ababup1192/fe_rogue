/// PhaseBannerScene の純粋な状態更新 `step` を検証する。
///
/// `step` は「今のフェーズが敵ターンか」と前フレームの状態から、(1) ターンが切り替わった
/// 瞬間にバナーを出し直すか、(2) スライド演出の段階を時間で進める、の 2 つを担う。
/// 帯の描画・色差し替え・オフセット反映は scene 副作用なので、ここでは扱わず実機確認に委ねる。
///
/// 段階の長さ: 滑り込み 440ms / 静止 1520ms / 滑り抜け 440ms。
/// 「段階が終わる」系のテストは、どの段階の長さ(最大 1520ms)も確実に超える 2 秒(2000ms)を
/// 1 回だけ進めて、次の段階へ移ることを確認する。
mod TestPhaseBannerScene {

    use PhaseBannerScene.Stage

    // ════════════════════════════════════════════════════════
    // トリガー判定: ターンの切り替わりでバナーが出る／同一ターンでは出ない
    // ════════════════════════════════════════════════════════

    /// 起動直後（wasEnemy = None）の最初のフレームは、味方ターンとして味方バナーを出し始める。
    /// triggered = Some(false)（= 敵ではない = 味方）、段階は滑り込み開始。
    @Test
    def testFirstFrameTriggersPlayerBanner(): Unit \ Assert =
        let result = PhaseBannerScene.step(
            {stage = Stage.Idle, elapsed = Duration.zero(), wasEnemy = None},
            false,
            Duration.millis(50));
        Assert.assertEq(expected = (Some(false), Stage.SlideIn),
                        (result#triggered, result#data#stage))

    /// 味方ターン表示中(wasEnemy = Some(false))に敵ターンへ切り替わると、敵バナーを出し直す。
    /// triggered = Some(true)、段階は滑り込みに戻る。
    @Test
    def testTurnChangeTriggersEnemyBanner(): Unit \ Assert =
        let result = PhaseBannerScene.step(
            {stage = Stage.Hold, elapsed = Duration.zero(), wasEnemy = Some(false)},
            true,
            Duration.millis(50));
        Assert.assertEq(expected = (Some(true), Stage.SlideIn),
                        (result#triggered, result#data#stage))

    /// 同じターンが続くフレームでは出し直さない（triggered = None、段階も維持）。
    /// 味方ターン中のサブフェーズ移動で何度もバナーが再生されないことの保証。
    @Test
    def testSameTurnDoesNotRetrigger(): Unit \ Assert =
        let result = PhaseBannerScene.step(
            {stage = Stage.Hold, elapsed = Duration.millis(100), wasEnemy = Some(false)},
            false,
            Duration.millis(50));
        Assert.assertEq(expected = (None, Stage.Hold),
                        (result#triggered, result#data#stage))

    // ════════════════════════════════════════════════════════
    // 段階遷移: 滑り込み → 静止 → 滑り抜け → 非表示
    // ════════════════════════════════════════════════════════

    /// 滑り込み(440ms)が終わると静止段階へ移り、帯は中央(offsetX = 0)に収まる。
    @Test
    def testSlideInEndsAtCenter(): Unit \ Assert =
        let result = PhaseBannerScene.step(
            {stage = Stage.SlideIn, elapsed = Duration.zero(), wasEnemy = Some(false)},
            false,
            Duration.millis(2000));
        Assert.assertEq(expected = (Stage.Hold, 0.0),
                        (result#data#stage, result#offsetX))

    /// 静止(1520ms)が終わると滑り抜け段階へ移る。抜け始めなので帯はまだ中央(offsetX = 0)。
    @Test
    def testHoldEndsStartsSlideOut(): Unit \ Assert =
        let result = PhaseBannerScene.step(
            {stage = Stage.Hold, elapsed = Duration.zero(), wasEnemy = Some(false)},
            false,
            Duration.millis(2000));
        Assert.assertEq(expected = (Stage.SlideOut, 0.0),
                        (result#data#stage, result#offsetX))

    /// 滑り抜け(440ms)が終わると非表示(Idle)になり、帯は画面右外(offsetX = 140)へ退避する。
    @Test
    def testSlideOutEndsParksOffScreen(): Unit \ Assert =
        let result = PhaseBannerScene.step(
            {stage = Stage.SlideOut, elapsed = Duration.zero(), wasEnemy = Some(false)},
            false,
            Duration.millis(2000));
        Assert.assertEq(expected = (Stage.Idle, 140.0),
                        (result#data#stage, result#offsetX))
}
