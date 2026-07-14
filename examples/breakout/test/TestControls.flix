// TestControls — Frame → Input の写像（キー割り当て）を具体値で固定する。
// 連続入力（moveX = 押しっぱなしで効く軸値）とエッジ入力（launch/enter = 新規押下だけ効く）の
// 区別が正しく Frame から引かれることを確かめる。App 自体の芯（frameOf / applySystems / quit）は
// engine_world の TestApp が固定している。

mod TestControls {

    /// テスト用の design サイズ。ここのテストは viewport を見ないので値は任意。
    def testViewport(): Vec2.Vec2 = { x = 320.0, y = 240.0 }

    /// キー無し・dt 0 の Frame。
    def emptyFrame(): App.Frame =
        App.frameOf(prev = Set#{}, current = Set#{}, 0.0, testViewport(), Vec2.zero(), { prevDown = false, down = false })

    /// Input を比較できるタプル (moveX, launch, enter) へ射影する。
    def inputTuple(input: Field.Input): (Float64, Bool, Bool) =
        (input#moveX, input#launch, input#enter)

    // 押しっぱなしの Left/Space/Enter: 移動の軸は左（-1.0）に倒れるが、エッジ待ちの launch/enter は立たない。
    @Test
    def testInputOfHeldKeys(): Unit \ Assert =
        let held = Set#{GameEngine.Key.Left, GameEngine.Key.Space, GameEngine.Key.Enter};
        let frame = App.frameOf(prev = held, current = held, 0.016, testViewport(), Vec2.zero(), { prevDown = false, down = false });
        Assert.assertEq(expected = (-1.0, false, false), inputTuple(Controls.inputOf(frame)))

    // 新規押下の Right/Space/Enter: 全部このフレームで意味を持つ（moveX は連続で右に倒れ・launch/enter はエッジ）。
    @Test
    def testInputOfFreshKeys(): Unit \ Assert =
        let frame = App.frameOf(
            prev = Set#{},
            current = Set#{GameEngine.Key.Right, GameEngine.Key.Space, GameEngine.Key.Enter}, 0.016, testViewport(), Vec2.zero(), { prevDown = false, down = false });
        Assert.assertEq(expected = (1.0, true, true), inputTuple(Controls.inputOf(frame)))

    // 何も押されていなければ noInput と同じ。
    @Test
    def testInputOfNoKeysIsNoInput(): Unit \ Assert =
        Assert.assertEq(expected = inputTuple(Field.noInput()),
            inputTuple(Controls.inputOf(emptyFrame())))
}
