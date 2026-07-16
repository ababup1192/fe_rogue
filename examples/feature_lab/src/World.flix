// World — 実験場の状態。今日の実験（Transition）は「今どの種類を見ているか」と
// 「どれだけ再生が進んだか」、それにラベル UI のページで足りる。
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
        kind = Transition.Kind,
        progress = Transition.Progress,
        steps = Int32,
        bgm = Bgm,
        ui = UiStore.UiWorld,
        fullscreen = Bool,     // Enter で切り替え（ウィンドウ⇄ボーダーレスフルスクリーン）
        cursorVisible = Bool   // H で切り替え（マウスカーソルの表示/非表示）
    }

    /// 起動直後は FadeOut を再生中の状態で始める（画面に出た瞬間から見比べられる）。
    /// BGM は無音からのフェードインで始まり、マスターは全開。
    /// ui は外の世界（ファイル）に触れるので、読み込み済みの物を Main から受け取る。
    /// ウィンドウ表示は通常の窓・カーソルは見える状態で始める。
    pub def initial(ui: UiStore.UiWorld): World =
        { kind = Transition.Kind.FadeOut, progress = Transition.start(duration()), steps = 0,
          bgm = { rising = true, progress = Transition.start(bgmDuration()), master = 1.0, playing = false },
          ui = ui, fullscreen = false, cursorVisible = true }

    /// いまの BGM 音量（フェードの向きと進み具合から導く。実機へ流す値と同じ計算）。
    pub def bgmVolume(bgm: Bgm): Float64 =
        let fade = if (bgm#rising) AudioFade.fadeIn() else AudioFade.fadeOut();
        AudioFade.volumeOf(fade, Transition.tOf(bgm#progress))

    /// 画面下の 1 行サマリ（遷移・固定ステップ・BGM 音量とマスター音量・フルスクリーン・カーソル）。
    pub def statusLine(world: World): String =
        "transition=${kindLabel(world#kind)} t=${round2(Transition.tOf(world#progress))} steps=${world#steps}"
            + " bgm=${round2(bgmVolume(world#bgm))} master=${round2(world#bgm#master)}"
            + " fullscreen=${onOff(world#fullscreen)} cursor=${onOff(world#cursorVisible)}"

    def onOff(b: Bool): String = if (b) "on" else "off"

    def round2(x: Float64): Float64 = Float64.round(x * 100.0) / 100.0

    pub def kindLabel(kind: Transition.Kind): String =
        match kind {
            case Transition.Kind.FadeOut   => "FadeOut"
            case Transition.Kind.FadeIn    => "FadeIn"
            case Transition.Kind.WipeLeft  => "WipeLeft"
            case Transition.Kind.WipeRight => "WipeRight"
        }
}
