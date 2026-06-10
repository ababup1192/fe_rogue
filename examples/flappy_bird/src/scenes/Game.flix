// Game — Flappy Bird のノードタグ定義・trait instance・シーン構築・ゲームループ

// ========================================================================
// ゲームフェーズ
// ========================================================================

/// ゲーム全体の進行状態
/// Menu:     メニュー画面
/// Playing:  プレイ中
/// GameOver: ゲームオーバー
pub enum GamePhase with Eq, ToString {
    case Menu
    case Playing
    case GameOver
}

/// ゲームフェーズの読み書きエフェクト（真値）
/// `get` : 現在のフェーズを取得
/// `put` : フェーズを変更（同一フレーム内に複数回呼ばれた場合は最後勝ち）
/// 「フェーズ変化に応じた scene 構築」は gameLoop が前フレームとの比較で実行する
pub eff GamePhaseState {
    def get(): GamePhase
    def put(target: GamePhase): Unit
}

/// 自殺したノードのリサイクル要求エフェクト
/// NodeRemovedHandler は scene を渡して新しい scene を受け取る。
/// ハンドラ側で Math.Random + spawn 関数を実行することで、
/// Node[NodeTag] / NodeRemovedHandler[NodeTag] の Aef から
/// Math.Random 直接依存を取り除いている。
pub eff Recycle {
    def ground(scene: Scene[NodeTag]): Scene[NodeTag]
    def pipe(scene: Scene[NodeTag]): Scene[NodeTag]
}

// ========================================================================
// ノードタグ
// ========================================================================

/// スコア値の型エイリアス
pub type alias Score = Int32

/// ベストスコア値の型エイリアス
pub type alias BestScore = Int32

/// ゲームオーバーアニメーションの経過時間
pub type alias GameOverAnimData = {elapsed = Float64}

/// 各ノードに付与する識別タグ（Scene[NodeTag] の型パラメータ）
pub enum NodeTag {
    /// 鳥の RigidBody2D に付与。BirdData を保持する
    case Bird(BirdScene.BirdData)
    /// 鳥の衝突検知用 Area2D に付与
    case BirdArea
    /// 地面の StaticBody2D に付与
    case Ground
    /// パイプペアの親ノード（Marker2D）に付与。process で画面外自殺判定を行う
    case Pipe
    /// パイプペアの子（Top/Bottom の StaticBody2D）に付与。AreaHandler で衝突判定に使う
    case PipePart
    /// パイプ間の採点用 Area2D に付与
    case Coin
    /// スコアラベルに付与。現在のスコア値を保持する
    case ScoreLabel(Score)
    /// ベストスコアラベルに付与。セッション中のベストスコアを保持する
    case BestScoreLabel(BestScore)
    /// カメラの追従対象とシェイク状態を保持する
    case Camera(CameraScene.CameraData)
    /// ゲームオーバーアニメーション状態を保持する
    case GameOverAnim(GameOverAnimData)
    /// タグ不要なノード（スプライト子ノード、ボタン等）
    /// ボタンの識別は ButtonHandler 側で path 比較によって行う
    case NoTag
}

// ========================================================================
// Node 実装
// ========================================================================

instance Node[NodeTag] {
    type Aef = { Recycle }
    type ProcessAef = { Recycle }
    // Bird: bird.gd `FlappingState._init → flap()` 相当の初期 flap を発火
    redef ready(node: EngineNode[NodeTag], path: NodePath,
                scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) \ Recycle =
        match node {
            case EngineNode.RigidBody2DWithState(_, NodeTag.Bird(_)) =>
                checked_ecast(BirdScene.ready(node, path, scene))
            case _ => (node, scene)
        }

    // 各シーンへ委譲するだけのディスパッチ
    // Bird は bird.gd に倣い _process を使わない（physicsProcess のみ）
    redef process(delta: Duration.Duration, node: EngineNode[NodeTag],
                  path: NodePath, scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) \ Recycle =
        match node {
            case EngineNode.Camera2DWithState(_, NodeTag.Camera(_)) =>
                checked_ecast(CameraScene.process(delta, node, scene))
            case EngineNode.CanvasLayerWithState(_, NodeTag.GameOverAnim(_)) =>
                checked_ecast(GameOverScene.process(delta, node, scene))
            case EngineNode.StaticBody2DWithState(_, NodeTag.Ground) =>
                GroundScene.process(node, path, scene)
            case EngineNode.Marker2DWithState(_, NodeTag.Pipe) =>
                PipeScene.process(node, path, scene)
            case _ => (node, scene)
        }

    // Bird: 回転 -30° クランプ + 落下時 angVel = 1.5（bird.gd FlappingState.update 準拠）
    redef physicsProcess(delta: Duration.Duration, node: EngineNode[NodeTag],
                         path: NodePath, scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) \ Recycle =
        match node {
            case EngineNode.RigidBody2DWithState(_, NodeTag.Bird(_)) =>
                checked_ecast(BirdScene.physicsProcess(delta, node, path, scene))
            case _ => (node, scene)
        }
}

