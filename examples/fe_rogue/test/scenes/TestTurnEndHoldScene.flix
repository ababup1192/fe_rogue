/// TurnEndHoldScene の純粋ロジック `step` のテスト
///
/// Shift 長押しゲージの 1 フレーム更新を、Scene / effect を使わず値だけで検証する。
///   - 非対象フェーズ / 離した → 即リセット（経過 0・非表示・非発火）
///   - 新規押下エッジ(justPressed = held ∧ ¬prevHeld)で arm。固着(prevHeld=true)では arm せず非表示・非発火
///   - showDelay〜0.64 秒 → 表示しつつ充填（充填率 = 経過 / 0.64 秒、1.0 でクランプ）
///   - 0.64 秒を初めて跨いだフレームのみ発火（fire=true）。満タン後 held 継続でも再発火しない
///   - 離す → リセットして再び armed（次の新規押下でやり直し）
///   - リセット枝でも prevHeld は今フレームの held に更新し続ける（敵ターン跨ぎの暴発防止の要）
mod TestTurnEndHoldScene {

    /// 経過 0・前フレーム未押下の初期状態（= 新規押下を受け付けられる armed 前の状態）。
    def fresh(): TurnEndHoldScene.GaugeData =
        {elapsed = Duration.zero(), prevHeld = false}

    // ========================================================================
    // リセット: 非対象フェーズ / 離したフレームは経過 0・非表示・非発火に戻す
    // ========================================================================

