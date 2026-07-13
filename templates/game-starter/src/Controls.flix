// Controls — キーの割り当て。App が用意したフレーム（押されているキーの集合）を
// World.Input の形に写し、World.step で状態を1歩進める。ここは純粋（外の世界に触れない）。

mod Controls {
    use GameEngine.Key

    /// このフレームのキーを World.Input へ写す。App.axis が左右・上下の押し下げを
    /// -1 / 0 / +1 の軸値に畳む（両押しは 0・押しっぱなしも効く）。
    pub def inputOf(frame: App.Frame): World.Input =
        { x = App.axis(negative = Key.Left, positive = Key.Right, frame),
          y = App.axis(negative = Key.Up,   positive = Key.Down,  frame) }

    /// 毎フレームのシステム: キーを Input へ写し、World を1歩進める。
    pub def step(frame: App.Frame, world: World.World): World.World =
        World.step(inputOf(frame), frame#dt, world)
}
