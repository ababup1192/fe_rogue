/// ゲーム本体エントリ。`yarn/output.json` を読み込み、`DialogueScene` レイヤを
/// 1 枚積んで対話デモを駆動する。
///
/// engine-guide / scene-editor / game-loop の各規約に揃えた構成：
///   - `NodeTag.Dialogue(DialogueScene.Data)` でレイヤ状態を NodeTag に内包
///   - `InputHandler[NodeTag]` は `DialogueScene.input` に委譲するだけ（dispatch のみ）
///   - `mod Game` は配線役。シーン構築・ロジックは XxxScene 側
///   - `gameLoop` は 7 段パイプライン:
///       F1 トグル → エディタ ON 判定 → ゲーム更新 → ホットリロード判定
///       → エディタオーバーレイ → 描画 → 末尾再帰

/// Scene[s] のジェネリック s に当てるタグ。
/// 対話レイヤだけがゲームロジックを持つ（root の `Dialogue.UIState` に状態を集約）。
/// Room レイヤは `RoomScene.Data`（現在の roomId）を持つ。
/// Hotspot は Area2D 1 個分のクリック対象で、`HotspotData` に部屋 id とホットスポット id を
/// 持って `AreaHandler.onAreaClicked` で yarn ノードを起動する。
/// Inventory レイヤは `InventoryScene.Data` (placeholder) を持ち、`process` で
/// `Game.Inventory.Access` の snapshot を scene tree に同期する。
pub enum NodeTag {
    case NoTag
    case Dialogue(Dialogue.UIState)
    case Room(RoomScene.Data)
    case Hotspot(RoomScene.HotspotData)
    case Inventory(InventoryScene.Data)
}

/// Node 実装。
///   - Dialogue レイヤ: `DialogueScene.process` に委譲 (auto-next / talk SE 等)
///   - Inventory レイヤ: `InventoryScene.process` に委譲 (Inventory.Access snapshot を
///     scene tree のアイコン Sprite + ハイライトに同期)
/// 各 redef は trait の Aef = (Dialogue.* + GameEngine.Audio + Inventory.Access) に
/// 揃える必要があるので `checked_ecast` でキャストアップする。
instance Node[NodeTag] {
    type Aef = { Dialogue.SceneView.Inbox, Dialogue.Session, GameEngine.Audio,
                 Game.Inventory.Access }

    redef process(delta: Duration.Duration, node: EngineNode[NodeTag],
                   _path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag])
                    \ {Dialogue.SceneView.Inbox, Dialogue.Session, GameEngine.Audio,
                       Game.Inventory.Access} =
        match node {
            case EngineNode.CanvasLayerWithState(layer, NodeTag.Dialogue(state)) =>
                checked_ecast(DialogueScene.process(delta, layer, state, scene))
            case EngineNode.CanvasLayerWithState(layer, NodeTag.Inventory(data)) =>
                let nextScene = InventoryScene.process(layer, data, scene);
                checked_ecast((node, nextScene))
            case _ => (node, scene)
        }
}

