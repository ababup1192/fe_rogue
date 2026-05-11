// Editor — シーン上のノードをマウスで選択・ドラッグ移動して JSON に書き戻すミニエディタ
//
// 公開ファサード。Game.flix への差し込みは最小限で、
//   - `run { gameLoop(...) } with Editor.withState(rc)` で Ref / handler / HotReload watcher を一括下準備
//   - gameLoop の毎フレームで Editor.handleInput / Editor.pollReload / Editor.applyOverlay を呼ぶ
// だけで動く。実装本体は SceneJsonIndex / EditableNode / Picking / DragInput /
// Overlay / SceneSerializer / KeyboardNudge / EditHistory のサブモジュールに分割されている。
//
// 動作概要:
//   - F1 でエディタ ON/OFF
//   - ON 時にシーンを走査し、Sprite2D / AnimatedSprite2D / TextureButton / Label2D / ColorRect を
//     編集対象として認識する
//   - 左クリックで対象ノードを選択（黄色の矩形で囲む）
//   - ドラッグで pos 変更（シーン上は即時更新、ドロップ時に JSON 書き戻し）
//   - リサイズハンドル（4 隅 + 4 辺）で scale 変更
//   - 矢印キーで 1px 微調整、Shift で 10px、Ctrl+Shift で scale ±0.1
//   - Cmd+Z / Ctrl+Z で直近編集を undo
//   - HotReload watcher が JSON 変更を拾って次フレームでシーン再構築

mod Editor {

    /// エディタの状態を保持するエフェクト。
    pub eff EditorState {
        def get(): EditorStateData
        def put(stateData: EditorStateData): Unit
        def pollReload(): Bool
    }

    /// リサイズハンドルドラッグ中に保持する、対象ノードのドラッグ開始時スナップショット。
    /// `nodeSnapshot`: 対象ノード（CanvasLayer の場合は CanvasLayer 自身）の開始状態。
    /// `childSnapshots`: CanvasLayer の cascade 用に直接の子の開始状態を全て保存。
    ///                   非 CanvasLayer のときは Nil。undo ですべて巻き戻すため
    pub type alias ResizeOrigin = {
        handle = ResizeHandle.Handle,
        boxTopLeftScreen = Vec2.Vec2,
        boxSize = Vec2.Vec2,
        topLeftOffset = Vec2.Vec2,
        nodeSnapshot = EditableNode.NodeResizeSnapshot,
        childSnapshots = List[EditableNode.NodeResizeSnapshot]
    }

    /// 回転ハンドルドラッグ中に保持する開始時スナップショット。
    pub type alias RotateOrigin = {
        centerScreen = Vec2.Vec2,
        startMouseAngle = Float64,
        startRotation = Float64,
        nodePath = NodePath,
        jsonPath = String
    }

    /// エディタ状態の record 表現
    pub type alias EditorStateData = {
        on = Bool,
        selected = Option[(String, NodePath)],
        dragOrigin = Option[Vec2.Vec2],
        nodeOrigin = Option[Vec2.Vec2],
        resizeOrigin = Option[ResizeOrigin],
        rotateOrigin = Option[RotateOrigin],
        prevF1 = Bool,
        prevMouseLeft = Bool,
        prevArrowKeys = KeyboardNudge.ArrowKeys,
        prevZ = Bool,
        rootJsonIndex = Map[NodeName, String]
    }

