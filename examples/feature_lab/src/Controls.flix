// Controls — キーで種類を選ぶと最初から再生し、Space で今の種類を再生し直す。
// 再生し終えたら自動で Idle（覆いなし）に戻る = FadeOut の黒も残らず画面が生き返る。
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
            case (Some(kind), _) => { kind = kind, playing = Some(Transition.start(World.duration())) | world }
            case (None, true)    => { playing = Some(Transition.start(World.duration())) | world }
            case (None, false)   => { playing = advanceOrIdle(frame#dt, world#playing) | world }
        }

    /// 再生中なら進め、最後まで行ったら Idle（None）へ戻す。FadeOut で終わった後も
    /// 黒い覆いを描き続けると画面が消えたように見えるため、「終われば消える」にする。
    def advanceOrIdle(dt: Float64, playing: Option[Transition.Progress]): Option[Transition.Progress] =
        playing |> Option.flatMap(progress -> {
            let advanced = Transition.advance(dt, progress);
            if (Transition.done(advanced)) None else Some(advanced)
        })

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

    /// light.json の置き場所（カンテラ探索デモの光の質感）。
    def lightDocPath(): String = "assets/Lantern.light.json"

    /// light.json を読む。読めない・壊れているときは LightDoc.empty()（fail-open —
    /// ランタイムを止めずに「今は質感の上書きなし」で走らせる）。
    pub def loadLightDoc(): LightDoc.Spec \ Fs.FileRead =
        LightDoc.load(lightDocPath()) |> Result.getWithDefault(LightDoc.empty())

    /// App.watchFile 用: light.json の保存を検知して World の質感を差し替える
    /// （at はここでは触らない — 位置は lantern#at が持ち続ける）。
    pub def reloadLightDoc(world: World.World): World.World \ {Fs.FileRead} =
        { lightDoc = loadLightDoc() | world }

    /// ブレンド実験の意図。Z/X/C で Normal/Add/Multiply を直接選ぶ
    /// （W/A/S/D の Transition 選択と同じ「N 択 = 専用キー N 個」の形）。
    enum BlendIntent with Eq {
        case PickNormal
        case PickAdd
        case PickMultiply
    }

    def blendTable(): InputMap.Table[BlendIntent] =
           (Key.Z, BlendIntent.PickNormal)
        :: (Key.X, BlendIntent.PickAdd)
        :: (Key.C, BlendIntent.PickMultiply)
        :: Nil

    def blendOf(intent: BlendIntent): DrawCmd.BlendMode = match intent {
        case BlendIntent.PickNormal   => DrawCmd.BlendMode.Normal
        case BlendIntent.PickAdd      => DrawCmd.BlendMode.Add
        case BlendIntent.PickMultiply => DrawCmd.BlendMode.Multiply
    }

    /// RGB 3 円デモの重ね方を選ぶ（初回のキーでデモが現れる）。View が world#blend を絵にする。
    pub def blendStep(frame: App.Frame, world: World.World): World.World =
        InputMap.taps(blendTable(), frame)
            |> List.head
            |> Option.map(intent -> { blend = Some(blendOf(intent)) | world })
            |> Option.getWithDefault(world)

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

    /// カンテラ（プレイヤー=光源）の 1 秒あたりの移動距離（40px 格子を 0.4 秒で渡る速さ）。
    def lanternSpeed(): Float64 = 100.0

    /// design 領域（View.design と同じ 320×240）の内側にプレイヤーを留める余白。
    /// カンテラ本体の見た目サイズぶん端で止まって見えるようにする目安値。
    def lanternMargin(): Float64 = 8.0

    /// design 領域の右下限（左上原点・余白を引いた可動範囲）。
    def lanternBounds(): Vec2.Vec2 = { x = 320.0 - lanternMargin(), y = 240.0 - lanternMargin() }

    /// カンテラ登場時の初期位置（design 中央）。
    def lanternStart(): Vec2.Vec2 = { x = 160.0, y = 120.0 }

    /// カンテラの当たり判定半径（見た目のカンテラ玉＝影の証明用マーカーと同じ 6px 級の
    /// 小さな円。光の穴 lanternRadius=48 は「見える範囲」であって当たり判定の大きさではない）。
    def lanternHitRadius(): Float64 = 6.0

    /// 矢印キーのどれかが押されているか（デモの出現条件と移動の両方に使う）。
    def arrowsDown(frame: App.Frame): Bool =
        App.isDown(Key.Left, frame) or App.isDown(Key.Right, frame) or
        App.isDown(Key.Up, frame) or App.isDown(Key.Down, frame)

    /// 暗闇 on/off と壁 on/off の意図。LeftShift・LeftCtrl
    /// （Key に L や V は無いため、feature_lab 未使用のキーで代用）。
    enum LanternIntent with Eq {
        case ToggleDarkness
        case ToggleWalls
    }

    def lanternTable(): InputMap.Table[LanternIntent] =
           (Key.LeftShift, LanternIntent.ToggleDarkness)
        :: (Key.LeftCtrl,  LanternIntent.ToggleWalls)
        :: Nil

    /// カンテラ実験の手本 system。他デモ（blend）と同じ Option パターン: 矢印キーを
    /// 押すまでは None（非表示。bake する他シーンに映り込まない）で、押した瞬間に
    /// 出現して以降は移動し続ける。移動は design 範囲の内側にクランプする
    /// （範囲外へ出るとカンテラの穴あき暗幕が画面から外れて見えなくなるため）。
    /// LeftShift は Bright ⇔ DarkWithLight をトグルする（Dark はゲーム内操作から経由しない）。
    pub def lanternStep(frame: App.Frame, world: World.World): World.World =
        let taps = InputMap.taps(lanternTable(), frame);
        let toggled = List.memberOf(LanternIntent.ToggleDarkness, taps);
        let toggledWalls = List.memberOf(LanternIntent.ToggleWalls, taps);
        match world#lantern {
            case None =>
                if (arrowsDown(frame)) { lantern = Some({ at = lanternStart(), mode = World.LanternMode.Bright, walls = false }) | world }
                else world
            case Some(lantern) =>
                let dx = App.axis({ negative = Key.Left }, { positive = Key.Right }, frame);
                let dy = App.axis({ negative = Key.Up }, { positive = Key.Down }, frame);
                let delta = Vec2.mul({ x = dx, y = dy }, lanternSpeed() * frame#dt);
                let walls = if (toggledWalls) not lantern#walls else lantern#walls;
                let moved = moveLantern(lantern#at, delta, walls);
                let bounds = lanternBounds();
                let clamped = { x = Float64.max(lanternMargin(), Float64.min(bounds#x, moved#x)),
                                 y = Float64.max(lanternMargin(), Float64.min(bounds#y, moved#y)) };
                let mode = if (toggled) toggleBrightness(lantern#mode) else lantern#mode;
                { lantern = Some({ at = clamped, mode = mode, walls = walls }) | world }
        }

    /// カンテラの新しい位置。walls=off なら delta をそのまま足すだけ（自由移動）。
    /// walls=on なら軸ごとに独立して「その軸だけ動かした先が壁と重ならないか」を判定し、
    /// 通れる軸だけ動かす（定番のスライド — 斜め入力で片方の軸が壁際でも、もう片方の軸は
    /// 通り続けられるので壁沿いで引っかかって止まらない）。
    pub def moveLantern(at: Vec2.Vec2, delta: Vec2.Vec2, walls: Bool): Vec2.Vec2 =
        if (not walls)
            Vec2.add(at, delta)
        else {
            let afterX = { x = at#x + delta#x, y = at#y };
            let steppedX = if (hitsWall(afterX)) at else afterX;
            let afterY = { x = steppedX#x, y = steppedX#y + delta#y };
            if (hitsWall(afterY)) steppedX else afterY
        }

    /// pos に置いたカンテラの当たり判定円が、壁のどれかと重なっているか
    /// （形は View.wallHitShapes — 見た目の壁と同じソースから導く。ここで手書きの
    /// AABB 判定は書かず、既存の Hit.overlaps 1 本に判定を委ねる）。
    def hitsWall(pos: Vec2.Vec2): Bool =
        let lanternShape = Hit.HitShape.CircleH({ dx = 0.0, dy = 0.0, r = lanternHitRadius() });
        Hit.overlaps(pos, lanternShape :: Nil, Vec2.zero(), View.wallHitShapes())

    /// Bright ⇔ DarkWithLight のトグル（Dark はゲーム内操作から経由しないので、
    /// 万一そこにいた場合も DarkWithLight 側へ寄せる）。
    def toggleBrightness(mode: World.LanternMode): World.LanternMode =
        if (mode == World.LanternMode.Bright) World.LanternMode.DarkWithLight else World.LanternMode.Bright
}
