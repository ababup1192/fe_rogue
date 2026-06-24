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
    case CommandSelect   // プレイヤーのコマンド選択中
    case SpellSelect     // じゅもんサブメニュー選択中
    case ItemSelect      // どうぐサブメニュー選択中
    case TargetSelect    // 攻撃 / 攻撃呪文のターゲット敵選択中
    case Resolving       // プレイヤー行動の解決中（攻撃メッセージ表示）
    case EnemyActing     // 敵の行動中（反撃メッセージ表示）
    case Victory         // 勝利（敵を倒した）
    case Defeat          // 敗北（勇者が倒れた）
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
///
/// `BattleState` は record 型 (`BattleScene.State`) を持つので、 `with Eq, ToString` の
/// 自動派生は外す（record の Eq 自動派生は使えないため）。
pub enum NodeTag {
    case TitleLayer
    case BattleLayer
    /// バトル状態の隠しノード (Marker2D + Data) — battle/state パスに置く。
    /// Data は current（毎フレーム更新）+ initial（起動時の Resource から作る不変値）を持ち、
    /// `resetBattle` で initial → current にコピーして戦闘をリセットする。
    case BattleState(BattleScene.Data)
    case MessagePanel
    case CommandPanel
    case CommandMenu
    case SpellPanel
    case SpellMenu
    case ItemPanel
    case ItemMenu
    /// 全画面フラッシュ用 ColorRect。 呪文発動時に短時間 alpha を上げて画面を光らせる
    case FlashOverlay
    case MessageBox
    case EnemySprite(Int32)
    /// TargetSelect フェーズで敵の上に表示する選択カーソル ▶
    case TargetCursor
    case StatusLabel
    case NoTag
}

// ========================================================================
// Node 実装（各シーンの process にディスパッチするだけ）
// ========================================================================

instance Node[NodeTag] {
    type Aef = { GamePhaseState }
    type ProcessAef = { GamePhaseState }

    // 毎フレーム動かす必要があるのは「状態 → 表示」 の連動だけ
    //   - StatusLabel              : HP の文字列表示更新
    //   - EnemySprite              : 被弾点滅・敗北時の hide
    //   - MessageBox               : タイプライターの 1 文字進行
    //   - ItemMenu                 : 所持アイテム数の変化を即反映
    // フェーズに依存する visibility / focused 制御は Game.applyVisibility が
    // フェーズ遷移時に 1 度だけ呼ぶ（Push モデル）ので process では扱わない。
    redef process(delta: Duration.Duration, node: EngineNode[NodeTag],
                  path: NodePath,
                  scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) \ GamePhaseState =
        match EngineNode.getState(node) {
            case NodeTag.BattleLayer =>
                checked_ecast(BattleScene.processBattleLayer(delta, node, path, scene))
            case NodeTag.StatusLabel =>
                checked_ecast(BattleScene.processStatusLabel(delta, node, path, scene))
            case NodeTag.EnemySprite(idx) =>
                checked_ecast(BattleScene.processEnemySprite(idx, delta, node, path, scene))
            case NodeTag.FlashOverlay =>
                checked_ecast(BattleScene.processFlashOverlay(delta, node, path, scene))
            case NodeTag.MessageBox =>
                MessageScene.processBox(delta, node, path, scene)
            case NodeTag.ItemMenu =>
                checked_ecast(ItemMenuScene.refreshItems(delta, node, path, scene))
            case NodeTag.TargetCursor =>
                checked_ecast(BattleScene.processTargetCursor(delta, node, path, scene))
            case _ => (node, scene)
        }
}

// ========================================================================
// InputHandler 実装（フェーズ put のみ。 scene 状態の操作はしない）
// ========================================================================

instance InputEvent.InputHandler[NodeTag] {
    type Aef = { GamePhaseState, Math.Random, GameEngine.Audio }
    // dispatch のみ。 実処理は BattleScene の各関数に委譲する。
    // TargetSelect フェーズでは ↑↓ ではなく ← → でカーソル移動する設計（Escape でキャンセル）。
    redef onKeyPressed(key: GameEngine.Key,
                       scene: Scene[NodeTag]):
                       Scene[NodeTag] \ {GamePhaseState, Math.Random, GameEngine.Audio} =
        let phase = GamePhaseState.get();
        match (key, phase) {
            case (GameEngine.Key.Enter, _) =>
                BattleScene.advancePhaseOnEnter(scene)
            case (GameEngine.Key.Left,  GamePhase.TargetSelect) =>
                checked_ecast(BattleScene.moveTargetCursor(-1, scene))
            case (GameEngine.Key.Right, GamePhase.TargetSelect) =>
                checked_ecast(BattleScene.moveTargetCursor(1, scene))
            case (GameEngine.Key.Escape, GamePhase.TargetSelect) =>
                checked_ecast(BattleScene.cancelTargetSelect(scene))
            case _ => scene
        }
}

