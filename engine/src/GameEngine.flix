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
    ///
    /// designWidth / designHeight:
    ///   ゲーム側の論理解像度（カメラのビューポート / 投影行列の基準）。
    ///   ピクセルアートゲームでは小さく固定し、ウィンドウサイズに引き伸ばす運用が定番。
    /// windowWidth / windowHeight:
    ///   起動時の OS ウィンドウサイズ（ピクセル）。design とは独立して指定でき、
    ///   `Stretch Mode = canvas_items` 風に design 側がウィンドウいっぱいに描画される。
    ///   project.json に任意キー `windowScale`(>0) があると、ProjectLoader が
    ///   window = design × scale を計算してこの値を上書きする（アスペクト維持で拡大）。
    /// maxDeltaTime:
    ///   getDeltaTime が返す値の上限（秒）。初回フレームのウィンドウ初期化遅延や
    ///   フォーカス復帰時の巨大 dt による物理破綻（tunneling 等）を防ぐ。
    ///   クランプ無効化したい場合は Float64.maxValue() を渡す。
    pub type alias EngineConfig = {
        designWidth = Int32,
        designHeight = Int32,
        windowWidth = Int32,
        windowHeight = Int32,
        title = String,
        textureManifest = List[TextureEntry],
        fontManifest = List[FontEntry],
        soundManifest = List[AudioEntry],
        clearColor = Color,
        maxDeltaTime = Float64
    }

    /// 角丸＋枠線スタイル (Godot StyleBoxFlat 相当)。`Drawable.style = Some(..)` ＆ texture="" のとき
    /// 単色矩形を「塗り＋枠＋角丸＋AA」で 1 フラグメント描画する。render_core の `RenderType.BoxStyle` と一致。
    ///
    /// stripe* は塗り領域に重ねる 45° 斜線ハッチ（CSS の repeating-linear-gradient 相当）。
    /// `stripeWidth <= 0` または `stripeAlpha <= 0` でハッチ無効＝従来の塗りのみ。
    /// stripePeriod は縞の周期 px、stripeWidth は縞 1 本の幅 px（どちらもデザイン解像度 px）。
    pub type alias BoxStyle = {
        cornerRadius = Float64,
        borderWidth  = Float64,
        borderColor  = Color,
        borderAlpha  = Float32,
        stripeColor  = Color,
        stripeAlpha  = Float32,
        stripeWidth  = Float64,
        stripePeriod = Float64
    }

    /// 描画用データ: renderCommands ハンドラに渡す
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
        zIndex = Int32,
        style = Option[BoxStyle]
    }

    /// TileMapLayer のインスタンス描画コマンド（1 draw call）。
    /// `tileScale` はカメラの zoom を反映するスクリーン倍率で、シェーダ側で
    /// (instPos + vertex * tileSize) に乗算する。zoom 未指定時は (1, 1)
    pub type alias TileMapRenderCmd = {
        textureName = String,
        tileSize    = Float64,
        position    = Vec2.Vec2,
        tileScale   = Vec2.Vec2,
        color       = Color,
        zIndex      = Int32,
        tileVaoId   = Int32,
        tileCount   = Int32
    }

    /// Polygon2D の塗り潰し描画コマンド。vertices は変換済みのスクリーン px 凸多角形頂点列。
    /// render_core の RenderType.PolygonCmd と構造一致（そのまま渡せる）。
    pub type alias PolygonRenderCmd = {
        vertices = List[Vec2.Vec2],
        color    = Color,
        alpha    = Float32,
        zIndex   = Int32
    }

    /// GPU インスタンスバッファ 1 タイル分のデータ
    /// tilemap loader (fe_rogue 側 `TileRendering.buildTileInstances` 等) が生成し、
    /// `initTileBuffer` で GPU にアップロードする。
    pub type alias TileInstance = {
        px    = Vec2.Vec2,
        uvOff = Vec2.Vec2,
        uvSc  = Vec2.Vec2,
        alpha = Float32
    }

    /// ノードを Drawable のリストに変換する能力を表す trait
    /// Label2D 等、1 ノードから複数 Drawable を生成するケースに対応。
    /// Sprite2D の region/hframes/vframes/frame から UV を計算するためにテクスチャ
    /// サイズを参照する必要があり、Game eff を要求する。
    pub trait Renderable[n] {
        pub def toDrawables(node: n, globalPos: Vec2.Vec2): List[Drawable] \ Game
    }

    /// キーボードキー
    pub enum Key with Eq, Order, ToString {
        case W
        case A
        case S
        case D
        case Z
        case X
        case C
        case M
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
        Key.W :: Key.A :: Key.S :: Key.D :: Key.Z :: Key.X :: Key.C :: Key.M ::
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
    /// LWJGL 3.3.4 同梱の GLFW 3.4 で利用可能な shape をエディタ用に列挙。
    /// 4 隅は OS ネイティブの方向別カーソル (NW/NE/SW/SE) を個別に持ち、AWT 側で
    /// 単方向矢印が「逆向き」に見える問題を避ける。GLFW には対角単位の双方向矢印
    /// しか無いので、NW+SE / NE+SW でエイリアスされる。
    pub enum Cursor with Eq, ToString {
        /// 通常の矢印カーソル（エディタ非操作中・ハンドル外）
        case Default
        /// 横方向の伸縮カーソル ←→（左右辺ハンドル）
        case HResize
        /// 縦方向の伸縮カーソル ↕（上下辺ハンドル）
        case VResize
        /// 全方向の伸縮カーソル（CanvasLayer 全体の操作）
        case AllResize
        /// 回転操作中・回転ノブにホバー中のカーソル（Hand）。
        /// 「ここを掴める」という視覚フィードバック
        case Rotate
        /// 北西方向のリサイズ (TopLeft 隅 ↖)
        case NWResize
        /// 北東方向のリサイズ (TopRight 隅 ↗)
        case NEResize
        /// 南西方向のリサイズ (BottomLeft 隅 ↙)
        case SWResize
        /// 南東方向のリサイズ (BottomRight 隅 ↘)
        case SEResize
    }

    /// ゲームエフェクト: 描画・ウィンドウ制御・時間取得・キー入力・マウス入力・フォント・
    /// ビューポート・マウスカーソル形状切り替え
    pub eff Game {
        /// zIndex 混合で sprites と tileMaps を 1 フレーム描画し、最後に polygons を塗る
        def renderCommands(sprites: List[Drawable], tileMaps: List[TileMapRenderCmd],
                           polygons: List[PolygonRenderCmd]): Unit
        /// タイルインスタンスデータを GPU VBO にアップロードし (vaoId, count) を返す
        def initTileBuffer(instances: List[TileInstance]): (Int32, Int32)
        def shouldClose(): Bool
        /// 前フレームからの経過時間。EngineConfig#maxDeltaTime で上限クランプ済み
        def getDeltaTime(): Duration.Duration
        def isKeyPressed(key: Key): Bool
        def getMousePosition(): Vec2.Vec2
        def isMouseButtonPressed(button: MouseButton): Bool
        /// 前回呼び出し以降に蓄積されたマウスホイールの y 方向 delta を返し、
        /// 内部アキュムレータを 0 にリセットする。1 ティックぶんの値が +1.0 / -1.0 程度
        /// （プラットフォーム依存）。スクロールアップで正、ダウンで負。
        def consumeScrollDelta(): Float64
        def getFontAtlas(name: String): FontAtlas
        def getViewportRect(): Rect2.Rect2
        /// 指定したテクスチャ名の元画像サイズ等を取得する。
        /// 登録されていないテクスチャ名なら None
        def getTextureInfo(name: String): Option[TextureInfo]
        /// マウスカーソル形状を切り替える。連続して同じ Cursor を渡しても問題ない（冪等）
        def setCursor(cursor: Cursor): Unit
    }

    /// オーディオエフェクト: サウンドの再生・停止・音量・ループ
    pub eff Audio {
        /// 指定した名前のサウンドを先頭から再生する
        def playAudio(name: String): Unit
        /// 指定した名前のサウンドを停止する
        def stopAudio(name: String): Unit
        /// 指定した名前のサウンドの音量（gain）を 0.0〜1.0 で設定する
        def setVolume(name: String, volume: Float32): Unit
        /// 指定した名前のサウンドの AL_LOOPING を実行時に切り替える。
        /// 起動時の `soundManifest#looping` 初期値を上書きする (再生中の音にも反映)
        def setLooping(name: String, loop: Bool): Unit
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
    /// Aef は `ready` 用 `Aef[s]` と `process` 用 `ProcessAef[s]` の和。
    pub def process(delta: {delta = Duration.Duration}, paused: {paused = Bool},
                    scene: Scene[s]): Scene[s] \ Node.Aef[s] + Node.ProcessAef[s]
            with Node[s] =
        Scene.processAll(delta#delta, paused#paused, scene)

    /// 物理演算（重力・ダンピング・速度積分）を適用する
    pub def physicsProcess(delta: {delta = Duration.Duration}, paused: {paused = Bool},
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

    /// ItemList のキー入力差分を検出し MenuHandler で応答する。
    /// focused = true な ItemList が ↑↓/Enter/Escape を受けて、確定/キャンセル時に
    /// ハンドラを発火する。`handleInput` と `handleButtons` の間に挟む想定。
    pub def handleMenus(scene: Scene[s]): Scene[s] \ {Game, MenuEvent.MenuHandler.Aef[s]}
            with MenuEvent.MenuHandler[s] =
        MenuEvent.handleMenus(scene)

    /// キー入力の差分を検出し InputHandler で応答する
    /// 前フレームとのキー状態差分から押下/離脱イベントを合成する
    pub def handleInput(scene: Scene[s]): Scene[s] \ {Game, InputEvent.InputHandler.Aef[s]}
            with InputEvent.InputHandler[s] =
        InputEvent.handleInput(scene)

    /// シーンを描画する
    /// アクティブな Camera2D があれば、ビューポートオフセットを計算して描画に適用する
    /// CanvasLayer 配下のノード（HUD 等）にはカメラオフセットを適用しない
    /// TileMapLayer はインスタンシング経由で描画する（1 draw call）
    pub def render(scene: Scene[s]): Unit \ Game =
        let transform = match Scene.findActiveCamera(scene) {
            case Some((cam, globalPos)) =>
                let vp = Game.getViewportRect();
                Camera2D.getViewTransform(cam, globalPos,
                    {viewportWidth = vp#size#x, viewportHeight = vp#size#y})
            case None => Camera2D.identityTransform()
        };
        let sprites = Scene.toDrawables(transform, scene);
        let tileMaps: List[TileMapRenderCmd] =
            List.filterMap(p -> match Scene.getEngineNode(p, scene) {
                case Some(EngineNode.TileMapLayerWithState(tm, _)) =>
                    let layerScreenPos =
                        Camera2D.applyToWorldPos(transform, Scene.globalPositionAt(p, scene));
                    Some(TileMapLayer.toRenderCmd(layerScreenPos, transform#scale, tm))
                case _ => None
            }, Scene.preorderPaths(scene));
        // Polygon2D / Arc2D ノードを収集（CanvasLayer 配下はカメラ非適用、zoom はワールドのみ）。
        // 不可視（自ノード or 祖先）はスキップ。Arc2D（リング）は中空円のためセグメントごとに複数の
        // PolygonRenderCmd を返すので flatMap で平坦化する。
        // 描画原点 screenPos と zoom はポリゴン系ノードに限って計算する（全ノードでは走らせない）。
        let placement = p ->
            ( Scene.screenPositionAt(p, transform, scene)
            , if (Scene.isUnderCanvasLayer(p, scene)) ({x = 1.0, y = 1.0}: Vec2.Vec2)
              else transform#scale );
        // sprite 経路と同等にするため、各 cmd の color を祖先 modulate 乗算後の実効色に、
        // zIndex を CanvasLayer/祖先を加味した実効 z に上書きする（toRenderCmd は node 生の値を返すため）。
        // これで待機/行動済みの暗転がグリフに乗り、ポップアップ（高 z の CanvasLayer）が手前で覆う。
        let withEffective = (p, cmd) ->
            ({ color = Scene.effectiveModulateAt(p, scene), zIndex = Scene.effectiveZIndexAt(p, scene)
             | cmd }: PolygonRenderCmd);
        let polygons: List[PolygonRenderCmd] =
            List.flatMap(p -> match Scene.getEngineNode(p, scene) {
                case Some(EngineNode.Polygon2DWithState(poly, _)) =>
                    if (not (CanvasItem.isVisible(poly) and Scene.effectiveVisibleAt(p, scene))) Nil
                    else { let (sp, sc) = placement(p); withEffective(p, Polygon2D.toRenderCmd(sp, sc, poly)) :: Nil }
                case Some(EngineNode.Arc2DWithState(arc, _)) =>
                    if (not (CanvasItem.isVisible(arc) and Scene.effectiveVisibleAt(p, scene))) Nil
                    else { let (sp, sc) = placement(p); Arc2D.toRenderCmds(sp, sc, arc) |> List.map(c -> withEffective(p, c)) }
                case _ => Nil
            }, Scene.preorderPaths(scene));
        Game.renderCommands(sprites, tileMaps, polygons)

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
