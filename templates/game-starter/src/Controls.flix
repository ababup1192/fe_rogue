// Controls — キーの割り当て。App が用意したフレーム（押されているキーの集合）を
// World.Input の形に写し、World.step で状態を1歩進める。ここは純粋（外の世界に触れない）。

mod Controls {
    use GameEngine.Key

    /// このフレームのキーを World.Input へ写す。移動は押しっぱなしで効いてほしいので isDown を使う。
    pub def inputOf(frame: App.Frame): World.Input =
        { left  = App.isDown(Key.Left, frame),
          right = App.isDown(Key.Right, frame),
          up    = App.isDown(Key.Up, frame),
          down  = App.isDown(Key.Down, frame) }

    /// 毎フレームのシステム: キーを Input へ写し、World を1歩進める。
    pub def step(frame: App.Frame, world: World.World): World.World =
        World.step(inputOf(frame), frame#dt, world)
}
