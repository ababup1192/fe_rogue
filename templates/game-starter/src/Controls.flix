// Controls — キーを World.Input へ写し、World.step で 1 歩進める（純粋）。
// ←→↑↓（矢印キー）で主人公を動かす。
// Doc の保存即反映（watchFile）と F1 一括リロードの読み直しもここに置く。
mod Controls {
    use GameEngine.Key

    /// このフレームのキーを World.Input へ。App.axis が押し下げを -1 / 0 / +1 に畳む。
    pub def inputOf(frame: App.Frame): World.Input =
        { x = App.axis(negative = Key.Left, positive = Key.Right, frame),
          y = App.axis(negative = Key.Up,   positive = Key.Down,  frame) }

    /// 毎フレームのシステム。
    pub def step(frame: App.Frame, w: World.World): World.World =
        World.step(inputOf(frame), frame#dt, w)

    // ── Doc の読み直し（watchFile / F1） ──

    pub def reloadDoc(w: World.World): World.World \ Fs.FileRead =
        World.withDoc(SampleDoc.load(SampleDoc.path()), w)

    /// テーマは色に加えて「塗りの仕上げ」も持つので、絵も読み直して掛け直す
    /// （仕上げは読み込み時に 1 回だけ掛かる = 絵の側に焼き込まれているため）。
    pub def reloadTheme(w: World.World): World.World \ Fs.FileRead =
        World.withTheme(ThemeDoc.load(ThemeDoc.path()),
            PxSpriteDoc.load(World.spritePath()), w)

    pub def reloadSprites(w: World.World): World.World \ Fs.FileRead =
        World.withSprites(PxSpriteDoc.load(World.spritePath()), w)

    /// 空の塗り。壊れていれば engine の見本の面に倒す（何も出ないより気付ける）。
    pub def loadShader(): ShaderDoc.Spec \ Fs.FileRead =
        ShaderJson.load(World.shaderPath())
            |> Result.getWithDefault(ShaderDoc.demoSurface())

    pub def reloadShader(w: World.World): World.World \ Fs.FileRead =
        World.withShader(loadShader(), w)

    pub def reloadAll(w: World.World): World.World \ Fs.FileRead =
        w |> reloadDoc |> reloadTheme |> reloadSprites |> reloadShader
}
