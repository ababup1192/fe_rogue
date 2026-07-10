// TestControls — キー割り当ての pin: 押しっぱなし（走り・ジャンプ長押し）とエッジ（バッファ充填）の区別。

mod TestControls {
    use GameEngine.Key

    def frameOf(down: Set[Key], justPressed: Set[Key]): App.Frame =
        { down = down, justPressed = justPressed, dt = 1.0 / 64.0 }

    // 押した瞬間の Space は jumpDown と jumpPressed の両方に立つ。
    @Test
    def testJumpEdgeSetsBoth(): Unit \ Assert =
        let input = Controls.inputOf(frameOf(Set#{Key.Space}, Set#{Key.Space}));
        Assert.assertEq(expected = (true, true), (input#jumpDown, input#jumpPressed))

    // 押しっぱなしの Space は jumpDown だけ（バッファは再充填されない）。
    @Test
    def testJumpHeldIsNotPressed(): Unit \ Assert =
        let input = Controls.inputOf(frameOf(Set#{Key.Space}, Set.empty()));
        Assert.assertEq(expected = (true, false), (input#jumpDown, input#jumpPressed))

    // 矢印は押しっぱなしで効く（走りは連続入力）。
    @Test
    def testArrowsAreHeld(): Unit \ Assert =
        let input = Controls.inputOf(frameOf(Set#{Key.Left, Key.Right}, Set.empty()));
        Assert.assertEq(expected = (true, true), (input#left, input#right))

    // B ダッシュは Z でも左 Shift でも効く（押しっぱなし）。
    @Test
    def testDashKeys(): Unit \ Assert =
        let zInput = Controls.inputOf(frameOf(Set#{Key.Z}, Set.empty()));
        let shiftInput = Controls.inputOf(frameOf(Set#{Key.LeftShift}, Set.empty()));
        Assert.assertEq(expected = (true, true), (zInput#dash, shiftInput#dash))

    // 何も押していなければ全て偽。
    @Test
    def testNoKeys(): Unit \ Assert =
        let input = Controls.inputOf(frameOf(Set.empty(), Set.empty()));
        Assert.assertEq(expected = (false, false, false, false),
            (input#left, input#right, input#jumpDown, input#jumpPressed))
}