// ========================================================================
// InputHandler 実装（bird.gd _input 相当を BirdScene にディスパッチ）
// Menu / GameOver(アニメ完了後) のスペースキー押下は Play ボタンと等価扱い
// ========================================================================

instance InputEvent.InputHandler[NodeTag] {
    type Aef = { GameEngine.Audio, GamePhaseState }
    redef onKeyPressed(key: GameEngine.Key,
                       scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Audio, GamePhaseState} =
        if (key == GameEngine.Key.Space and Game.canStart(scene)) {
            GamePhaseState.put(GamePhase.Playing); scene
        } else
            BirdScene.input(BirdInputEvent.KeyPressed(key), scene)

    redef onMouseButtonPressed(button: GameEngine.MouseButton,
                               _position: Vec2.Vec2,
                               scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Audio, GamePhaseState} =
        checked_ecast(BirdScene.input(BirdInputEvent.MouseButtonPressed(button), scene))
}

// ========================================================================
// ButtonHandler 実装（Godot TextureButton.pressed シグナル相当）
// godot btn_play.gd と同じく、押下時に GamePhaseState.put(Playing) を発火する
// ========================================================================

instance ButtonEvent.ButtonHandler[NodeTag] {
    type Aef = { GamePhaseState }
    redef onButtonPressed(buttonPath: NodePath, _state: NodeTag,
                          scene: Scene[NodeTag]): Scene[NodeTag] \ GamePhaseState =
        let isPlayPath = buttonPath == MenuScene.playButtonPath()
                         or buttonPath == GameOverScene.playButtonPath();
        if (isPlayPath and Game.canStart(scene)) {
            GamePhaseState.put(GamePhase.Playing); scene
        } else scene
}

// ========================================================================
// AreaHandler 実装（Area2D の重なり通知）
// 鳥 ↔ 地面 / パイプ / コイン の交差を各シーンの応答処理にディスパッチする
// ========================================================================

instance AreaEvent.AreaHandler[NodeTag] {
    type Aef = { GameEngine.Audio, BirdStateChanged }
    pub def onAreaEntered(selfPath: NodePath, selfState: NodeTag,
                          otherPath: NodePath, otherState: NodeTag,
                          scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Audio, BirdStateChanged} =
        match (selfState, otherState) {
            case (NodeTag.BirdArea, NodeTag.Ground) =>
                BirdScene.onBirdHitGround(scene)
            case (NodeTag.Ground, NodeTag.BirdArea) =>
                BirdScene.onBirdHitGround(scene)
            case (NodeTag.BirdArea, NodeTag.PipePart) =>
                BirdScene.onBirdHitPipe(pipePath = otherPath, scene)
            case (NodeTag.PipePart, NodeTag.BirdArea) =>
                BirdScene.onBirdHitPipe(pipePath = selfPath, scene)
            case (NodeTag.BirdArea, NodeTag.Coin) =>
                ScoreScene.onBirdPassedCoin(coinPath = otherPath, scene)
            case (NodeTag.Coin, NodeTag.BirdArea) =>
                ScoreScene.onBirdPassedCoin(coinPath = selfPath, scene)
            case _ => checked_ecast(scene)
        }
}

// ========================================================================
// NodeRemovedHandler 実装（godot tree_exited シグナル相当）
// 自殺した Ground / Pipe ペアの Coin を受けて、新しい個体を spawn する
// ========================================================================

instance NodeRemovedHandler[NodeTag] {
    type Aef = { Recycle }
    redef onNodeRemoved(_path: NodePath, state: NodeTag,
                        scene: Scene[NodeTag]): Scene[NodeTag] \ Recycle =
        match state {
            case NodeTag.Ground => Recycle.ground(scene)
            case NodeTag.Pipe => Recycle.pipe(scene)
            case _ => scene
        }
}

// ========================================================================
// mod Game
// ========================================================================

mod Game {

