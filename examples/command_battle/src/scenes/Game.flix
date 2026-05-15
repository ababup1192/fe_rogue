// Game — DQ1 風コマンドバトル example のノードタグ定義・trait instance・シーン構築・ゲームループ
//
// 設計方針:
//   - 全シーン (Title / Battle / Message / Command) を 1 度に build し、 以降フェーズ遷移で
//     scene rebuild しない。
//   - 各シーンが自分の `process` 内で `GamePhaseState` を読んで自分の visible / focused を
//     決める（Title 以外で BattleScene/MessagePanel/CommandPanel visible=true、 CommandSelect
//     のときだけ CommandMenu focused=true、 など）。
//   - メッセージウィンドウのテキストも MessageScene.processBox が phase に応じて差し替え、
//     差分が出たら setText + visibleCharacters=0 でタイプライターを最初からやり直す。
//   - InputHandler / MenuHandler はフェーズ put だけを担当し、 scene の rebuild も
//     scene 状態の操作も行わない。
//   - これにより gameLoop / applyPhaseChange にゲームロジックが残らず、 engine の Scene API
//     を拡張する必要もなくなる。

// ========================================================================
// ゲームフェーズ
// ========================================================================

pub enum GamePhase with Eq, ToString {
    case Title           // タイトル画面
    case CommandSelect   // たたかう / じゅもん / どうぐ のコマンド選択中
    case Resolving       // メッセージウィンドウでタイプライター表示中
    case BattleEnd       // 戦闘終了（PR2 では固定で 1 ターン後に到達）
}

/// ゲームフェーズの読み書きエフェクト。
pub eff GamePhaseState {
    def get(): GamePhase
    def put(target: GamePhase): Unit
}

// ========================================================================
// ノードタグ
// ========================================================================

/// 各ノードに付与する識別タグ（Scene[NodeTag] の型パラメータ）。
/// 全シーンを常駐させ、各シーンが自分の `process` 内で GamePhase を読んで visible や
/// focused を更新する設計。 そのために各シーンのルートに識別タグを振る。
pub enum NodeTag with Eq, ToString {
    case TitleLayer
    case BattleLayer
    case MessagePanel
    case CommandPanel
    case CommandMenu
    case MessageBox
    case EnemyLabel
    case StatusLabel
    case NoTag
}

// ========================================================================
// Node 実装（各シーンの process にディスパッチするだけ）
// ========================================================================

instance Node[NodeTag] {
    type Aef = { GamePhaseState }

    redef process(delta: Duration.Duration, node: EngineNode[NodeTag],
                  path: NodePath,
                  scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) \ GamePhaseState =
        match node {
            case EngineNode.CanvasLayerWithState(_, NodeTag.TitleLayer) =>
                TitleScene.process(delta, node, path, scene)
            case EngineNode.CanvasLayerWithState(_, NodeTag.BattleLayer) =>
                BattleScene.process(delta, node, path, scene)
            case EngineNode.PanelWithState(_, NodeTag.MessagePanel) =>
                MessageScene.processPanel(delta, node, path, scene)
            case EngineNode.RichTextLabelWithState(_, NodeTag.MessageBox) =>
                MessageScene.processBox(delta, node, path, scene)
            case EngineNode.PanelWithState(_, NodeTag.CommandPanel) =>
                CommandScene.processPanel(delta, node, path, scene)
            case EngineNode.ItemListWithState(_, NodeTag.CommandMenu) =>
                CommandScene.processMenu(delta, node, path, scene)
            case _ => (node, scene)
        }
}

// ========================================================================
// InputHandler 実装（フェーズ put のみ。 scene 状態の操作はしない）
// ========================================================================

