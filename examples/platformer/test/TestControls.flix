// TestControls — キー割り当ての pin: 押しっぱなし（走りの軸値・ジャンプ長押し）とエッジ
// （バッファ充填・キャラ切り替え）の区別。Z = ダッシュ / X = ジャンプ / 左 Shift = 切り替え。

mod TestControls {
    use GameEngine.Key

    def frameOf(down: Set[Key], justPressed: Set[Key]): App.Frame =
        // viewport はここのテストの対象外（キー割り当てだけ見る）。値は design と同じにしておく。
        { down = down, justPressed = justPressed, dt = 1.0 / 64.0, viewport = { x = 480.0, y = 360.0 },
          cursor = Vec2.zero(), mouseDown = false, mouseClicked = false }

    // 押した瞬間の X は jumpDown と jumpPressed の両方に立つ。
    @Test
    def testJumpEdgeSetsBoth(): Unit \ Assert =
        let input = Controls.inputOf(frameOf(Set#{Key.X}, Set#{Key.X}));
        Assert.assertEq(expected = (true, true), (input#jumpDown, input#jumpPressed))

    // 押しっぱなしの X は jumpDown だけ（バッファは再充填されない）。
    @Test
    def testJumpHeldIsNotPressed(): Unit \ Assert =
        let input = Controls.inputOf(frameOf(Set#{Key.X}, Set.empty()));
        Assert.assertEq(expected = (true, false), (input#jumpDown, input#jumpPressed))

    // 矢印は押しっぱなしで効く（走りは連続入力の軸値）。左右同時押しは打ち消して 0.0。
    @Test
    def testArrowsAreHeld(): Unit \ Assert =
        let left = Controls.inputOf(frameOf(Set#{Key.Left}, Set.empty()));
        let right = Controls.inputOf(frameOf(Set#{Key.Right}, Set.empty()));
        let both = Controls.inputOf(frameOf(Set#{Key.Left, Key.Right}, Set.empty()));
        Assert.assertEq(expected = (-1.0, 1.0, 0.0), (left#moveX, right#moveX, both#moveX))

    // B ダッシュは Z だけ。左 Shift はダッシュに効かない（キャラ切り替え専用へ移った）。
    @Test
    def testDashIsZOnly(): Unit \ Assert =
        let zInput = Controls.inputOf(frameOf(Set#{Key.Z}, Set.empty()));
        let shiftInput = Controls.inputOf(frameOf(Set#{Key.LeftShift}, Set.empty()));
        Assert.assertEq(expected = (true, false), (zInput#dash, shiftInput#dash))

    // キャラ切り替えは左 Shift の押した瞬間だけ（押しっぱなしでは連打にならない）。
    @Test
    def testSwitchIsShiftEdge(): Unit \ Assert =
        let edge = Controls.inputOf(frameOf(Set#{Key.LeftShift}, Set#{Key.LeftShift}));
        let held = Controls.inputOf(frameOf(Set#{Key.LeftShift}, Set.empty()));
        Assert.assertEq(expected = (true, false), (edge#switchPressed, held#switchPressed))

    // Space はもう何にも割り当てられていない（ジャンプは X へ移った）。
    @Test
    def testSpaceIsInert(): Unit \ Assert =
        let input = Controls.inputOf(frameOf(Set#{Key.Space}, Set#{Key.Space}));
        Assert.assertEq(expected = (false, false, false, false),
            (input#jumpDown, input#jumpPressed, input#dash, input#switchPressed))

    // 何も押していなければ軸は 0.0、他は全て偽。
    @Test
    def testNoKeys(): Unit \ Assert =
        let input = Controls.inputOf(frameOf(Set.empty(), Set.empty()));
        Assert.assertEq(expected = (0.0, false, false, false),
            (input#moveX, input#jumpDown, input#jumpPressed, input#switchPressed))

    // 下キーは押しっぱなしで効く（すり抜け降下の構え）。
    @Test
    def testDownIsHeld(): Unit \ Assert =
        let input = Controls.inputOf(frameOf(Set#{Key.Down}, Set.empty()));
        Assert.assertEq(expected = true, input#down)
}
