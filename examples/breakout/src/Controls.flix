// Controls — キー割り当て: Frame を breakout の意味（Input）へ写し、Step のルールで 1 歩進める。
// キー → 意図の対応は table が 1 枚で持ち、写しは InputMap に任せる（同じ意図は 1 回に畳まれる）。
// 絵は View.frame が App に直結するのでここを通らない。唯一の effect は reloadParams の
// parameters.json 読み直し（F1 で遊びながら効きを変える）で、シグネチャがそれを語る: `\ {Fs.FileRead}`。

mod Controls {
    use GameEngine.Key

    /// キーが写る先の意図。移動は押しっぱなし（held）、Launch / Confirm は押した瞬間（taps）で読む。
    enum Intent with Eq {
        case MoveLeft   // パドルを左へ
        case MoveRight  // パドルを右へ
        case Launch     // サーブ（ボール発射）
        case Confirm    // 決定（開始・次の面・やり直し）
    }

    /// キー → 意図の表。パドル移動は矢印と A/D の両対応（同時に押しても意図は 1 回に畳まれる）。
    def table(): InputMap.Table[Intent] =
           (Key.Left,  Intent.MoveLeft)
        :: (Key.A,     Intent.MoveLeft)
        :: (Key.Right, Intent.MoveRight)
        :: (Key.D,     Intent.MoveRight)
        :: (Key.Space, Intent.Launch)
        :: (Key.Enter, Intent.Confirm)
        :: Nil

    /// このフレームのキーを breakout の意味（Input）へ写す。moveX はパドル移動の軸値
    /// （held の移動意図を fold で畳んだもの）、launch/enter は 1 回きり効けばよいので taps を見る。
    pub def inputOf(frame: App.Frame): Field.Input =
        let tapped = InputMap.taps(table(), frame);
        { moveX  = InputMap.held(table(), frame) |> List.foldLeft(axis, 0.0),
          launch = List.memberOf(Intent.Launch, tapped),
          enter  = List.memberOf(Intent.Confirm, tapped) }

    /// 移動の意図を軸値へ畳む: 左は -1.0、右は +1.0、両方押しは打ち消して 0.0。
    def axis(acc: Float64, intent: Intent): Float64 = match intent {
        case Intent.MoveLeft  => acc - 1.0
        case Intent.MoveRight => acc + 1.0
        case _                => acc
    }

    /// 毎フレームのシステム: キーを Input へ写し、Step のルールで World を 1 歩進める（純粋）。
    pub def step(frame: App.Frame, world: Field.World): Field.World =
        Step.update(inputOf(frame), frame#dt, world)

    /// F1 リロード: parameters.json と hitbox.json を読み直して差し替える。hitbox は読めて
    /// 欠けが無いときだけ替わり、組み済みの盤のブロック形は次の盤から反映される。
    pub def reloadParams(world: Field.World): Field.World \ {Fs.FileRead} =
        { params = GameParameters.load(), hits = Hits.reloaded(world#hits) | world }
}
