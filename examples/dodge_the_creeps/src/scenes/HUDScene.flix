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

    /// HUD のフォントサイズ
    def scoreFontSize(): Float64 = 60.0
    def messageFontSize(): Float64 = 40.0
    def buttonFontSize(): Float64 = 30.0

    /// スタートボタンの大きさ
    def startButtonSize(): Vec2.Vec2 = {x = 200.0, y = 60.0}

    // ── 構築 ──

    pub def addHUD(fontAtlas: FontAtlas, scene: Scene[NodeTag]): Scene[NodeTag] =
        let layer = CanvasLayer.make(1);
        let centerX = Int32.toFloat64(Game.designWi()) / 2.0;
        let centerY = Int32.toFloat64(Game.designHi()) / 2.0;
        // score: 画面上部中央。position を中心アンカーにするため Center 揃え
        let score = Label2D.make("0", fontAtlas, scoreFontSize())
            |> Label2D.setHorizontalAlignment(HorizontalAlignment.Center)
            |> Node2D.setPosition({x = centerX, y = 80.0});
        // message: 画面中央
        let message = Label2D.make("", fontAtlas, messageFontSize())
            |> Label2D.setHorizontalAlignment(HorizontalAlignment.Center)
            |> Label2D.setVerticalAlignment(VerticalAlignment.Center)
            |> Node2D.setPosition({x = centerX, y = centerY - 40.0})
            |> CanvasItem.setVisible(false);
        // start button: 画面中央 (Button は左上 anchor なので半幅ぶん戻す)
        let btnSize = startButtonSize();
        let startBtn = Button.make("Start", fontAtlas, buttonFontSize(), btnSize)
            |> Node2D.setPosition({x = centerX - btnSize#x / 2.0,
                                    y = centerY + 40.0})
            |> CanvasItem.setVisible(false);
        let messageTimer = Timer.make(Duration.seconds(2.0))
            |> Timer.setOneShot(true);
        let titleTimer = Timer.make(Duration.seconds(1.0))
            |> Timer.setOneShot(true);
        scene
            |> Scene.addNode(hudName(),
                EngineNode.CanvasLayerWithState(layer, NodeTag.NoTag))
            |> Scene.addChild(hudName(), scoreLabelName(),
                EngineNode.Label2DWithState(score, NodeTag.ScoreLabel(0)))
            |> Scene.addChild(hudName(), messageLabelName(),
                EngineNode.Label2DWithState(message, NodeTag.MessageLabel))
            |> Scene.addChild(hudName(), startButtonName(),
                EngineNode.ButtonWithState(startBtn, NodeTag.StartButton))
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
