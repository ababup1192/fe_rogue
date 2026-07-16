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

    /// BGM 実験の意図。B = フェードの向きを反転、M = マスター音量 1.0/0.3 の切り替え。
    enum AudioIntent with Eq {
        case ToggleFade
        case ToggleMaster
    }

    def audioTable(): InputMap.Table[AudioIntent] =
           (Key.B, AudioIntent.ToggleFade)
        :: (Key.M, AudioIntent.ToggleMaster)
        :: Nil

    /// BGM フェードとマスター音量の手本 system。
    /// 分業: 音量の「値」はエンジンの純関数（Transition.Progress + AudioFade.volumeOf）が導き、
    /// それを実機へ流す setVolume / setMasterVolume の副作用だけをこの system が受け持つ。
    pub def audioStep(frame: App.Frame, world: World.World): World.World \ GameEngine.Audio =
        let taps = InputMap.taps(audioTable(), frame);
        let bgm = world#bgm
            |> (b -> if (List.memberOf(AudioIntent.ToggleFade, taps)) reverseFade(b) else b)
            |> (b -> if (List.memberOf(AudioIntent.ToggleMaster, taps))
                         { master = if (b#master < 1.0) 1.0 else 0.3 | b } else b)
            |> (b -> { progress = Transition.advance(frame#dt, b#progress) | b });
        if (not bgm#playing) GameEngine.Audio.playAudio("bgm") else ();
        GameEngine.Audio.setVolume("bgm", RenderUtil.f32(World.bgmVolume(bgm)));
        GameEngine.Audio.setMasterVolume(RenderUtil.f32(bgm#master));
        { bgm = { playing = true | bgm } | world }

    /// フェードの向きを反転する。今の音量から続きになるよう、進み具合も左右反転して引き継ぐ
    /// （例: t=0.3 のフェードインを反転すると t=0.7 のフェードアウト。音量が飛ばない）。
    def reverseFade(bgm: World.Bgm): World.Bgm =
        let remaining = (1.0 - Transition.tOf(bgm#progress)) * World.bgmDuration();
        { rising = not bgm#rising,
          progress = Transition.start(World.bgmDuration()) |> Transition.advance(remaining) | bgm }

    /// 毎フレームのシステムその二: 進んだ後の状態から UI の bind 文言を整える。
    pub def projectUi(_frame: App.Frame, world: World.World): World.World =
        GameUi.projectUi(world)

    /// F1 リロード: ui.json をディスクから読み直す（遊びながらラベルの見た目を直せる）。
    pub def reloadUi(world: World.World): World.World \ {Fs.FileRead} =
        { ui = UiSpec.reloadAll(world#ui) | world }

    /// フルスクリーン切替・カーソル表示切替の意図。Enter = フルスクリーン、H = カーソル。
    enum WindowIntent with Eq {
        case ToggleFullscreen
        case ToggleCursor
    }

    def windowTable(): InputMap.Table[WindowIntent] =
           (Key.Enter, WindowIntent.ToggleFullscreen)
        :: (Key.H,     WindowIntent.ToggleCursor)
        :: Nil

    /// ウィンドウ実験の手本 system。分業は audioStep と同じ: 値（on/off）は World が持ち、
    /// 実機へ反映する setFullscreen / setCursorVisible の副作用だけをこの system が受け持つ。
    /// 切り替わった回だけ呼ぶ（毎フレーム呼んでも実装は冪等だが、既存の setDebugBadge /
    /// setCursor 呼び出し = App.flix の F8 トグルと同じ「変化した時だけ」の流儀に合わせる）。
    pub def windowStep(frame: App.Frame, world: World.World): World.World \ GameEngine.Game =
        let taps = InputMap.taps(windowTable(), frame);
        let toggleFullscreen = List.memberOf(WindowIntent.ToggleFullscreen, taps);
        let toggleCursor = List.memberOf(WindowIntent.ToggleCursor, taps);
        let fullscreen = if (toggleFullscreen) not world#fullscreen else world#fullscreen;
        let cursorVisible = if (toggleCursor) not world#cursorVisible else world#cursorVisible;
        if (toggleFullscreen) GameEngine.Game.setFullscreen(fullscreen) else ();
        if (toggleCursor) GameEngine.Game.setCursorVisible(cursorVisible) else ();
        { fullscreen = fullscreen, cursorVisible = cursorVisible | world }
}
