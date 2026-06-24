///
/// Shape Survivors — Game（NodeTag / GamePhaseState / trait instance / start / gameLoop）
///
/// エンジン本来の流儀（dodge / fe_rogue 参照）：
///   - 局面は `GamePhaseState` effect（Game.start の region 内 Ref）で持つ。
///   - trait instance（Node / InputHandler / MenuHandler）は **dispatch に徹し**、ロジックは XxxScene へ委譲。
///   - gameLoop はエンジンのパイプライン（process → handleInput → handleMenus → render）を呼ぶだけ。
///
/// ハイブリッド設計：敵・弾の「群れ」は純粋 `Model.World` の List のまま `WorldDriver` ノード 1 個に
/// 抱えさせる（engine ノードを 1 体ずつにしない）。衝突・移動は純粋層（game/）でテスト可能なまま。
/// 一方でレベルアップの3択 UI は engine の ItemList/MenuHandler（per-node メニュー dispatch）を使う。
///
/// 設計の全体像は同じディレクトリ階層の DESIGN.md を参照。
///

// ── 1. GamePhase ───────────────────────────────────────────────
/// ゲームの局面。Playing 中だけ世界が動く。GameOver は停止して再挑戦待ち、
/// LevelUp は停止して3択メニューの選択待ち。
pub enum GamePhase with Eq, ToString {
    case Playing
    case GameOver
    case LevelUp
}

// ── 2. カスタム effect ─────────────────────────────────────────
/// 局面の読み書き effect。Scene 側は `GamePhaseState.put(target)` で遷移を要求するだけ。
/// 実体は Game.start の region 内 Ref に格納され、gameLoop が前フレームとの差分で applyPhaseChange を起動する。
pub eff GamePhaseState {
    def get(): GamePhase
    def put(target: GamePhase): Unit
}

// ── 3. NodeTag ─────────────────────────────────────────────────
/// シーン上のノード識別タグ。
pub enum NodeTag {
    /// 群れ駆動ノード（Marker2D）。純粋 World を丸ごと抱える単一の真実の源。
    /// process が Update.step を回し、WorldScene が描画用の図形ノードを展開する。
    case WorldDriver(Model.World)
    /// HUD ラベル（毎フレーム text を更新する）
    case Hud
    /// レベルアップ3択の ItemList。提示中の選択肢を埋めておき、確定時に idx で引く。
    case LevelUpMenu(List[Upgrade.Kind])
    /// タグ不要のノード（背景・群れの図形など）
    case NoTag
}

// ── 4. trait instance（dispatch のみ） ─────────────────────────
instance Node[NodeTag] {
    type Aef = { GameEngine.Game, Math.Random, GamePhaseState }
    type ProcessAef = { GameEngine.Game, Math.Random, GamePhaseState }

    redef process(delta: Duration.Duration, node: EngineNode[NodeTag],
                  path: NodePath, scene: Scene[NodeTag]):
                 (EngineNode[NodeTag], Scene[NodeTag]) \ { GameEngine.Game, Math.Random, GamePhaseState } =
        match node {
            case EngineNode.Marker2DWithState(_, NodeTag.WorldDriver(_)) =>
                WorldScene.process(delta, node, path, scene)
            case _ => (node, scene)
        }
}

instance InputEvent.InputHandler[NodeTag] {
    type Aef = { GamePhaseState }

    redef onKeyPressed(key: GameEngine.Key, scene: Scene[NodeTag]):
                       Scene[NodeTag] \ GamePhaseState =
        match GamePhaseState.get() {
            case GamePhase.GameOver =>
                if (key == GameEngine.Key.Enter or key == GameEngine.Key.Space) {
                    GamePhaseState.put(GamePhase.Playing);  // 次フレームで Playing を再構築
                    scene
                } else scene
            case _ => scene  // Playing の移動は process 内 polling、LevelUp の選択は MenuHandler
        }
}

instance MenuEvent.MenuHandler[NodeTag] {
    type Aef = { GamePhaseState }

    redef onItemConfirmed(_menuPath: NodePath, idx: Int32, _entry: ItemEntry,
                          state: NodeTag, scene: Scene[NodeTag]): Scene[NodeTag] \ GamePhaseState =
        match state {
            case NodeTag.LevelUpMenu(choices) => WorldScene.applyChosenUpgrade(idx, choices, scene)
            case _ => scene
        }
}

// ── 5. mod Game（配線：start / gameLoop / applyPhaseChange） ────
mod Game {

    /// 起動エントリ。region 内に局面 Ref を作り、GamePhaseState の handler を注入してループを回す。
    pub def start(fontAtlas: FontAtlas): Unit \ {GameEngine.Game, Math.Random, Fs.FileRead} =
        region rc {
            let phaseRef: Ref[GamePhase, rc] = Ref.fresh(rc, GamePhase.Playing);
            run {
                gameLoop(fontAtlas, GamePhase.Playing, WorldScene.buildScene(fontAtlas))
            } with handler GamePhaseState {
                def get(k)         = k(Ref.get(phaseRef))
                def put(target, k) = { Ref.put(target, phaseRef); k() }
            }
        }

    /// 局面が変わったときだけシーンを組み替える（前局面 → 現局面）。
    ///   - GameOver→Playing : まっさらに作り直す（再挑戦＝初期状態）。
    ///   - LevelUp→Playing  : 何もしない（強化適用とメニュー除去は MenuHandler が済ませている）。
    ///   - →GameOver        : 結果オーバーレイを重ねる。
    ///   - →LevelUp         : 3択メニューを重ねる。
    def applyPhaseChange(previousPhase: GamePhase, currentPhase: GamePhase, fontAtlas: FontAtlas,
                         scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Game, Math.Random, Fs.FileRead} =
        match currentPhase {
            case GamePhase.Playing =>
                if (previousPhase == GamePhase.GameOver) WorldScene.buildScene(fontAtlas) else scene
            case GamePhase.GameOver => WorldScene.addGameOverOverlay(fontAtlas, scene)
            case GamePhase.LevelUp  => WorldScene.addLevelUpMenu(fontAtlas, scene)
        }

    /// メインループ：終了判定 → process → 入力 → メニュー → 局面差分 → 描画同期 → 描画 → 末尾再帰。
    /// gameLoop 自身はパイプラインを順に呼ぶだけ。ロジックは WorldScene と純粋層に委譲。
    def gameLoop(fontAtlas: FontAtlas, previousPhase: GamePhase,
                 scene: Scene[NodeTag]): Unit \ {GameEngine.Game, Math.Random, GamePhaseState, Fs.FileRead} =
        if (GameEngine.Game.shouldClose() or
            GameEngine.Game.isKeyPressed(GameEngine.Key.Escape))
            ()
        else {
            let dt = GameEngine.Game.getDeltaTime();
            // Playing 以外（GameOver / LevelUp）は paused=true ＝ WorldDriver の process が止まり世界が凍る。
            let paused = previousPhase != GamePhase.Playing;
            let updated = scene
                |> GameEngine.process(delta = dt, paused = paused)
                |> GameEngine.handleInput
                |> GameEngine.handleMenus;   // focused な ItemList の ↑↓/Enter を処理
            let currentPhase = GamePhaseState.get();
            let phased =
                if (currentPhase != previousPhase)
                    applyPhaseChange(previousPhase, currentPhase, fontAtlas, updated)
                else updated;
            // World から描画用の図形ノード（群れ・HUD）を毎フレーム作り直す。
            let synced = WorldScene.syncVisual(phased);
            GameEngine.render(synced);
            gameLoop(fontAtlas, currentPhase, synced)
        }
}
