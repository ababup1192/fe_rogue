// World — 実験場の状態。今日の実験（Transition）は「最後にどの種類を選んだか」と
// 「いま再生中か（Idle か）」、それにラベル UI のページで足りる。
// steps は別実験（固定タイムステップ）の検証用カウンタ: withFixedStep を有効にした Main で
// updateSystems が回った回数を数え、可変 dt と同じ絵になるかを目視できるようにする。
// bgm は別実験（AudioFade + マスター音量）の状態: フェードの向き・進み具合・全体つまみを持つ。

mod World {

    /// 遷移の再生に使う所要時間（秒）。長すぎず・短すぎず、見比べやすい長さ。
    pub def duration(): Float64 = 1.2

    /// BGM フェードの所要時間（秒）。耳で「だんだん」が分かる長さ。
    pub def bgmDuration(): Float64 = 2.0

    /// BGM 実験の状態。
    pub type alias Bgm = {
        rising = Bool,                     // true = フェードイン中（無音へ向かうなら false）
        progress = Transition.Progress,    // フェードの進み具合（B で向きを反転して引き継ぐ）
        master = Float64,                  // マスター音量（M で 1.0 / 0.3 を切り替え）
        playing = Bool                     // playAudio を一度呼んだか（起動後の初回だけ鳴らし始める）
    }

    /// カンテラ実験の暗闇モード。Bright=通常表示（暗幕なし）、Dark=暗闇のみ
    /// （Light.multiLightItems を lights=Nil で呼ぶ全面暗幕、光源なし）、
    /// DarkWithLight=穴あき暗幕+ハロ（Light.singleLightItems）。
    /// LeftShift は Bright ⇔ DarkWithLight をトグルする（Dark は比較用の対照カット専用で
    /// ゲーム内操作からは経由しない — bakeLanternComparisonPngs の3枚がそれぞれ1モードに対応する）。
    pub enum LanternMode with Eq {
        case Bright
        case Dark
        case DarkWithLight
    }

    /// カンテラ実験の状態。at はプレイヤー（=光源）の位置、mode は今の暗闇の見せ方。
    /// walls は壁と影（Shadow）のデモの表示スイッチ（既定 off — 常時表示にすると
    /// 既存の lantern 系 bake の絵が変わってしまうため、トグルで足す）。
    pub type alias Lantern = { at = Vec2.Vec2, mode = LanternMode, walls = Bool }

    pub type alias World = {
        kind = Transition.Kind,                   // 最後に選んだ種類（Idle 中の Space もこれを再生）
        playing = Option[Transition.Progress],    // None = Idle（覆いなし）/ Some = 再生中の進み具合
        steps = Int32,
        bgm = Bgm,
        ui = UiStore.UiWorld,
        fullscreen = Bool,     // Enter で切り替え（ウィンドウ⇄ボーダーレスフルスクリーン）
        cursorVisible = Bool,  // H で切り替え（マウスカーソルの表示/非表示）
        blend = Option[DrawCmd.BlendMode],  // None = デモ非表示 / Z/X/C で重ね方を選ぶと表示
        // None = デモ非表示 / 矢印キーを押した瞬間に現れる（他デモと同じ Option パターン。
        // 常時表示にすると他シーンの bake（blend/fps/遷移 GIF）にも部屋と目印が映り込んでしまう）。
        lantern = Option[Lantern]
    }

    /// 起動直後は Idle（覆いなし）で始める。いきなり遷移を再生すると画面が
    /// フェードアウトして「消えた」ように見え、フルスクリーン等の起動確認ができないため。
    /// BGM は無音からのフェードインで始まり、マスターは全開。
    /// ui は外の世界（ファイル）に触れるので、読み込み済みの物を Main から受け取る。
    /// ウィンドウ表示は通常の窓・カーソルは見える状態で始める。
    /// blend デモは初期非表示（None）。常時表示にすると遷移 GIF や fps 見本の bake に
    /// 映り込み、既存の gallery の絵が変わってしまう。
    pub def initial(ui: UiStore.UiWorld): World =
        { kind = Transition.Kind.FadeOut, playing = None, steps = 0,
          bgm = { rising = true, progress = Transition.start(bgmDuration()), master = 1.0, playing = false },
          ui = ui, fullscreen = false, cursorVisible = true,
          blend = None,
          lantern = None }