    /// エディタ状態の初期値。
    pub def initialState(rootJsonIndex: Map[NodeName, String]): EditorStateData = {
        on = false,
        selected = None,
        dragOrigin = None,
        nodeOrigin = None,
        resizeOrigin = None,
        rotateOrigin = None,
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
    /// EditorState ハンドラ + EditHistory.Rewind ハンドラを掛けた状態で thunk を実行する。
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
        let undoTriggered = (cmdNow or ctrlNow) and zNow and not stateData#prevZ;
        let toggledOn = if (f1 and not stateData#prevF1) not stateData#on else stateData#on;
        let stateAfterToggle = if (toggledOn)
            {on = true, prevF1 = f1 | stateData}
        else
            {on = false, selected = None, dragOrigin = None, nodeOrigin = None,
             resizeOrigin = None, rotateOrigin = None, prevF1 = f1 | stateData};
        if (not toggledOn) {
            GameEngine.Game.setCursor(GameEngine.Cursor.Default);
            EditorState.put({prevMouseLeft = mouseLeft,
                             prevArrowKeys = curArrows,
                             prevZ = zNow | stateAfterToggle});
            scene
        } else {
            let transform = activeViewTransform(scene);
            let mouse = {pos = mousePos, leftDown = mouseLeft};
            let (afterMouseState, afterMouseScene) =
                DragInput.handleMouse(mouse, transform, stateAfterToggle, scene);
            let nudgedScene = if (Option.isEmpty(afterMouseState#dragOrigin))
                KeyboardNudge.applyNudge(afterMouseState, curArrows, afterMouseScene)
            else
                afterMouseScene;
            let finalScene = if (undoTriggered and Option.isEmpty(afterMouseState#dragOrigin))
                applyUndo(nudgedScene)
            else
                nudgedScene;
            updateCursor(mousePos, transform, afterMouseState, finalScene);
            EditorState.put({prevMouseLeft = mouseLeft,
                             prevArrowKeys = curArrows,
                             prevZ = zNow | afterMouseState});
            finalScene
        }

    /// 現在のリサイズ状態またはマウス hover に応じてカーソル形状を更新する。
    def updateCursor(mousePos: Vec2.Vec2, transform: Camera2D.ViewTransform,
                     stateData: EditorStateData,
                     scene: Scene[NodeTag]): Unit \ {GameEngine.Game} =
        let cursor = match stateData#resizeOrigin {
            case Some(origin) => cursorForHandle(origin#handle)
            case None         => match stateData#rotateOrigin {
                case Some(_) => GameEngine.Cursor.AllResize
                case None    => hoverCursor(mousePos, transform, stateData, scene)
            }
        };
        GameEngine.Game.setCursor(cursor)

    /// 選択中ノードのハンドル領域に hover していればそのハンドル用カーソル、
    /// 外していれば Default を返す
    def hoverCursor(mousePos: Vec2.Vec2, transform: Camera2D.ViewTransform,
                    stateData: EditorStateData,
                    scene: Scene[NodeTag]): GameEngine.Cursor \ GameEngine.Game =
        match stateData#selected {
            case None => GameEngine.Cursor.Default
            case Some((_, nodePath)) =>
                let ctx = {rootJsonIndex = stateData#rootJsonIndex, scene = scene};
                match EditableNode.findByNodePath(ctx, nodePath) {
                    case None => GameEngine.Cursor.Default
                    case Some(entry) =>
                        let refPos = Scene.screenPositionAt(nodePath, transform, scene);
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
    /// 4 隅は GLFW 3.4 の対角リサイズカーソル（↘↖ / ↗↙）を使う
    def cursorForHandle(handle: ResizeHandle.Handle): GameEngine.Cursor =
        match handle {
            case ResizeHandle.Handle.Top         => GameEngine.Cursor.VResize
            case ResizeHandle.Handle.Bottom      => GameEngine.Cursor.VResize
            case ResizeHandle.Handle.Left        => GameEngine.Cursor.HResize
            case ResizeHandle.Handle.Right       => GameEngine.Cursor.HResize
            case ResizeHandle.Handle.TopLeft     => GameEngine.Cursor.NWSEResize
            case ResizeHandle.Handle.BottomRight => GameEngine.Cursor.NWSEResize
            case ResizeHandle.Handle.TopRight    => GameEngine.Cursor.NESWResize
            case ResizeHandle.Handle.BottomLeft  => GameEngine.Cursor.NESWResize
        }

    /// Rewind から 1 件取り出してノードを記録された状態（位置 / スケール / サイズ / 回転）に
    /// 戻し、JSON にも書き戻す。履歴に何もなければ scene 不変
    def applyUndo(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {EditHistory.Rewind, Fs.FileRead, Fs.FileWrite} =
        match EditHistory.Rewind.rewind() {
            case None => scene
            case Some(EditHistory.Entry.MoveEntry(entry)) =>
                let restored = Scene.setGlobalPositionAt(
                    entry#nodePath, entry#prevWorldPos, scene);
                let localPos = match Scene.getEngineNode(entry#nodePath, restored) {
                    case Some(engineNode) => Node2D.getPosition(engineNode)
                    case None             => Vec2.zero()
                };
                SceneSerializer.updatePos(entry#jsonPath, entry#nodePath, localPos);
                restored
            case Some(EditHistory.Entry.ScaleEntry(entry)) =>
                // 後方互換: 旧 scale ベースの編集（現在は実質使われていない）
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
            case Some(EditHistory.Entry.ResizeEntry(entry)) =>
                // 各 snapshot のノードを開始時状態に戻し、まとめて 1 ファイル書込で永続化
                let restoredScene = List.foldLeft((acc, snap) ->
                    Scene.mapEngineNode(snap#nodePath,
                        n -> EditableNode.restoreFromSnapshot(snap, n), acc),
                    scene, entry#snapshots);
                let nodeUpdates = List.map(snap -> ({
                    nodePath = snap#nodePath,
                    updates = EditableNode.snapshotToFieldUpdates(snap)
                }: SceneSerializer.NodeUpdate), entry#snapshots);
                SceneSerializer.updateMany(entry#jsonPath, nodeUpdates);
                restoredScene
            case Some(EditHistory.Entry.RotateEntry(entry)) =>
                let restored = Scene.mapEngineNode(entry#nodePath,
                    Node2D.setRotation(entry#prevRotation), scene);
                SceneSerializer.updateRotation(entry#jsonPath, entry#nodePath,
                                                entry#prevRotation);
                restored
        }

    /// 現在のシーンの有効カメラから ViewTransform を計算する。
    /// カメラがなければ identity（CanvasLayer のみのシーン等）
    def activeViewTransform(scene: Scene[NodeTag]): Camera2D.ViewTransform \ GameEngine.Game =
        match Scene.findActiveCamera(scene) {
            case Some((cam, globalPos)) =>
                let vp = GameEngine.Game.getViewportRect();
                Camera2D.getViewTransform(cam, globalPos,
                    {viewportWidth = vp#size#x, viewportHeight = vp#size#y})
            case None => Camera2D.identityTransform()
        }

    /// HotReload watcher の通知をノンブロッキングで消費する。
    pub def pollReload(): Bool \ EditorState =
        EditorState.pollReload()

    /// 描画用のオーバーレイをシーンに合成する。Game.flix の render 直前に呼ぶ。
    pub def applyOverlay(fontAtlas: FontAtlas, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {EditorState, GameEngine.Game} =
        let stateData = EditorState.get();
        if (not stateData#on) scene
        else {
            let mousePos = GameEngine.Game.getMousePosition();
            let transform = activeViewTransform(scene);
            scene
                |> Overlay.addCollisionShapes(transform)
                |> Overlay.addEditorIndicator(fontAtlas)
                |> Overlay.addSelectionBox(stateData#rootJsonIndex, stateData#selected,
                                           transform)
                |> Overlay.addHoverBox(stateData#rootJsonIndex, mousePos, stateData#selected,
                                       transform)
        }
}
