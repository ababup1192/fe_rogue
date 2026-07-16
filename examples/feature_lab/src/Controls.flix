// Controls — キーで種類を選び、Space で再生し直す。dt は毎フレーム Progress に積む
// （再生し終えたらそこで止まる。ループはしない = 切り替えの一瞬を眺める用途に合わせる）。
// キー → 意図の対応は table が 1 枚で持ち、写しは InputMap に任せる。

mod Controls {
    use GameEngine.Key

    /// 押した瞬間だけ効く操作の意図。矢印の代わりに WASD を使い、Left/Right は
    /// 今後スクラブ等の他機能と衝突しないようにする。
    enum Intent with Eq {
        case PickFadeOut
        case PickFadeIn
        case PickWipeLeft
        case PickWipeRight
        case Restart
    }

    /// キー → 意図の表。W=FadeOut, A=FadeIn, S=WipeLeft, D=WipeRight, Space=再生し直し。
    def table(): InputMap.Table[Intent] =
           (Key.W,     Intent.PickFadeOut)
        :: (Key.A,     Intent.PickFadeIn)
        :: (Key.S,     Intent.PickWipeLeft)
        :: (Key.D,     Intent.PickWipeRight)
        :: (Key.Space, Intent.Restart)
        :: Nil

    /// 意図から選ばれる種類を引く（Restart は種類を選ばないので None）。
    def kindOf(intent: Intent): Option[Transition.Kind] = match intent {
        case Intent.PickFadeOut   => Some(Transition.Kind.FadeOut)
        case Intent.PickFadeIn    => Some(Transition.Kind.FadeIn)
        case Intent.PickWipeLeft  => Some(Transition.Kind.WipeLeft)
        case Intent.PickWipeRight => Some(Transition.Kind.WipeRight)
        case Intent.Restart       => None
    }

    pub def step(frame: App.Frame, world: World.World): World.World =
        let tapped = InputMap.taps(table(), frame);
        let picked = tapped |> List.filterMap(kindOf) |> List.head;
        let restarted = List.memberOf(Intent.Restart, tapped);
        match (picked, restarted) {
            case (Some(kind), _) => { kind = kind, progress = Transition.start(World.duration()) | world }
            case (None, true)    => { progress = Transition.start(World.duration()) | world }
            case (None, false)   => { progress = Transition.advance(frame#dt, world#progress) | world }
        }

    /// withFixedStep 実験用のカウンタ: サブステップも含め updateSystems が回るたび 1 増える
    /// （statusLine の steps= に出る。可変 dt 時の増分と見比べる目安）。
    pub def countStep(_frame: App.Frame, world: World.World): World.World =
        { steps = world#steps + 1 | world }

    /// 毎フレームのシステムその二: 進んだ後の状態から UI の bind 文言を整える。
    pub def projectUi(_frame: App.Frame, world: World.World): World.World =
        GameUi.projectUi(world)

    /// F1 リロード: ui.json をディスクから読み直す（遊びながらラベルの見た目を直せる）。
    pub def reloadUi(world: World.World): World.World \ {Fs.FileRead} =
        { ui = UiSpec.reloadAll(world#ui) | world }
}
