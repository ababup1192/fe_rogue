// Editor — シーン上のノードをマウスで選択・ドラッグ移動して JSON に書き戻すミニエディタ
//
// 公開ファサード。Game.flix への差し込みは最小限で、
//   - `run { gameLoop(...) } with Editor.withState(rc)` で Ref / handler / HotReload watcher を一括下準備
//   - gameLoop の毎フレームで Editor.handleInput / Editor.pollReload / Editor.applyOverlay を呼ぶ
// だけで動く。実装本体は SceneJsonIndex / EditableNode / Picking / DragInput /
// Overlay / SceneSerializer のサブモジュールに分割されている。
//
// 動作概要:
//   - F1 でエディタ ON/OFF
//   - ON 時にシーンを走査し、Sprite2D / AnimatedSprite2D / TextureButton / Label2D を
//     編集対象として認識する
//   - 左クリックで対象ノードを選択（黄色の矩形で囲む）
//   - ドラッグで pos 変更（シーン上は即時更新、ドロップ時に JSON 書き戻し）
//   - HotReload watcher が JSON 変更を拾って次フレームでシーン再構築

mod Editor {

    /// エディタの状態を保持するエフェクト。withState ハンドラが Ref と
    /// HotReload watcher の Receiver を closure で握って実装する
    pub eff EditorState {
        def get(): EditorStateData
        def put(stateData: EditorStateData): Unit
        def pollReload(): Bool
    }

    /// リサイズハンドルドラッグ中に保持する、対象ノードのドラッグ開始時スナップショット。
    /// scale や bbox の更新は「開始時の値 × 倍率」で計算するため、開始値を凍結しておく
    pub type alias ResizeOrigin = {
        handle = ResizeHandle.Handle,
        boxTopLeftScreen = Vec2.Vec2,    // ドラッグ開始時の bbox 左上（screen 座標）
        boxSize = Vec2.Vec2,             // ドラッグ開始時の bbox 表示サイズ
        scale = Vec2.Vec2,               // ドラッグ開始時のノードの scale
        worldPos = Vec2.Vec2,            // ドラッグ開始時のノード global 座標
        topLeftOffset = Vec2.Vec2        // 中央寄せ補正分（centered=true なら -size/2 など）
    }

    /// エディタ状態の record 表現
    /// on:             エディタモード ON / OFF
    /// selected:       現在選択中のノード（編集対象 JSON のパスとシーン内の NodePath）
    /// dragOrigin:     ドラッグ開始時のマウス座標（None ならドラッグ中ではない）
    /// nodeOrigin:     ドラッグ開始時のノードのグローバル座標
    /// resizeOrigin:   リサイズハンドルドラッグ中の開始時スナップショット
    /// prevF1:         前フレームの F1 押下状態（エッジ検出用）
    /// prevMouseLeft:  前フレームのマウス左ボタン押下状態（エッジ検出用）
    /// prevArrowKeys:  前フレームの矢印キー押下状態（KeyboardNudge のエッジ検出用）
    /// prevZ:          前フレームの Z 押下状態（Cmd+Z エッジ検出用）
    /// rootJsonIndex:  「シーンのルートノード名 → 由来する scene.json ファイルパス」の
    ///                 索引。Game.start で loadJsonRootIndex() の結果を入れる
    pub type alias EditorStateData = {
        on = Bool,
        selected = Option[(String, NodePath)],
        dragOrigin = Option[Vec2.Vec2],
        nodeOrigin = Option[Vec2.Vec2],
        resizeOrigin = Option[ResizeOrigin],
        prevF1 = Bool,
        prevMouseLeft = Bool,
        prevArrowKeys = KeyboardNudge.ArrowKeys,
        prevZ = Bool,
        rootJsonIndex = Map[NodeName, String]
    }

    /// エディタ状態の初期値。rootJsonIndex は呼び出し側で別途与える
    pub def initialState(rootJsonIndex: Map[NodeName, String]): EditorStateData = {
        on = false,
        selected = None,
        dragOrigin = None,
        nodeOrigin = None,
        resizeOrigin = None,
        prevF1 = false,
        prevMouseLeft = false,
        prevArrowKeys = KeyboardNudge.initialPrev(),
        prevZ = false,
        rootJsonIndex = rootJsonIndex
    }

