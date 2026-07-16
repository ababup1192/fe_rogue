// Controls — キー割り当て: Frame を sokoban の意味（Board.Input）へ写し、Session を
// 1 歩進める。どのキーがどの意図かは InputMap の表が 1 か所で持つ（移動は WASD と
// 矢印の両対応）。移動・巻き戻し・リセットは押しっぱなしで効き、Enter と Escape は
// 押した瞬間だけ効く。唯一の effect は reloadUi の ui.json 読み直し
// （F1 で遊びながらページを変える）で、シグネチャがそれを語る: `\ {Fs.FileRead}`。

mod Controls {
    use GameEngine.Key

    /// 操作の意図。キーとの対応は heldTable / tapTable が持ち、ルールはこの意図だけを見る。
    enum Intent with Eq {
        case MoveUp
        case MoveDown
        case MoveLeft
        case MoveRight
        case Undo
        case Reset
        case Confirm
        case Cancel
    }

    /// 押しっぱなしで効く操作の表。移動は WASD と矢印のどちらでも同じ意図になる。
    def heldTable(): InputMap.Table[Intent] =
        (Key.W,     Intent.MoveUp)    ::
        (Key.Up,    Intent.MoveUp)    ::
        (Key.S,     Intent.MoveDown)  ::
        (Key.Down,  Intent.MoveDown)  ::
        (Key.A,     Intent.MoveLeft)  ::
        (Key.Left,  Intent.MoveLeft)  ::
        (Key.D,     Intent.MoveRight) ::
        (Key.Right, Intent.MoveRight) ::
        (Key.Z,     Intent.Undo)      ::
        (Key.X,     Intent.Reset)     :: Nil

    /// 押した瞬間だけ効く操作の表（決定と、CLEAR を閉じる・終了の Escape）。
    def tapTable(): InputMap.Table[Intent] =
        (Key.Enter,  Intent.Confirm) ::
        (Key.Escape, Intent.Cancel)  :: Nil

    /// このフレームのキーを sokoban の意味（Board.Input）へ写す。押しっぱなし系と
    /// 単発系それぞれの発火した意図を、中立の入力へ旗として畳み込む。
    pub def inputOf(frame: App.Frame): Board.Input =
        let held = InputMap.held(heldTable(), frame) |> List.foldLeft(applyHeld, Board.noKeys());
        InputMap.taps(tapTable(), frame) |> List.foldLeft(applyTap, held)

    /// 押しっぱなし系の意図 1 つを Input の旗にする。
    def applyHeld(acc: Board.Input, intent: Intent): Board.Input = match intent {
        case Intent.MoveUp    => { up = true | acc }
        case Intent.MoveDown  => { down = true | acc }
        case Intent.MoveLeft  => { left = true | acc }
        case Intent.MoveRight => { right = true | acc }
        case Intent.Undo      => { undo = true | acc }
        case Intent.Reset     => { back = true | acc }
        case _                => acc
    }

    /// 単発系の意図 1 つを Input の旗にする。
    def applyTap(acc: Board.Input, intent: Intent): Board.Input = match intent {
        case Intent.Confirm => { enter = true | acc }
        case Intent.Cancel  => { esc = true | acc }
        case _              => acc
    }

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
        inputOf(frame)#esc
            and not Sokoban.clearModal(Worldline.current(s#line))
}
