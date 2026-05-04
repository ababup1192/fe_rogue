// DragInput — マウス入力 → 選択 → ドラッグ → 書き戻し のディスパッチ
//
// 押下／継続／離脱 のフレーム判定を `EditorStateData#prevMouseLeft` のエッジから行い、
// 編集対象ノードへの選択 / 移動 / リサイズ / JSON 書き戻し に振り分ける。
// 押下したがそのまま離した（クリック選択のみ）場合は位置が変わっていないので
// ファイル書き込みをスキップする（mtime 更新で HotReload を無駄打ちさせない）。
//
// 押下時は「先に選択中ノードのリサイズハンドルに hit したか」を判定し、
// hit していれば scale を編集するリサイズドラッグへ、外していれば従来どおり
// 編集対象ノードを掴んで位置を移動するドラッグへ進む

mod DragInput {

    /// 1 フレーム分のマウス状態スナップ（位置 + 左ボタン押下中かどうか）。
    /// 押下／継続／離脱 の判定は `EditorStateData#prevMouseLeft` とのエッジから出す
    pub type alias MouseSnapshot = {
        pos = Vec2.Vec2,
        leftDown = Bool
    }

    /// マウスの押下／継続／離脱を判定し、選択 / ドラッグ更新 / リサイズ / 書き戻し を
    /// ディスパッチする。
    /// cameraOffset はカメラ追従中のノード（CanvasLayer 配下でないもの）を選択するため
    /// に必要。Editor.handleInput で `Scene.findActiveCamera` から計算して渡す
    pub def handleMouse(mouse: MouseSnapshot,
                        cameraOffset: Vec2.Vec2,
                        stateData: Editor.EditorStateData,
                        scene: Scene[NodeTag]):
            (Editor.EditorStateData, Scene[NodeTag]) \
            {EditHistory.Rewind, GameEngine.Game, Fs.FileRead, Fs.FileWrite} =
        let prevLeft = stateData#prevMouseLeft;
        let pressedNow = mouse#leftDown and not prevLeft;       // 押下したフレーム
        let releasedNow = (not mouse#leftDown) and prevLeft;    // 離した（ドロップ）フレーム
        if (pressedNow) {
            handleMouseDown(mouse#pos, cameraOffset, stateData, scene)
        } else if (mouse#leftDown and Option.nonEmpty(stateData#resizeOrigin)) {
            // リサイズ中: 選択ノードの scale + position を更新（書き戻しはまだしない）
            (stateData, applyResize(mouse#pos, stateData, scene))
        } else if (mouse#leftDown and Option.nonEmpty(stateData#dragOrigin)) {
            // ドラッグ中: 選択ノードの位置を更新（書き戻しはまだしない）
            (stateData, applyDrag(mouse#pos, stateData, scene))
        } else if (releasedNow and Option.nonEmpty(stateData#resizeOrigin)) {
            // リサイズドロップ: 最終 scale + position を JSON に書き戻し
            saveResizedNode(stateData, scene)
        } else if (releasedNow and Option.nonEmpty(stateData#dragOrigin)) {
            // ドロップ: シーンの最終 pos を JSON に書き戻し（位置が変わっていれば）
            saveDraggedPos(stateData, scene)
        } else {
            (stateData, scene)
        }

    /// ドラッグ中: マウスの移動量に応じてノードのグローバル位置を更新する。
    /// ピクセル単位に整数スナップして「カクカク」動かす（drop 時の保存値とも一致する）。
    /// 単体テストしやすいよう pub。状態 + シーンに対して pure
    pub def applyDrag(mousePos: Vec2.Vec2, stateData: Editor.EditorStateData,
                      scene: Scene[NodeTag]): Scene[NodeTag] =
        match (stateData#selected, stateData#dragOrigin, stateData#nodeOrigin) {
            case (Some((_, nodePath)), Some(dragOrigin), Some(nodeOrigin)) =>
                let delta = Vec2.sub(mousePos, dragOrigin);
                let newGlobalPos = snapVec2(Vec2.add(nodeOrigin, delta));
                Scene.setGlobalPositionAt(nodePath, newGlobalPos, scene)
            case _ => scene
        }

    /// リサイズ中: マウス移動量から新しい bbox を計算し、scale と position を更新する。
    /// scale は (新サイズ / 旧サイズ × 旧 scale)、position は新 bbox 左上から
    /// topLeftOffset を引いて求める（centered=true のスプライトなら新中心になる）。
    /// 単体テストしやすいよう pub。状態 + シーンに対して pure
    pub def applyResize(mousePos: Vec2.Vec2, stateData: Editor.EditorStateData,
                        scene: Scene[NodeTag]): Scene[NodeTag] =
        match (stateData#selected, stateData#dragOrigin, stateData#resizeOrigin) {
            case (Some((_, nodePath)), Some(dragOrigin), Some(origin)) =>
                let delta = Vec2.sub(mousePos, dragOrigin);
                let originalBox = {topLeft = origin#boxTopLeftScreen,
                                   size = origin#boxSize};
                let newBox = ResizeHandle.applyDrag(origin#handle,
                    originalBox, delta, minDisplaySize());
                let scaleRatio = {x = safeRatio(newBox#size#x, origin#boxSize#x),
                                  y = safeRatio(newBox#size#y, origin#boxSize#y)};
                let newScale = {x = origin#scale#x * scaleRatio#x,
                                y = origin#scale#y * scaleRatio#y};
                // 新 bbox 左上からの逆算で新しいワールド座標を出す。
                // topLeftOffset は centered=true なら -size/2 のような相対値なので、
                // 新サイズに合わせて再スケーリングする
                let newOffset = scaleTopLeftOffset(origin#topLeftOffset,
                                                    origin#boxSize, newBox#size);
                let newWorldPos = snapVec2(Vec2.sub(newBox#topLeft, newOffset));
                scene
                    |> Scene.mapEngineNode(nodePath, Node2D.setScale(newScale))
                    |> Scene.setGlobalPositionAt(nodePath, newWorldPos)
            case _ => scene
        }

    /// 表示サイズの最小値（リサイズで負スケールに反転しないためのクランプ）
    def minDisplaySize(): Vec2.Vec2 = {x = 1.0, y = 1.0}

    /// 旧サイズから新サイズへの倍率。0 除算は 1.0 を返してフォールバックする
    /// （元から幅 0 のノードは scale を変えても意味がないため変更なし扱い）
    def safeRatio(newSize: Float64, originalSize: Float64): Float64 =
        if (originalSize == 0.0) 1.0 else newSize / originalSize

    /// topLeftOffset は「ノード中央 → bbox 左上」のベクトルで、サイズに比例する
    /// （centered=true なら -size/2、centered=false なら 0）。サイズが変わったら
    /// 同じ比率で伸縮させる
    def scaleTopLeftOffset(originalOffset: Vec2.Vec2,
                           originalSize: Vec2.Vec2,
                           newSize: Vec2.Vec2): Vec2.Vec2 =
        {x = originalOffset#x * safeRatio(newSize#x, originalSize#x),
         y = originalOffset#y * safeRatio(newSize#y, originalSize#y)}

    /// Vec2 を整数ピクセルに丸める（HotReload 後の JSON も整数値で残るようにするため）
    pub def snapVec2(v: Vec2.Vec2): Vec2.Vec2 =
        {x = Float64.round(v#x), y = Float64.round(v#y)}

    /// クリック押下時: まず選択中ノードのリサイズハンドルに hit したかを判定し、
    /// hit していればリサイズドラッグを開始する。外していれば従来どおり編集対象ノードを
    /// pickTopAt で掴んで移動ドラッグを開始する。
    /// nodeOrigin にはノードのワールド座標を入れる（applyDrag は delta 加算のみ使うため
    /// screen と world の差は影響しない）
    def handleMouseDown(mousePos: Vec2.Vec2, cameraOffset: Vec2.Vec2,
                        stateData: Editor.EditorStateData,
                        scene: Scene[NodeTag]):
            (Editor.EditorStateData, Scene[NodeTag]) \ GameEngine.Game =
        match tryStartResize(mousePos, cameraOffset, stateData, scene) {
            case Some(newState) => (newState, scene)
            case None =>
                let ctx = {rootJsonIndex = stateData#rootJsonIndex, scene = scene};
                let entries = EditableNode.collectAll(ctx);
                let hit = Picking.pickTopAt(mousePos, entries, cameraOffset, scene);
                match hit {
                    case None =>
                        ({selected = None, dragOrigin = None, nodeOrigin = None,
                          resizeOrigin = None | stateData}, scene)
                    case Some((entry, _)) =>
                        let nodeWorld = Scene.globalPositionAt(entry#nodePath, scene);
                        let newState = {
                            selected = Some((entry#jsonPath, entry#nodePath)),
                            dragOrigin = Some(mousePos),
                            nodeOrigin = Some(nodeWorld),
                            resizeOrigin = None
                            | stateData
                        };
                        (newState, scene)
                }
        }

    /// 選択中ノードがあり、マウスがそのリサイズハンドル領域内にあるかを判定する。
    /// hit していれば「リサイズドラッグ開始済み」の EditorStateData を返す
    def tryStartResize(mousePos: Vec2.Vec2, cameraOffset: Vec2.Vec2,
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
                        let refPos = Scene.screenPositionAt(nodePath, cameraOffset, scene);
                        let topLeft = Vec2.add(refPos, entry#topLeftOffset);
                        let box = {topLeft = topLeft,
                                   size = {x = entry#width, y = entry#height}};
                        match ResizeHandle.hitTest(mousePos, box) {
                            case None => None
                            case Some(handle) =>
                                let nodeWorld = Scene.globalPositionAt(nodePath, scene);
                                let nodeScale = match Scene.getEngineNode(nodePath, scene) {
                                    case Some(engineNode) => Node2D.getScale(engineNode)
                                    case None             => {x = 1.0, y = 1.0}
                                };
                                let resizeOrigin: Editor.ResizeOrigin = {
                                    handle = handle,
                                    boxTopLeftScreen = topLeft,
                                    boxSize = {x = entry#width, y = entry#height},
                                    scale = nodeScale,
                                    worldPos = nodeWorld,
                                    topLeftOffset = entry#topLeftOffset
                                };
                                Some({
                                    dragOrigin = Some(mousePos),
                                    nodeOrigin = Some(nodeWorld),
                                    resizeOrigin = Some(resizeOrigin)
                                    | stateData
                                })
                        }
                }
        }

    /// ドロップ: 現在のシーン上のノード位置を JSON に書き戻し、ドラッグ状態を解除する。
    /// 書き戻し対象は「ローカル位置」（JSON が pos として持つのはローカル座標のため）。
    /// クリックのみで位置が変わっていない場合はファイル書き込みをスキップする。
    /// 移動が発生したときは `EditHistory.Rewind.save` で巻き戻し用にドラッグ開始位置を残す
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
                    // 巻き戻し先 = ドラッグ開始時の global 位置
                    match stateData#nodeOrigin {
                        case Some(origin) =>
                            EditHistory.Rewind.save(EditHistory.Entry.MoveEntry({
                                jsonPath = jsonPath,
                                nodePath = nodePath,
                                prevWorldPos = origin}))
                        case None => ()
                    };
                    let localPos = match Scene.getEngineNode(nodePath, scene) {
                        case Some(engineNode) => Node2D.getPosition(engineNode)
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

    /// リサイズドロップ: scale と pos の両方を JSON に書き戻し、リサイズ状態を解除する。
    /// scale も pos も変化していなければ書き込みスキップ（HotReload 無駄打ち回避）。
    /// 変化があったときは `EditHistory.Rewind.save` で巻き戻し用に開始時 scale + pos を残す
    def saveResizedNode(stateData: Editor.EditorStateData,
                        scene: Scene[NodeTag]):
            (Editor.EditorStateData, Scene[NodeTag]) \
            {EditHistory.Rewind, Fs.FileRead, Fs.FileWrite} =
        match (stateData#selected, stateData#resizeOrigin) {
            case (Some((jsonPath, nodePath)), Some(origin)) =>
                let currentScale = match Scene.getEngineNode(nodePath, scene) {
                    case Some(engineNode) => Node2D.getScale(engineNode)
                    case None             => origin#scale
                };
                let currentGlobal = Scene.globalPositionAt(nodePath, scene);
                let scaleChanged = currentScale#x != origin#scale#x or
                                   currentScale#y != origin#scale#y;
                let posChanged = currentGlobal#x != origin#worldPos#x or
                                 currentGlobal#y != origin#worldPos#y;
                if (scaleChanged or posChanged) {
                    EditHistory.Rewind.save(EditHistory.Entry.ScaleEntry({
                        jsonPath = jsonPath,
                        nodePath = nodePath,
                        prevWorldPos = origin#worldPos,
                        prevScale = origin#scale}));
                    let localPos = match Scene.getEngineNode(nodePath, scene) {
                        case Some(engineNode) => Node2D.getPosition(engineNode)
                        case None => Vec2.zero()
                    };
                    SceneSerializer.updatePosAndScale(jsonPath, nodePath, localPos,
                                                       currentScale)
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
}
