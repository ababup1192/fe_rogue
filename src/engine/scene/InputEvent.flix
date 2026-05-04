/// キー・マウス入力イベントの検出と応答（合成イベント方式）
///
/// ButtonEvent / TimerEvent パターンに倣い、InputHandler トレイトで
/// キー押下/離脱、マウスボタン押下/離脱、マウス移動のイベント駆動を実現する。
///
/// GLFW のコールバックは使わず、毎フレーム現在の入力状態を取得し、
/// 前フレーム（Scene の prev*）との差分から押下/離脱・移動を合成する。
/// 1 フレーム内に押して離されたキー/ボタンは取りこぼすが、通常の操作では実用上問題ない。
///
/// Godot の `_input(event)` 準拠で、キーとマウスの両方を 1 つのトレイトで扱う。
///
/// 使い方:
///   1. InputHandler[s] を実装し必要なコールバックを記述
///   2. handleInput(scene) または GameEngine.handleInput をゲームループで呼び出す

pub mod InputEvent {

    /// キー・マウス入力イベントに応答するトレイト
    /// 関連エフェクト Aef により、インスタンスごとに必要なエフェクトを宣言できる。
    /// 例: 効果音を鳴らす場合は `type Aef = { GameEngine.Audio }`、
    ///      純粋な場合は `type Aef = {}` とする。
    pub trait InputHandler[s] {

        /// 入力応答で発生するエフェクト
        type Aef: Eff

        /// キーがこのフレームで新たに押されたとき呼ばれる。
        /// 押しっぱなしのキーは（押された最初のフレームのみ）1 度だけ発火する。
        pub def onKeyPressed(_key: GameEngine.Key, scene: Scene[s]): Scene[s] \ InputHandler.Aef[s] =
            checked_ecast(scene)

        /// キーがこのフレームで離されたとき呼ばれる。
        pub def onKeyReleased(_key: GameEngine.Key, scene: Scene[s]): Scene[s] \ InputHandler.Aef[s] =
            checked_ecast(scene)

        /// マウスボタンがこのフレームで新たに押されたとき呼ばれる。
        /// position は押された瞬間のマウス座標。
        pub def onMouseButtonPressed(_button: GameEngine.MouseButton,
                                     _position: Vec2.Vec2,
                                     scene: Scene[s]): Scene[s] \ InputHandler.Aef[s] =
            checked_ecast(scene)

        /// マウスボタンがこのフレームで離されたとき呼ばれる。
        pub def onMouseButtonReleased(_button: GameEngine.MouseButton,
                                      _position: Vec2.Vec2,
                                      scene: Scene[s]): Scene[s] \ InputHandler.Aef[s] =
            checked_ecast(scene)

        /// マウスがこのフレームで移動したとき呼ばれる。
        /// relative は前フレーム位置からの差分（current - prev）。
        /// 初回フレーム（前フレーム位置が無い場合）は発火しない。
        pub def onMouseMotion(_position: Vec2.Vec2,
                              _relative: Vec2.Vec2,
                              scene: Scene[s]): Scene[s] \ InputHandler.Aef[s] =
            checked_ecast(scene)
    }

    /// 現在押されているキーのセットを取得する（GameEngine.allKeys() を全て走査）
    pub def currentKeys(): Set[GameEngine.Key] \ GameEngine.Game =
        List.foldLeft((acc, key) ->
            if (GameEngine.Game.isKeyPressed(key)) Set.insert(key, acc)
            else acc,
            Set.empty(),
            GameEngine.allKeys())

    /// 現在押されているマウスボタンのセットを取得する
    pub def currentMouseButtons(): Set[GameEngine.MouseButton] \ GameEngine.Game =
        List.foldLeft((acc, btn) ->
            if (GameEngine.Game.isMouseButtonPressed(btn)) Set.insert(btn, acc)
            else acc,
            Set.empty(),
            GameEngine.allMouseButtons())

    /// 入力差分を検出し、InputHandler の各コールバックを発火する。
    /// 1. 現在のキー/マウスボタン状態とマウス位置を取得
    /// 2. Scene の prev* との差分でキー・マウスボタンの押下/離脱イベントを発火
    /// 3. マウス位置が変化していれば onMouseMotion を発火
    /// 4. Scene の prev* を現在の状態に更新して返す
    pub def handleInput(scene: Scene[s]): Scene[s] \ {GameEngine.Game, InputHandler.Aef[s]} with InputHandler[s] =
        let prevKeys = Scene.getPrevKeyState(scene);
        let currentK = currentKeys();
        let keysPressed = Set.difference(currentK, prevKeys);
        let keysReleased = Set.difference(prevKeys, currentK);

        let prevButtons = Scene.getPrevMouseButtonState(scene);
        let currentB = currentMouseButtons();
        let buttonsPressed = Set.difference(currentB, prevButtons);
        let buttonsReleased = Set.difference(prevButtons, currentB);

        let currentPos = GameEngine.Game.getMousePosition();
        let prevPosOpt = Scene.getPrevMousePosition(scene);

        let s1 = Set.foldLeft((sc, key) ->
            InputHandler.onKeyPressed(key, sc),
            scene, keysPressed);
        let s2 = Set.foldLeft((sc, key) ->
            InputHandler.onKeyReleased(key, sc),
            s1, keysReleased);
        let s3 = Set.foldLeft((sc, btn) ->
            InputHandler.onMouseButtonPressed(btn, currentPos, sc),
            s2, buttonsPressed);
        let s4 = Set.foldLeft((sc, btn) ->
            InputHandler.onMouseButtonReleased(btn, currentPos, sc),
            s3, buttonsReleased);
        let s5 = match prevPosOpt {
            case Some(prevPos) =>
                if (prevPos#x == currentPos#x and prevPos#y == currentPos#y) s4
                else
                    let relative = Vec2.sub(currentPos, prevPos);
                    InputHandler.onMouseMotion(currentPos, relative, s4)
            case None => s4
        };

        s5
            |> Scene.setPrevKeyState(currentK)
            |> Scene.setPrevMouseButtonState(currentB)
            |> Scene.setPrevMousePosition(Some(currentPos))
}
