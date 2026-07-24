// Controls — 入力の解釈（純粋）と Doc の読み直し。
// 操作は「寄せる」(←→ 押しっぱなしで動く)・「撃つ」(Space 押しっぱなしで連射レートに従い発射)・
// 場面の「決定」(Space/Enter で Title→遊び / Clear・GameOver→Title)。
// 左右の移動は連続入力なので isDown（押しっぱなしで動く）。決定は justPressed（押した瞬間）。
// 発射は「押しっぱなしで連射」なので isDown を渡し、実際に撃つ間隔は World.tryFire（fireInterval）が握る。
mod Controls {
    use GameEngine.Key

    /// 毎フレームのシステム: 状態を dt 進める。左右入力（axis）と発射（Space 押下）を World.step へ渡し、
    /// そのあと押した瞬間の「決定」（場面の切り替え）を反映する。
    pub def step(frame: App.Frame, w: World.World): World.World =
        let dir = App.axis(negative = Key.Left, positive = Key.Right, frame);
        let firing = App.isDown(Key.Space, frame) and w#phase == World.Phase.Playing;
        World.step(dir, firing, frame#dt, w)
            |> (w1 -> applyConfirm(frame, w1))

    /// 場面の「決定」（Space / Enter を押した瞬間）を反映する。意味は場面依存（World.confirm）。
    /// 遊び中の Space は発射なので決定には回さない（Playing では confirm は何もしない）。
    def applyConfirm(frame: App.Frame, w: World.World): World.World =
        let tapped = App.justPressed(Key.Space, frame) or App.justPressed(Key.Enter, frame);
        if (tapped) World.confirm(w) else w

    // ── Doc の読み込み・読み直し（watchFile / F1） ──

    /// 起動時と bake が同じ形で読む Doc の束。
    pub def loadDocs(): World.Docs \ Fs.FileRead =
        { rules = RulesDoc.load(RulesDoc.path()),
          theme = ThemeDoc.load(ThemeDoc.path()),
          waves = WavesDoc.load(WavesDoc.path()) }

    pub def reloadRules(w: World.World): World.World \ Fs.FileRead =
        World.withRules(RulesDoc.load(RulesDoc.path()), w)

    pub def reloadTheme(w: World.World): World.World \ Fs.FileRead =
        World.withTheme(ThemeDoc.load(ThemeDoc.path()), w)

    pub def reloadWaves(w: World.World): World.World \ Fs.FileRead =
        World.withWaves(WavesDoc.load(WavesDoc.path()), w)

    /// F1: Doc を全部読み直す。
    pub def reloadAll(w: World.World): World.World \ Fs.FileRead =
        w |> reloadRules |> reloadTheme |> reloadWaves
}
