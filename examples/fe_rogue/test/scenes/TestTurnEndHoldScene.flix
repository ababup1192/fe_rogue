/// TurnEndHoldScene の純粋ロジック `step` のテスト
///
/// Shift 長押しゲージの 1 フレーム更新を、Scene / effect を使わず値だけで検証する。
///   - 非対象フェーズ / 離した → 即リセット（経過 0・非表示・非発火）
///   - 押下直後（showDelay 未満）→ まだ非表示
///   - showDelay〜3 秒 → 表示しつつ充填（充填率 = 経過 / 3 秒）
///   - 3 秒到達フレーム → 発火（fire=true）＋発火済み(consumed)
///   - 発火済みで押しっぱなし → 再発火しない
///   - 離す → リセットして再び armed
mod TestTurnEndHoldScene {

    /// 経過 0・未発火の初期状態。
    def fresh(): TurnEndHoldScene.GaugeData =
        {elapsed = Duration.zero(), consumed = false}

    // ========================================================================
    // リセット: 非対象フェーズ / 離したフレームは経過 0・非表示・非発火に戻す
    // ========================================================================

    /// 対象フェーズでない(active=false)なら、押していても即リセットする。
    @Test
    def testInactiveResets(): Unit \ Assert =
        let r = TurnEndHoldScene.step(
            {elapsed = Duration.seconds(1.0), consumed = false}, false, true, Duration.seconds(1.0));
        Assert.assertEq(
            expected = (false, false, 0.0),
            (r#visible, r#fire, Duration.toSeconds(r#data#elapsed)))

    /// Shift を離したフレームは経過 0・非表示に戻す。
    @Test
    def testReleasedResets(): Unit \ Assert =
        let r = TurnEndHoldScene.step(
            {elapsed = Duration.seconds(2.0), consumed = false}, true, false, Duration.seconds(0.5));
        Assert.assertEq(
            expected = (false, false, 0.0),
            (r#visible, r#fire, Duration.toSeconds(r#data#elapsed)))

    // ========================================================================
    // 充填: showDelay 未満は非表示、超えたら表示しつつ充填率を返す
    // ========================================================================

    /// 押下 0.2 秒（表示しきい 0.3 秒未満）はまだ非表示・非発火。
    @Test
    def testHiddenBeforeShowDelay(): Unit \ Assert =
        let r = TurnEndHoldScene.step(fresh(), true, true, Duration.seconds(0.2));
        Assert.assertEq(expected = (false, false), (r#visible, r#fire))

    /// 押下 1.0 秒 → 表示し、充填率 0.5（= 1.0 / 2.0）。まだ発火しない。
    @Test
    def testFillsMidway(): Unit \ Assert =
        let r = TurnEndHoldScene.step(fresh(), true, true, Duration.seconds(1.0));
        Assert.assertEq(expected = (true, false, 0.5), (r#visible, r#fire, r#ratio))

    // ========================================================================
    // 発火: 2 秒到達フレームだけ fire=true、以後は再発火しない
    // ========================================================================

    /// 経過 1.5 秒から 0.5 秒進めて 2.0 秒に到達 → 発火・充填率 1.0・発火済み。
    @Test
    def testFiresAtThreshold(): Unit \ Assert =
        let r = TurnEndHoldScene.step(
            {elapsed = Duration.seconds(1.5), consumed = false}, true, true, Duration.seconds(0.5));
        Assert.assertEq(
            expected = (true, true, 1.0, true),
            (r#visible, r#fire, r#ratio, r#data#consumed))

    /// 発火済み(consumed)で押しっぱなしのフレームは再発火しない（満タン表示は維持）。
    @Test
    def testNoRefireWhileConsumed(): Unit \ Assert =
        let r = TurnEndHoldScene.step(
            {elapsed = Duration.seconds(2.0), consumed = true}, true, true, Duration.seconds(0.1));
        Assert.assertEq(expected = (true, false), (r#visible, r#fire))

    /// 発火済みでも離せばリセットして再び armed（consumed=false）に戻る。
    @Test
    def testReleaseRearmsAfterConsumed(): Unit \ Assert =
        let r = TurnEndHoldScene.step(
            {elapsed = Duration.seconds(2.0), consumed = true}, true, false, Duration.seconds(0.1));
        Assert.assertEq(
            expected = (false, false, false),
            (r#visible, r#fire, r#data#consumed))
}