    /// いまの BGM 音量（フェードの向きと進み具合から導く。実機へ流す値と同じ計算）。
    pub def bgmVolume(bgm: Bgm): Float64 =
        let fade = if (bgm#rising) AudioFade.fadeIn() else AudioFade.fadeOut();
        AudioFade.volumeOf(fade, Transition.tOf(bgm#progress))

    /// HUD と statusLine の遷移表示。Idle のときは操作案内を出す
    /// （何も再生していない画面で種類名だけ出ていると「再生中に見える」ため）。
    pub def transitionLabel(world: World): String =
        world#playing
            |> Option.map(_ -> kindLabel(world#kind))
            |> Option.getWithDefault("idle (W/A/S/D)")

    /// いまの再生位置 t（Idle のときは 0）。
    pub def transitionT(world: World): Float64 =
        world#playing |> Option.map(Transition.tOf) |> Option.getWithDefault(0.0)

    /// 画面下の 1 行サマリ（遷移・固定ステップ・BGM・フルスクリーン・カーソル・ブレンド・カンテラ）。
    pub def statusLine(world: World): String =
        "transition=${transitionLabel(world)} t=${round2(transitionT(world))} steps=${world#steps}"
            + " bgm=${round2(bgmVolume(world#bgm))} master=${round2(world#bgm#master)}"
            + " fullscreen=${onOff(world#fullscreen)} cursor=${onOff(world#cursorVisible)}"
            + " blend=${blendLabel(world#blend)} ${lanternLabel(world#lantern)}"

    /// blend デモの表示名（HUD の bind と statusLine の両方が使う）。非表示中は操作案内。
    pub def blendLabel(blend: Option[DrawCmd.BlendMode]): String =
        blend |> Option.map(modeLabel) |> Option.getWithDefault("off (Z/X/C)")

    /// カンテラ実験の表示名。非表示中は操作案内、表示中は暗闇の on/off を出す
    /// （LeftShift が行き来する Bright/DarkWithLight の2値として見せる — Dark はゲーム内
    /// 操作から経由しないため on/off 表記のままで足りる）。
    pub def lanternLabel(lantern: Option[Lantern]): String =
        lantern
            |> Option.map(l -> "darkness=${onOff(l#mode == LanternMode.DarkWithLight)}${wallsSuffix(l)}")
            |> Option.getWithDefault("lantern=off (Arrows to start)")

    /// walls=off のときは何も足さない（既存 bake の文字列＝絵をバイト単位で変えないため）。
    def wallsSuffix(l: Lantern): String = if (l#walls) " walls=on" else ""

    /// ブレンドモード単体の表示名（gallery のカード名にも使う）。
    pub def modeLabel(mode: DrawCmd.BlendMode): String =
        match mode {
            case DrawCmd.BlendMode.Normal   => "Normal"
            case DrawCmd.BlendMode.Add      => "Add"
            case DrawCmd.BlendMode.Multiply => "Multiply"
        }

    /// on/off 表記。statusLine と HUD 表示（GameUi.bindText）の両方が使う共通表記。
    pub def onOff(b: Bool): String = if (b) "on" else "off"

    def round2(x: Float64): Float64 = Float64.round(x * 100.0) / 100.0

    pub def kindLabel(kind: Transition.Kind): String =
        match kind {
            case Transition.Kind.FadeOut   => "FadeOut"
            case Transition.Kind.FadeIn    => "FadeIn"
            case Transition.Kind.WipeLeft  => "WipeLeft"
            case Transition.Kind.WipeRight => "WipeRight"
        }
}