// ========================================================================
// MenuHandler 実装（CommandMenu 確定で Resolving に遷移）
// ========================================================================

instance MenuEvent.MenuHandler[NodeTag] {
    type Aef = { GamePhaseState, Math.Random, GameEngine.Audio }
    // dispatch のみ。 各 menu のロジックは Scene の関数に委譲する。
    redef onItemConfirmed(_menuPath: NodePath, _idx: Int32, entry: ItemEntry,
                          state: NodeTag,
                          scene: Scene[NodeTag]):
                          Scene[NodeTag] \ {GamePhaseState, Math.Random, GameEngine.Audio} =
        match state {
            case NodeTag.CommandMenu => CommandScene.onCommandConfirmed(entry, scene)
            case NodeTag.SpellMenu   => SpellMenuScene.onSpellConfirmed(entry, scene)
            case NodeTag.ItemMenu    => checked_ecast(ItemMenuScene.onItemConfirmed(entry, scene))
            case _                   => scene
        }
    redef onItemCancelled(_menuPath: NodePath, state: NodeTag,
                          scene: Scene[NodeTag]):
                          Scene[NodeTag] \ {GamePhaseState, Math.Random, GameEngine.Audio} =
        match state {
            case NodeTag.SpellMenu => checked_ecast(SpellMenuScene.onSpellCancelled(scene))
            case NodeTag.ItemMenu  => checked_ecast(ItemMenuScene.onItemCancelled(scene))
            case _                 => scene
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

    /// 上に重ねる UI パネル 4 枚（メッセージウィンドウ + 3 つのメニュー）を追加する。
    /// `|>` chain が長くなると inline 展開で MethodTooLargeException が起きるので、 さらに
    /// 2 段に分割する。
    def addUiPanels(fontAtlas: FontAtlas, scene: Scene[NodeTag]):
                    Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        scene
            |> addMessageAndCommand(fontAtlas)
            |> addSubMenus(fontAtlas)

    def addMessageAndCommand(fontAtlas: FontAtlas, scene: Scene[NodeTag]):
                             Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        scene
            |> MessageScene.add(fontAtlas)
            |> CommandScene.add(fontAtlas)

    def addSubMenus(fontAtlas: FontAtlas, scene: Scene[NodeTag]):
                    Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        scene
            |> SpellMenuScene.add(fontAtlas)
            |> ItemMenuScene.add(fontAtlas)

    // ── visibility 適用 (Push モデル) ──
    //
    // フェーズが変わった瞬間に 1 度だけ呼ばれる。 各 Scene の applyVisibility を chain して、
    // 全パネルの visible / focused を一括設定する。 毎フレーム回さないので process から
    // GamePhase 判定ロジックを排除できる。

    pub def applyVisibility(phase: GamePhase, scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
            |> applyBackgroundVisibility(phase)
            |> applyUiVisibility(phase)

    def applyBackgroundVisibility(phase: GamePhase, scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
            |> TitleScene.applyVisibility(phase)
            |> BattleScene.applyVisibility(phase)

    def applyUiVisibility(phase: GamePhase, scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
            |> MessageScene.applyVisibility(phase)
            |> CommandScene.applyVisibility(phase)
            |> SpellMenuScene.applyVisibility(phase)
            |> ItemMenuScene.applyVisibility(phase)

    // ── start / gameLoop ──

    pub def start(fontAtlas: FontAtlas):
                  Unit \ {GameEngine.Game, GameEngine.Audio, Math.Random, Fs.FileRead, IO} =
        region rc {
            let phaseRef: Ref[GamePhase, rc] = Ref.fresh(rc, GamePhase.Title);
            run {
                // 起動時に初期 visibility (Title フェーズ) を適用してから gameLoop に入る。
                let initialScene = applyVisibility(GamePhase.Title, buildScene(fontAtlas));
                gameLoop(GamePhase.Title, initialScene)
            } with handler GamePhaseState {
                def get(k) = k(Ref.get(phaseRef))
                def put(target, k) = { Ref.put(target, phaseRef); k() }
            }
        }

    /// gameLoop は engine のパイプラインを順に呼ぶだけ。
    /// フェーズが変わったフレームでだけ applyVisibility で UI 状態を一括更新する。
    def gameLoop(previousPhase: GamePhase, scene: Scene[NodeTag]):
                 Unit \ {GameEngine.Game, GameEngine.Audio, Math.Random, Fs.FileRead,
                         GamePhaseState} =
        if (GameEngine.Game.shouldClose()) ()
        else {
            let dt = GameEngine.Game.getDeltaTime();
            let updated = scene
                |> GameEngine.process(delta = dt, paused = false)
                |> GameEngine.handleInput
                |> GameEngine.handleMenus;
            let currentPhase = GamePhaseState.get();
            let withVisibility =
                if (currentPhase != previousPhase)
                    applyVisibility(currentPhase, updated)
                else updated;
            GameEngine.render(withVisibility);
            gameLoop(currentPhase, withVisibility)
        }
}