    /// エディタが現在 ON かどうかを返す。gameLoop からゲーム更新を止めるか判断するのに使う
    pub def isOn(): Bool \ EditorState = (EditorState.get())#on

    /// scene.json ルート索引を構築する。Game.start から 1 回だけ呼ぶ
    pub def loadJsonRootIndex(): Map[NodeName, String] \ {Fs.Glob, Fs.FileRead} =
        SceneJsonIndex.load()

    /// エディタ状態の Ref と HotReload watcher を一括して下準備し、
    /// EditorState ハンドラを掛けた状態で thunk を実行する。
    /// Game.start からはこの関数 1 つを `run { ... } with Editor.withState(rc)` の形で
    /// 使うだけでビジュアルエディタが使える。watcher の Receiver はハンドラが内部に
    /// 隠して持つので、gameLoop からは Editor.pollReload() で消費する。
    pub def withState(rc: Region[r]):
            (Unit -> Unit \ ef) -> Unit \ (ef - EditorState - EditHistory.Rewind) + r +
                                          Fs.Glob + Fs.FileRead + Chan + NonDet + IO +
                                          Fs.ModificationTime =
        thunk -> {
            let editorIndex = loadJsonRootIndex();
            let editorRef: Ref[EditorStateData, r] = Ref.fresh(rc, initialState(editorIndex));
            let historyRef: Ref[List[EditHistory.Entry], r] = Ref.fresh(rc, Nil);
            let reloadRx = HotReload.startWatcher();
            run {
                thunk()
            } with handler EditorState {
                def get(k) = k(Ref.get(editorRef))
                def put(stateData, k) = { Ref.put(stateData, editorRef); k() }
                def pollReload(k) = k(HotReload.pollReload(reloadRx))
            } with handler EditHistory.Rewind {
                def save(entry, k) = {
                    Ref.put(entry :: Ref.get(historyRef), historyRef);
                    k(())
                }
                def rewind(k) = match Ref.get(historyRef) {
                    case Nil          => k(None)
                    case top :: rest =>
                        Ref.put(rest, historyRef);
                        k(Some(top))
                }
            }
        }

