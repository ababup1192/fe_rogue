// App — ゲームを「宣言」で組み立てて走らせるランナー。Main は初期 World にシステムと絵を
// 繋いで launch を呼ぶだけ、窓・時計・キー・描画・末尾再帰のループはすべてここが引き受ける。
// 外の世界に触れる処理（effect）はこのモジュールが独占するので、ゲームのシステムは (Frame, w) -> w の純粋関数として
// 書ける: 押されているキーとエッジと dt は、毎フレーム App が Frame という値に焼いて渡す。
// World の型 w には触れない（初期値・システム・絵はぜんぶ利用側が持ち込む）。

mod App {

    // ── システムが受け取る 1 フレームぶんの外界 ──

    /// このフレームの入力と時計のスナップショット。キーの生読みはランナーが済ませてあるので、
    /// システムは down（押されている）と justPressed（この瞬間押された）を値として引くだけ。
    pub type alias Frame = {
        down = Set[GameEngine.Key],        // いま押されているキー
        justPressed = Set[GameEngine.Key], // このフレームで新しく押されたキー（エッジ）
        dt = Float64                       // 前フレームからの経過秒（エンジンがクランプ済み）
    }

    /// key がいま押されているか（押しっぱなしも true）。移動などの連続入力に。
    pub def isDown(key: GameEngine.Key, frame: Frame): Bool =
        Set.memberOf(key, frame#down)

    /// key がこのフレームで新しく押されたか（押しっぱなしは false）。決定・発射などの単発入力に。
    pub def justPressed(key: GameEngine.Key, frame: Frame): Bool =
        Set.memberOf(key, frame#justPressed)

    // ── App: 宣言の入れ物 ──

    /// ゲーム 1 本の宣言。make で空を作り、addStartup / addSystem / reloadOn / withView で
    /// 部品を繋ぎ、launch へ渡す。w はゲームが持ち込む World の型。
    pub type alias App[w] = {
        init = w,                                                  // 出発点の World
        startupSystems = List[w -> w],                             // 起動時に 1 回だけ・追加順
        updateSystems = List[(Frame, w) -> w],                     // 毎フレーム・追加順
        reload = Option[(GameEngine.Key, w -> w \ {Fs.FileRead})], // ホットリロード（キーと、ファイル読みの副作用）
        view = (FontAtlas, w) -> List[Render.Placed],              // World を (置き場所, 見せたい物) の列へ投影する純粋関数
        audio = { before = w, after = w } -> List[String]          // 1 フレームの前後から鳴らす音名を導く純粋関数
    }

    /// 初期 World だけを持つ空の App。絵はまだ無い（withView で繋ぐまで何も描かない）。
    pub def make(init: w): App[w] =
        { init = init,
          startupSystems = Nil,
          updateSystems = Nil,
          reload = None,
          view = (_atlas, _world) -> Nil,
          audio = _worlds -> Nil }

    /// 起動時に 1 回だけ走るシステムを末尾へ繋ぐ（追加順に適用される）。
    pub def addStartup(sys: w -> w, app: App[w]): App[w] =
        { startupSystems = List.append(app#startupSystems, sys :: Nil) | app }

    /// 毎フレーム走るシステムを末尾へ繋ぐ（追加順に適用される）。
    pub def addSystem(sys: (Frame, w) -> w, app: App[w]): App[w] =
        { updateSystems = List.append(app#updateSystems, sys :: Nil) | app }

    /// key が押された瞬間に World を作り直すホットリロードを繋ぐ（ファイル読みの副作用つき）。
    /// 遊びながら設定ファイルを編集し、キー一発で効きを変える用途に。
    pub def reloadOn(key: GameEngine.Key, f: w -> w \ {Fs.FileRead}, app: App[w]): App[w] =
        { reload = Some((key, f)) | app }

    /// World を絵（(置き場所, 見せたい物) の列）へ投影する関数を繋ぐ。
    pub def withView(v: (FontAtlas, w) -> List[Render.Placed],
                     app: App[w]): App[w] =
        { view = v | app }

    /// 1 フレームの前後の World（{before, after}）から鳴らす音名を導く関数を繋ぐ
    /// （再生は App が引き受ける）。
    pub def withAudio(sfx: { before = w, after = w } -> List[String], app: App[w]): App[w] =
        { audio = sfx | app }

    // ── 純粋な芯（テストはここを直接叩く）──

    /// 前フレームと今フレームのキー集合から Frame を組む。justPressed は差分
    /// （今あって前に無いキー）なので、押しっぱなしはエッジにならない。
    pub def frameOf(prev: {prev = Set[GameEngine.Key]},
                    current: {current = Set[GameEngine.Key]}, dt: Float64): Frame =
        { down = current#current,
          justPressed = Set.difference(current#current, prev#prev),
          dt = dt }

    /// システムの列を追加順（左から右）に World へ畳み込む。
    pub def applySystems(frame: Frame, systems: List[(Frame, w) -> w], world: w): w =
        List.foldLeft((acc, sys) -> sys(frame, acc), world, systems)

    // ── ランナー: 窓を開け、閉じるまで回す ──

    /// App を走らせる。ウィンドウと effect ハンドラ一式を立ち上げ、閉じるまでフレームを回す。
    /// Escape はどのゲームでも終了（押した瞬間に閉じる）。
    pub def launch(app: App[w]): Unit \ IO =
        if (GameEngine.ensureMainThread()) ()
        else {
            run {
                boot(app)
            } with LwjglLayer.withProject(".")
              with Fs.FileRead.runWithIO
              with Fs.FileWrite.runWithIO
              with Fs.Glob.runWithIO
              with Fs.ModificationTime.runWithFileTime
              with Fs.FileTime.runWithIO
        }

    /// 起動: フォントを取り、startup を 1 回だけ畳み、いま押されているキーを prev の種にして
    /// ループへ入る（起動時にすでに押されているキーは、一度離すまでエッジにならない）。
    def boot(app: App[w]): Unit \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead} =
        let atlas = GameEngine.Game.getFontAtlas("default");
        let world0 = List.foldLeft((acc, sys) -> sys(acc), app#init, app#startupSystems);
        loop(app, atlas, world0, InputEvent.currentKeys())

    /// 毎フレーム: キーを読み Frame に焼く → 終了判定 → リロード → システム → 音 → 描画 → 末尾再帰。
    /// 前フレームのキー集合は引数で次のフレームへ渡し続ける（エッジ検出の記憶はこれだけ）。
    def loop(app: App[w], atlas: FontAtlas, world: w, prevKeys: Set[GameEngine.Key]): Unit \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead} =
        let currentKeys = InputEvent.currentKeys();
        let frame = frameOf(prev = prevKeys, current = currentKeys, readDt());
        if (GameEngine.Game.shouldClose() or justPressed(GameEngine.Key.Escape, frame)) ()
        else {
            let reloaded = applyReload(app, frame, world);
            let advanced = applySystems(frame, app#updateSystems, reloaded);
            playSounds(app, reloaded, advanced);
            renderFrame(app, atlas, advanced);
            loop(app, atlas, advanced, currentKeys)
        }

    /// reloadOn で繋いだキーが押された瞬間だけ、リロード関数で World を作り直す。
    def applyReload(app: App[w], frame: Frame, world: w): w \ {Fs.FileRead} =
        match app#reload {
            case Some((key, f)) => if (justPressed(key, frame)) f(world) else world
            case None           => world
        }

    /// audio の導いた音名を鳴らす（システム適用の前後の World から導く）。
    def playSounds(app: App[w], before: w, after: w): Unit \ GameEngine.Audio =
        let derive = app#audio;
        derive({ before = before, after = after }) |> List.forEach(name -> GameEngine.Audio.playAudio(name))

    /// 時計は World の外に住む。エンジンが値をクランプするので、長いカクつきでも先へワープしない。
    def readDt(): Float64 \ GameEngine.Game =
        Duration.toSeconds(GameEngine.Game.getDeltaTime())

    /// view の投影した絵を描画命令にしてエンジンへ渡す（タイルマップは使わないので空の列を添える）。
    def renderFrame(app: App[w], atlas: FontAtlas, world: w): Unit \ GameEngine.Game =
        let toItems = app#view;
        let (sprites, polygons) = Render.draw(toItems(atlas, world));
        GameEngine.Game.renderCommands(sprites, Nil, polygons)
}
