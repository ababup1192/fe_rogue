// Game — Dodge the Creeps の NodeTag / trait instance / start / gameLoop / applyPhaseChange
//
// 並び順 (engine-guide):
//   1. GamePhase enum
//   2. カスタム effect (GamePhaseState)
//   3. type alias (MobId)
//   4. NodeTag enum
//   5. trait instance (Node / Input / Button / Area / ScreenNotify / Timer)
//   6. mod Game (定数 / シーン構築 / start / gameLoop / applyPhaseChange)
//
// 各 trait instance はディスパッチに徹し、ロジックは XxxScene の関数で行う。
// 一方でアセット読み込み (Fs.FileRead) は使用していない (シーンは programmatic に構築する)。

// ────────────────────────────────────────────────────────────────
// 1. GamePhase
// ────────────────────────────────────────────────────────────────

pub enum GamePhase with Eq, ToString {
    case Menu
    case Playing
    case GameOver
}

// ────────────────────────────────────────────────────────────────
// 2. カスタム effect
// ────────────────────────────────────────────────────────────────

/// ゲームフェーズの読み書き effect。
/// handler / Scene のロジックは `GamePhaseState.put(target)` で遷移要求するだけ。
/// 実体は Game.start の region 内 Ref に格納され、gameLoop が前フレームとの差分から
/// applyPhaseChange を起動する。
pub eff GamePhaseState {
    def get(): GamePhase
    def put(target: GamePhase): Unit
}

// ────────────────────────────────────────────────────────────────
// 3. 型 alias
// ────────────────────────────────────────────────────────────────

pub type alias MobId = Int32

// ────────────────────────────────────────────────────────────────
// 4. NodeTag
// ────────────────────────────────────────────────────────────────

pub enum NodeTag {
    /// プレイヤー本体 (AnimatedSprite2D)。状態を埋め込んで保持する
    case Player(PlayerScene.Data)
    /// プレイヤーの衝突検知 Area2D (子ノード)
    case PlayerArea
    /// モブ本体 (RigidBody2D)。状態を埋め込んで保持する
    case Mob(MobScene.Data)
    /// モブを連番でスポーンするタイマー (現在のカウンタ値を埋め込む)
    case MobTimer(MobId)
    /// 開始遅延タイマー (Playing 突入後の "Get Ready" 表示 → mob/score 開始)
    case StartTimer
    /// スコア更新タイマー (1 秒ごとに +1)
    case ScoreTimer
    /// GameOver → タイトル切替タイマー
    case MessageTimer
    /// タイトル → スタートボタン表示タイマー
    case TitleTimer
    /// スコアラベル。現在のスコア値を保持
    case ScoreLabel(HUDScene.Score)
    /// メッセージラベル ("Get Ready" / "Game Over" / "Dodge the Creeps")
    case MessageLabel
    /// スタートボタン
    case StartButton
    /// タグ不要なノード (背景・スプライト子・コリジョン形状など)
    case NoTag
}

// ────────────────────────────────────────────────────────────────
// 5. trait instance — dispatch only
// ────────────────────────────────────────────────────────────────

instance Node[NodeTag] {
    type Aef = { GameEngine.Game }
    type ProcessAef = { GameEngine.Game }

    redef ready(node: EngineNode[NodeTag], path: NodePath,
                scene: Scene[NodeTag]):
                (EngineNode[NodeTag], Scene[NodeTag]) \ GameEngine.Game =
        match EngineNode.getState(node) {
            case NodeTag.Player(_) =>
                checked_ecast(PlayerScene.ready(node, path, scene))
            case _ => (node, scene)
        }

    redef physicsProcess(delta: Duration.Duration, node: EngineNode[NodeTag],
                          path: NodePath, scene: Scene[NodeTag]):
                         (EngineNode[NodeTag], Scene[NodeTag]) \ GameEngine.Game =
        match EngineNode.getState(node) {
            case NodeTag.Player(_) =>
                PlayerScene.physicsProcess(delta, node, path, scene)
            case _ => (node, scene)
        }
}

