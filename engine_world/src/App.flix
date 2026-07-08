// App — ゲームを「宣言」で組み立てて走らせるランナー。ゲーム側は初期 World にシステムと
// 絵と音を繋いで launch を呼ぶだけ、窓・時計・キー・描画・末尾再帰のループはすべてここが引き受ける。
// 外の世界に触れる処理（effect）はこのモジュールが独占するので、ゲームのシステムは
// (Frame, w) -> w の純粋関数として書ける: 押されているキーとエッジと dt は、毎フレーム
// App が Frame という値に焼いて渡す。World の型 w には触れない（初期値・システム・絵・音は
// ぜんぶゲーム側が持ち込む。初期値の組み立てに effect が要るなら、main が自分のハンドラで
// 組んでから App.make へ渡せばよい）。

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

    /// ゲーム 1 本の宣言。make で空を作り、addStartup / addSystem / reloadOn / withView /
    /// withAudio / quitWhen で部品を繋ぎ、launch へ渡す。w はゲームが持ち込む World の型。
    /// ef はゲームのシステム・絵・音・終了判定が帯びる効果（外の世界に触れる処理）の行。
    /// 純粋なゲームは ef = {}（Pure）、effect で状態を持つゲームは自分の効果行を ef に載せて
    /// 同じ App に乗せる（効果多相）。
    pub type alias App[w: Type, ef: Eff] = {
        init = w,                                                  // 出発点の World
        startupSystems = List[w -> w \ ef],                        // 起動時に 1 回だけ・追加順
        updateSystems = List[(Frame, w) -> w \ ef],                // 毎フレーム・追加順
        reload = Option[(GameEngine.Key, w -> w \ {Fs.FileRead})], // ホットリロード（キーと、ファイル読みの副作用）
        // World を (置き場所, 見せたい物) の列へ投影する。None のゲームは App に描画させず自分の
        // システム内で描く（タイルマップ等の複数チャンネルを直接組むゲーム向け）。
        view = Option[(FontAtlas, w) -> List[Render.Placed] \ ef],
        audio = { before = w, after = w } -> List[String] \ ef,    // 1 フレームの前後から鳴らす音名を導く
        quit = (Frame, w) -> Bool \ ef                             // 終了判定（既定 = Escape のエッジ）
    }

    /// 初期 World だけを持つ空の App。絵はまだ無い（withView で繋ぐまで何も描かない）。
    pub def make(init: w): App[w, ef] =
        // 既定の hook は純粋だが、フィールド型は効果多相 ef。Pure は任意の ef に安全に広げられるので
        // 本体を checked_ecast で ef へ widen して型を合わせる（呼び出し側が ef を絞る）。
        { init = init,
          startupSystems = Nil,
          updateSystems = Nil,
          reload = None,
          view = None,
          audio = _worlds -> checked_ecast(Nil),
          quit = (frame, _world) -> checked_ecast(justPressed(GameEngine.Key.Escape, frame)) }

    /// 起動時に 1 回だけ走るシステムを末尾へ繋ぐ（追加順に適用される）。
    pub def addStartup(sys: w -> w \ ef, app: App[w, ef]): App[w, ef] =
        { startupSystems = List.append(app#startupSystems, sys :: Nil) | app }

    /// 毎フレーム走るシステムを末尾へ繋ぐ（追加順に適用される）。
    pub def addSystem(sys: (Frame, w) -> w \ ef, app: App[w, ef]): App[w, ef] =
        { updateSystems = List.append(app#updateSystems, sys :: Nil) | app }

    /// key が押された瞬間に World を作り直すホットリロードを繋ぐ（ファイル読みの副作用つき）。
    /// 遊びながら設定ファイルを編集し、キー一発で効きを変える用途に。
    pub def reloadOn(key: GameEngine.Key, f: w -> w \ {Fs.FileRead}, app: App[w, ef]): App[w, ef] =
        { reload = Some((key, f)) | app }

    /// World を絵（(置き場所, 見せたい物) の列）へ投影する関数を繋ぐ。
    pub def withView(v: (FontAtlas, w) -> List[Render.Placed] \ ef,
                     app: App[w, ef]): App[w, ef] =
        { view = Some(v) | app }

    /// 1 フレームの前後の World（{before, after}）から鳴らす音名を導く関数を繋ぐ
    /// （再生は App が引き受ける）。
    pub def withAudio(sfx: { before = w, after = w } -> List[String] \ ef, app: App[w, ef]): App[w, ef] =
        { audio = sfx | app }

    /// 終了判定を差し替える。既定は「Escape のエッジで終了」だが、モーダル表示中は
    /// Escape をパネル閉じに使いたい、といったゲームはここで自分の条件を宣言する。
    pub def quitWhen(f: (Frame, w) -> Bool \ ef, app: App[w, ef]): App[w, ef] =
        { quit = f | app }

    // ── 純粋な芯（テストはここを直接叩く）──

    /// 前フレームと今フレームのキー集合から Frame を組む。justPressed は差分
    /// （今あって前に無いキー）なので、押しっぱなしはエッジにならない。
    pub def frameOf(prev: {prev = Set[GameEngine.Key]},
                    current: {current = Set[GameEngine.Key]}, dt: Float64): Frame =
        { down = current#current,
          justPressed = Set.difference(current#current, prev#prev),
          dt = dt }

    /// システムの列を追加順（左から右）に World へ畳み込む。
    pub def applySystems(frame: Frame, systems: List[(Frame, w) -> w \ ef], world: w): w \ ef =
        List.foldLeft((acc, sys) -> sys(frame, acc), world, systems)

    // ── ランナー: 起動して、閉じるまで回す ──

    /// App を走らせる単一の効果多相ランナー。startup を 1 回だけ畳み、いま押されているキーを prev の
    /// 種にしてループへ入る（起動時にすでに押されているキーは、一度離すまでエッジにならない）。
    ///
    /// ウィンドウ（GameEngine.Game/Audio）・Fs・ゲーム固有の effect（ef）は 隠蔽せず呼び出し側の
    /// Main が `with` で明示的に張る（effect-oriented の素直な形）。効果多相なので純粋なゲーム（ef = {}）も
    /// effect で状態を持つゲームも同じ launch を使う。前者は Main で LwjglLayer + Fs を張り、後者は加えて
    /// 自分の effect ハンドラ束を張った内側で呼ぶ。
    pub def launch(app: App[w, ef]): Unit \ (ef + GameEngine.Game + GameEngine.Audio + Fs.FileRead) =
        let world0 = List.foldLeft((acc, sys) -> sys(acc), app#init, app#startupSystems);
        loop(app, world0, InputEvent.currentKeys())

    /// 毎フレーム: キーを読み Frame に焼く → 終了判定 → リロード → システム → 音 → 描画 → 末尾再帰。
    /// 前フレームのキー集合は引数で次のフレームへ渡し続ける（エッジ検出の記憶はこれだけ）。
    def loop(app: App[w, ef], world: w, prevKeys: Set[GameEngine.Key]): Unit \ (ef + GameEngine.Game + GameEngine.Audio + Fs.FileRead) =
        let currentKeys = InputEvent.currentKeys();
        let frame = frameOf(prev = prevKeys, current = currentKeys, readDt());
        let wantsQuit = app#quit;
        if (GameEngine.Game.shouldClose() or wantsQuit(frame, world)) ()
        else {
            let reloaded = applyReload(app, frame, world);
            let advanced = applySystems(frame, app#updateSystems, reloaded);
            playSounds(app, reloaded, advanced);
            renderFrame(app, advanced);
            loop(app, advanced, currentKeys)
        }

    /// reloadOn で繋いだキーが押された瞬間だけ、リロード関数で World を作り直す。
    def applyReload(app: App[w, ef], frame: Frame, world: w): w \ {Fs.FileRead} =
        match app#reload {
            case Some((key, f)) => if (justPressed(key, frame)) f(world) else world
            case None           => world
        }

    /// audio の導いた音名を鳴らす（システム適用の前後の World から導く）。
    def playSounds(app: App[w, ef], before: w, after: w): Unit \ (ef + GameEngine.Audio) =
        let derive = app#audio;
        derive({ before = before, after = after }) |> List.forEach(name -> GameEngine.Audio.playAudio(name))

    /// 時計は World の外に住む。エンジンが値をクランプするので、長いカクつきでも先へワープしない。
    def readDt(): Float64 \ GameEngine.Game =
        Duration.toSeconds(GameEngine.Game.getDeltaTime())

    /// view の投影した絵を描画命令にしてエンジンへ渡す（タイルマップは使わないので空の列を添える）。
    /// view = None のゲームは App では描かない（自分のシステム内で renderCommands を呼ぶ）。
    def renderFrame(app: App[w, ef], world: w): Unit \ (ef + GameEngine.Game) =
        match app#view {
            case None          => ()
            case Some(toItems) =>
                let atlas = GameEngine.Game.getFontAtlas("default");
                let (sprites, polygons) = Render.draw(toItems(atlas, world));
                GameEngine.Game.renderCommands(sprites, Nil, polygons)
        }
}
