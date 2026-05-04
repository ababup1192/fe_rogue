// GameEngine module — shared types and effects for the game engine layer

mod GameEngine {
    import java.lang.ProcessBuilder
    import java.lang.System
    import java.util.ArrayList

    /// テクスチャアセットのマニフェストエントリ
    pub type alias TextureEntry = { name = String, path = String, hasAlpha = Bool }

    /// フォントアセットのマニフェストエントリ
    pub type alias FontEntry = { name = String, path = String, fontSize = Float64 }

    /// サウンドアセットのマニフェストエントリ
    /// looping = true でループ再生する
    pub type alias AudioEntry = { name = String, path = String, looping = Bool }

    /// サウンドの論理名 → OpenAL ソース ID
    pub type alias AudioRegistry = Map[String, Int32]

    /// テクスチャ情報: GPU ハンドル ID + 元画像サイズ
    pub type alias TextureInfo = { id = Int32, width = Float64, height = Float64 }

    /// テクスチャの論理名 → TextureInfo
    pub type alias TextureRegistry = Map[String, TextureInfo]

    /// エンジン初期化に必要な設定
    /// maxDeltaTime: getDeltaTime が返す値の上限（秒）。初回フレームのウィンドウ初期化遅延や
    ///               フォーカス復帰時の巨大 dt による物理破綻（tunneling 等）を防ぐ。
    ///               クランプ無効化したい場合は Float64.maxValue() を渡す。
    pub type alias EngineConfig = {
        screenWidth = Int32,
        screenHeight = Int32,
        title = String,
        textureManifest = List[TextureEntry],
        fontManifest = List[FontEntry],
        soundManifest = List[AudioEntry],
        clearColor = Color,
        maxDeltaTime = Float64
    }

    /// 描画用データ: render ハンドラに渡す
    pub type alias Drawable = {
        texture = String,
        position = Vec2.Vec2,
        scale = Vec2.Vec2,
        rotation = Float64,
        color = Color,
        alpha = Float32,
        centered = Bool,
        uvOffset = Vec2.Vec2,
        uvScale = Vec2.Vec2,
        zIndex = Int32
    }

    /// ノードを Drawable のリストに変換する能力を表す trait
    /// Label2D 等、1 ノードから複数 Drawable を生成するケースに対応
    pub trait Renderable[n] {
        pub def toDrawables(node: n, globalPos: Vec2.Vec2): List[Drawable]
    }

    /// キーボードキー
    pub enum Key with Eq, Order, ToString {
        case W
        case A
        case S
        case D
        case Z
        case Up
        case Down
        case Left
        case Right
        case Enter
        case Space
        case Escape
        case F1
        case LeftShift
        case LeftCtrl
        case LeftSuper
    }

    /// Key の全バリアント。InputEvent などのイベント駆動入力で
    /// 走査対象として使う。新しい Key を追加した際はここにも追加する。
    pub def allKeys(): List[Key] =
        Key.W :: Key.A :: Key.S :: Key.D :: Key.Z ::
        Key.Up :: Key.Down :: Key.Left :: Key.Right ::
        Key.Enter :: Key.Space :: Key.Escape :: Key.F1 ::
        Key.LeftShift :: Key.LeftCtrl :: Key.LeftSuper :: Nil

    /// マウスボタン
    pub enum MouseButton with Eq, Order, ToString {
        case Left
        case Right
        case Middle
    }

    /// MouseButton の全バリアント。InputEvent でマウス押下/離脱の
    /// 走査対象として使う。
    pub def allMouseButtons(): List[MouseButton] =
        MouseButton.Left :: MouseButton.Right :: MouseButton.Middle :: Nil

    /// マウスカーソル形状（エディタのリサイズハンドルなどで切り替える）。
    /// GLFW 3.3.4 が提供する 6 種のうち、エディタで意味があるものだけ列挙する
    pub enum Cursor with Eq, ToString {
        /// 通常の矢印カーソル（エディタ非操作中・ハンドル外）
        case Default
        /// 横方向の伸縮カーソル ←→（左右辺ハンドル）
        case HResize
        /// 縦方向の伸縮カーソル ↕（上下辺ハンドル）
        case VResize
        /// 全方向の伸縮カーソル（4 隅ハンドル — GLFW 3.3.4 に diagonal がないため
        /// 十字カーソルで代用する）
        case AllResize
    }

    /// ゲームエフェクト: 描画・ウィンドウ制御・時間取得・キー入力・マウス入力・フォント・
    /// ビューポート・マウスカーソル形状切り替え
    pub eff Game {
        def render(drawables: List[Drawable]): Unit
        def shouldClose(): Bool
        /// 前フレームからの経過時間（秒）。EngineConfig#maxDeltaTime で上限クランプ済み
        def getDeltaTime(): Float64
        def isKeyPressed(key: Key): Bool
        def getMousePosition(): Vec2.Vec2
        def isMouseButtonPressed(button: MouseButton): Bool
        def getFontAtlas(name: String): FontAtlas
        def getViewportRect(): Rect2.Rect2
        /// 指定したテクスチャ名の元画像サイズ等を取得する。
        /// 登録されていないテクスチャ名なら None
        def getTextureInfo(name: String): Option[TextureInfo]
        /// マウスカーソル形状を切り替える。連続して同じ Cursor を渡しても問題ない（冪等）
        def setCursor(cursor: Cursor): Unit
    }