    /// 対象フェーズでない(active=false)なら、押していても即リセットする。
    @Test
    def testInactiveResets(): Unit \ Assert =
        let r = TurnEndHoldScene.step(
            {elapsed = Duration.seconds(1.0), prevHeld = true}, false, true, Duration.seconds(1.0));
        Assert.assertEq(
            expected = (false, false, 0.0),
            (r#visible, r#fire, Duration.toSeconds(r#data#elapsed)))

    /// Shift を離したフレームは経過 0・非表示に戻す。
    @Test
    def testReleasedResets(): Unit \ Assert =
        let r = TurnEndHoldScene.step(
            {elapsed = Duration.seconds(2.0), prevHeld = true}, true, false, Duration.seconds(0.5));
        Assert.assertEq(
            expected = (false, false, 0.0),
            (r#visible, r#fire, Duration.toSeconds(r#data#elapsed)))

    // ========================================================================
    // (a) arm: 新規押下エッジ(prevHeld=false→held=true)で充填を開始する
    // ========================================================================

    /// 新規押下（prevHeld=false, held=true）で arm し、経過が進み始める。
    @Test
    def testArmsOnJustPressed(): Unit \ Assert =
        let r = TurnEndHoldScene.step(fresh(), true, true, Duration.seconds(0.2));
        Assert.assertEq(
            expected = (true, 0.2),
            (Duration.toSeconds(r#data#elapsed) > 0.0, Duration.toSeconds(r#data#elapsed)))

    // ========================================================================
    // (b)(c) 固着: prevHeld=true（離した瞬間を取りこぼした押下のまま）では arm しない
    // ========================================================================

    /// held=true でも prevHeld=true（固着）なら justPressed が立たず arm しない →
    /// 大きめ dt を与えても経過 0・非表示・非発火のまま（cmd+shift+4 等の暴発防止）。
    @Test
    def testStuckHeldDoesNotArm(): Unit \ Assert =
        let r = TurnEndHoldScene.step(
            {elapsed = Duration.zero(), prevHeld = true}, true, true, Duration.seconds(5.0));
        Assert.assertEq(
            expected = (false, false, 0.0),
            (r#visible, r#fire, Duration.toSeconds(r#data#elapsed)))

    /// (c) 再発防止の核: 敵ターン跨ぎ後の状態 {elapsed=0, prevHeld=true} を
    /// プレイヤーターン復帰フレーム(active=true, held=true)で step しても、
    /// justPressed=false ゆえ arm されず発火しない（毎ターン自動スキップしない）。
    @Test
    def testNoArmAfterEnemyTurnWhileStillHeld(): Unit \ Assert =
        let r = TurnEndHoldScene.step(
            {elapsed = Duration.zero(), prevHeld = true}, true, true, Duration.seconds(1.0));
        Assert.assertEq(expected = (false, false), (r#visible, r#fire))

    /// (c') リセット枝でも prevHeld は今フレームの held に更新し続ける。
    /// 敵ターン相当(active=false)を held=true で通すと prevHeld=true になり、
    /// これが (c) の「復帰フレームで justPressed=false」を保証する不変条件。
    @Test
    def testResetBranchUpdatesPrevHeld(): Unit \ Assert =
        let r = TurnEndHoldScene.step(
            {elapsed = Duration.seconds(0.3), prevHeld = false}, false, true, Duration.seconds(0.1));
        Assert.assertEq(expected = true, r#data#prevHeld)

    // ========================================================================
    // 充填: showDelay 未満は非表示、超えたら表示しつつ充填率を返す
    // ========================================================================

    /// arm 済み(prevHeld=true で継続)・経過 0.1 秒（表示しきい 0.15 秒未満）はまだ非表示・非発火。
    @Test
    def testHiddenBeforeShowDelay(): Unit \ Assert =
        let r = TurnEndHoldScene.step(
            {elapsed = Duration.seconds(0.05), prevHeld = true}, true, true, Duration.seconds(0.05));
        Assert.assertEq(expected = (false, false), (r#visible, r#fire))

    /// arm 済み・経過 0.32 秒 → 表示し、充填率 0.5（= 0.32 / 0.64）。まだ発火しない。
    @Test
    def testFillsMidway(): Unit \ Assert =
        let r = TurnEndHoldScene.step(
            {elapsed = Duration.seconds(0.16), prevHeld = true}, true, true, Duration.seconds(0.16));
        Assert.assertEq(expected = (true, false, 0.5), (r#visible, r#fire, r#ratio))

    // ========================================================================
    // (d) 発火: 0.64 秒を初めて跨いだフレームだけ fire=true、以後は再発火しない
    // ========================================================================

    /// 経過 0.14 秒から 0.5 秒進めて 0.64 秒に到達 → 発火・充填率 1.0。
    @Test
    def testFiresAtThreshold(): Unit \ Assert =
        let r = TurnEndHoldScene.step(
            {elapsed = Duration.seconds(0.14), prevHeld = true}, true, true, Duration.seconds(0.5));
        Assert.assertEq(
            expected = (true, true, 1.0),
            (r#visible, r#fire, r#ratio))

    /// 既に満タン(prevSecs >= fill)で押しっぱなしのフレームは再発火しない（満タン表示は維持）。
    @Test
    def testNoRefireAfterThreshold(): Unit \ Assert =
        let r = TurnEndHoldScene.step(
            {elapsed = Duration.seconds(1.0), prevHeld = true}, true, true, Duration.seconds(0.1));
        Assert.assertEq(expected = (true, false, 1.0), (r#visible, r#fire, r#ratio))

    // ========================================================================
    // (e) 残存リスクの明示: arm 済み充填中に held が固着しても、進行中の 1 回はそのまま発火する
    //     （これは「正規押下で arm 済み」かつ「その押下中に OS が key-up を食った」稀ケースで、
    //      無表示の毎ターン暴発とは別物。許容される既知挙動として固定する）。
    // ========================================================================

    @Test
    def testInProgressFillStillFiresWhenStuck(): Unit \ Assert =
        let r = TurnEndHoldScene.step(
            {elapsed = Duration.seconds(0.5), prevHeld = true}, true, true, Duration.seconds(0.2));
        Assert.assertEq(expected = (true, true), (r#visible, r#fire))

    // ========================================================================
    // (f) 離すとリセットして、次の新規押下でやり直せる
    // ========================================================================

    /// 満タン到達後でも離せば経過 0・非表示にリセットされる（prevHeld=false へ）。
    @Test
    def testReleaseResetsAfterFire(): Unit \ Assert =
        let r = TurnEndHoldScene.step(
            {elapsed = Duration.seconds(1.0), prevHeld = true}, true, false, Duration.seconds(0.1));
        Assert.assertEq(
            expected = (false, false, 0.0, false),
            (r#visible, r#fire, Duration.toSeconds(r#data#elapsed), r#data#prevHeld))
}