/// 入力ハンドラ。
/// 確定キーで tap SE を鳴らすため `GameEngine.Audio`、マウスクリックの伝播先である
/// AreaHandler が `Dialogue.Session`、インベントリ選択で `Game.Inventory.Access` を要求するため
/// `Aef` に同包。各 redef の body はこのうち一部しか使わないので `checked_ecast` で
/// trait Aef に揃える。
///
/// マウスクリックは:
///   1. 対話モード中 (Yarn busy)            → DialogueScene.confirm (▼ 進行 / 一気出し / 選択肢確定)
///   2. クリックがインベントリバー領域内      → InventoryScene.onClick (スロット選択切替)
///   3. それ以外 (探索モードかつ室内クリック)  → AreaEvent.dispatchClicks (ホットスポット起動)
/// の優先順で処理する。
///
/// `isActive = false` でも UI 側に transition 演出が残っているフレームでクリックすると
/// 新 Session が走るが、`Dialogue.applyEvent` が transition 中の panel 起点イベントを
/// `pendingEvent` 差し替え経路に流すので、旧 `Complete` が新 VM の表示行を消す競合は
/// 起きない (Dialogue.flix の `eventStartsNewPanel` を参照)。
instance InputEvent.InputHandler[NodeTag] {
    type Aef = { Dialogue.Session, GameEngine.Audio, Game.Inventory.Access }

    redef onKeyPressed(key: GameEngine.Key, scene: Scene[NodeTag]):
                        Scene[NodeTag] \ { Dialogue.Session, GameEngine.Audio,
                                            Game.Inventory.Access } =
        checked_ecast(DialogueScene.input(key, scene))

    redef onMouseButtonPressed(button: GameEngine.MouseButton,
                                position: Vec2.Vec2,
                                scene: Scene[NodeTag]):
                                Scene[NodeTag] \ { Dialogue.Session, GameEngine.Audio,
                                                    Game.Inventory.Access } =
        if (Dialogue.Session.isActive()) checked_ecast(DialogueScene.confirm(scene))
        else if (InventoryScene.containsPoint(position))
            checked_ecast(InventoryScene.onClick(position, scene))
        else checked_ecast(AreaEvent.dispatchClicks(button, position, scene))

    // 対話モード中はホバーイベントを DialogueScene.onHover に委譲し、
    // 選択肢上にマウスが乗ったらカーソルをそこに合わせる。
    // Body 以外のホバー（白枠 / 黒地など）は DialogueScene 側で no-op。
    redef onMouseHover(path: NodePath, localPosition: Vec2.Vec2,
                        scene: Scene[NodeTag]):
                        Scene[NodeTag] \ { Dialogue.Session, GameEngine.Audio,
                                            Game.Inventory.Access } =
        if (Dialogue.Session.isActive())
            checked_ecast(DialogueScene.onHover(path, localPosition, scene))
        else checked_ecast(scene)
}

