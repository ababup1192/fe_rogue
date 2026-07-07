// Controls — キー割り当て: Frame を sokoban の意味（Board.Input）へ写し、Session を
// 1 歩進める。矢印と Z（巻き戻し）と X（リセット）は押しっぱなしで効き、Enter と
// Escape は押した瞬間だけ効く。唯一の effect は reloadUi の ui.json 読み直し
// （F1 で遊びながらページを変える）で、シグネチャがそれを語る: `\ {Fs.FileRead}`。

mod Controls {
    use GameEngine.Key

    /// このフレームのキーを sokoban の意味（Board.Input）へ写す。移動と巻き戻しは
    /// 押しっぱなしを見て（held）、enter/esc は 1 回きり効けばよいのでエッジを見る。
    pub def inputOf(frame: App.Frame): Board.Input =
        { up    = App.isDown(Key.Up, frame),
          down  = App.isDown(Key.Down, frame),
          left  = App.isDown(Key.Left, frame),
          right = App.isDown(Key.Right, frame),
          undo  = App.isDown(Key.Z, frame),
          enter = App.justPressed(Key.Enter, frame),
          back  = App.isDown(Key.X, frame),
          esc   = App.justPressed(Key.Escape, frame) }

    /// 毎フレームのシステムその一: キーを Input へ写し、tick のルールで盤面と履歴を
    /// 1 歩進める（純粋）。
    pub def step(frame: App.Frame, s: Sokoban.Session): Sokoban.Session =
        { line = Sokoban.tick(inputOf(frame), frame#dt, s#line) | s }

    /// 毎フレームのシステムその二: 進んだ後の盤面から UI ページの見た目を導く
    /// （Title / Clear の表示切替と手数の文言）。UI の状態はここで毎フレーム
    /// 上書きされるので、どの画面に居るかを UI 側が別に覚える必要はない。
    pub def projectUi(_frame: App.Frame, s: Sokoban.Session): Sokoban.Session =
        { ui = GameUi.projectUi(Worldline.pastLength(s#line), Worldline.current(s#line), s#ui) | s }

    /// F1 リロード: 生成済みの UI Spec を 1 つ残らずディスクから読み直す。
    /// ゲーム実行中に ui.json を編集し、F1 を押せば、その場でページが変わる。
    pub def reloadUi(s: Sokoban.Session): Sokoban.Session \ {Fs.FileRead} =
        { ui = UiSpec.reloadAll(s#ui) | s }

    /// 終了判定: Escape の押した瞬間 —— ただし CLEAR パネルが出ている間は除く
    /// （そのときの Escape はパネルを閉じる操作として tick が受け取る）。
    pub def wantsQuit(frame: App.Frame, s: Sokoban.Session): Bool =
        App.justPressed(Key.Escape, frame)
            and not Sokoban.clearModal(Worldline.current(s#line))
}
