// World — 実験場の状態。今日の実験（Transition）は「今どの種類を見ているか」と
// 「どれだけ再生が進んだか」、それにラベル UI のページで足りる。
// steps は別実験（固定タイムステップ）の検証用カウンタ: withFixedStep を有効にした Main で
// updateSystems が回った回数を数え、可変 dt と同じ絵になるかを目視できるようにする。

mod World {

    /// 遷移の再生に使う所要時間（秒）。長すぎず・短すぎず、見比べやすい長さ。
    pub def duration(): Float64 = 1.2

    pub type alias World = {
        kind = Transition.Kind,
        progress = Transition.Progress,
        steps = Int32,
        ui = UiStore.UiWorld
    }

    /// 起動直後は FadeOut を再生中の状態で始める（画面に出た瞬間から見比べられる）。
    /// ui は外の世界（ファイル）に触れるので、読み込み済みの物を Main から受け取る。
    pub def initial(ui: UiStore.UiWorld): World =
        { kind = Transition.Kind.FadeOut, progress = Transition.start(duration()), steps = 0, ui = ui }

    /// 画面下の 1 行サマリ（今の種類・進行度・固定ステップ実験のステップ数）。
    pub def statusLine(world: World): String =
        "transition=${kindLabel(world#kind)} t=${Float64.round(Transition.tOf(world#progress) * 100.0) / 100.0} steps=${world#steps} fixed=on"

    pub def kindLabel(kind: Transition.Kind): String =
        match kind {
            case Transition.Kind.FadeOut   => "FadeOut"
            case Transition.Kind.FadeIn    => "FadeIn"
            case Transition.Kind.WipeLeft  => "WipeLeft"
            case Transition.Kind.WipeRight => "WipeRight"
        }
}