/// 衝突応答ハンドラ。Phase 2 ではマウスクリック時に Hotspot タグの Area2D に着地した
/// イベントだけを処理する（`onAreaEntered` / `onAreaExited` は使わずデフォルトのまま）。
/// Hotspot は `RoomScene` が enter で配置する Area2D 1 個分のクリック対象。
/// `HotspotData#roomId` と `HotspotData#hotspotId` から命名規約 `Hotspot_<>_<>` の
/// yarn ノードを `Dialogue.Session.start` で起動する。
instance AreaEvent.AreaHandler[NodeTag] {
    type Aef = { Dialogue.Session }

    pub def onAreaEntered(_selfPath: NodePath, _selfState: NodeTag,
                           _otherPath: NodePath, _otherState: NodeTag,
                           scene: Scene[NodeTag]): Scene[NodeTag] \ Dialogue.Session =
        checked_ecast(scene)

    redef onAreaClicked(_selfPath: NodePath, selfState: NodeTag,
                         _button: GameEngine.MouseButton, _position: Vec2.Vec2,
                         scene: Scene[NodeTag]): Scene[NodeTag] \ Dialogue.Session =
        match selfState {
            case NodeTag.Hotspot(data) =>
                Dialogue.Session.start(RoomScene.yarnNodeNameFor(data#roomId, data#hotspotId));
                scene
            case _ => checked_ecast(scene)
        }
}

mod Game {
    use Yarn.Types.YarnProject

    // ════════════════════════════════════════════════════════════════════════
    // 解像度
    // ════════════════════════════════════════════════════════════════════════

    /// デザイン解像度（ロジック側の基準）。
    /// 16:10 アスペクト比は Steam Deck (1280×800 ネイティブ) を主軸に、
    /// ROG Ally (1920×1080 16:9) でも上下にわずかな黒帯で収まる選択。
    pub def designWi(): Int32 = 480
    pub def designHi(): Int32 = 300

    /// 初期ウィンドウサイズ（OS ピクセル）。design × 3 (= 1440×900) で
    /// 一般的なノート PC ディスプレイに収まるサイズ。整数スケールで pixel art の
    /// シャープさを保つ。
    pub def windowWi(): Int32 = 1440
    pub def windowHi(): Int32 = 900

    // ════════════════════════════════════════════════════════════════════════
    // fixture 読み込み
    // ════════════════════════════════════════════════════════════════════════

    /// `yarn/output.json` を読み込み `YarnProject` を返す。失敗は `bug!`。
    /// ファイルシステム依存はここに局所化される（本番経路はディスクから読む）。
    /// 読み込み API は `Fs.ReadFile.read` + `Fs.ReadFile.runWithFileRead` で
    /// `Fs.FileRead` 効果に変換する（プロジェクトの SceneLoader と同じパターン）。
    def loadProject(): YarnProject \ Fs.FileRead =
        let readResult = run {
            Fs.ReadFile.read("yarn/output.json")
        } with Fs.ReadFile.runWithFileRead;
        let jsonText = readResult |> Result.getWithDefault("");
        match Yarn.Loader.parseProject(jsonText) {
            case Ok(loaded)  => loaded
            case Err(error)  => bug!("yarn/output.json parse failed: ${error}")
        }

    // ════════════════════════════════════════════════════════════════════════
    // シーン構築
    // ════════════════════════════════════════════════════════════════════════

    /// 対話レイヤを 1 枚積んだ初期シーンを構築する。
    /// `addDialogueLayer` 自身が `DialogueScene.scene.json` を読みに行くので Fs.FileRead が必要。
    /// `fontAtlas` / `boldFontAtlas` は `start` で事前取得して渡す
    /// （ホットリロード時の再構築でも再利用）。bold は `[b]...[/b]` 用。
    def buildScene(fontAtlas: FontAtlas, boldFontAtlas: FontAtlas):
                    Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        Scene.empty()
            |> WorldScene.addWorldLayers
            |> RoomScene.addRoomLayer
            |> InventoryScene.addInventoryLayer
            |> DialogueScene.addDialogueLayer(fontAtlas, boldFontAtlas)

    // ════════════════════════════════════════════════════════════════════════
    // start / gameLoop
    // ════════════════════════════════════════════════════════════════════════

    /// ゲーム起動エントリ。`$hp` 等の変数初期値は yarn の `<<declare>>` に従う。
    ///
    /// 対話関連の handler 連結（Runner / AsyncOnly / SceneView+Inbox+CommandInbox）は
    /// `Dialogue.withDialog` に閉じ込めてあり、region / event queue は外には漏れない。
    ///
    /// ゲーム特有状態（wait queue / shake / audio fader）は region 内 Ref に閉じ込め、
    /// 各 module の `Access` effect 経由で読み書きする handler を注入する。
    /// gameLoop からは Ref が見えない。
    pub def start():
            Unit \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead, Fs.FileWrite,
                    Math.Random, IO} =
        // 注意: Flix では `project` は予約語のため変数名に使えない。
        let yarnProject = loadProject();
        let fontAtlas = GameEngine.Game.getFontAtlas(DialogueScene.fontName());
        let boldFontAtlas = GameEngine.Game.getFontAtlas(DialogueScene.boldFontName());
        region rc {
            run {
                Dialogue.Session.start("Start");
                gameLoop(buildScene(fontAtlas, boldFontAtlas))
            } with Dialogue.withDialog(yarnProject)
              with Game.YarnBuiltinExtension.withGameBuiltins
              with Game.Inventory.withState(rc)
              with Game.RoomState.withState(rc)
              with Game.ShakeState.withState(rc)
              with Game.AudioFader.withState(rc)
              with Game.CommandWaitQueue.withState(rc)
        }

    /// メインループ。
    ///   (1) ゲーム更新
    ///   (2) Yarn コマンド処理（音再生・wait カウントダウン・フラグ書き込み）
    ///   (3) 画面ゆれ・BGM フェード
    ///   (4) 描画
    ///   (5) 末尾再帰
    def gameLoop(scene: Scene[NodeTag]):
                  Unit \ {GameEngine.Game, GameEngine.Audio, Dialogue.Session,
                          Dialogue.SceneView.Inbox, Dialogue.SceneView.CommandInbox,
                          Yarn.VariableAccess,
                          Fs.FileRead, Fs.FileWrite,
                          Math.Random,
                          Game.CommandWaitQueue.Access,
                          Game.ShakeState.Access,
                          Game.AudioFader.Access,
                          Game.RoomState.Access,
                          Game.Inventory.Access,
                          IO} =
        if (GameEngine.Game.shouldClose()
            or GameEngine.Game.isKeyPressed(GameEngine.Key.Escape)) ()
        else {
            let dt = GameEngine.Game.getDeltaTime();
            let updated = scene
                |> GameEngine.handleInput
                |> GameEngine.process(delta = dt, paused = false);
            let afterCommands = Game.CommandRouter.processCommands(delta = dt, updated);
            let afterShake = Game.ShakeState.tickAndApply(dt, afterCommands);
            Game.AudioFader.tick(dt);
            GameEngine.render(afterShake);
            gameLoop(afterShake)
        }
}
