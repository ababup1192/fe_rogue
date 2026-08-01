// Controls — 入力の解釈（純粋）と Doc の読み直し。
// 操作は「ハンドル」(←→ 押しっぱなしで左右に寄る)・場面の「決定」(Space/Enter で
// Title→レース / Finish→Title)。
// ハンドルは連続入力なので isDown（押しっぱなしで動く）を axis で拾う。決定は justPressed（押した瞬間）。
mod Controls {
    use GameEngine.Key

    /// 毎フレームのシステム: 状態を dt 進める。左右入力（axis = ハンドル）を World.step へ渡し、
    /// そのあと押した瞬間の「決定」（場面の切り替え）を反映する。
    pub def step(frame: App.Frame, w: World.World): World.World =
        let dir = App.axis(negative = Key.Left, positive = Key.Right, frame);
        World.step(dir, frame#dt, w)
            |> (w1 -> applyConfirm(frame, w1))

    /// 場面の「決定」（Space / Enter を押した瞬間）を反映する。意味は場面依存（World.confirm）。
    /// 走行中の Space/Enter は何もしない（ハンドルは ←→ で別入力）。
    def applyConfirm(frame: App.Frame, w: World.World): World.World =
        let tapped = App.justPressed(Key.Space, frame) or App.justPressed(Key.Enter, frame);
        if (tapped) World.confirm(w) else w

    // ── Doc の読み込み・読み直し（watchFile / F1） ──

    /// 起動時と bake が同じ形で読む Doc の束。
    pub def loadDocs(): World.Docs \ Fs.FileRead =
        { rules = RulesDoc.load(RulesDoc.path()),
          theme = ThemeDoc.load(ThemeDoc.path()),
          course = CourseDoc.load(CourseDoc.path()),
          shader = loadShader() }

    /// 路肩の面。読めない・語彙が違うときはエンジンの見本の面へ倒す（fail-open）。
    pub def loadShader(): ShaderDoc.Spec \ Fs.FileRead =
        ShaderJson.load(World.shaderPath())
            |> Result.getWithDefault(ShaderDoc.demoSurface())

    pub def reloadRules(w: World.World): World.World \ Fs.FileRead =
        World.withRules(RulesDoc.load(RulesDoc.path()), w)

    pub def reloadTheme(w: World.World): World.World \ Fs.FileRead =
        World.withTheme(ThemeDoc.load(ThemeDoc.path()), w)

    pub def reloadCourse(w: World.World): World.World \ Fs.FileRead =
        World.withCourse(CourseDoc.load(CourseDoc.path()), w)

    pub def reloadShader(w: World.World): World.World \ Fs.FileRead =
        World.withShader(loadShader(), w)

    /// F1: Doc を全部読み直す。
    pub def reloadAll(w: World.World): World.World \ Fs.FileRead =
        w |> reloadRules |> reloadTheme |> reloadCourse |> reloadShader
}
