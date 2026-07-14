// Controls — キー割り当て: Frame をこのゲームの意味（Input）へ写し、Step のルールで 1 歩進める。
// 絵は View.frame が App に直結するのでここを通らない。唯一の effect は reloadParams の
// parameters.json 読み直し（F1 で遊びながら手触りを変える）で、シグネチャがそれを語る: `\ {Fs.FileRead}`。

mod Controls {
    use GameEngine.Key

    /// このフレームのキーをゲームの意味（Input）へ写す。moveX は走りの軸値
    /// （左右キーの押し下げを畳んだもの）。B ダッシュは Z の押しっぱなし。
    /// down は下+ジャンプ=すり抜け降下用で押しっぱなしを見る。
    /// ジャンプ（X）は両方要る: jumpDown（押しっぱなし = 高く飛ぶ）と jumpPressed（押した瞬間 = バッファ充填）。
    /// 左 Shift はキャラ切り替え（押した瞬間だけ = 押しっぱなしで連打にならない）。
    pub def inputOf(frame: App.Frame): Field.Input =
        { moveX         = App.axis(negative = Key.Left, positive = Key.Right, frame),
          dash          = App.isDown(Key.Z, frame),
          jumpDown      = App.isDown(Key.X, frame),
          jumpPressed   = App.justPressed(Key.X, frame),
          down          = App.isDown(Key.Down, frame),
          switchPressed = App.justPressed(Key.LeftShift, frame) }

    /// 毎フレームのシステム: キーを Input へ写し、Step のルールで World を 1 歩進める（純粋）。
    pub def step(frame: App.Frame, world: Field.World): Field.World =
        Step.update(inputOf(frame), frame#dt, world)

    /// F1 リロード: assets/parameters.json を読み直してパラメータを差し替える。
    /// 遊びながら json を編集し、F1 を押せばその場で手触りが変わる（ファイル読みはここだけ）。
    pub def reloadParams(world: Field.World): Field.World \ {Fs.FileRead} =
        { params = GameParameters.load() | world }
}
