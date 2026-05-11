// DragInput — マウス入力 → 選択 → ドラッグ → 書き戻し のディスパッチ
//
// 押下／継続／離脱 のフレーム判定を `EditorStateData#prevMouseLeft` のエッジから行い、
// 編集対象ノードへの選択 / 移動 / リサイズ / 回転 / JSON 書き戻し に振り分ける。
//
// リサイズはノード型ごとにディスパッチ:
//   - ColorRect / TextureButton: size を ratio 倍
//   - Label2D: fontSize を ratio 倍
//   - Sprite2D / AnimatedSprite2D: scale を ratio 倍
//   - CanvasLayer: 直接の子ノード全部に再帰的に上記を適用 + 子の position も比例分配（cascade）
//
// 回転はマウスのノブハンドルでドラッグ、CanvasLayer は engine が rotation を子に伝播するので
// CanvasLayer 自身を回せばダイアログ全体が傾く

mod DragInput {

    /// 1 フレーム分のマウス状態スナップ（位置 + 左ボタン押下中かどうか）。
    pub type alias MouseSnapshot = {
        pos = Vec2.Vec2,
        leftDown = Bool
    }

    /// マウスの押下／継続／離脱を判定し、選択 / ドラッグ更新 / リサイズ / 回転 / 書き戻し を
    /// ディスパッチする。
    pub def handleMouse(mouse: MouseSnapshot,
                        transform: Camera2D.ViewTransform,
                        stateData: Editor.EditorStateData,
                        scene: Scene[NodeTag]):
            (Editor.EditorStateData, Scene[NodeTag]) \
            {EditHistory.Rewind, GameEngine.Game, Fs.FileRead, Fs.FileWrite} =
        let prevLeft = stateData#prevMouseLeft;
        let pressedNow = mouse#leftDown and not prevLeft;
        let releasedNow = (not mouse#leftDown) and prevLeft;
        if (pressedNow) {
            handleMouseDown(mouse#pos, transform, stateData, scene)
        } else if (mouse#leftDown and Option.nonEmpty(stateData#rotateOrigin)) {
            (stateData, applyRotate(mouse#pos, stateData, scene))
        } else if (mouse#leftDown and Option.nonEmpty(stateData#resizeOrigin)) {
            (stateData, applyResize(mouse#pos, stateData, scene))
        } else if (mouse#leftDown and Option.nonEmpty(stateData#dragOrigin)) {
            (stateData, applyDrag(mouse#pos, stateData, scene))
        } else if (releasedNow and Option.nonEmpty(stateData#rotateOrigin)) {
            saveRotatedNode(stateData, scene)
        } else if (releasedNow and Option.nonEmpty(stateData#resizeOrigin)) {
            saveResizedNode(stateData, scene)
        } else if (releasedNow and Option.nonEmpty(stateData#dragOrigin)) {
            saveDraggedPos(stateData, scene)
        } else {
            (stateData, scene)
        }

    /// ドラッグ中: マウスの移動量に応じてノードのグローバル位置を更新する。
    /// グローバル位置を整数に丸めたうえで、setGlobalPositionAt が逆算したローカル位置も
    /// 再度整数に丸める（親に小数オフセットがあってもローカル座標が整数で揃う）。
    pub def applyDrag(mousePos: Vec2.Vec2, stateData: Editor.EditorStateData,
                      scene: Scene[NodeTag]): Scene[NodeTag] =
        match (stateData#selected, stateData#dragOrigin, stateData#nodeOrigin) {
            case (Some((_, nodePath)), Some(dragOrigin), Some(nodeOrigin)) =>
                let delta = Vec2.sub(mousePos, dragOrigin);
                let newGlobalPos = Vec2.round(Vec2.add(nodeOrigin, delta));
                scene
                    |> Scene.setGlobalPositionAt(nodePath, newGlobalPos)
                    |> Scene.mapEngineNode(nodePath, engineNode ->
                        Node2D.setPosition(Vec2.round(Node2D.getPosition(engineNode)),
                                           engineNode))
            case _ => scene
        }

    /// リサイズ中: マウス移動量から新しい bbox を計算し、ノード型に応じて size/fontSize/scale と
    /// position を更新する。CanvasLayer なら子ノードに cascade。
    /// 重要: snapshot に保存した開始時の値を起点にして ratio を掛けるので、
    /// 毎フレーム呼ばれても累乗にならず常に「原始サイズ × 現在フレームの ratio」になる
    pub def applyResize(mousePos: Vec2.Vec2, stateData: Editor.EditorStateData,
                        scene: Scene[NodeTag]): Scene[NodeTag] =
        match (stateData#selected, stateData#dragOrigin, stateData#resizeOrigin) {
            case (Some((_, nodePath)), Some(dragOrigin), Some(origin)) =>
                let delta = Vec2.sub(mousePos, dragOrigin);
                let originalBox = {topLeft = origin#boxTopLeftScreen,
                                   size = origin#boxSize};
                let newBox = ResizeHandle.applyDrag(origin#handle,
                    originalBox, delta, minDisplaySize());
                let ratio = {x = safeRatio(newBox#size#x, origin#boxSize#x),
                             y = safeRatio(newBox#size#y, origin#boxSize#y)};
                // 新しい topLeft offset は ratio 比率で伸縮する
                let newOffset = scaleTopLeftOffset(origin#topLeftOffset,
                                                    origin#boxSize, newBox#size);
                let newWorldPos = Vec2.round(Vec2.sub(newBox#topLeft, newOffset));
                if (List.isEmpty(origin#childSnapshots)) {
                    // 単独ノードのリサイズ。原始サイズ起点で ratio を掛ける
                    scene
                        |> Scene.mapEngineNode(nodePath,
                            EditableNode.applyResizeFromSnapshot(
                                origin#nodeSnapshot, ratio))
                        |> Scene.setGlobalPositionAt(nodePath, newWorldPos)
                } else {
                    // CanvasLayer の cascade: CanvasLayer 自身の位置 + 子の位置・サイズを更新
                    let scene1 = Scene.setGlobalPositionAt(nodePath, newWorldPos, scene);
                    List.foldLeft((acc, snap) -> {
                        let childPath = snap#nodePath;
                        let newChildLocal = {
                            x = snap#prevPosition#x * ratio#x,
                            y = snap#prevPosition#y * ratio#y
                        };
                        acc
                            |> Scene.mapEngineNode(childPath,
                                EditableNode.applyResizeFromSnapshot(snap, ratio))
                            |> Scene.mapEngineNode(childPath,
                                Node2D.setPosition(Vec2.round(newChildLocal)))
                    }, scene1, origin#childSnapshots)
                }
            case _ => scene
        }

    /// 回転中: マウス位置から角度を計算し、ノードの rotation を更新する。
    /// CanvasLayer なら engine が子に伝播するので CanvasLayer 1 つ更新するだけ
    pub def applyRotate(mousePos: Vec2.Vec2, stateData: Editor.EditorStateData,
                        scene: Scene[NodeTag]): Scene[NodeTag] =
        match stateData#rotateOrigin {
            case None => scene
            case Some(origin) =>
                let curAngle = Vec2.atan2(
                    mousePos#y - origin#centerScreen#y,
                    mousePos#x - origin#centerScreen#x);
                let delta = curAngle - origin#startMouseAngle;
                let newRotation = origin#startRotation + delta;
                Scene.mapEngineNode(origin#nodePath,
                    Node2D.setRotation(newRotation), scene)
        }

    def minDisplaySize(): Vec2.Vec2 = {x = 1.0, y = 1.0}

    def safeRatio(newSize: Float64, originalSize: Float64): Float64 =
        if (originalSize == 0.0) 1.0 else newSize / originalSize

    def scaleTopLeftOffset(originalOffset: Vec2.Vec2,
                           originalSize: Vec2.Vec2,
                           newSize: Vec2.Vec2): Vec2.Vec2 =
        {x = originalOffset#x * safeRatio(newSize#x, originalSize#x),
         y = originalOffset#y * safeRatio(newSize#y, originalSize#y)}

    /// クリック押下時: 優先順位は 回転ノブ > リサイズハンドル > 編集対象ノード選択 / 移動。
    /// Shift を押しながらクリックすると、コンテナ優先ピックを切って z-index 最大の
    /// 子要素を直接掴める。
    def handleMouseDown(mousePos: Vec2.Vec2, transform: Camera2D.ViewTransform,
                        stateData: Editor.EditorStateData,
                        scene: Scene[NodeTag]):
            (Editor.EditorStateData, Scene[NodeTag]) \ GameEngine.Game =
        match tryStartRotate(mousePos, transform, stateData, scene) {
            case Some(newState) => (newState, scene)
            case None => match tryStartResize(mousePos, transform, stateData, scene) {
                case Some(newState) => (newState, scene)
                case None =>
                    let ctx = {rootJsonIndex = stateData#rootJsonIndex, scene = scene};
                    let entries = EditableNode.collectAll(ctx);
                    let preferDescendant = GameEngine.Game.isKeyPressed(GameEngine.Key.LeftShift);
                    let hit = Picking.pickTopAt(mousePos, entries, transform,
                                                 preferDescendant, scene);
                    match hit {
                        case None =>
                            ({selected = None, dragOrigin = None, nodeOrigin = None,
                              resizeOrigin = None, rotateOrigin = None | stateData}, scene)
                        case Some((entry, _)) =>
                            let nodeWorld = Scene.globalPositionAt(entry#nodePath, scene);
                            let newState = {
                                selected = Some((entry#jsonPath, entry#nodePath)),
                                dragOrigin = Some(mousePos),
                                nodeOrigin = Some(nodeWorld),
                                resizeOrigin = None,
                                rotateOrigin = None
                                | stateData
                            };
                            (newState, scene)
                    }
            }
        }

    /// 選択中ノードがあり、マウスがそのリサイズハンドル領域内にあるかを判定する。
    /// CanvasLayer の場合は子ノードのスナップショットも収集（cascade 用）
    def tryStartResize(mousePos: Vec2.Vec2, transform: Camera2D.ViewTransform,
                       stateData: Editor.EditorStateData,
                       scene: Scene[NodeTag]):
            Option[Editor.EditorStateData] \ GameEngine.Game =
        match stateData#selected {
            case None => None
            case Some((_, nodePath)) =>
                let ctx = {rootJsonIndex = stateData#rootJsonIndex, scene = scene};
                match EditableNode.findByNodePath(ctx, nodePath) {
                    case None => None
                    case Some(entry) =>
                        let refPos = Scene.screenPositionAt(nodePath, transform, scene);
                        let topLeft = Vec2.add(refPos, entry#topLeftOffset);
                        let box = {topLeft = topLeft,
                                   size = {x = entry#width, y = entry#height}};
                        match ResizeHandle.hitTest(mousePos, box) {
                            case None => None
                            case Some(handle) =>
                                match Scene.getEngineNode(nodePath, scene) {
                                    case None => None
                                    case Some(engineNode) =>
                                        let nodeSnap = EditableNode.snapshotForResize(
                                            nodePath, engineNode);
                                        let childSnaps = collectChildSnapshots(
                                            engineNode, nodePath, scene);
                                        let resizeOrigin: Editor.ResizeOrigin = {
                                            handle = handle,
                                            boxTopLeftScreen = topLeft,
                                            boxSize = {x = entry#width, y = entry#height},
                                            topLeftOffset = entry#topLeftOffset,
                                            nodeSnapshot = nodeSnap,
                                            childSnapshots = childSnaps
                                        };
                                        Some({
                                            dragOrigin = Some(mousePos),
                                            nodeOrigin = Some(nodeSnap#prevPosition),
                                            resizeOrigin = Some(resizeOrigin),
                                            rotateOrigin = None
                                            | stateData
                                        })
                                }
                        }
                }
        }

    /// CanvasLayer の場合、直接の子ノードのスナップショットを集める。
    /// 非 CanvasLayer なら Nil
    def collectChildSnapshots(engineNode: EngineNode[NodeTag], path: NodePath,
                               scene: Scene[NodeTag]):
            List[EditableNode.NodeResizeSnapshot] =
        match engineNode {
            case EngineNode.CanvasLayerWithState(_, _) =>
                let childNames = Scene.getChildrenAt(path, scene);
                List.filterMap(name -> {
                    let childPath = List.append(path, name :: Nil);
                    match Scene.getEngineNode(childPath, scene) {
                        case None => None
                        case Some(child) =>
                            Some(EditableNode.snapshotForResize(childPath, child))
                    }
                }, childNames)
            case _ => Nil
        }

    /// 選択中ノードがあり、マウスが回転ノブ領域内にあるかを判定する。
    /// hit していれば回転ドラッグを開始する EditorStateData を返す
    def tryStartRotate(mousePos: Vec2.Vec2, transform: Camera2D.ViewTransform,
                       stateData: Editor.EditorStateData,
                       scene: Scene[NodeTag]):
            Option[Editor.EditorStateData] \ GameEngine.Game =
        match stateData#selected {
            case None => None
            case Some((jsonPath, nodePath)) =>
                let ctx = {rootJsonIndex = stateData#rootJsonIndex, scene = scene};
                match EditableNode.findByNodePath(ctx, nodePath) {
                    case None => None
                    case Some(entry) =>
                        let refPos = Scene.screenPositionAt(nodePath, transform, scene);
                        let topLeft = Vec2.add(refPos, entry#topLeftOffset);
                        let box = {topLeft = topLeft,
                                   size = {x = entry#width, y = entry#height}};
                        if (not ResizeHandle.rotateKnobHit(mousePos, box)) None
                        else {
                            let center = ResizeHandle.boxCenter(box);
                            let startAngle = Vec2.atan2(
                                mousePos#y - center#y, mousePos#x - center#x);
                            let curRot = match Scene.getEngineNode(nodePath, scene) {
                                case Some(engineNode) => Node2D.getRotation(engineNode)
                                case None             => 0.0
                            };
                            let rotateOrigin: Editor.RotateOrigin = {
                                centerScreen = center,
                                startMouseAngle = startAngle,
                                startRotation = curRot,
                                nodePath = nodePath,
                                jsonPath = jsonPath
                            };
                            Some({
                                dragOrigin = Some(mousePos),
                                rotateOrigin = Some(rotateOrigin),
                                resizeOrigin = None
                                | stateData
                            })
                        }
                }
        }

    /// ドロップ: 現在のシーン上のノード位置を JSON に書き戻し、ドラッグ状態を解除する。
    def saveDraggedPos(stateData: Editor.EditorStateData,
                       scene: Scene[NodeTag]):
            (Editor.EditorStateData, Scene[NodeTag]) \
            {EditHistory.Rewind, Fs.FileRead, Fs.FileWrite} =
        match stateData#selected {
            case Some((jsonPath, nodePath)) =>
                let currentGlobal = Scene.globalPositionAt(nodePath, scene);
                let moved = match stateData#nodeOrigin {
                    case Some(origin) =>
                        currentGlobal#x != origin#x or currentGlobal#y != origin#y
                    case None => false
                };
                if (moved) {
                    match stateData#nodeOrigin {
                        case Some(origin) =>
                            EditHistory.Rewind.save(EditHistory.Entry.MoveEntry({
                                jsonPath = jsonPath,
                                nodePath = nodePath,
                                prevWorldPos = origin}))
                        case None => ()
                    };
                    let localPos = match Scene.getEngineNode(nodePath, scene) {
                        case Some(engineNode) => Vec2.round(Node2D.getPosition(engineNode))
                        case None => Vec2.zero()
                    };
                    SceneSerializer.updatePos(jsonPath, nodePath, localPos)
                } else ();
                let cleared = {
                    dragOrigin = None,
                    nodeOrigin = None
                    | stateData
                };
                (cleared, scene)
            case None => (stateData, scene)
        }

    /// リサイズドロップ: 自ノード（と CanvasLayer なら子も）の更新を 1 回の書込で永続化。
    /// undo 用に snapshots を ResizeEntry に積む。
    def saveResizedNode(stateData: Editor.EditorStateData,
                        scene: Scene[NodeTag]):
            (Editor.EditorStateData, Scene[NodeTag]) \
            {EditHistory.Rewind, Fs.FileRead, Fs.FileWrite} =
        match (stateData#selected, stateData#resizeOrigin) {
            case (Some((jsonPath, _)), Some(origin)) =>
                let allSnapshots = origin#nodeSnapshot :: origin#childSnapshots;
                let changed = anyNodeChanged(allSnapshots, scene);
                if (changed) {
                    EditHistory.Rewind.save(EditHistory.Entry.ResizeEntry({
                        jsonPath = jsonPath,
                        snapshots = allSnapshots
                    }));
                    let nodeUpdates = List.filterMap(snap ->
                        buildNodeUpdateAfterResize(snap, scene), allSnapshots);
                    SceneSerializer.updateMany(jsonPath, nodeUpdates)
                } else ();
                let cleared = {
                    dragOrigin = None,
                    nodeOrigin = None,
                    resizeOrigin = None
                    | stateData
                };
                (cleared, scene)
            case _ => (stateData, scene)
        }

    /// 1 ノードについて「現在のシーン上の位置 + applyResize 用のサイズ系 field」を
    /// FieldUpdate のリストとして組み立てる
    def buildNodeUpdateAfterResize(snap: EditableNode.NodeResizeSnapshot,
                                    scene: Scene[NodeTag]):
            Option[SceneSerializer.NodeUpdate] =
        match Scene.getEngineNode(snap#nodePath, scene) {
            case None => None
            case Some(engineNode) =>
                let posUpd: SceneSerializer.FieldUpdate = {
                    key = "pos",
                    value = SceneSerializer.FieldValue.VecValue(
                        Node2D.getPosition(engineNode))
                };
                let sizeUpds = EditableNode.resizeFieldUpdates(engineNode);
                Some({
                    nodePath = snap#nodePath,
                    updates = posUpd :: sizeUpds
                })
        }

    /// snapshots のいずれかが現在のシーン上で変化していれば true（mtime 無駄打ち回避）
    def anyNodeChanged(snapshots: List[EditableNode.NodeResizeSnapshot],
                       scene: Scene[NodeTag]): Bool =
        List.exists(snap -> {
            match Scene.getEngineNode(snap#nodePath, scene) {
                case None => false
                case Some(engineNode) =>
                    let curPos = Node2D.getPosition(engineNode);
                    let posChanged = curPos#x != snap#prevPosition#x or
                                     curPos#y != snap#prevPosition#y;
                    let sizeChanged = match snap#prevSize {
                        case Some(prev) => match engineNode {
                            case EngineNode.ColorRectWithState(rect, _) =>
                                let cur = ColorRect.getSize(rect);
                                cur#x != prev#x or cur#y != prev#y
                            case EngineNode.TextureButtonWithState(btn, _) =>
                                let cur = TextureButton.getSize(btn);
                                cur#x != prev#x or cur#y != prev#y
                            case EngineNode.RichTextLabelWithState(label, _) =>
                                let cur = RichTextLabel.getSize(label);
                                cur#x != prev#x or cur#y != prev#y
                            case _ => false
                        }
                        case None => false
                    };
                    let fontSizeChanged = match snap#prevFontSize {
                        case Some(prev) => match engineNode {
                            case EngineNode.Label2DWithState(label, _) =>
                                Label2D.getFontSize(label) != prev
                            case _ => false
                        }
                        case None => false
                    };
                    let scaleChanged = match snap#prevScale {
                        case Some(prev) =>
                            let cur = Node2D.getScale(engineNode);
                            cur#x != prev#x or cur#y != prev#y
                        case None => false
                    };
                    posChanged or sizeChanged or fontSizeChanged or scaleChanged
            }
        }, snapshots)

    /// 回転ドロップ: 現在の rotation を JSON に書き戻し、回転状態を解除する
    def saveRotatedNode(stateData: Editor.EditorStateData,
                        scene: Scene[NodeTag]):
            (Editor.EditorStateData, Scene[NodeTag]) \
            {EditHistory.Rewind, Fs.FileRead, Fs.FileWrite} =
        match stateData#rotateOrigin {
            case None => (stateData, scene)
            case Some(origin) =>
                let curRot = match Scene.getEngineNode(origin#nodePath, scene) {
                    case Some(engineNode) => Node2D.getRotation(engineNode)
                    case None             => origin#startRotation
                };
                if (curRot != origin#startRotation) {
                    EditHistory.Rewind.save(EditHistory.Entry.RotateEntry({
                        jsonPath = origin#jsonPath,
                        nodePath = origin#nodePath,
                        prevRotation = origin#startRotation
                    }));
                    SceneSerializer.updateRotation(origin#jsonPath, origin#nodePath, curRot)
                } else ();
                let cleared = {
                    dragOrigin = None,
                    rotateOrigin = None
                    | stateData
                };
                (cleared, scene)
        }
}