    /// scene.json の `tag` 文字列を NodeTag に変換する。
    /// 各シーンの `"tag": "Ground"` 等を受けて型付きの NodeTag を返す。
    /// `Bird(...)` `Camera(...)` `ScoreLabel(...)` のようなデータ付きタグは
    /// JSON 側ではタグを書かず、ロード後に `Scene.setState` で注入する方針なので
    /// ここでは扱わない（None もしくは未知タグ → NoTag フォールバック）。
    pub def parseNodeTag(opt: Option[String]): Result[Util.Json.JsonError, NodeTag] =
        match opt {
            case None => Ok(NodeTag.NoTag)
            case Some(s) => match s {
                case "BirdArea" => Ok(NodeTag.BirdArea)
                case "Ground"   => Ok(NodeTag.Ground)
                case "Pipe"     => Ok(NodeTag.Pipe)
                case "PipePart" => Ok(NodeTag.PipePart)
                case "Coin"     => Ok(NodeTag.Coin)
                case "NoTag"    => Ok(NodeTag.NoTag)
                case _          => Ok(NodeTag.NoTag)
            }
        }

    // ========================================================================
    // 画面定数
    // ========================================================================

    /// デザイン解像度の幅（参考実装 144 の 2 倍）。ゲーム内の論理座標基準
    pub def designWi(): Int32 = 288

    /// デザイン解像度の高さ（参考実装 256 の 2 倍）
    pub def designHi(): Int32 = 512

    /// OS ウィンドウの幅（design の 2 倍。canvas_items 風スケーリング）
    pub def windowWi(): Int32 = 576

    /// OS ウィンドウの高さ
    pub def windowHi(): Int32 = 1024

    // ========================================================================
    // 背景定数
    // ========================================================================

    /// 背景レイヤーノード名
    def backgroundName(): String = "background"

    /// 背景スプライト子ノード名
    def bgSpriteName(): String = "bg_sprite"

    // ========================================================================
    // 開始入力受付判定
    // ========================================================================

    /// ゲーム開始入力を受け付けるか判定する
    /// Menu: 常に true / Playing: false / GameOver: アニメ完了後のみ true
    pub def canStart(scene: Scene[NodeTag]): Bool \ GamePhaseState =
        match GamePhaseState.get() {
            case GamePhase.Menu     => true
            case GamePhase.Playing  => false
            case GamePhase.GameOver => GameOverScene.isAnimationFinished(scene)
        }

    // ========================================================================
    // 初期状態構築
    // ========================================================================

    /// プレイ中のシーンを構築する（GamePhase.Playing 用）
    /// bestScore: セッション中のベストスコア（初回は 0）
    /// GroundScene.addGrounds が JSON ファイル読み込みを行うため Fs.FileRead を伴う
    pub def buildPlayingScene(fontAtlas: FontAtlas, bestScore: BestScore): Scene[NodeTag] \ {Math.Random, Fs.FileRead, GameEngine.Game} =
        Scene.empty()
            |> addBackground
            |> BirdScene.addBird
            |> CameraScene.addCamera(BirdScene.name())
            |> ScoreScene.addHud(fontAtlas, bestScore)
            |> GroundScene.addGrounds
            |> PipeScene.addPipes

    /// メニュー画面のシーンを構築する（GamePhase.Menu 用）
    /// 背景 + 鳥(Flying) + カメラ + HUD(スコア非表示) + 地面 + メニュー UI
    /// MenuScene.addMenuUI が JSON ファイル読み込みを行うため Fs.FileRead を伴う
    pub def buildMenuScene(fontAtlas: FontAtlas, bestScore: BestScore): Scene[NodeTag] \ {Fs.FileRead, GameEngine.Game} =
        Scene.empty()
            |> addBackground
            |> BirdScene.addBirdForMenu
            |> CameraScene.addCamera(BirdScene.name())
            |> ScoreScene.addHud(fontAtlas, bestScore)
            |> GroundScene.addGrounds
            |> MenuScene.addMenuUI
            |> ScoreScene.hideScoreLabel

    // ========================================================================
    // シーン構築ヘルパー
    // ========================================================================

