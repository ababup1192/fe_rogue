// Controls — キー割り当て: Frame を breakout の意味（Input）へ写し、Step のルールで 1 歩進める。
// 絵は View.frame が App に直結するのでここを通らない。唯一の effect は reloadParams の
// parameters.json 読み直し（F1 で遊びながら効きを変える）で、シグネチャがそれを語る: `\ {Fs.FileRead}`。

mod Controls {
    use GameEngine.Key

    /// このフレームのキーを breakout の意味（Input）へ写す。moveX はパドル移動の軸値
    /// （左右キーの押し下げを畳んだもの）、launch/enter は 1 回きり効けばよいのでエッジを見る。
    pub def inputOf(frame: App.Frame): Field.Input =
        { moveX  = App.axis(negative = Key.Left, positive = Key.Right, frame),
          launch = App.justPressed(Key.Space, frame),
          enter  = App.justPressed(Key.Enter, frame) }

    /// 毎フレームのシステム: キーを Input へ写し、Step のルールで World を 1 歩進める（純粋）。
    pub def step(frame: App.Frame, world: Field.World): Field.World =
        Step.update(inputOf(frame), frame#dt, world)

    /// F1 リロード: assets/parameters.json を読み直してパラメータを差し替える。
    /// 遊びながら json を編集し、F1 を押せばその場で効きが変わる（ファイル読みはここだけ）。
    pub def reloadParams(world: Field.World): Field.World \ {Fs.FileRead} =
        { params = GameParameters.load() | world }
}
