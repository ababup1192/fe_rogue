/// タイマータイムアウトイベントの検出と応答（Godot Timer.timeout シグナル準拠）
///
/// AreaEvent / AreaHandler パターンに倣い、TimerHandler トレイトで
/// タイムアウト時のイベント駆動を実現する。
///
/// 使い方:
///   1. TimerHandler[s] を実装し onTimeout でタイムアウト応答を記述
///   2. handleTimeouts(scene) をゲームループで呼び出す

pub mod TimerEvent {

    /// タイマータイムアウトに応答するトレイト
    pub trait TimerHandler[s] {
        /// タイマーがタイムアウトしたとき呼ばれる。
        /// timerPath: タイマーノードのパス
        /// state: タイマーノードのゲーム状態
        /// scene: 現在のシーン
        pub def onTimeout(_timerPath: NodePath, _state: s, scene: Scene[s]): Scene[s] \ Math.Random =
            checked_ecast(scene)
    }

    /// timedOut=true の TimerWithState ノードパスを収集する
    pub def detectTimeoutPaths(scene: Scene[s]): List[NodePath] =
        let paths = Scene.preorderPaths(scene);
        List.filterMap(path ->
            match Scene.getEngineNode(path, scene) {
                case Some(EngineNode.TimerWithState(timer, _)) =>
                    if (Timer.isTimedOut(timer)) Some(path)
                    else None
                case _ => None
            }, paths)

    /// タイムアウトを処理し、フラグをクリアする
    /// 1. detectTimeoutPaths で対象パスを収集
    /// 2. 各パスに対して TimerHandler.onTimeout を呼び出し
    /// 3. 各パスの Timer.clearTimedOut を呼び出してフラグをリセット
    pub def handleTimeouts(scene: Scene[s]): Scene[s] \ Math.Random with TimerHandler[s] =
        let timedOutPaths = detectTimeoutPaths(scene);
        // onTimeout を呼び出し
        let sceneAfterHandlers = List.foldLeft((sc, path) ->
            match Scene.getState(path, sc) {
                case Some(state) => TimerHandler.onTimeout(path, state, sc)
                case None => sc
            },
            scene,
            timedOutPaths);
        // timedOut フラグをクリア
        List.foldLeft((sc, path) ->
            Scene.mapEngineNode(path, EngineNode.mapTimer(Timer.clearTimedOut), sc),
            sceneAfterHandlers,
            timedOutPaths)
}