    /// 背景を追加する（CanvasLayer layer=-1 + Sprite2D）
    def addBackground(scene: Scene[NodeTag]): Scene[NodeTag] =
        let layer = CanvasLayer.make(-1);
        let sprite = Sprite2D.make("background_day", {x = 144.0, y = 256.0}, {x = 2.0, y = 2.0});
        scene
            |> Scene.addNode(backgroundName(),
                EngineNode.CanvasLayerWithState(layer, NodeTag.NoTag))
            |> Scene.addChild(backgroundName(), bgSpriteName(),
                EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag))

    /// ビューポートの左端 X 座標を取得する
    pub def getViewportLeftX(scene: Scene[NodeTag]): Float64 =
        let birdPos = Scene.globalPosition(BirdScene.name(), scene);
        birdPos#x + CameraScene.offsetX()

    // ========================================================================
    // メインループ
    // ========================================================================

    /// ゲームのエントリポイント
    /// GamePhase は region 内の Ref 1 個で保持。handler 群が `GamePhaseState.put` で書き換え、
    /// gameLoop が前フレームとの差分を検出して scene を組み立てる。
    /// Recycle ハンドラはノード自殺時のリサイクル要求を Math.Random + spawn 関数で
    /// 実体化する責務を担う（NodeRemovedHandler から Math.Random を切り離すため）。
    pub def start(fontAtlas: FontAtlas):
                  Unit \ {GameEngine.Game, GameEngine.Audio, Math.Random, Fs.FileRead,
                          IO} =
        region rc {
            let phaseRef: Ref[GamePhase, rc] = Ref.fresh(rc, GamePhase.Menu);
            run {
                gameLoop(fontAtlas, GamePhase.Menu, buildMenuScene(fontAtlas, 0))
            } with handler BirdStateChanged {
                def emit(newState, scene, k) = {
                    let nextScene = match newState {
                        case BirdState.Hit =>
                            CameraScene.triggerShake(CameraScene.shakeIntensity(),
                                                     CameraScene.shakeDuration(), scene)
                        case BirdState.Grounded =>
                            GamePhaseState.put(GamePhase.GameOver);
                            CameraScene.triggerShake(CameraScene.shakeIntensity(),
                                                     CameraScene.shakeDuration(), scene)
                        case _ => scene
                    };
                    k(nextScene)
                }
            } with handler GamePhaseState {
                def get(k) = k(Ref.get(phaseRef))
                def put(target, k) = { Ref.put(target, phaseRef); k() }
            } with handler Recycle {
                def ground(scene, k) = k(GroundScene.spawnRecycledGround(scene))
                def pipe(scene, k) =
                    k(PipeScene.spawnRecycledPair(ScoreScene.getScore(scene), scene))
            }
        }

    /// フェーズ変化時に呼ばれる。新しい phase に応じて scene を組み立てる。
    ///   - Playing  : フルリビルド + swoosh SE
    ///   - Menu     : フルリビルド
    ///   - GameOver : 既存 scene に GameOver オーバーレイを追加
    def applyPhaseChange(phase: GamePhase, fontAtlas: FontAtlas,
                         scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Audio, GameEngine.Game, Math.Random, Fs.FileRead} =
        match phase {
            case GamePhase.Playing =>
                GameEngine.Audio.playAudio("sfx_swooshing");
                buildPlayingScene(fontAtlas, ScoreScene.getBestScore(scene))
            case GamePhase.Menu =>
                buildMenuScene(fontAtlas, ScoreScene.getBestScore(scene))
            case GamePhase.GameOver =>
                GameOverScene.enterGameOver(fontAtlas, scene)
        }

    /// メインループ: shouldClose 判定 → engineUpdate → phase 差分検出 → render
    /// previousPhase: 前フレーム末の phase（変化検出のため引き連れる）
    def gameLoop(fontAtlas: FontAtlas, previousPhase: GamePhase,
                 scene: Scene[NodeTag]):
                 Unit \ {GameEngine.Game, GameEngine.Audio, Math.Random, Fs.FileRead,
                         BirdStateChanged, GamePhaseState, Recycle} =
        if (GameEngine.Game.shouldClose() or
            GameEngine.Game.isKeyPressed(GameEngine.Key.Escape)) ()
        else {
            let dt = GameEngine.Game.getDeltaTime();
            let updatedScene = scene
                |> GameEngine.process(delta = dt, paused = false)
                |> GameEngine.physicsProcess(delta = dt, paused = false,
                                             gravity = PhysicsStep.defaultGravity())
                |> GameEngine.handleInput
                |> GameEngine.handleButtons
                |> GameEngine.handleCollisions;
            let currentPhase = GamePhaseState.get();
            let nextScene = if (currentPhase != previousPhase)
                                applyPhaseChange(currentPhase, fontAtlas, updatedScene)
                            else updatedScene;
            GameEngine.render(nextScene);
            gameLoop(fontAtlas, currentPhase, nextScene)
        }
}