    /// オーディオエフェクト: サウンドの再生・停止
    pub eff Audio {
        /// 指定した名前のサウンドを先頭から再生する
        def playAudio(name: String): Unit
        /// 指定した名前のサウンドを停止する
        def stopAudio(name: String): Unit
    }

    // ========================================================================
    // パイプライン — >> で合成してフレーム更新を組み立てる
    // ========================================================================
    //
    //   let updateScene =
    //       GameEngine.process(delta = dt, paused = false)
    //       >> GameEngine.physicsProcess(delta = dt, paused = false, gravity = gravity)
    //       >> GameEngine.handleCollisions
    //       >> GameEngine.handleScreenTransitions(screenWidth = 480, screenHeight = 720);
    //   GameEngine.render(updateScene(scene));

    /// 全ノードの毎フレーム処理を実行する
    pub def process(delta: {delta = Float64}, paused: {paused = Bool},
                    scene: Scene[s]): Scene[s] \ Node.Aef[s]
            with Node[s] =
        Scene.processAll(delta#delta, paused#paused, scene)

    /// 物理演算（重力・ダンピング・速度積分）を適用する
    pub def physicsProcess(delta: {delta = Float64}, paused: {paused = Bool},
                    gravity: {gravity = Vec2.Vec2},
                    scene: Scene[s]): Scene[s] \ Node.Aef[s]
            with Node[s] =
        PhysicsStep.step(delta#delta, paused#paused, gravity#gravity, scene)

    /// 衝突フェーズ: Area2D 重なり検出 → AreaHandler 発火 → RigidBody2D ↔ StaticBody2D 押し戻し
    /// 押し戻しは検出の後に行う（順序を逆にすると境界ピッタリで Area2D 重なりが外れる）
    pub def handleCollisions(scene: Scene[s]): Scene[s] \ AreaEvent.AreaHandler.Aef[s]
            with AreaEvent.AreaHandler[s] =
        AreaEvent.handleOverlaps(scene) |> PhysicsStep.resolveStaticCollisions

    /// 画面内外の遷移を検出し ScreenNotifyHandler で通知する
    pub def handleScreenTransitions(screenWidth: {screenWidth = Int32},
                      screenHeight: {screenHeight = Int32},
                      scene: Scene[s]): Scene[s]
            with ScreenNotifyEvent.ScreenNotifyHandler[s] =
        ScreenNotifyEvent.handleScreenTransitions(screenWidth, screenHeight, scene)

    /// タイマータイムアウトを検出し TimerHandler で応答する
    pub def handleTimers(scene: Scene[s]): Scene[s] \ Math.Random
            with TimerEvent.TimerHandler[s] =
        TimerEvent.handleTimeouts(scene)

    /// ボタンプレスを検出し ButtonHandler で応答する
    pub def handleButtons(scene: Scene[s]): Scene[s] \ {Game, ButtonEvent.ButtonHandler.Aef[s]}
            with ButtonEvent.ButtonHandler[s] =
        ButtonEvent.handleButtons(scene)

    /// キー入力の差分を検出し InputHandler で応答する
    /// 前フレームとのキー状態差分から押下/離脱イベントを合成する
    pub def handleInput(scene: Scene[s]): Scene[s] \ {Game, InputEvent.InputHandler.Aef[s]}
            with InputEvent.InputHandler[s] =
        InputEvent.handleInput(scene)

    /// シーンを描画する
    /// アクティブな Camera2D があれば、ビューポートオフセットを計算して描画に適用する
    /// CanvasLayer 配下のノード（HUD 等）にはカメラオフセットを適用しない
    pub def render(scene: Scene[s]): Unit \ Game =
        let cameraOffset = match Scene.findActiveCamera(scene) {
            case Some(cam) =>
                let vp = Game.getViewportRect();
                Camera2D.getViewportOffset(cam, {viewportWidth = vp#size#x, viewportHeight = vp#size#y})
            case None => Vec2.zero()
        };
        Scene.toDrawables(cameraOffset, scene) |> Game.render

    // ========================================================================
    // プラットフォーム
    // ========================================================================

    /// macOS では -XstartOnFirstThread 付きでプロセスを再起動する。
    /// 再起動した場合 true を返す（呼び出し元は終了すべき）。
    pub def ensureMainThread(): Bool \ IO =
        let osName = System.getProperty("os.name");
        if (Object.isNull(osName) or not String.contains({substr = "Mac"}, osName))
            false
        else if (not Object.isNull(System.getProperty("game.relaunched")))
            false
        else {
            println("Relaunching with -XstartOnFirstThread...");
            let javaHome = System.getProperty("java.home");
            let javaBin = "${javaHome}/bin/java";
            let args = new ArrayList();
            discard args.add(javaBin);
            discard args.add("-XstartOnFirstThread");
            discard args.add("-Dgame.relaunched=true");
            let projectPath = System.getProperty("projectPath");
            if (not Object.isNull(projectPath))
                discard args.add("-DprojectPath=${projectPath}")
            else ();
            discard args.add("-jar");
            discard args.add("bin/flix.jar");
            discard args.add("run");
            let pb = new ProcessBuilder(args);
            discard pb.inheritIO();
            let proc = pb.start();
            let code = proc.waitFor();
            System.exit(code);
            true
        }
}
