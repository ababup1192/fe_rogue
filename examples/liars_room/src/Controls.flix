// Controls — キー割り当て: Frame をこのゲームの意味（Room.Input）へ写し、Session を進める。
// どのキーがどの意図かは InputMap の表が 1 か所で持つ（移動は WASD と矢印の両対応）。
// 移動とデバッグ長押しは押しっぱなしで効き、Z（話す・決定）/ C（メモ）/ H（ヒント）/
// X（もどる）/ Enter / Escape は押した瞬間だけ効く。唯一の effect は reloadUi の
// ui.json 読み直し（F1）。
mod Controls {
    use GameEngine.Key

    /// 操作の意図。キーとの対応は heldTable / tapTable が持ち、ルールはこの意図だけを見る。
    enum Intent with Eq {
        case MoveUp
        case MoveDown
        case MoveLeft
        case MoveRight
        case Talk
        case Memo
        case Hint
        case Cancel
        case Confirm
        case Quit
        case Debug
    }

    /// 押しっぱなしで効く操作の表。移動は WASD と矢印のどちらでも同じ意図になる。
    /// デバッグの長押しは移動と重ならない左 Shift（D は WASD の右移動に譲った）。
    def heldTable(): InputMap.Table[Intent] =
        (Key.W,         Intent.MoveUp)    ::
        (Key.Up,        Intent.MoveUp)    ::
        (Key.S,         Intent.MoveDown)  ::
        (Key.Down,      Intent.MoveDown)  ::
        (Key.A,         Intent.MoveLeft)  ::
        (Key.Left,      Intent.MoveLeft)  ::
        (Key.D,         Intent.MoveRight) ::
        (Key.Right,     Intent.MoveRight) ::
        (Key.LeftShift, Intent.Debug)     :: Nil

    /// 押した瞬間だけ効く操作の表。
    def tapTable(): InputMap.Table[Intent] =
        (Key.Z,      Intent.Talk)    ::
        (Key.C,      Intent.Memo)    ::
        (Key.H,      Intent.Hint)    ::
        (Key.X,      Intent.Cancel)  ::
        (Key.Enter,  Intent.Confirm) ::
        (Key.Escape, Intent.Quit)    :: Nil

    /// このフレームのキーをゲームの意味へ写す。押しっぱなし系・移動キーの押した瞬間
    /// （メニュー用の upTap / downTap）・単発系の発火した意図を、中立の入力へ旗として畳み込む。
    pub def inputOf(frame: App.Frame): Room.Input =
        let held = InputMap.held(heldTable(), frame) |> List.foldLeft(applyHeld, Room.noKeys());
        let moved = InputMap.taps(heldTable(), frame) |> List.foldLeft(applyMoveTap, held);
        InputMap.taps(tapTable(), frame) |> List.foldLeft(applyTap, moved)

    /// 押しっぱなし系の意図 1 つを Input の旗にする（移動 4 方向とデバッグ長押し）。
    def applyHeld(acc: Room.Input, intent: Intent): Room.Input = match intent {
        case Intent.MoveUp    => { up = true | acc }
        case Intent.MoveDown  => { down = true | acc }
        case Intent.MoveLeft  => { left = true | acc }
        case Intent.MoveRight => { right = true | acc }
        case Intent.Debug     => { debug = true | acc }
        case _                => acc
    }

    /// 移動キーの押した瞬間をメニュー移動の旗にする（メモのカーソル用）。
    def applyMoveTap(acc: Room.Input, intent: Intent): Room.Input = match intent {
        case Intent.MoveUp   => { upTap = true | acc }
        case Intent.MoveDown => { downTap = true | acc }
        case _               => acc
    }

    /// 単発系の意図 1 つを Input の旗にする。
    def applyTap(acc: Room.Input, intent: Intent): Room.Input = match intent {
        case Intent.Talk    => { talk = true | acc }
        case Intent.Memo    => { memo = true | acc }
        case Intent.Hint    => { hint = true | acc }
        case Intent.Cancel  => { cancel = true | acc }
        case Intent.Confirm => { enter = true | acc }
        case Intent.Quit    => { esc = true | acc }
        case _              => acc
    }

    /// 毎フレームのシステムその一: キーを Input へ写し、tick のルールで World を進める（純粋）。
    pub def step(frame: App.Frame, s: LiarsRoom.Session): LiarsRoom.Session =
        { world = LiarsRoom.tick(inputOf(frame), frame#dt, s#world) | s }

    /// 毎フレームのシステムその二: 進んだ後の World から UI ページの見た目を導く。
    pub def projectUi(_frame: App.Frame, s: LiarsRoom.Session): LiarsRoom.Session =
        { ui = GameUi.projectUi(s#world, s#ui) | s }

    /// F1 リロード: 生成済みの UI Spec をディスクから読み直す（遊びながらページを直せる）。
    pub def reloadUi(s: LiarsRoom.Session): LiarsRoom.Session \ {Fs.FileRead} =
        { ui = UiSpec.reloadAll(s#ui) | s }

    /// 終了判定: タイトル画面での Escape だけがウィンドウを閉じる
    /// （それ以外の Escape は tick が「タイトルへ戻る・閉じる」として受け取る）。
    pub def wantsQuit(frame: App.Frame, s: LiarsRoom.Session): Bool =
        let Room.World.World(state) = s#world;
        inputOf(frame)#esc and state#phase == Room.Phase.Title
}
