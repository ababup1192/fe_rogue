/// ボタンプレスイベントの検出と応答（TimerEvent パターン準拠）
///
/// ButtonHandler トレイトでボタンプレス時のイベント駆動を実現する。
///
/// 使い方:
///   1. ButtonHandler[s] を実装し onButtonPressed でプレス応答を記述
///   2. handleButtons(scene) をゲームループで呼び出す

pub mod ButtonEvent {

    /// ボタンプレスに応答するトレイト
    /// 関連エフェクト Aef により、インスタンスごとに必要なエフェクトを宣言できる。
    pub trait ButtonHandler[s] {

        /// ボタン応答で発生するエフェクト
        type Aef: Eff

        /// ボタンが押されたとき呼ばれる。
        /// buttonPath: ボタンノードのパス
        /// state: ボタンノードのゲーム状態
        /// scene: 現在のシーン
        pub def onButtonPressed(_buttonPath: NodePath, _state: s, scene: Scene[s]): Scene[s] \ ButtonHandler.Aef[s] =
            checked_ecast(scene)
    }

    /// マウス状態を全 ButtonWithState / TextureButtonWithState に反映する
    pub def updateButtons(scene: Scene[s]): Scene[s] \ GameEngine.Game =
        let mousePos = GameEngine.Game.getMousePosition();
        let mousePressed = GameEngine.Game.isMouseButtonPressed(GameEngine.MouseButton.Left);
        let paths = Scene.preorderPaths(scene);
        List.foldLeft((sc, path) ->
            match Scene.getEngineNode(path, sc) {
                case Some(EngineNode.ButtonWithState(btn, _)) =>
                    if (not CanvasItem.isVisible(btn)) sc
                    else {
                        let globalPos = Scene.globalPositionAt(path, sc);
                        let newBtn = Button.updateInteraction(mousePos, mousePressed, globalPos, btn);
                        Scene.mapEngineNode(path, EngineNode.mapButton(_ -> newBtn), sc)
                    }
                case Some(EngineNode.TextureButtonWithState(btn, _)) =>
                    if (not CanvasItem.isVisible(btn)) sc
                    else {
                        let globalPos = Scene.globalPositionAt(path, sc);
                        let newBtn = TextureButton.updateInteraction(mousePos, mousePressed, globalPos, btn);
                        Scene.mapEngineNode(path, EngineNode.mapTextureButton(_ -> newBtn), sc)
                    }
                case _ => sc
            },
            scene,
            paths)

    /// justPressed=true のボタンノードパスを収集する（Button / TextureButton 両対応）
    pub def detectPressedPaths(scene: Scene[s]): List[NodePath] =
        let paths = Scene.preorderPaths(scene);
        List.filterMap(path ->
            match Scene.getEngineNode(path, scene) {
                case Some(EngineNode.ButtonWithState(btn, _)) =>
                    if (Button.isJustPressed(btn)) Some(path)
                    else None
                case Some(EngineNode.TextureButtonWithState(btn, _)) =>
                    if (TextureButton.isJustPressed(btn)) Some(path)
                    else None
                case _ => None
            }, paths)

    /// justPressed フラグをクリアする（Button / TextureButton 両対応）
    def clearJustPressed(paths: List[NodePath], scene: Scene[s]): Scene[s] =
        List.foldLeft((sc, path) ->
            match Scene.getEngineNode(path, sc) {
                case Some(EngineNode.ButtonWithState(_, _)) =>
                    Scene.mapEngineNode(path, EngineNode.mapButton(Button.clearJustPressed), sc)
                case Some(EngineNode.TextureButtonWithState(_, _)) =>
                    Scene.mapEngineNode(path, EngineNode.mapTextureButton(TextureButton.clearJustPressed), sc)
                case _ => sc
            },
            scene,
            paths)

    /// ボタンイベントを処理する
    /// 1. updateButtons でマウス状態を反映
    /// 2. detectPressedPaths で justPressed を収集
    /// 3. onButtonPressed を呼び出し
    /// 4. clearJustPressed でフラグをリセット
    pub def handleButtons(scene: Scene[s]): Scene[s] \ {GameEngine.Game, ButtonHandler.Aef[s]}
            with ButtonHandler[s] =
        let sceneAfterUpdate = updateButtons(scene);
        let pressedPaths = detectPressedPaths(sceneAfterUpdate);
        let sceneAfterHandlers = List.foldLeft((sc, path) ->
            match Scene.getState(path, sc) {
                case Some(state) => ButtonHandler.onButtonPressed(path, state, sc)
                case None => sc
            },
            sceneAfterUpdate,
            pressedPaths);
        clearJustPressed(pressedPaths, sceneAfterHandlers)
}
