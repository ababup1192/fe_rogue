// Controls — キーを World.Input へ写し、World.step で 1 歩進める（純粋）。
// どのキーがどの操作かは KeysDoc（player.keys.json）が決める — 既定は
// ←→↑↓（矢印キー）と WASD。エディタで割り当てを変えて保存すると即反映。
// Doc の保存即反映（watchFile）と F1 一括リロードの読み直しもここに置く。
mod Controls {

    /// このフレームのキーを World.Input へ。操作ごとのキーの列（keys Doc）の
    /// どれか 1 つでも押されていれば効き、逆向きが同時なら打ち消して 0。
    pub def inputOf(frame: App.Frame, keys: KeysDoc.Doc): World.Input =
        let held = ks -> List.exists(k -> App.isDown(k, frame), ks);
        let axis = (negDown, posDown) ->
            (if (posDown) 1.0 else 0.0) - (if (negDown) 1.0 else 0.0);
        { x = axis(held(keys#left), held(keys#right)),
          y = axis(held(keys#up), held(keys#down)) }

    /// 毎フレームのシステム。
    pub def step(frame: App.Frame, w: World.World): World.World =
        World.step(inputOf(frame, w#keys), frame#dt, w)

    // ── Doc の読み直し（watchFile / F1） ──

    pub def reloadDoc(w: World.World): World.World \ Fs.FileRead =
        World.withDoc(SampleDoc.load(SampleDoc.path()), w)

    pub def reloadKeys(w: World.World): World.World \ Fs.FileRead =
        World.withKeys(KeysDoc.load(KeysDoc.path()), w)

    /// テーマは色に加えて「塗りの仕上げ」も持つので、絵も読み直して掛け直す
    /// （仕上げは読み込み時に 1 回だけ掛かる = 絵の側に生成の結果として定着しているため）。
    pub def reloadTheme(w: World.World): World.World \ Fs.FileRead =
        World.withTheme(ThemeDoc.load(ThemeDoc.path()),
            PxSpriteDoc.load(World.spritePath()), w)

    pub def reloadSprites(w: World.World): World.World \ Fs.FileRead =
        World.withSprites(PxSpriteDoc.load(World.spritePath()), w)

    /// 空の塗り。壊れていれば engine の見本の面に倒す（何も出ないより気付ける）。
    pub def loadShader(): ShaderDoc.Spec \ Fs.FileRead =
        ShaderJson.loadOr(ShaderDoc.demoSurface(), World.shaderPath())

    pub def reloadShader(w: World.World): World.World \ Fs.FileRead =
        World.withShader(loadShader(), w)

    pub def reloadAll(w: World.World): World.World \ Fs.FileRead =
        w |> reloadDoc |> reloadKeys |> reloadTheme |> reloadSprites |> reloadShader
}
