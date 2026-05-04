/// 画面内外検出とハンドラ発火（Godot VisibleOnScreenNotifier2D シグナル準拠）
///
/// ScreenNotifier2DWithState 子ノードを持つ親ノードを自動検出し、
/// 画面外に出たときに onScreenExited、画面内に入ったときに onScreenEntered を発火する。
///
/// AreaEvent パターンを踏襲し、Scene 内の prevOnScreen を使ってフレーム間の状態遷移を検出する。
///
///   フレーム N:   Mob は画面内 → prevOnScreen に登録
///   フレーム N+1: Mob は画面外 → prevOnScreen にあるので onScreenExited 発火
///
///   フレーム N:   Mob は画面外 → prevOnScreen に未登録
///   フレーム N+1: Mob は画面内 → prevOnScreen になかったので onScreenEntered 発火

pub mod ScreenNotifyEvent {

    /// 画面内外通知トレイト（VisibleOnScreenNotifier2D のコールバック）
    ///
    /// ScreenNotifier2DWithState 子ノードの存在で自動検出される。
    /// ゲーム固有の状態 s を受け取り、Godot の screen_entered / screen_exited シグナル相当を実現する。
    ///
    /// 使い方:
    ///   1. 親ノードに ScreenNotifier2DWithState 子ノードを追加
    ///   2. onScreenExited / onScreenEntered で画面外・画面内に遷移したときの処理を定義
    ///   3. ScreenNotifyEvent.handleScreenTransitions がフレーム毎に自動発火
    pub trait ScreenNotifyHandler[s] {

        /// ノードが画面外に出たとき呼ばれる（Godot screen_exited 相当）。
        /// Scene を書き換えて返す。
        ///
        /// path: ノードのパス（親ノードのパス）
        /// state: ノードのゲーム状態
        /// scene: 現在のシーン
        pub def onScreenExited(
            _path: NodePath,
            _state: s,
            scene: Scene[s]
        ): Scene[s] = scene

        /// ノードが画面内に入ったとき呼ばれる（Godot screen_entered 相当）。
        /// Scene を書き換えて返す。
        ///
        /// path: ノードのパス（親ノードのパス）
        /// state: ノードのゲーム状態
        /// scene: 現在のシーン
        pub def onScreenEntered(
            _path: NodePath,
            _state: s,
            scene: Scene[s]
        ): Scene[s] = scene
    }

    /// パスの親パスを返す（末尾要素を除去）
    def parentPath(path: NodePath): NodePath =
        match List.reverse(path) {
            case Nil => Nil
            case _ :: rest => List.reverse(rest)
        }

    /// Scene 内の ScreenNotifier2DWithState 子ノードを検出し、
    /// その親ノードの画面内外を判定する。
    /// 前フレームとの差分から onScreenExited / onScreenEntered を発火する。
    ///
    /// prevOnScreen を更新して返す。
    pub def handleScreenTransitions(
            screenWidth: {screenWidth = Int32},
            screenHeight: {screenHeight = Int32},
            scene: Scene[s]): Scene[s] with ScreenNotifyHandler[s] =
        let prevOnScreen = Scene.getPrevOnScreen(scene);
        let paths = Scene.preorderPaths(scene);
        // Step 1: ScreenNotifier2DWithState 子ノードを検出し、親の画面内外を判定
        let currentOnScreen = List.foldLeft((acc, path) ->
            match Scene.getEngineNode(path, scene) {
                case Some(EngineNode.ScreenNotifier2DWithState(notifier, _)) =>
                    let pp = parentPath(path);
                    let pos = Scene.globalPositionAt(pp, scene);
                    if (VisibleOnScreenNotifier2D.isOnScreen(
                            pos, notifier, screenWidth, screenHeight))
                        Set.insert(pp, acc)
                    else
                        acc
                case _ => acc
            },
            Set.empty(),
            paths);
        // Step 2: 前フレーム画面内 → 今フレーム画面外の親ノードに onScreenExited を発火
        let exitedPaths = Set.difference(prevOnScreen, currentOnScreen);
        let sceneAfterExited = Set.foldLeft((sc, path) ->
            match Scene.getState(path, sc) {
                case Some(state) =>
                    ScreenNotifyHandler.onScreenExited(path, state, sc)
                case None => sc
            },
            scene,
            exitedPaths);
        // Step 3: 前フレーム画面外 → 今フレーム画面内の親ノードに onScreenEntered を発火
        let enteredPaths = Set.difference(currentOnScreen, prevOnScreen);
        let sceneAfterEntered = Set.foldLeft((sc, path) ->
            match Scene.getState(path, sc) {
                case Some(state) =>
                    ScreenNotifyHandler.onScreenEntered(path, state, sc)
                case None => sc
            },
            sceneAfterExited,
            enteredPaths);
        Scene.setPrevOnScreen(currentOnScreen, sceneAfterEntered)
}
