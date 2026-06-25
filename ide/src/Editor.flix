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
    ///                   非 CanvasLayer のときは Nil。undo ですべて巻き戻すため。
    /// `jsonNodePath`: SceneSerializer 書き戻し用の JSON 内 path（プレハブ翻訳済み）
    pub type alias ResizeOrigin = {
        handle = ResizeHandle.Handle,
        boxTopLeftScreen = Vec2.Vec2,
        boxSize = Vec2.Vec2,
        topLeftOffset = Vec2.Vec2,
        nodeSnapshot = EditableNode.NodeResizeSnapshot,
        childSnapshots = List[EditableNode.NodeResizeSnapshot],
        jsonNodePath = NodePath
    }

    /// 回転ハンドルドラッグ中に保持する開始時スナップショット。
    pub type alias RotateOrigin = {
        centerScreen = Vec2.Vec2,
        startMouseAngle = Float64,
        startRotation = Float64,
        nodePath = NodePath,
        jsonPath = String,
        jsonNodePath = NodePath
    }

    /// 現在の選択ノード。`nodePath` は live scene 内の path（DragInput 等の操作対象）、
    /// `jsonNodePath` は JSON ファイル内の path（SceneSerializer に渡す書き戻し先）。
    /// 静的シーンでは両者は等しい。プレハブ由来ノードでは先頭名が違う
    pub type alias Selection = {
        jsonPath = String,
        nodePath = NodePath,
        jsonNodePath = NodePath
    }

    /// エディタ状態の record 表現
    pub type alias EditorStateData = {
        on = Bool,
        selected = Option[Selection],
        dragOrigin = Option[Vec2.Vec2],
        nodeOrigin = Option[Vec2.Vec2],
        resizeOrigin = Option[ResizeOrigin],
        rotateOrigin = Option[RotateOrigin],
        prevF1 = Bool,
        prevMouseLeft = Bool,
        prevArrowKeys = KeyboardNudge.ArrowKeys,
        prevZ = Bool,
        rootJsonIndex = Map[NodeName, String],
        // ビュー変換 (pan/zoom)。ViewTransform { offset, scale } に対応:
        //   screen = world * editorZoom - editorOffset
        editorOffset = Vec2.Vec2,
        editorZoom = Float64,
        // パンドラッグ中の (開始マウス, 開始 offset)。非ドラッグ時 None
        panOrigin = Option[(Vec2.Vec2, Vec2.Vec2)],
        // グリッドスナップの間隔(px)。0.0 = OFF（従来の 1px 丸め）。ドラッグ移動の確定値に効く
        snapStep = Float64
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
        rootJsonIndex = rootJsonIndex,
        editorOffset = Vec2.zero(),
        editorZoom = 1.0,
        panOrigin = None,
        snapStep = 0.0
    }

    /// scene.json ルート索引を構築する。Game.start から 1 回だけ呼ぶ
    pub def loadJsonRootIndex(): Map[NodeName, String] \ {Fs.Glob, Fs.FileRead} =
        SceneJsonIndex.load()

    /// エディタ状態の Ref と HotReload watcher を一括して下準備し、
    /// EditorState ハンドラ + EditHistory.Rewind ハンドラを掛けた状態で thunk を実行する。
    pub def withState(rc: Region[r]):
            (Unit -> Unit \ ef) -> Unit \ (ef - EditorState - EditHistory.Rewind) + r +
                                          Fs.Glob + Fs.FileRead + Chan + NonDet + IO +
                                          Fs.ModificationTime =
        withStateInternal(rc, loadJsonRootIndex, "src/scenes")

    /// withState のプロジェクトルート指定版。`SceneJsonIndex.loadAt(projectRoot)` で索引を作り、
    /// HotReload も `<projectRoot>/src/scenes` を監視する。
    /// cwd 固定で動く `withState` と違って、IDE のように複数プロジェクトを切り替えるホストから
    /// 安全に呼べる
    pub def withStateAt(rc: Region[r], projectRoot: String):
            (Unit -> Unit \ ef) -> Unit \ (ef - EditorState - EditHistory.Rewind) + r +
                                          Fs.Glob + Fs.FileRead + Chan + NonDet + IO +
                                          Fs.ModificationTime =
        withStateInternal(rc, () -> SceneJsonIndex.loadAt(projectRoot),
                          projectRoot + "/src/scenes")

    /// withState / withStateAt の共通本体。索引のロード方法と HotReload 監視ディレクトリを
    /// 呼び出し側に切り出した版
    def withStateInternal(rc: Region[r],
                           loadIndex: Unit -> Map[NodeName, String] \ {Fs.Glob, Fs.FileRead},
                           watchedDir: String):
            (Unit -> Unit \ ef) -> Unit \ (ef - EditorState - EditHistory.Rewind) + r +
                                          Fs.Glob + Fs.FileRead + Chan + NonDet + IO +
                                          Fs.ModificationTime =
        thunk -> {
            let editorIndex = loadIndex();
            let editorRef: Ref[EditorStateData, r] = Ref.fresh(rc, initialState(editorIndex));
            let historyRef: Ref[List[EditHistory.Entry], r] = Ref.fresh(rc, Nil);
            let reloadRx = HotReload.startWatcherAt(watchedDir);
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

    /// 入力処理を行いシーンを更新する。Game.flix / IDE の gameLoop から毎フレーム呼ぶ。
    /// toolMode: 0=選択ツール（左ドラッグでノード選択/移動）, 1=手のひらツール（左ドラッグでパン）。
    /// ズーム（ホイール）と中ボタンドラッグのパンはツールに依らず常に効く（Godot 準拠）。
    pub def handleInput(view: {toolMode = Int32, zoomCommand = Int32, snapStep = Float64},
                        scene: Scene[t]):
            Scene[t] \ {EditorState, EditHistory.Rewind, GameEngine.Game,
                              Fs.FileRead, Fs.FileWrite} =
        let toolMode = view#toolMode;
        let zoomCmd = view#zoomCommand;
        // グリッドスナップ間隔を毎フレーム state に取り込む（DragInput が stateData 経由で読む）
        let stateData = {snapStep = view#snapStep | EditorState.get()};
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
            // ビュー操作（ズーム＝ピンチ/ボタン / パン＝二本指ドラッグ・中ボタン・手のひらツール）
            let scroll = GameEngine.Game.consumeScrollDelta();
            let (scrollPanX, scrollPanY) = GameEngine.Game.consumeScrollPan();
            let middle = GameEngine.Game.isMouseButtonPressed(GameEngine.MouseButton.Middle);
            let panning = middle or ((toolMode == 1i32) and mouseLeft);
            let wheelState = applyWheelZoom(stateAfterToggle, scroll, mousePos);
            let zoomedState = applyButtonZoom(wheelState, zoomCmd, mousePos);
            let scrolledState = applyScrollPan(zoomedState, scrollPanX, scrollPanY);
            let pannedState = applyPan(scrolledState, panning, mousePos);
            if (panning)
                handlePanFrame(pannedState, mouseLeft, curArrows, zNow, scene)
            else
                handleEditFrame(pannedState, mousePos, mouseLeft, curArrows, zNow,
                                undoTriggered, scene)
        }

    /// パン中フレーム: ビューだけ更新し、ノード操作はしない。掴みカーソルを出す。
    def handlePanFrame(stateData: EditorStateData, mouseLeft: Bool,
                       curArrows: KeyboardNudge.ArrowKeys, zNow: Bool,
                       scene: Scene[t]): Scene[t] \ {EditorState, GameEngine.Game} =
        GameEngine.Game.setCursor(GameEngine.Cursor.Rotate);
        EditorState.put({prevMouseLeft = mouseLeft,
                         prevArrowKeys = curArrows, prevZ = zNow | stateData});
        scene

    /// 通常編集フレーム: 選択/移動/リサイズ/nudge/undo を従来どおり処理する。
    def handleEditFrame(stateData: EditorStateData, mousePos: Vec2.Vec2, mouseLeft: Bool,
                        curArrows: KeyboardNudge.ArrowKeys, zNow: Bool, undoTriggered: Bool,
                        scene: Scene[t]):
            Scene[t] \ {EditorState, EditHistory.Rewind, GameEngine.Game,
                              Fs.FileRead, Fs.FileWrite} =
        let transform = viewTransformOf(stateData);
        let mouse = {pos = mousePos, leftDown = mouseLeft};
        let (afterMouseState, afterMouseScene) =
            DragInput.handleMouse(mouse, transform, stateData, scene);
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

    /// 現在のリサイズ状態またはマウス hover に応じてカーソル形状を更新する。
    def updateCursor(mousePos: Vec2.Vec2, transform: Camera2D.ViewTransform,
                     stateData: EditorStateData,
                     scene: Scene[t]): Unit \ {GameEngine.Game} =
        let cursor = match stateData#resizeOrigin {
            case Some(origin) => cursorForHandle(origin#handle)
            case None         => match stateData#rotateOrigin {
                case Some(_) => GameEngine.Cursor.Rotate
                case None    => hoverCursor(mousePos, transform, stateData, scene)
            }
        };
        GameEngine.Game.setCursor(cursor)

    /// 選択中ノードのハンドル領域に hover していればそのハンドル用カーソル、
    /// 外していれば Default を返す。回転ノブが優先、次に 8 リサイズハンドル。
    def hoverCursor(mousePos: Vec2.Vec2, transform: Camera2D.ViewTransform,
                    stateData: EditorStateData,
                    scene: Scene[t]): GameEngine.Cursor \ GameEngine.Game =
        match stateData#selected {
            case None => GameEngine.Cursor.Default
            case Some(sel) =>
                let nodePath = sel#nodePath;
                let ctx = {rootJsonIndex = stateData#rootJsonIndex, scene = scene};
                match EditableNode.findByNodePath(ctx, nodePath) {
                    case None => GameEngine.Cursor.Default
                    case Some(entry) =>
                        let refPos = Scene.screenPositionAtWith(nodePath, transform, editor = true, scene);
                        let topLeft = Vec2.add(refPos, entry#topLeftOffset);
                        let box = {topLeft = topLeft,
                                   size = {x = entry#width, y = entry#height}};
                        // 回転ノブを先に判定。ノブはリサイズハンドルより外側に出るので
                        // 重なることは無いが、優先順を明示しておく
                        let z = stateData#editorZoom;
                        if (ResizeHandle.rotateKnobHit(mousePos, box,
                                ResizeHandle.knobOffsetFor(z), ResizeHandle.hitHalfFor(z)))
                            GameEngine.Cursor.Rotate
                        else {
                            let allowed = match Scene.getEngineNode(nodePath, scene) {
                                case Some(n) => EditableNode.allowedHandles(n)
                                case None    => ResizeHandle.all()
                            };
                            match ResizeHandle.hitTest(mousePos, box, ResizeHandle.hitHalfFor(z)) {
                                case Some(handle) if List.memberOf(handle, allowed) =>
                                    cursorForHandle(handle)
                                case _ => GameEngine.Cursor.Default
                            }
                        }
                }
        }

    /// ハンドル方向に対応するカーソル形状を返す。
    /// 4 隅は方向別の corner cursor を使う (AWT のネイティブ ↖↗↙↘ 矢印)
    def cursorForHandle(handle: ResizeHandle.Handle): GameEngine.Cursor =
        match handle {
            case ResizeHandle.Handle.Top         => GameEngine.Cursor.VResize
            case ResizeHandle.Handle.Bottom      => GameEngine.Cursor.VResize
            case ResizeHandle.Handle.Left        => GameEngine.Cursor.HResize
            case ResizeHandle.Handle.Right       => GameEngine.Cursor.HResize
            case ResizeHandle.Handle.TopLeft     => GameEngine.Cursor.NWResize
            case ResizeHandle.Handle.TopRight    => GameEngine.Cursor.NEResize
            case ResizeHandle.Handle.BottomLeft  => GameEngine.Cursor.SWResize
            case ResizeHandle.Handle.BottomRight => GameEngine.Cursor.SEResize
        }

    /// Rewind から 1 件取り出してノードを記録された状態（位置 / スケール / サイズ / 回転）に
    /// 戻し、JSON にも書き戻す。履歴に何もなければ scene 不変
    def applyUndo(scene: Scene[t]):
            Scene[t] \ {EditHistory.Rewind, Fs.FileRead, Fs.FileWrite} =
        match EditHistory.Rewind.rewind() {
            case None => scene
            case Some(EditHistory.Entry.MoveEntry(entry)) =>
                let restored = Scene.setGlobalPositionAt(
                    entry#nodePath, entry#prevWorldPos, scene);
                let localPos = match Scene.getEngineNode(entry#nodePath, restored) {
                    case Some(engineNode) => Node2D.getPosition(engineNode)
                    case None             => Vec2.zero()
                };
                SceneSerializer.updatePos(entry#jsonPath, entry#jsonNodePath, localPos);
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
                SceneSerializer.updatePosAndScale(entry#jsonPath, entry#jsonNodePath,
                                                   localPos, entry#prevScale);
                restored
            case Some(EditHistory.Entry.ResizeEntry(entry)) =>
                // 各 snapshot のノードを開始時状態に戻し、まとめて 1 ファイル書込で永続化。
                // snapshot は live path を持つため、書き戻し時に toJsonNodePath で翻訳する
                let restoredScene = List.foldLeft((acc, snap) ->
                    Scene.mapEngineNode(snap#nodePath,
                        n -> EditableNode.restoreFromSnapshot(snap, n), acc),
                    scene, entry#snapshots);
                let nodeUpdates = List.map(snap -> ({
                    nodePath = EditableNode.toJsonNodePath(snap#nodePath, restoredScene),
                    updates = EditableNode.snapshotToFieldUpdates(snap)
                }: SceneSerializer.NodeUpdate), entry#snapshots);
                SceneSerializer.updateMany(entry#jsonPath, nodeUpdates);
                restoredScene
            case Some(EditHistory.Entry.RotateEntry(entry)) =>
                let restored = Scene.mapEngineNode(entry#nodePath,
                    Node2D.setRotation(entry#prevRotation), scene);
                SceneSerializer.updateRotation(entry#jsonPath, entry#jsonNodePath,
                                                entry#prevRotation);
                restored
            case Some(EditHistory.Entry.RemoveSubtreeEntry(entry)) =>
                // 除去したサブツリーを同位置へ戻す。live scene は JSON 書き戻し→
                // HotReload の再 load で復元される（構造復元を live Scene へ直接行わない）。
                discard SceneSerializer.insertSubtree(entry#jsonPath, entry#parentPath,
                                                       entry#index, entry#fragment);
                scene
            case Some(EditHistory.Entry.AddedNodeEntry(entry)) =>
                // 追加/複製したノードを取り除く（追加の逆操作）。同じく HotReload で反映。
                discard SceneSerializer.removeChild(entry#jsonPath, entry#nodePath);
                scene
        }

    /// 現在のシーンの有効カメラから ViewTransform を計算する。
    /// カメラがなければ identity（CanvasLayer のみのシーン等）
    /// エディタの自由カメラ (pan/zoom) を ViewTransform に変換する。シーン内カメラには依らず、
    /// editor の offset/zoom だけで決まる (Godot のエディタビューと同じく独立)。
    /// エディタの操作・描画・オーバーレイはすべて design-px (zoom=1) 空間で行う。
    /// pan/zoom は投影 (setEditorView 経由) とマウス逆変換だけで効かせるので、
    /// ここで返す変換は常に identity。これで move/resize/picking の計算が zoom に依らず一定になる。
    def viewTransformOf(_stateData: EditorStateData): Camera2D.ViewTransform =
        Camera2D.identityTransform()

    /// 現在のエディタビュー変換 = identity（pan/zoom は投影側）。
    /// Main の renderWith / overlay / 入力で共有する。
    pub def currentViewTransform(): Camera2D.ViewTransform =
        Camera2D.identityTransform()

    /// 投影に焼き込む自由カメラ。panX/panY は FBO 原点に表示する design-px 座標、zoom は拡大率。
    /// Main が毎フレーム GameEngine.Game.setEditorView へ渡す。
    pub def currentEditorView(): {panX = Float64, panY = Float64, zoom = Float64} \ EditorState =
        let s = EditorState.get();
        {panX = s#editorOffset#x, panY = s#editorOffset#y, zoom = s#editorZoom}

    /// 現在のスナップ間隔(px)。0.0 = スナップ OFF。グリッド表示判定に使う。
    pub def currentSnapStep(): Float64 \ EditorState =
        EditorState.get()#snapStep

    def activeViewTransform(_scene: Scene[t]): Camera2D.ViewTransform =
        Camera2D.identityTransform()

    def zoomStepButton(): Float64 = 1.25

    /// scroll（ホイール / ピンチの 1 フレーム蓄積量）を倍率に変換する。大きさに比例するので
    /// ピンチの微調整も効く。1 フレームの急変を避けるため [0.4, 2.5] にクランプ。
    def zoomFactorFromScroll(scroll: Float64): Float64 =
        let f = 1.0 + scroll * 0.05;
        if (f < 0.4) 0.4 else if (f > 2.5) 2.5 else f

    /// center（カーソル下の design-px 点）を画面上で固定したまま zoom を factor 倍する。
    /// 投影は fbo = (design - pan) * zoom。center を同じ fbo に保つ pan:
    ///   pan' = center - (center - pan) * (zoom / newZoom)
    def applyZoomFactor(stateData: EditorStateData, factor: Float64, center: Vec2.Vec2):
            EditorStateData =
        let newZoom = clampZoom(stateData#editorZoom * factor);
        let ratio = stateData#editorZoom / newZoom;
        let pan = stateData#editorOffset;
        let newPan = {x = center#x - (center#x - pan#x) * ratio,
                      y = center#y - (center#y - pan#y) * ratio};
        {editorZoom = newZoom, editorOffset = newPan | stateData}

    /// マウスホイール / ピンチでカーソル中心にズーム。scroll は scrollDelta（ピンチも合算済み）。
    def applyWheelZoom(stateData: EditorStateData, scroll: Float64, cursor: Vec2.Vec2):
            EditorStateData =
        if (scroll == 0.0) stateData
        else applyZoomFactor(stateData, zoomFactorFromScroll(scroll), cursor)

    /// ツールバーのズームボタン。1=イン, -1=アウト（ともにビュー中心基準）, 2=リセット(100%)。
    def applyButtonZoom(stateData: EditorStateData, cmd: Int32, center: Vec2.Vec2):
            EditorStateData =
        if (cmd == 1i32) applyZoomFactor(stateData, zoomStepButton(), center)
        else if (cmd == -1i32) applyZoomFactor(stateData, 1.0 / zoomStepButton(), center)
        else if (cmd == 2i32) {editorZoom = 1.0, editorOffset = Vec2.zero() | stateData}
        else stateData

    def clampZoom(z: Float64): Float64 =
        if (z < 0.1) 0.1 else if (z > 60.0) 60.0 else z

    /// 二本指ドラッグ(スクロール)でキャンバスをパン。dx/dy は screen px の移動量。
    /// editorOffset は panDesign（FBO 原点に映す design-px）なので screen 量を /zoom で換算する。
    def applyScrollPan(stateData: EditorStateData, dx: Float64, dy: Float64): EditorStateData =
        if (dx == 0.0 and dy == 0.0) stateData
        else {
            let z = if (stateData#editorZoom <= 0.0) 1.0 else stateData#editorZoom;
            let pan = stateData#editorOffset;
            {editorOffset = {x = pan#x - dx / z, y = pan#y - dy / z} | stateData}
        }

    /// ドラッグでパン。掴んだ design 点 (designStart) を物理カーソルに追従させる。
    /// mouse は getMousePosition の逆変換済み design-px（現在の pan に依存）。
    /// pan' = pan + (designStart - mouse) と置くと、毎フレーム pan = designStart - fboCur/zoom に
    /// 収束し、掴んだ点がカーソル直下に留まる（pan への依存が打ち消される）。
    def applyPan(stateData: EditorStateData, panning: Bool, mouse: Vec2.Vec2): EditorStateData =
        match (panning, stateData#panOrigin) {
            case (true, None) =>
                {panOrigin = Some((mouse, Vec2.zero())) | stateData}
            case (true, Some((designStart, _))) =>
                let adjust = Vec2.sub(designStart, mouse);
                {editorOffset = Vec2.add(stateData#editorOffset, adjust) | stateData}
            case (false, _) =>
                {panOrigin = None | stateData}
        }

    /// HotReload watcher の通知をノンブロッキングで消費する。
    /// editor ON 中は HotReload を握り潰す。理由:
    ///   - editor の編集は Scene.mapEngineNode で live scene に即時反映済みなので、
    ///     JSON 書き戻し後に applyPhaseChange でシーンを再構築する必要が無い
    ///   - editor ON のとき GameEngine.process / physicsProcess 等もスキップしているのと
    ///     対称的に、HotReload も止めるのが意図に合う（ゲームを止めて編集に集中する）
    ///   - editor 経由の save → HotReload → rebuild の連鎖でパイプ等が
    ///     初期位置から再 spawn されてしまう regression を防ぐ
    ///
    /// 受信した通知自体は捨てず、`EditorState.pollReload` を呼んで非ブロッキング受信は実行する
    /// （チャネルにメッセージが溜まり続けないようにするため）
    pub def pollReload(): Bool \ EditorState =
        let consumed = EditorState.pollReload();
        let s = EditorState.get();
        if (s#on) false else consumed

    /// editor の on/off に関わらず HotReload 通知をそのまま返す。
    /// IDE のように「editor ON が通常状態」のホストでも、ドラッグ確定で書き戻された
    /// JSON を再読込して JTree / Inspector を最新値に更新したいときに使う。
    /// pollReload とは違って消費後に握り潰さない
    pub def pollRawReload(): Bool \ EditorState =
        EditorState.pollReload()

    /// 描画用のオーバーレイをシーンに合成する。Game.flix の render 直前に呼ぶ。
    pub def applyOverlay(defaultTag: t, scene: Scene[t]):
            Scene[t] \ {EditorState, GameEngine.Game} =
        let stateData = EditorState.get();
        if (not stateData#on) scene
        else {
            let mousePos = GameEngine.Game.getMousePosition();
            let transform = activeViewTransform(scene);
            let zoom = stateData#editorZoom;
            scene
                |> Overlay.addCollisionShapes(transform, zoom, defaultTag)
                |> Overlay.addSelectionBox(stateData#rootJsonIndex, stateData#selected,
                                           transform, zoom, defaultTag)
                |> Overlay.addHoverBox(stateData#rootJsonIndex, mousePos, stateData#selected,
                                       transform, zoom, defaultTag)
        }
}
