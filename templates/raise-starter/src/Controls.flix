// Controls — 入力の解釈（純粋）と Doc の読み直し。
// ターン制なので操作は「選ぶだけ」: ↑↓（またはマウスホイール無し・キーのみ）で行動を選び、
// Space/Enter で決定する。連続入力（押しっぱなし）は無く、すべて justPressed（押した瞬間）で拾う
// — ターンが 1 回の押下で 1 つ進むのが素直で、初学者にも追いやすい。
// Doc の保存即反映（watchFile）と F1 一括リロードの読み直しもここに置く。
mod Controls {
    use GameEngine.Key

    /// 毎フレームのシステム: 入力を状態へ写す。
    /// カーソル移動（↑↓ / ←→）は Day のときだけ効き、決定（Space/Enter）は場面ごとに意味が変わる。
    /// dt は使わない（ターン制で毎フレーム進む状態が無い）が、システムの形は他テンプレと同じに保つ。
    pub def step(frame: App.Frame, w: World.World): World.World =
        w |> applyNav(frame) |> applyConfirm(frame)

    /// カーソル移動（押した瞬間だけ 1 つ動く）。↑ ← が前、↓ → が後ろ。Day 以外では World が無視する。
    def applyNav(frame: App.Frame, w: World.World): World.World =
        let up = App.justPressed(Key.Up, frame) or App.justPressed(Key.Left, frame);
        let down = App.justPressed(Key.Down, frame) or App.justPressed(Key.Right, frame);
        if (up) World.moveCursor(-1, w)
        else if (down) World.moveCursor(1, w)
        else w

    /// 決定（Space / Enter を押した瞬間）。意味は場面依存（World.confirm）:
    /// Title→はじめる / Day→行動を決める / Reveal→次の日へ / Result→タイトルへ。
    def applyConfirm(frame: App.Frame, w: World.World): World.World =
        let tapped = App.justPressed(Key.Space, frame) or App.justPressed(Key.Enter, frame);
        if (tapped) World.confirm(w) else w

    // ── Doc の読み込み・読み直し（watchFile / F1） ──

    /// 起動時と bake が同じ形で読む Doc の束。
    pub def loadDocs(): World.Docs \ Fs.FileRead =
        { rules = RulesDoc.load(RulesDoc.path()),
          theme = ThemeDoc.load(ThemeDoc.path()),
          plan = PlanDoc.load(PlanDoc.path()) }

    pub def reloadRules(w: World.World): World.World \ Fs.FileRead =
        World.withRules(RulesDoc.load(RulesDoc.path()), w)

    pub def reloadTheme(w: World.World): World.World \ Fs.FileRead =
        World.withTheme(ThemeDoc.load(ThemeDoc.path()), w)

    pub def reloadPlan(w: World.World): World.World \ Fs.FileRead =
        World.withPlan(PlanDoc.load(PlanDoc.path()), w)

    /// F1: Doc を全部読み直す。
    pub def reloadAll(w: World.World): World.World \ Fs.FileRead =
        w |> reloadRules |> reloadTheme |> reloadPlan
}