instance InputEvent.InputHandler[NodeTag] {
    type Aef = { GamePhaseState }

    redef onKeyPressed(key: GameEngine.Key, scene: Scene[NodeTag]):
                       Scene[NodeTag] \ GamePhaseState =
        // Menu / GameOver で Enter / Space を押したら Playing に遷移
        if (key == GameEngine.Key.Enter or key == GameEngine.Key.Space) {
            if (Game.canStart(scene)) {
                GamePhaseState.put(GamePhase.Playing);
                scene
            } else scene
        } else scene
}

instance ButtonEvent.ButtonHandler[NodeTag] {
    type Aef = { GamePhaseState }

    redef onButtonPressed(buttonPath: NodePath, _state: NodeTag,
                           scene: Scene[NodeTag]): Scene[NodeTag] \ GamePhaseState =
        // StartButton (HUD 内) が押されたら Playing に遷移
        if (buttonPath == HUDScene.startButtonPath() and Game.canStart(scene)) {
            GamePhaseState.put(GamePhase.Playing);
            scene
        } else scene
}

instance AreaEvent.AreaHandler[NodeTag] {
    type Aef = { GameEngine.Audio, GamePhaseState }

    pub def onAreaEntered(_selfPath: NodePath, selfState: NodeTag,
                          _otherPath: NodePath, _otherState: NodeTag,
                          scene: Scene[NodeTag]):
                          Scene[NodeTag] \ {GameEngine.Audio, GamePhaseState} =
        // Mob 側は collisionMask=0 なので (Mob, PlayerArea) 方向の発火は
        // エンジンレベルで遮断され、ここに来ない。
        // PlayerArea 側だけが Mob を観測する（mask=Mob）。
        match selfState {
            case NodeTag.PlayerArea => PlayerScene.onHitMob(scene)
            case _ => checked_ecast(scene)
        }
}

instance ScreenNotifyEvent.ScreenNotifyHandler[NodeTag] {
    redef onScreenExited(path: NodePath, state: NodeTag,
                          scene: Scene[NodeTag]): Scene[NodeTag] =
        match state {
            case NodeTag.Mob(_) => MobScene.onScreenExit(path, scene)
            case _              => scene
        }
}

instance TimerEvent.TimerHandler[NodeTag] {
    redef onTimeout(timerPath: NodePath, state: NodeTag,
                     scene: Scene[NodeTag]): Scene[NodeTag] \ Math.Random =
        match state {
            case NodeTag.MobTimer(counter) =>
                // モブを 1 体スポーンしてカウンタをインクリメント
                let next = MobScene.spawnFromPath(counter, scene);
                Scene.setState(timerPath, NodeTag.MobTimer(counter + 1), next)
            case NodeTag.StartTimer =>
                // "Get Ready" を消し、Mob / Score タイマーを開始
                scene
                    |> HUDScene.hideMessage
                    |> Scene.mapEngineNode(Game.mobTimerPath(),
                        EngineNode.mapTimer(Timer.start))
                    |> Scene.mapEngineNode(Game.scoreTimerPath(),
                        EngineNode.mapTimer(Timer.start))
            case NodeTag.ScoreTimer =>
                HUDScene.incrementScore(scene)
            case NodeTag.MessageTimer =>
                // GameOver 後 2 秒経過: タイトル表示 + TitleTimer 開始
                scene
                    |> HUDScene.showMessage("Dodge the\nCreeps")
                    |> HUDScene.startTitleTimer
            case NodeTag.TitleTimer =>
                // タイトル表示後 1 秒経過: StartButton を出す
                HUDScene.showStartButton(scene)
            case _ => scene
        }
}

// ────────────────────────────────────────────────────────────────
// 6. mod Game
// ────────────────────────────────────────────────────────────────

mod Game {

    // ── scene.json タグパーサ ──

    /// SceneLoader.loadScene に渡す tagParser。scene.json の "tag" フィールド (Option[String])
    /// を NodeTag に翻訳する。
    /// パラメータ付きの variant (Player(Data) / Mob(Data) / ScoreLabel(Score) / MobTimer(MobId))
    /// は scene.json 側からは復元できないため、構築コードが loadScene 直後の Scene.setState
    /// で別途注入する。ここではパラメータレスの variant のみ扱う。
    pub def parseNodeTag(opt: Option[String]): Result[Util.Json.JsonError, NodeTag] =
        match opt {
            case None => Ok(NodeTag.NoTag)
            case Some(s) => match s {
                case "PlayerArea"    => Ok(NodeTag.PlayerArea)
                case "StartTimer"    => Ok(NodeTag.StartTimer)
                case "ScoreTimer"    => Ok(NodeTag.ScoreTimer)
                case "MessageTimer"  => Ok(NodeTag.MessageTimer)
                case "TitleTimer"    => Ok(NodeTag.TitleTimer)
                case "MessageLabel"  => Ok(NodeTag.MessageLabel)
                case "StartButton"   => Ok(NodeTag.StartButton)
                case "NoTag"         => Ok(NodeTag.NoTag)
                case _               => Ok(NodeTag.NoTag)
            }
        }

