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

    pub type alias World = {
        kind = Transition.Kind,                   // 最後に選んだ種類（Idle 中の Space もこれを再生）
        playing = Option[Transition.Progress],    // None = Idle（覆いなし）/ Some = 再生中の進み具合
        steps = Int32,
        bgm = Bgm,
        ui = UiStore.UiWorld,
        fullscreen = Bool,     // Enter で切り替え（ウィンドウ⇄ボーダーレスフルスクリーン）
        cursorVisible = Bool   // H で切り替え（マウスカーソルの表示/非表示）
    }

    /// 起動直後は Idle（覆いなし）で始める。いきなり遷移を再生すると画面が
    /// フェードアウトして「消えた」ように見え、フルスクリーン等の起動確認ができないため。
    /// BGM は無音からのフェードインで始まり、マスターは全開。
    /// ui は外の世界（ファイル）に触れるので、読み込み済みの物を Main から受け取る。
    /// ウィンドウ表示は通常の窓・カーソルは見える状態で始める。
    pub def initial(ui: UiStore.UiWorld): World =
        { kind = Transition.Kind.FadeOut, playing = None, steps = 0,
          bgm = { rising = true, progress = Transition.start(bgmDuration()), master = 1.0, playing = false },
          ui = ui, fullscreen = false, cursorVisible = true }

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

    /// 画面下の 1 行サマリ（遷移・固定ステップ・BGM 音量とマスター音量・フルスクリーン・カーソル）。
    pub def statusLine(world: World): String =
        "transition=${transitionLabel(world)} t=${round2(transitionT(world))} steps=${world#steps}"
            + " bgm=${round2(bgmVolume(world#bgm))} master=${round2(world#bgm#master)}"
            + " fullscreen=${onOff(world#fullscreen)} cursor=${onOff(world#cursorVisible)}"

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
