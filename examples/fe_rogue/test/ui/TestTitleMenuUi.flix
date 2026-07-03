/// TitleMenuUi の純粋部分（確定分岐 / カーソル反転）を固定する。
/// onKeyPressed は「(カーソル, 再開可否) → 確定先」を経て画面遷移 / ResumeRequest を要求する。
/// 遷移・要求は effect なので、その手前の純関数（confirmOutcome / toggleCursor）を pin する。
mod TestTitleMenuUi {

    use TitleMenuUi.Confirm

    /// 状態レコードの簡易ビルダ。
    def mkData(cursor: Int32, resumable: Bool): TitleMenuState.Data =
        {cursor = cursor, resumable = resumable}

    // ════════════════════════════════════════════════════════
    // confirmOutcome: (カーソル, 再開可否) → 確定先
    // ════════════════════════════════════════════════════════

    /// カーソル 0（はじめから）は再開可否によらず StartNew。
    @Test
    def testConfirmStartNew(): Unit \ Assert =
        Assert.assertEq(
            expected = (Confirm.StartNew, Confirm.StartNew),
            (TitleMenuUi.confirmOutcome(0, false), TitleMenuUi.confirmOutcome(0, true)))

    /// カーソル 1（中断から再開）は再開可能なら Resume、不可なら Blocked。
    @Test
    def testConfirmResumeVsBlocked(): Unit \ Assert =
        Assert.assertEq(
            expected = (Confirm.Resume, Confirm.Blocked),
            (TitleMenuUi.confirmOutcome(1, true), TitleMenuUi.confirmOutcome(1, false)))

    // ════════════════════════════════════════════════════════
    // toggleCursor: 2 択カーソルの反転
    // ════════════════════════════════════════════════════════

    /// 0 ⇄ 1 を反転する（resumable は保持）。
    @Test
    def testToggleCursorFlips(): Unit \ Assert =
        let fromZero = TitleMenuUi.toggleCursor(mkData(0, true));
        let fromOne  = TitleMenuUi.toggleCursor(mkData(1, true));
        Assert.assertEq(
            expected = (1, 0),
            (fromZero#cursor, fromOne#cursor))
}