    // ── 画面定数 ──

    pub def designWi(): Int32 = 480
    pub def designHi(): Int32 = 720
    pub def windowWi(): Int32 = 480
    pub def windowHi(): Int32 = 720

    // ── 音 ──

    def musicKey(): String = "music"

    // ── タイマーパス ──

    def mobTimerName(): String   = "mob_timer"
    def startTimerName(): String = "start_timer"
    def scoreTimerName(): String = "score_timer"
    def mobPathName(): String    = "mob_path"

    pub def mobTimerPath(): NodePath   = mobTimerName() :: Nil
    pub def startTimerPath(): NodePath = startTimerName() :: Nil
    pub def scoreTimerPath(): NodePath = scoreTimerName() :: Nil

    // ── 開始入力判定 ──

    /// Playing への遷移を受け付けるかどうか。
    /// Menu / GameOver(StartButton 表示中) のみ true、Playing 中は false
    pub def canStart(scene: Scene[NodeTag]): Bool \ GamePhaseState =
        match GamePhaseState.get() {
            case GamePhase.Menu     => true
            case GamePhase.Playing  => false
            case GamePhase.GameOver => HUDScene.isStartButtonVisible(scene)
        }

    // ── シーン構築 ──

    /// 共通の土台シーン: 背景 + プレイヤー + Mob/Start/Score タイマー + mob_path + HUD
    /// Playing / Menu / GameOver で同じノードツリーを使い、HUD の見た目だけを切り替える。
    /// HUDScene が scene.json を読むため Fs.FileRead、loadSceneWithFont が GameEngine.Game を要求
    def buildBaseScene(fontAtlas: FontAtlas): Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        let bg = ColorRect.make(
            {x = Int32.toFloat64(designWi()), y = Int32.toFloat64(designHi())},
            {r = 0.219608f32, g = 0.372549f32, b = 0.380392f32}
        );
        let bgNode = EngineNode.ColorRectWithState(
            CanvasItem.setZIndex(-100, bg),
            NodeTag.NoTag
        );
        // 0.5 秒ごとに発火する Mob スポーンタイマー (初期は停止)
        let mobTimer = Timer.make(Duration.seconds(0.5))
            |> Timer.setOneShot(false);
        // 2 秒の Get Ready 表示用タイマー (one-shot)
        let startTimer = Timer.make(Duration.seconds(2.0))
            |> Timer.setOneShot(true);
        // 1 秒ごとのスコアタイマー (初期は停止)
        let scoreTimer = Timer.make(Duration.seconds(1.0))
            |> Timer.setOneShot(false);
        // モブを湧かせる画面端パス
        let mobPath = Path2D.screenEdgePath(designWi(), designHi());
        Scene.empty()
            |> Scene.addNode("background", bgNode)
            |> PlayerScene.addPlayer
            |> Scene.addNode(mobTimerName(),
                EngineNode.TimerWithState(mobTimer, NodeTag.MobTimer(0)))
            |> Scene.addNode(mobPathName(),
                EngineNode.Path2DWithState(mobPath, NodeTag.NoTag))
            |> Scene.addNode(startTimerName(),
                EngineNode.TimerWithState(startTimer, NodeTag.StartTimer))
            |> Scene.addNode(scoreTimerName(),
                EngineNode.TimerWithState(scoreTimer, NodeTag.ScoreTimer))
            |> HUDScene.addHUD(fontAtlas)

    /// メニュー画面のシーン: 共通シーン + タイトル + StartButton
    pub def buildMenuScene(fontAtlas: FontAtlas): Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        buildBaseScene(fontAtlas)
            |> HUDScene.enterMenu

