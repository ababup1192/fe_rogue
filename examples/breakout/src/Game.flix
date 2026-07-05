// Game — 副作用の縁（World の外）の番地: 入力を読み |> Step で進め |> View で絵にし |> 画面へ描く。
// ウィンドウが閉じるまでこれを回すランチャー loop と、その起点 start。純粋な値の世界（World・
// Step・View）へ触れるのはここだけで、シグネチャがそれを語る: `\ {GameEngine.Game, Fs.FileRead}`。
// キー読み・時計読み・描画・F1 での parameters.json 読み直し —— 境界越えはすべてこの縁に閉じる。

mod Game {

    // ── ランチャー: キーと時計を読む |> Step.update |> frame、ウィンドウが閉じるまで ──

    pub def start(atlas: FontAtlas): Unit \ {GameEngine.Game, Fs.FileRead} =
        loop(atlas, Field.titleWorld(), { enter = true, launch = true, esc = true, f1 = false })

    /// loop は World と前フレームのキー状態を糸のように繋ぐ（enter/launch/esc は true から
    /// 始まるので、起動時にすでに押されているキーは一度離すまで何も語らない）。
    /// F1 は assets/parameters.json を読み直してパラメータを差し替える: 遊びながら json を編集し、
    /// F1 を押せばその場で効きが変わる（ファイル読みの effect はこの縁だけ）。
    def loop(atlas: FontAtlas, world: Field.World,
             prev: { enter = Bool, launch = Bool, esc = Bool, f1 = Bool }): Unit \ {GameEngine.Game, Fs.FileRead} =
        let enterDown = GameEngine.Game.isKeyPressed(GameEngine.Key.Enter);
        let launchDown = GameEngine.Game.isKeyPressed(GameEngine.Key.Space);
        let escDown = GameEngine.Game.isKeyPressed(GameEngine.Key.Escape);
        let f1Down = GameEngine.Game.isKeyPressed(GameEngine.Key.F1);
        if (GameEngine.Game.shouldClose() or InputEdge.pressed(prev#esc, escDown)) ()
        else {
            let tuned = if (InputEdge.pressed(prev#f1, f1Down)) { params = GameParameters.load() | world } else world;
            let input: Field.Input = {
                left = GameEngine.Game.isKeyPressed(GameEngine.Key.Left),
                right = GameEngine.Game.isKeyPressed(GameEngine.Key.Right),
                launch = InputEdge.pressed(prev#launch, launchDown),
                enter = InputEdge.pressed(prev#enter, enterDown) };
            let advanced = Step.update(input, readDt(), tuned);
            renderFrame(atlas, advanced);
            loop(atlas, advanced, { enter = enterDown, launch = launchDown, esc = escDown, f1 = f1Down })
        }

    /// 時計は World の外に住む。エンジンが値をクランプするので、長いカクつきでも先へワープしない。
    def readDt(): Float64 \ GameEngine.Game =
        Duration.toSeconds(GameEngine.Game.getDeltaTime())

    /// 盤の絵をエンジンに渡す。
    def renderFrame(atlas: FontAtlas, world: Field.World): Unit \ GameEngine.Game =
        let (drawables, polygons) = View.frame(atlas, world);
        GameEngine.Game.renderCommands(drawables, Nil, polygons)
}