instance InputEvent.InputHandler[NodeTag] {
    type Aef = { GamePhaseState }

    redef onKeyPressed(key: GameEngine.Key,
                       scene: Scene[NodeTag]): Scene[NodeTag] \ GamePhaseState =
        let phase = GamePhaseState.get();
        match (key, phase) {
            case (GameEngine.Key.Enter, GamePhase.Title) =>
                GamePhaseState.put(GamePhase.CommandSelect); scene
            case (GameEngine.Key.Enter, GamePhase.Resolving) =>
                if (MessageScene.isComplete(scene))
                    { GamePhaseState.put(GamePhase.BattleEnd); scene }
                else
                    MessageScene.skipTypewriter(scene)
            case (GameEngine.Key.Enter, GamePhase.BattleEnd) =>
                GamePhaseState.put(GamePhase.Title); scene
            case _ => scene
        }
}

// ========================================================================
// MenuHandler 実装（CommandMenu 確定で Resolving に遷移）
// ========================================================================

instance MenuEvent.MenuHandler[NodeTag] {
    type Aef = { GamePhaseState }

    redef onItemConfirmed(_menuPath: NodePath, _idx: Int32, _entry: ItemEntry,
                          state: NodeTag,
                          scene: Scene[NodeTag]): Scene[NodeTag] \ GamePhaseState =
        match state {
            case NodeTag.CommandMenu =>
                GamePhaseState.put(GamePhase.Resolving); scene
            case _ => scene
        }
}

// ========================================================================
// mod Game
// ========================================================================

mod Game {

    // ── 画面サイズ ──

    pub def designWi(): Int32 = 640
    pub def designHi(): Int32 = 480
    pub def windowWi(): Int32 = 640
    pub def windowHi(): Int32 = 480

    // ── シーン構築（1 度だけ build、 フェーズ遷移で rebuild しない） ──
    //
    // `|>` chain を 1 関数にまとめると SceneLoader.loadSceneWithFont の forM が
    // すべて inline されて JVM のメソッドサイズ上限 (64KB) を超える
    // (`MethodTooLargeException`)。 そこで「背景レイヤー (CanvasLayer)」と
    // 「UI パネル (Panel)」 の 2 段に分けて各メソッドサイズを抑える。

    pub def buildScene(fontAtlas: FontAtlas):
                       Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        Scene.empty()
            |> addBackgroundLayers(fontAtlas)
            |> addUiPanels(fontAtlas)

    /// 画面の基底になる CanvasLayer 2 枚（タイトル画面・バトル背景）を追加する。
    def addBackgroundLayers(fontAtlas: FontAtlas, scene: Scene[NodeTag]):
                            Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        scene
            |> TitleScene.add(fontAtlas)
            |> BattleScene.add(fontAtlas)

    /// 上に重ねる UI パネル 2 枚（メッセージウィンドウ・コマンドメニュー）を追加する。
    def addUiPanels(fontAtlas: FontAtlas, scene: Scene[NodeTag]):
                    Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        scene
            |> MessageScene.add(fontAtlas)
            |> CommandScene.add(fontAtlas)

    // ── start / gameLoop ──

    pub def start(fontAtlas: FontAtlas):
                  Unit \ {GameEngine.Game, GameEngine.Audio, Math.Random, Fs.FileRead, IO} =
        region rc {
            let phaseRef: Ref[GamePhase, rc] = Ref.fresh(rc, GamePhase.Title);
            run {
                gameLoop(buildScene(fontAtlas))
            } with handler GamePhaseState {
                def get(k) = k(Ref.get(phaseRef))
                def put(target, k) = { Ref.put(target, phaseRef); k() }
            }
        }

    /// gameLoop は engine のパイプラインを順に呼ぶだけ。 ゲーム固有の判定は各シーンの
    /// process / InputHandler / MenuHandler に委譲する。
    def gameLoop(scene: Scene[NodeTag]):
                 Unit \ {GameEngine.Game, GameEngine.Audio, Math.Random, Fs.FileRead,
                         GamePhaseState} =
        if (GameEngine.Game.shouldClose()) ()
        else {
            let dt = GameEngine.Game.getDeltaTime();
            let updated = scene
                |> GameEngine.process(delta = dt, paused = false)
                |> GameEngine.handleInput
                |> GameEngine.handleMenus;
            GameEngine.render(updated);
            gameLoop(updated)
        }
}