    /// プレイ開始時のシーン: 共通シーン + プレイヤー初期化 + StartTimer 起動 + BGM
    /// 注意: 副作用 (BGM 再生) を含むため Aef に GameEngine.Audio を含める
    pub def buildPlayingScene(fontAtlas: FontAtlas): Scene[NodeTag] \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead} =
        AudioStreamPlayer.play(musicKey());
        buildBaseScene(fontAtlas)
            |> PlayerScene.start
            |> HUDScene.showMessage("Get Ready")
            |> HUDScene.hideStartButton
            |> HUDScene.updateScore(0)
            |> Scene.mapEngineNode(startTimerPath(),
                EngineNode.mapTimer(Timer.start))

    // ── GameOver 演出 ──

    /// 既存のシーンに GameOver の演出を載せる:
    /// BGM 停止 / mob・score タイマー停止 / "Game Over" + MessageTimer 開始 / StartButton 非表示
    pub def enterGameOver(scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Audio =
        AudioStreamPlayer.stop(musicKey());
        scene
            |> Scene.mapEngineNode(mobTimerPath(),   EngineNode.mapTimer(Timer.stop))
            |> Scene.mapEngineNode(scoreTimerPath(), EngineNode.mapTimer(Timer.stop))
            |> HUDScene.showMessage("Game Over")
            |> HUDScene.hideStartButton
            |> HUDScene.startMessageTimer

    // ── start / gameLoop / applyPhaseChange ──

    /// ゲーム起動エントリ。region 内に phaseRef を確保し、GamePhaseState handler で
    /// それを読み書きする。gameLoop は phaseRef の差分を見て applyPhaseChange を呼ぶ。
    pub def start(fontAtlas: FontAtlas):
                  Unit \ {GameEngine.Game, GameEngine.Audio, Math.Random, Fs.FileRead} =
        region rc {
            let phaseRef: Ref[GamePhase, rc] = Ref.fresh(rc, GamePhase.Menu);
            run {
                gameLoop(fontAtlas, GamePhase.Menu, buildMenuScene(fontAtlas))
            } with handler GamePhaseState {
                def get(k)         = k(Ref.get(phaseRef))
                def put(target, k) = { Ref.put(target, phaseRef); k() }
            }
        }

    /// applyPhaseChange: phase 遷移時にシーンを組み立てる。
    /// - Playing : フルリビルド (player リセット + BGM スタート)
    /// - Menu    : フルリビルド (タイトル + ボタン)
    /// - GameOver: 既存シーンに overlay (mob/score 停止 + Game Over 表示)
    def applyPhaseChange(phase: GamePhase, fontAtlas: FontAtlas,
                          scene: Scene[NodeTag]):
                          Scene[NodeTag] \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead} =
        match phase {
            case GamePhase.Playing  => buildPlayingScene(fontAtlas)
            case GamePhase.Menu     => buildMenuScene(fontAtlas)
            case GamePhase.GameOver => enterGameOver(scene)
        }

    /// メインループ: 終了判定 → エンジンパイプライン → フェーズ差分 → 描画 → 末尾再帰
    def gameLoop(fontAtlas: FontAtlas, previousPhase: GamePhase,
                  scene: Scene[NodeTag]):
                 Unit \ {GameEngine.Game, GameEngine.Audio, GamePhaseState, Math.Random, Fs.FileRead} =
        if (GameEngine.Game.shouldClose() or
            GameEngine.Game.isKeyPressed(GameEngine.Key.Escape)) ()
        else {
            let dt = GameEngine.Game.getDeltaTime();
            let updatedScene = scene
                |> GameEngine.process(delta = dt, paused = false)
                |> GameEngine.physicsProcess(delta = dt, paused = false,
                                              gravity = Vec2.zero())
                |> GameEngine.handleInput
                |> GameEngine.handleButtons
                |> GameEngine.handleCollisions
                |> GameEngine.handleScreenTransitions(screenWidth = designWi(),
                                                       screenHeight = designHi())
                |> GameEngine.handleTimers;
            let currentPhase = GamePhaseState.get();
            let nextScene = if (currentPhase != previousPhase)
                                applyPhaseChange(currentPhase, fontAtlas, updatedScene)
                            else updatedScene;
            GameEngine.render(nextScene);
            gameLoop(fontAtlas, currentPhase, nextScene)
        }
}
