/// LogUi の純粋ロジックテスト。
///
/// `enqueue`: 新着を「上=最新」で積み、最大 5 行に切り詰めるキュー操作。
/// `tickIdle`: 最後のログから 5 秒で消えるタイマー。
/// 守る仕様: 6 件目が来たら最古が落ちる / ちょうど 5 秒で消える / 空のときは消えるも進めもしない /
///          新着で 0 に戻した直後のフレームでは消えない。
mod TestLogUi {

    /// テキストだけ指定した最小の表示エントリ(色はキュー操作に無関係なので白固定)。
    def entry(text: String): LogState.LogEntry =
        { text = text, color = {r = 1.0f32, g = 1.0f32, b = 1.0f32} }

    /// キューを assertEq 用にテキスト列へ写すアダプタ(値の取り出しのみ)。
    def texts(queue: List[LogState.LogEntry]): List[String] =
        List.map(e -> e#text, queue)

    // ========================================================================
    // enqueue: 上=最新で積み、最大 5 件に切り詰める
    // ========================================================================

    /// 空キューに 1 件積むとその 1 件だけになる。
    @Test
    def testEnqueueToEmpty(): Unit \ Assert =
        Assert.assertEq(
            expected = "A" :: Nil,
            texts(LogUi.enqueue(entry("A") :: Nil, Nil)))

    /// 新着は既存キューの先頭(最新側)に積まれる。drain([A]) + [B,C] → [A,B,C]。
    @Test
    def testEnqueuePrepends(): Unit \ Assert =
        Assert.assertEq(
            expected = "A" :: "B" :: "C" :: Nil,
            texts(LogUi.enqueue(entry("A") :: Nil,
                                    entry("B") :: entry("C") :: Nil)))

    /// 6 件目が来たら最古(末尾)が落ちて 5 件に収まる。
    /// drain([A]) + [B,C,D,E,F] → [A,B,C,D,E](F 脱落)。
    @Test
    def testEnqueueDropsOldestAtCap(): Unit \ Assert =
        Assert.assertEq(
            expected = "A" :: "B" :: "C" :: "D" :: "E" :: Nil,
            texts(LogUi.enqueue(entry("A") :: Nil,
                                    entry("B") :: entry("C") :: entry("D")
                                        :: entry("E") :: entry("F") :: Nil)))

    /// drain は古→新順。drain([B,A]) は A が最新なので [A,B,...] になり、cap で F が落ちる。
    /// drain([B,A]) + [C,D,E,F] → reverse して [A,B] を前に積み [A,B,C,D,E,F] → 5 件で [A,B,C,D,E]。
    @Test
    def testEnqueueDrainOrderNewestOnTop(): Unit \ Assert =
        Assert.assertEq(
            expected = "A" :: "B" :: "C" :: "D" :: "E" :: Nil,
            texts(LogUi.enqueue(entry("B") :: entry("A") :: Nil,
                                    entry("C") :: entry("D") :: entry("E") :: entry("F") :: Nil)))

    // ========================================================================
    // tickIdle: 最後のログから 5 秒で消える
    // ========================================================================

    /// 5 秒未満ならキュー据置でタイマーだけ進む。3.0s + 1.0s = 4.0s。
    @Test
    def testTickAdvancesBelowHold(): Unit \ Assert =
        let (q, idle) = LogUi.tickIdle(entry("A") :: Nil,
                            Duration.seconds(3.0f64), Duration.seconds(1.0f64));
        Assert.assertEq(
            expected = ("A" :: Nil, 4.0f64),
            (texts(q), Duration.toSeconds(idle)))

    /// ちょうど 5.0 秒に達したらキューを空にして消す(>= 境界)。4.5s + 0.5s = 5.0s。
    @Test
    def testTickClearsAtHold(): Unit \ Assert =
        let (q, idle) = LogUi.tickIdle(entry("A") :: Nil,
                            Duration.seconds(4.5f64), Duration.seconds(0.5f64));
        Assert.assertEq(
            expected = (Nil, 0.0f64),
            (texts(q), Duration.toSeconds(idle)))

    /// 空キューはタイマーを進めない(消えるタイマーは表示中だけ動く)。
    @Test
    def testTickEmptyDoesNotAdvance(): Unit \ Assert =
        let (q, idle) = LogUi.tickIdle(Nil,
                            Duration.seconds(1.0f64), Duration.seconds(1.0f64));
        Assert.assertEq(
            expected = (Nil, 1.0f64),
            (texts(q), Duration.toSeconds(idle)))

    /// 新着で 0 に戻した直後のフレームでは消えない(0 + 0.5s = 0.5s < 5s)。
    @Test
    def testTickAfterResetStaysVisible(): Unit \ Assert =
        let (q, idle) = LogUi.tickIdle(entry("A") :: Nil,
                            Duration.zero(), Duration.seconds(0.5f64));
        Assert.assertEq(
            expected = ("A" :: Nil, 0.5f64),
            (texts(q), Duration.toSeconds(idle)))
}
