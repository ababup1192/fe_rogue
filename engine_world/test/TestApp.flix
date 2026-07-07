// TestApp — App の純粋な芯を具体値で固定する: frameOf のエッジ判定（新規押下だけが
// justPressed に立ち、押しっぱなし・離しは立たない）、applySystems の適用順（追加順 =
// 左から右。+1 して ×2 なら 2、逆なら 1 なので順序が数字に出る）、quit の既定
// （Escape のエッジで終了・押しっぱなしでは終了しない）。
// Frame は record なので、比較はタプルへ射影して行う。

mod TestApp {

    /// Frame を比較できるタプル (down, justPressed, dt) へ射影する。
    def frameTuple(frame: App.Frame): (Set[GameEngine.Key], Set[GameEngine.Key], Float64) =
        (frame#down, frame#justPressed, frame#dt)

    /// キー無し・dt 0 の Frame。
    def emptyFrame(): App.Frame =
        App.frameOf(prev = Set#{}, current = Set#{}, 0.0)

    // ========================================================================
    // frameOf: エッジ判定
    // ========================================================================

    // 新規押下: 前に無く今ある Left は down にも justPressed にも立つ。dt は素通し。
    @Test
    def testFrameOfNewPressIsEdge(): Unit \ Assert =
        let actual = App.frameOf(prev = Set#{}, current = Set#{GameEngine.Key.Left}, 0.016);
        Assert.assertEq(expected = (Set#{GameEngine.Key.Left}, Set#{GameEngine.Key.Left}, 0.016),
            frameTuple(actual))

    // 押しっぱなし: 前も今もある Left は down のまま、justPressed には立たない。
    @Test
    def testFrameOfHeldKeyIsNotEdge(): Unit \ Assert =
        let actual = App.frameOf(prev = Set#{GameEngine.Key.Left}, current = Set#{GameEngine.Key.Left}, 0.016);
        Assert.assertEq(expected = (Set#{GameEngine.Key.Left}, Set#{}, 0.016),
            frameTuple(actual))

    // 離し: 前にあって今無い Left はどちらにも立たない（離しエッジは追わない）。
    @Test
    def testFrameOfReleaseIsSilent(): Unit \ Assert =
        let actual = App.frameOf(prev = Set#{GameEngine.Key.Left}, current = Set#{}, 0.016);
        Assert.assertEq(expected = (Set#{}, Set#{}, 0.016),
            frameTuple(actual))

    // 混在: 押しっぱなしの Left と新規の Space が並ぶと、エッジは Space だけ。
    @Test
    def testFrameOfMixedKeysSplitEdges(): Unit \ Assert =
        let actual = App.frameOf(
            prev = Set#{GameEngine.Key.Left},
            current = Set#{GameEngine.Key.Left, GameEngine.Key.Space}, 0.016);
        Assert.assertEq(
            expected = (Set#{GameEngine.Key.Left, GameEngine.Key.Space}, Set#{GameEngine.Key.Space}, 0.016),
            frameTuple(actual))

    // ========================================================================
    // applySystems: 追加順 = 適用順
    // ========================================================================

    // +1 → ×2 の順なら (0+1)*2 = 2。逆順なら 0*2+1 = 1 なので、順序の取り違えは数字に出る。
    @Test
    def testApplySystemsRunsInOrder(): Unit \ Assert =
        let systems = ((_frame, n) -> n + 1) :: ((_frame, n) -> n * 2) :: Nil;
        Assert.assertEq(expected = 2, App.applySystems(emptyFrame(), systems, 0))

    // システム無しなら World はそのまま。
    @Test
    def testApplySystemsEmptyIsIdentity(): Unit \ Assert =
        Assert.assertEq(expected = 7, App.applySystems(emptyFrame(), Nil, 7))

    // ========================================================================
    // quit: 既定は Escape のエッジ・quitWhen で差し替え
    // ========================================================================

    // 既定の quit は Escape の新規押下で true。
    @Test
    def testQuitDefaultFiresOnEscapeEdge(): Unit \ Assert =
        let frame = App.frameOf(prev = Set#{}, current = Set#{GameEngine.Key.Escape}, 0.016);
        let wantsQuit = App.make(0)#quit;
        Assert.assertEq(expected = true, wantsQuit(frame, 0))

    // 押しっぱなしの Escape では終了しない（起動時に押されていたキーの誤発火を防ぐ）。
    @Test
    def testQuitDefaultIgnoresHeldEscape(): Unit \ Assert =
        let frame = App.frameOf(
            prev = Set#{GameEngine.Key.Escape}, current = Set#{GameEngine.Key.Escape}, 0.016);
        let wantsQuit = App.make(0)#quit;
        Assert.assertEq(expected = false, wantsQuit(frame, 0))

    // quitWhen は判定を丸ごと差し替える（World も見られる）。
    @Test
    def testQuitWhenReplacesJudge(): Unit \ Assert =
        let app = App.make(9) |> App.quitWhen((_frame, n) -> n == 9);
        let wantsQuit = app#quit;
        Assert.assertEq(expected = true, wantsQuit(emptyFrame(), 9))
}
