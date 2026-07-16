// Controls — キー割り当て: Frame をこのゲームの意味（Input）へ写し、Step のルールで 1 歩進める。
// キー → 意図の対応は table が 1 枚で持ち、写しは InputMap に任せる（同じ意図は 1 回に畳まれる）。
// 絵は View.frame が App に直結するのでここを通らない。唯一の effect は reloadParams の
// parameters.json 読み直し（F1 で遊びながら手触りを変える）で、シグネチャがそれを語る: `\ {Fs.FileRead}`。

mod Controls {
    use GameEngine.Key

    /// キーが写る先の意図。Jump だけは held（押しっぱなし = 高く飛ぶ）と
    /// taps（押した瞬間 = バッファ充填）の両方で読む。
    enum Intent with Eq {
        case MoveLeft   // 左へ走る
        case MoveRight  // 右へ走る
        case Dash       // B ダッシュ（押しっぱなし）
        case Jump       // ジャンプ
        case Sink       // 下入力（下+ジャンプ=すり抜け降下の構え）
        case Switch     // キャラ切り替え（押した瞬間だけ）
    }

    /// 単発の操作の意図（押した瞬間だけ効く）。押しっぱなしの Intent とは別の語彙。
    enum Tap with Eq {
        case ToggleHits
    }

    /// 単発キー → 意図の表。H で当たり形の重ね描き（デバッグ表示）を切り替える。
    def tapTable(): InputMap.Table[Tap] =
        (Key.H, Tap.ToggleHits) :: Nil

    /// キー → 意図の表。走りは矢印と A/D、ジャンプは X に加えて Space / W / ↑、
    /// 下は ↓ と S の両対応（同じ意図は同時に押しても 1 回に畳まれる）。
    def table(): InputMap.Table[Intent] =
           (Key.Left,      Intent.MoveLeft)
        :: (Key.A,         Intent.MoveLeft)
        :: (Key.Right,     Intent.MoveRight)
        :: (Key.D,         Intent.MoveRight)
        :: (Key.Z,         Intent.Dash)
        :: (Key.X,         Intent.Jump)
        :: (Key.Space,     Intent.Jump)
        :: (Key.W,         Intent.Jump)
        :: (Key.Up,        Intent.Jump)
        :: (Key.Down,      Intent.Sink)
        :: (Key.S,         Intent.Sink)
        :: (Key.LeftShift, Intent.Switch)
        :: Nil

    /// このフレームのキーをゲームの意味（Input）へ写す。moveX は走りの軸値
    /// （held の移動意図を fold で畳んだもの）。ジャンプは両方要る:
    /// jumpDown（held = 高く飛ぶ）と jumpPressed（taps = バッファ充填）。
    /// 切り替えは taps だけ（押しっぱなしで連打にならない）。
    pub def inputOf(frame: App.Frame): Field.Input =
        let heldNow = InputMap.held(table(), frame);
        let tapped  = InputMap.taps(table(), frame);
        { moveX         = List.foldLeft(axis, 0.0, heldNow),
          dash          = List.memberOf(Intent.Dash, heldNow),
          jumpDown      = List.memberOf(Intent.Jump, heldNow),
          jumpPressed   = List.memberOf(Intent.Jump, tapped),
          down          = List.memberOf(Intent.Sink, heldNow),
          switchPressed = List.memberOf(Intent.Switch, tapped) }

    /// 移動の意図を軸値へ畳む: 左は -1.0、右は +1.0、両方押しは打ち消して 0.0。
    def axis(acc: Float64, intent: Intent): Float64 = match intent {
        case Intent.MoveLeft  => acc - 1.0
        case Intent.MoveRight => acc + 1.0
        case _                => acc
    }

    /// 毎フレームのシステム: 単発キー（表示切り替え）を先に効かせ、
    /// キーを Input へ写して Step のルールで World を 1 歩進める（純粋）。
    pub def step(frame: App.Frame, world: Field.World): Field.World =
        let tapped = List.foldLeft(applyTap, world, InputMap.taps(tapTable(), frame));
        Step.update(inputOf(frame), frame#dt, tapped)

    /// 単発の意図 1 個ぶんを World へ効かせる。
    def applyTap(world: Field.World, tap: Tap): Field.World =
        match tap {
            case Tap.ToggleHits => Field.toggleHits(world)
        }

    /// F1 リロード: parameters.json と hitbox.json を読み直して差し替える。
    /// hitbox は読めて欠けが無いときだけ替わる（壊れていれば今の宣言を守る）。
    pub def reloadParams(world: Field.World): Field.World \ {Fs.FileRead} =
        { params = GameParameters.load(), hits = Hits.reloaded(world#hits) | world }
}
