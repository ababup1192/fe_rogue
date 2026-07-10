// Controls — キー割り当て: Frame をこのゲームの意味（Input）へ写し、Step のルールで 1 歩進める。
// 絵は View.frame が App に直結するのでここを通らない。唯一の effect は reloadParams の
// parameters.json 読み直し（F1 で遊びながら手触りを変える）で、シグネチャがそれを語る: `\ {Fs.FileRead}`。

mod Controls {
    use GameEngine.Key

    /// このフレームのキーをゲームの意味（Input）へ写す。left/right は走りなので押しっぱなしを見る。
    /// B ダッシュは Z か左 Shift の押しっぱなし。down は下+ジャンプ=すり抜け降下用で押しっぱなしを見る。
    /// ジャンプは両方要る: jumpDown（押しっぱなし = 高く飛ぶ）と jumpPressed（押した瞬間 = バッファ充填）。
    pub def inputOf(frame: App.Frame): Field.Input =
        { left        = App.isDown(Key.Left, frame),
          right       = App.isDown(Key.Right, frame),
          dash        = App.isDown(Key.Z, frame) or App.isDown(Key.LeftShift, frame),
          jumpDown    = App.isDown(Key.Space, frame),
          jumpPressed = App.justPressed(Key.Space, frame),
          down        = App.isDown(Key.Down, frame) }

    /// 毎フレームのシステム: キーを Input へ写し、Step のルールで World を 1 歩進める（純粋）。
    pub def step(frame: App.Frame, world: Field.World): Field.World =
        Step.update(inputOf(frame), frame#dt, world)

    /// F1 リロード: assets/parameters.json を読み直してパラメータを差し替える。
    /// 遊びながら json を編集し、F1 を押せばその場で手触りが変わる（ファイル読みはここだけ）。
    pub def reloadParams(world: Field.World): Field.World \ {Fs.FileRead} =
        { params = GameParameters.load() | world }
}