    /// 入力処理を行いシーンを更新する。Game.flix の gameLoop から毎フレーム呼ぶ。
    /// 副作用: EditorState を読み書き、JSON を読み書き、マウス・キー入力を読む
    pub def handleInput(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {EditorState, EditHistory.Rewind, GameEngine.Game,
                              Fs.FileRead, Fs.FileWrite} =
        let stateData = EditorState.get();
        let f1 = GameEngine.Game.isKeyPressed(GameEngine.Key.F1);
        let mouseLeft = GameEngine.Game.isMouseButtonPressed(GameEngine.MouseButton.Left);
        let mousePos = GameEngine.Game.getMousePosition();
        let curArrows = KeyboardNudge.readArrows();
        let zNow = GameEngine.Game.isKeyPressed(GameEngine.Key.Z);
        let cmdNow = GameEngine.Game.isKeyPressed(GameEngine.Key.LeftSuper);
        let ctrlNow = GameEngine.Game.isKeyPressed(GameEngine.Key.LeftCtrl);
        // Cmd+Z / Ctrl+Z のエッジ検出。
        // macOS GLFW は Cmd 押下中に Z の状態を更新しないことがあるため Ctrl もフォールバックで拾う
        let undoTriggered = (cmdNow or ctrlNow) and zNow and not stateData#prevZ;
        // F1 のエッジ検出: 前フレーム未押下 → 今フレーム押下 でトグル
        let toggledOn = if (f1 and not stateData#prevF1) not stateData#on else stateData#on;
        // OFF へ倒れたフレームは選択 / ドラッグ状態をクリアする。
        // ON 中（または ON のまま）は既存の選択 / ドラッグ状態を維持
        let stateAfterToggle = if (toggledOn)
            {on = true, prevF1 = f1 | stateData}
        else
            {on = false, selected = None, dragOrigin = None, nodeOrigin = None,
             resizeOrigin = None, prevF1 = f1 | stateData};
        if (not toggledOn) {
            // エディタ OFF へ倒れた / 元から OFF のフレームではカーソルを通常に戻す
            GameEngine.Game.setCursor(GameEngine.Cursor.Default);
            EditorState.put({prevMouseLeft = mouseLeft,
                             prevArrowKeys = curArrows,
                             prevZ = zNow | stateAfterToggle});
            scene
        } else {
            // エディタ ON 時のマウス処理。カメラ追従中のノード（bird など）も
            // 正しく当たり判定できるよう cameraOffset を計算して渡す
            let cameraOffset = activeCameraOffset(scene);
            let mouse = {pos = mousePos, leftDown = mouseLeft};
            let (afterMouseState, afterMouseScene) =
                DragInput.handleMouse(mouse, cameraOffset, stateAfterToggle, scene);
            // ドラッグ中でなければ矢印キーで微調整できる
            let nudgedScene = if (Option.isEmpty(afterMouseState#dragOrigin))
                KeyboardNudge.applyNudge(afterMouseState, curArrows, afterMouseScene)
            else
                afterMouseScene;
            // Cmd+Z で直近の編集を巻き戻す（ドラッグ中は触らない）
            let finalScene = if (undoTriggered and Option.isEmpty(afterMouseState#dragOrigin))
                applyUndo(nudgedScene)
            else
                nudgedScene;
            // ハンドル hover / リサイズ中ならリサイズ用カーソル、それ以外は通常カーソル
            updateCursor(mousePos, cameraOffset, afterMouseState, finalScene);
            EditorState.put({prevMouseLeft = mouseLeft,
                             prevArrowKeys = curArrows,
                             prevZ = zNow | afterMouseState});
            finalScene
        }

    /// 現在のリサイズ状態またはマウス hover に応じてカーソル形状を更新する。
    /// 優先順位: リサイズドラッグ中 > 選択ノードのハンドル hover > Default
    def updateCursor(mousePos: Vec2.Vec2, cameraOffset: Vec2.Vec2,
                     stateData: EditorStateData,
                     scene: Scene[NodeTag]): Unit \ {GameEngine.Game} =
        let cursor = match stateData#resizeOrigin {
            case Some(origin) => cursorForHandle(origin#handle)
            case None         => hoverCursor(mousePos, cameraOffset, stateData, scene)
        };
        GameEngine.Game.setCursor(cursor)

    /// 選択中ノードのハンドル領域に hover していればそのハンドル用カーソル、
    /// 外していれば Default を返す
    def hoverCursor(mousePos: Vec2.Vec2, cameraOffset: Vec2.Vec2,
                    stateData: EditorStateData,
                    scene: Scene[NodeTag]): GameEngine.Cursor \ GameEngine.Game =
        match stateData#selected {
            case None => GameEngine.Cursor.Default
            case Some((_, nodePath)) =>
                let ctx = {rootJsonIndex = stateData#rootJsonIndex, scene = scene};
                match EditableNode.findByNodePath(ctx, nodePath) {
                    case None => GameEngine.Cursor.Default
                    case Some(entry) =>
                        let refPos = Scene.screenPositionAt(nodePath, cameraOffset, scene);
                        let topLeft = Vec2.add(refPos, entry#topLeftOffset);
                        let box = {topLeft = topLeft,
                                   size = {x = entry#width, y = entry#height}};
                        match ResizeHandle.hitTest(mousePos, box) {
                            case None         => GameEngine.Cursor.Default
                            case Some(handle) => cursorForHandle(handle)
                        }
                }
        }

    /// ハンドル方向に対応するカーソル形状を返す。
    /// GLFW 3.3 系には対角リサイズカーソルがないので、4 隅は AllResize（CROSSHAIR）で代用
    def cursorForHandle(handle: ResizeHandle.Handle): GameEngine.Cursor =
        match handle {
            case ResizeHandle.Handle.Top         => GameEngine.Cursor.VResize
            case ResizeHandle.Handle.Bottom      => GameEngine.Cursor.VResize
            case ResizeHandle.Handle.Left        => GameEngine.Cursor.HResize
            case ResizeHandle.Handle.Right       => GameEngine.Cursor.HResize
            case ResizeHandle.Handle.TopLeft     => GameEngine.Cursor.AllResize
            case ResizeHandle.Handle.TopRight    => GameEngine.Cursor.AllResize
            case ResizeHandle.Handle.BottomLeft  => GameEngine.Cursor.AllResize
            case ResizeHandle.Handle.BottomRight => GameEngine.Cursor.AllResize
        }

    /// Rewind から 1 件取り出してノードを記録された状態（位置 / スケール）に戻し、
    /// JSON にも書き戻す。履歴に何もなければ scene 不変
    def applyUndo(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {EditHistory.Rewind, Fs.FileRead, Fs.FileWrite} =
        match EditHistory.Rewind.rewind() {
            case None => scene
            case Some(EditHistory.Entry.MoveEntry(entry)) =>
                let restored = Scene.setGlobalPositionAt(
                    entry#nodePath, entry#prevWorldPos, scene);
                // 復元位置を JSON にも書き戻す（ここでは save しない = stack に積まない）
                let localPos = match Scene.getEngineNode(entry#nodePath, restored) {
                    case Some(engineNode) => Node2D.getPosition(engineNode)
                    case None             => Vec2.zero()
                };
                SceneSerializer.updatePos(entry#jsonPath, entry#nodePath, localPos);
                restored
            case Some(EditHistory.Entry.ScaleEntry(entry)) =>
                // スケール復元 → 位置復元 の順。位置はローカル座標を再計算するため
                // scale 復元後のシーンを基準にする（centered=true なら親座標は無依存だが、
                // CanvasLayer 配下のオフセット計算に影響しないよう順序を固定する）
                let scaled = Scene.mapEngineNode(entry#nodePath,
                    Node2D.setScale(entry#prevScale), scene);
                let restored = Scene.setGlobalPositionAt(
                    entry#nodePath, entry#prevWorldPos, scaled);
                let localPos = match Scene.getEngineNode(entry#nodePath, restored) {
                    case Some(engineNode) => Node2D.getPosition(engineNode)
                    case None             => Vec2.zero()
                };
                SceneSerializer.updatePosAndScale(entry#jsonPath, entry#nodePath,
                                                   localPos, entry#prevScale);
                restored
        }

    /// 現在のシーンの有効カメラからビューポートオフセットを計算する。
    /// カメラがなければゼロ（CanvasLayer のみのシーン等）
    def activeCameraOffset(scene: Scene[NodeTag]): Vec2.Vec2 \ GameEngine.Game =
        match Scene.findActiveCamera(scene) {
            case Some(cam) =>
                let vp = GameEngine.Game.getViewportRect();
                Camera2D.getViewportOffset(cam,
                    {viewportWidth = vp#size#x, viewportHeight = vp#size#y})
            case None => Vec2.zero()
        }

    /// HotReload watcher の通知をノンブロッキングで消費する。
    /// withState ハンドラが内部で抱えている Receiver から 1 件取ったかどうかを返す
    pub def pollReload(): Bool \ EditorState =
        EditorState.pollReload()

    /// 描画用のオーバーレイをシーンに合成する。Game.flix の render 直前に呼ぶ。
    /// 戻り値の Scene は次フレームに引き継がない（一回限りの描画用）。
    /// エディタ OFF のときは何もせず scene をそのまま返す
    pub def applyOverlay(fontAtlas: FontAtlas, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {EditorState, GameEngine.Game} =
        let stateData = EditorState.get();
        if (not stateData#on) scene
        else {
            let mousePos = GameEngine.Game.getMousePosition();
            let cameraOffset = activeCameraOffset(scene);
            scene
                |> Overlay.addCollisionShapes(cameraOffset)
                |> Overlay.addEditorIndicator(fontAtlas)
                |> Overlay.addSelectionBox(stateData#rootJsonIndex, stateData#selected,
                                           cameraOffset)
                |> Overlay.addHoverBox(stateData#rootJsonIndex, mousePos, stateData#selected,
                                       cameraOffset)
        }
}
