// TestUiTypewriter — 文字送りの進行・早送り・完了判定・切替検出を具体値で固定する。
// UiWorld に依存しない純粋な値なので、Reveal をそのまま組んで assert する。
mod TestUiTypewriter {

    // ── step: dt の足し込みと床関数の見え方 ──

    @Test
    def testStepAccumulatesFraction(): Unit \ Assert =
        // cps=2 × dt=0.25 を 3 回 → 1.5 文字ぶん。見えるのは floor で 1 文字（「こ」）。
        let reveal = UiTypewriter.start("こんにちは")
            |> UiTypewriter.step(cps = 2.0, 0.25)
            |> UiTypewriter.step(cps = 2.0, 0.25)
            |> UiTypewriter.step(cps = 2.0, 0.25);
        Assert.assertEq(expected = ("こ", false),
            (UiTypewriter.visibleText(reveal), UiTypewriter.isDone(reveal)))

    @Test
    def testStepStopsAtFullText(): Unit \ Assert =
        // 大きな dt を与えても全文（5 文字）で止まり、isDone になる。
        let reveal = UiTypewriter.start("こんにちは") |> UiTypewriter.step(cps = 60.0, 10.0);
        Assert.assertEq(expected = ("こんにちは", true),
            (UiTypewriter.visibleText(reveal), UiTypewriter.isDone(reveal)))

    @Test
    def testStartShowsNothing(): Unit \ Assert =
        // 開始直後は 0 文字。空文字の全文は最初から isDone。
        let fresh = UiTypewriter.start("うそつき");
        let empty = UiTypewriter.start("");
        Assert.assertEq(expected = ("", false, true),
            (UiTypewriter.visibleText(fresh), UiTypewriter.isDone(fresh), UiTypewriter.isDone(empty)))

    // ── skip / done: 早送り ──

    @Test
    def testSkipJumpsToFullText(): Unit \ Assert =
        // 途中まで進んだ状態から skip すると全文が見える（決定キーの早送り）。
        let reveal = UiTypewriter.start("みどりの人はうそつきだよ")
            |> UiTypewriter.step(cps = 1.0, 2.0)
            |> UiTypewriter.skip;
        Assert.assertEq(expected = ("みどりの人はうそつきだよ", true),
            (UiTypewriter.visibleText(reveal), UiTypewriter.isDone(reveal)))

    @Test
    def testDoneEqualsSkippedStart(): Unit \ Assert =
        // done(text) は start(text) |> skip と同じ状態を作る（record は Eq を持たないのでタプルへ射影）。
        let skipped = UiTypewriter.start("あいう") |> UiTypewriter.skip;
        let direct = UiTypewriter.done("あいう");
        Assert.assertEq(expected = (skipped#text, skipped#shown), (direct#text, direct#shown))

    // ── sync: 文言切替の検出 ──

    @Test
    def testSyncKeepsProgressForSameText(): Unit \ Assert =
        // 同じ全文なら進み具合を保つ（毎フレーム呼んでもタイプが巻き戻らない）。
        let reveal = UiTypewriter.start("こんにちは") |> UiTypewriter.step(cps = 2.0, 1.0);
        let synced = UiTypewriter.sync("こんにちは", reveal);
        Assert.assertEq(expected = (reveal#text, reveal#shown), (synced#text, synced#shown))

    @Test
    def testSyncRestartsForNewText(): Unit \ Assert =
        // 全文が変われば 0 文字からやり直す（メッセージ切替）。
        let reveal = UiTypewriter.done("ふるい文") |> UiTypewriter.sync("あたらしい文");
        Assert.assertEq(expected = ("あたらしい文", 0.0), (reveal#text, reveal#shown))
}
