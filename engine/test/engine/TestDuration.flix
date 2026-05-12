/// Duration の構築と演算を検証する。
///
/// 単純な getter / setter（seconds → toSeconds の往復）は型から自明なので書かない。
/// 価値があるのは:
///   - 単位混在の構築（millis / frames）が想定の秒数になるか
///   - ratio が 0..1 にクランプされるか（Tween の進度計算で必要）
///   - subClampedToZero がマイナスに突き抜けないか（Timer のカウントダウンで必要）
///   - isExpired の境界（ちょうど 0 で expired）
mod TestDuration {

    // ════════════════════════════════════════════════════════
    // 構築: 単位の意味が合っているか
    // ════════════════════════════════════════════════════════

    /// 500 ミリ秒は 0.5 秒として扱われる
    @Test
    def testMillisConvertsToHalfSecond(): Unit \ Assert =
        let duration = 500 |> Duration.millis;
        Assert.assertEq(expected = 0.5, Duration.toSeconds(duration))

    /// frames(count = 16, fps = 200) は 16/200 = 0.08 秒
    /// （モーション 1 サイクル ≈ 16 フレームを 200fps 想定で再生する長さ）
    @Test
    def testFramesComputesCountOverFps(): Unit \ Assert =
        let duration = Duration.frames(count = 16, fps = 200);
        Assert.assertEq(expected = 0.08, Duration.toSeconds(duration))

    // ════════════════════════════════════════════════════════
    // 演算: add / sub / subClampedToZero
    // ════════════════════════════════════════════════════════

    /// 単位の異なる Duration 同士を足せる（500ms + 0.5s = 1.0s）
    @Test
    def testAddCombinesAcrossUnits(): Unit \ Assert =
        let total = Duration.add(500 |> Duration.millis, 0.5 |> Duration.seconds);
        Assert.assertEq(expected = 1.0, Duration.toSeconds(total))

    /// sub はマイナスに突き抜ける（カウントダウン演算用に許容）
    /// 1.0 秒から 1.5 秒を引くと -0.5 秒になる
    @Test
    def testSubAllowsNegativeForCountdownChecks(): Unit \ Assert =
        let result = Duration.sub(1.0 |> Duration.seconds, 1.5 |> Duration.seconds);
        Assert.assertEq(expected = -0.5, Duration.toSeconds(result))

    /// subClampedToZero は 0 で止まる（Timer の timeLeft 用）
    /// 1.0 秒から 1.5 秒を引くと 0 にクランプされる
    @Test
    def testSubClampedToZeroDoesNotGoNegative(): Unit \ Assert =
        let result = Duration.subClampedToZero(
            1.0 |> Duration.seconds,
            1.5 |> Duration.seconds);
        Assert.assertEq(expected = 0.0, Duration.toSeconds(result))

    // ════════════════════════════════════════════════════════
    // ratio: Tween 進度計算（0.0..1.0 にクランプ）
    // ════════════════════════════════════════════════════════

    /// 0.5 秒経過 / 2.0 秒総時間 → 進度 0.25
    @Test
    def testRatioReturnsProgressFraction(): Unit \ Assert =
        let progress = Duration.ratio(
            0.5 |> Duration.seconds,
            2.0 |> Duration.seconds);
        Assert.assertEq(expected = 0.25, progress)

    /// 経過が総時間を超えても 1.0 で頭打ち（Tween の lerp が overshoot しないように）
    @Test
    def testRatioClampsAtOneWhenOverflow(): Unit \ Assert =
        let progress = Duration.ratio(
            3.0 |> Duration.seconds,
            2.0 |> Duration.seconds);
        Assert.assertEq(expected = 1.0, progress)

    // ════════════════════════════════════════════════════════
    // isExpired: 残り時間ぴったり 0 が境界
    // ════════════════════════════════════════════════════════

    /// 残り 0 秒は **期限切れ扱い**（Timer がちょうど鳴る瞬間）
    /// + 残り 0.1 秒なら **まだ動いている**
    @Test
    def testIsExpiredAtZeroAndAbove(): Unit \ Assert =
        let zero    = Duration.zero();
        let stillOn = 0.1 |> Duration.seconds;
        Assert.assertEq(expected = (true, false),
            (Duration.isExpired(zero), Duration.isExpired(stillOn)))
}
