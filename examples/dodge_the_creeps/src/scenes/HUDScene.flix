/// HUDScene — スコア / メッセージ / スタートボタンの HUD レイヤー
///
/// ノード構成 (CanvasLayer 配下):
///   CanvasLayer "hud"                ─ NodeTag.NoTag
///     ├── Label2D "score"            ─ NodeTag.ScoreLabel(Score)
///     ├── Label2D "message"          ─ NodeTag.MessageLabel
///     └── Button  "start"            ─ NodeTag.StartButton
///
/// 加えてゲーム全体に関わるタイマー類は HUD ではなくシーンのルートに置く:
///   Timer "message_timer"            ─ NodeTag.MessageTimer
///   Timer "title_timer"              ─ NodeTag.TitleTimer
///
/// 「ボタンが押された」「メッセージタイマーが時間切れになった」などのイベントは
/// Game.flix の ButtonHandler / TimerHandler 経由で各 HUD 関数に委譲される。
mod HUDScene {

    // ── 型 ──

    pub type alias Score = Int32

    // ── 定数 ──

    pub def hudName(): String = "hud"
    def scoreLabelName(): String = "score"
    def messageLabelName(): String = "message"
    def startButtonName(): String = "start"

    pub def hudPath(): NodePath = hudName() :: Nil
    pub def scoreLabelPath(): NodePath = hudName() :: scoreLabelName() :: Nil
    pub def messageLabelPath(): NodePath = hudName() :: messageLabelName() :: Nil
    pub def startButtonPath(): NodePath = hudName() :: startButtonName() :: Nil

    def messageTimerName(): String = "message_timer"
    def titleTimerName(): String = "title_timer"
    pub def messageTimerPath(): NodePath = messageTimerName() :: Nil
    pub def titleTimerPath(): NodePath = titleTimerName() :: Nil

    // フォントサイズ・スタートボタンサイズは scene.json 側に移動 (HUDScene.scene.json)。

    // ── 構築 ──

    /// シーン定義 JSON のパス。CanvasLayer hud + score / message Label2D を持つ。
    /// Button (start) と root レベルの Timer 2 つは engine の scene.json schema が
    /// 未対応のため addHUD 内のコードで追加する (ハイブリッド構成)。
    def sceneJsonPath(): String = "src/scenes/HUDScene.scene.json"

    pub def addHUD(fontAtlas: FontAtlas, scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        // Timer は scene.json schema が未対応なのでコードで構築する
        let messageTimer = Timer.make(Duration.seconds(2.0))
            |> Timer.setOneShot(true);
        let titleTimer = Timer.make(Duration.seconds(1.0))
            |> Timer.setOneShot(true);
        SceneLoader.loadSceneWithFont(sceneJsonPath(), fontAtlas, Game.parseNodeTag, scene)
            // ScoreLabel(0) は Score (Int32) を含むため scene.json には書けない。post-load で注入する。
            |> Scene.setState(scoreLabelPath(), NodeTag.ScoreLabel(0))
            |> Scene.addNode(messageTimerName(),
                EngineNode.TimerWithState(messageTimer, NodeTag.MessageTimer))
            |> Scene.addNode(titleTimerName(),
                EngineNode.TimerWithState(titleTimer, NodeTag.TitleTimer))

    // ── スコア ──

    pub def updateScore(n: Score, scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
            |> Scene.mapEngineNode(scoreLabelPath(),
                EngineNode.mapLabel2D(Label2D.setText(Int32.toString(n))))
            |> Scene.setState(scoreLabelPath(), NodeTag.ScoreLabel(n))

    pub def getScore(scene: Scene[NodeTag]): Score =
        match Scene.getState(scoreLabelPath(), scene) {
            case Some(NodeTag.ScoreLabel(n)) => n
            case _                                  => 0
        }

    pub def incrementScore(scene: Scene[NodeTag]): Scene[NodeTag] =
        updateScore(getScore(scene) + 1, scene)

    // ── メッセージ ──

    pub def showMessage(text: String, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(messageLabelPath(),
            EngineNode.mapLabel2D(label -> label
                |> Label2D.setText(text)
                |> CanvasItem.setVisible(true)), scene)

    pub def hideMessage(scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(messageLabelPath(),
            EngineNode.mapLabel2D(CanvasItem.setVisible(false)), scene)

    // ── スタートボタン ──

    pub def showStartButton(scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(startButtonPath(),
            EngineNode.mapButton(CanvasItem.setVisible(true)), scene)

    pub def hideStartButton(scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(startButtonPath(),
            EngineNode.mapButton(CanvasItem.setVisible(false)), scene)

    pub def isStartButtonVisible(scene: Scene[NodeTag]): Bool =
        match Scene.getEngineNode(startButtonPath(), scene) {
            case Some(EngineNode.ButtonWithState(btn, _)) => CanvasItem.isVisible(btn)
            case _                                          => false
        }

    // ── タイマー制御 ──

    pub def startMessageTimer(scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(messageTimerPath(),
            EngineNode.mapTimer(Timer.start), scene)

    pub def startTitleTimer(scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(titleTimerPath(),
            EngineNode.mapTimer(Timer.start), scene)

    // ── フェーズ別エントリ ──

    /// Menu 状態への遷移: スコアラベル非表示・タイトル + ボタン表示
    pub def enterMenu(scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
            |> showMessage("Dodge the\nCreeps")
            |> showStartButton
            |> updateScore(0)
}
