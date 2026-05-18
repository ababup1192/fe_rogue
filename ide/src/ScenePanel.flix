// ScenePanel — Scenes タブ専用 (Scene TreeView + Inspector + Status bar)
//
// JavaFXIdeUI.customize から wireTreeSelection / startStatusBarTimer が呼ばれる。
// startStatusBarTimer は AnimationTimer を起動して 60Hz で:
//   - status bar の各 Label (Scene path / Mouse / Selection / FPS) を更新
//   - selection 文字列が変わったら rebuildInspector を呼んで Inspector を再構築
//   - Inspector の各 widget を currentValues map から最新化
// する。
//
// Inspector は schema 駆動: NodeInspector.fieldsFor が返す FieldDef リストに従って
// widget を組み立て、value updater を widgetUpdaters Map に登録する。
// 編集 commit は state#inspector#pendingEdits に積み、Main が consume してファイル書き戻す。

mod ScenePanel {
    import java.lang.{Object => JObject}
    import javafx.animation.AnimationTimer
    import javafx.collections.ObservableList
    import javafx.scene.Node
    import javafx.scene.control.Label
    import javafx.scene.control.TextField
    import javafx.scene.control.CheckBox
    import javafx.scene.control.ColorPicker
    import javafx.scene.control.ComboBox
    import javafx.scene.control.Spinner
    import javafx.scene.paint.{Color => FxColor}
    import javafx.scene.control.TitledPane
    import javafx.scene.control.TreeView
    import javafx.scene.control.TreeItem
    import javafx.scene.control.MultipleSelectionModel
    import javafx.scene.image.ImageView
    import javafx.scene.input.MouseEvent
    import javafx.scene.layout.HBox
    import javafx.scene.layout.VBox
    import javafx.event.EventHandler
    import javafx.beans.value.ChangeListener
    import javafx.beans.value.ObservableValue
    import java.lang.Double
    import java.lang.Integer

    /// TreeView の選択変更を処理する。
    /// シーンファイル (top-level) を選んだ場合は pendingSceneRef に積む。
    /// シーン内 node を選んだ場合は pendingNodeSelection に積み、Main が Editor#selected に反映
    pub def wireTreeSelection(state: IdeState.IdeState, tree: TreeView[String]): Unit \ IO = {
        let selectionModel = tree.getSelectionModel();
        let prop = selectionModel.selectedItemProperty();
        let listener = new ChangeListener[TreeItem[String]] {
            def changed(_cThis: ChangeListener[TreeItem[String]],
                         _obs: ObservableValue[JObject],
                         _old: TreeItem[String], newSel: TreeItem[String]): Unit \ IO = {
                if (Object.isNull(newSel)) ()
                else {
                    let pairs = Array.get(0, state#sceneFilesRef);
                    let chain = collectFromTopLevel(newSel);
                    match chain {
                        case Nil => ()
                        case sceneRel :: rest =>
                            match List.find(p -> { let r = snd(p); r == sceneRel }, pairs) {
                                case None => ()
                                case Some((abs, _)) =>
                                    if (List.isEmpty(rest)) {
                                        // scene file クリック → 読み込み要求
                                        println("[IdeUI] Scene selected: ${sceneRel}");
                                        Array.put(Some(abs), 0, state#pendingSceneRef)
                                    } else {
                                        // scene 内 node クリック → 選択要求
                                        let sel: Editor.Selection = {
                                            jsonPath = abs,
                                            nodePath = rest,
                                            jsonNodePath = rest
                                        };
                                        Array.put(Some(sel), 0, state#runtime#pendingNodeSelection)
                                    }
                            }
                    }
                }
            }
        };
        prop.addListener(listener)
    }

    /// 選択 TreeItem から top-level (シーンファイル) までを root→leaf 順で値リスト化する。
    /// hidden root (getParent() == null の祖先) はスキップ
    def collectFromTopLevel(item: TreeItem[String]): List[String] \ IO = {
        let parent = item.getParent();
        if (Object.isNull(parent)) {
            // hidden root を踏んだ場合
            Nil
        } else if (Object.isNull(parent.getParent())) {
            // 親が hidden root = 自分が top-level
            item.getValue() :: Nil
        } else {
            List.append(collectFromTopLevel(parent), item.getValue() :: Nil)
        }
    }

    /// Scenes TreeView を sceneFilesRef + 現シーンの SceneTree から populate する。
    /// 各シーンファイルを top-level TreeItem として並べ、現在ロード中のシーンには
    /// 子として node 階層を展開する (他シーンは leaf 扱い)
    pub def populateSceneTree(state: IdeState.IdeState): Unit \ IO = {
        match Array.get(0, state#widgets#sceneTree) {
            case None => ()
            case Some(tree) => {
                let pairs = Array.get(0, state#sceneFilesRef);
                let currentScenePath = Array.get(0, state#currentScenePathRef);
                let sceneTree = Array.get(0, state#runtime#sceneTree);
                let root: TreeItem[String] = new TreeItem("Scenes");
                root.setExpanded(true);
                List.forEach(p -> {
                    let (abs, rel) = p;
                    let fileItem: TreeItem[String] = new TreeItem(rel);
                    fileItem.setExpanded(true);
                    // このシーンが現在ロード中なら、その node 階層を子として展開
                    if (Some(abs) == currentScenePath) {
                        List.forEach(n -> {
                            let child = buildTreeItem(n);
                            discard fileItem.getChildren().add(child)
                        }, sceneTree)
                    } else ();
                    discard root.getChildren().add(fileItem)
                }, pairs);
                tree.setRoot(root);
                tree.setShowRoot(false)
            }
        }
    }

    /// SceneTreeNode を JavaFX TreeItem 階層に変換する
    def buildTreeItem(n: NodeInspector.SceneTreeNode): TreeItem[String] \ IO = {
        let NodeInspector.SceneTreeNode.SNode(displayName, _path, children) = n;
        let item: TreeItem[String] = new TreeItem(displayName);
        item.setExpanded(true);
        List.forEach(c -> {
            let childItem = buildTreeItem(c);
            discard item.getChildren().add(childItem)
        }, children);
        item
    }

    /// ステータスバー更新タイマーを起動する。FX thread で 60Hz で発火し、state の各 Ref を
    /// 読んで Label.setText するだけ。Label 更新は FX thread でしか許されないので Timer 内で完結
    pub def startStatusBarTimer(state: IdeState.IdeState, canvasView: ImageView): Unit \ IO = {
        let lastTimeRef = Array#{0i64} @ Static;
        let frameCountRef = Array#{0i32} @ Static;
        let mouseXRef = Array#{0.0} @ Static;
        let mouseYRef = Array#{0.0} @ Static;
        canvasView.addEventHandler(MouseEvent.MOUSE_MOVED,
            new EventHandler[MouseEvent] {
                def handle(_this: EventHandler[MouseEvent], e: MouseEvent): Unit \ IO = {
                    Array.put(e.getX(), 0, mouseXRef);
                    Array.put(e.getY(), 0, mouseYRef)
                }
            });

        let timer = new AnimationTimer {
            def handle(_this: AnimationTimer, now: Int64): Unit \ IO = {
                // FPS 計測
                let last = Array.get(0, lastTimeRef);
                if (last == 0i64) {
                    Array.put(now, 0, lastTimeRef)
                } else {
                    let elapsed = now - last;
                    let frames = Array.get(0, frameCountRef) + 1i32;
                    if (elapsed >= 1000000000i64) {
                        PropertyWidgets.withRef(state#statusBar#fpsLabel, lbl ->
                            lbl.setText("${frames} fps"));
                        Array.put(0i32, 0, frameCountRef);
                        Array.put(now, 0, lastTimeRef)
                    } else {
                        Array.put(frames, 0, frameCountRef)
                    }
                };

                // Scene path
                PropertyWidgets.withRef(state#statusBar#sceneLabel, lbl -> {
                    let txt = match Array.get(0, state#currentScenePathRef) {
                        case Some(p) => "Scene: ${shortenPath(p)}"
                        case None    => "(no scene)"
                    };
                    lbl.setText(txt)
                });

                // Mouse
                PropertyWidgets.withRef(state#statusBar#mouseLabel, lbl -> {
                    let mx = Float64.tryToInt32(Array.get(0, mouseXRef))
                              |> Option.getWithDefault(0i32);
                    let my = Float64.tryToInt32(Array.get(0, mouseYRef))
                              |> Option.getWithDefault(0i32);
                    lbl.setText("mouse: ${mx}, ${my}")
                });

                // Selection
                let curSel = Array.get(0, state#runtime#editorSelDisplay);
                PropertyWidgets.withRef(state#statusBar#selectionLabel, lbl ->
                    lbl.setText("sel: ${curSel}"));

                // Inspector: selection 文字列が変わったら rebuild
                let prevSel = Array.get(0, state#inspector#lastSel);
                if (curSel != prevSel) {
                    rebuildInspector(state, curSel);
                    Array.put(curSel, 0, state#inspector#lastSel)
                } else ();

                // Inspector の各 widget を currentValues から最新化
                let values = Array.get(0, state#inspector#currentValues);
                let updaters = Array.get(0, state#inspector#widgetUpdaters);
                Map.forEach((name, json) -> {
                    match Map.get(name, updaters) {
                        case Some(updater) => updater(json)
                        case None          => ()
                    }
                }, values);

                // World position は schema 外の特別行 (read-only)
                updateWorldPosLabel(state);

                // canvas クリックなどで editor#selected が変わったら TreeView の
                // 選択もそれに合わせる (Swing 版の SelectionBridge.syncEditorSelectionToTree 相当)
                syncTreeSelectionFromEditor(state)
            }
        };
        timer.start()
    }

    /// editor の selected を TreeView に反映する。canvas クリックで sprite を選んだとき
    /// 左の TreeView でも対応行がハイライトされるようにする。
    ///
    /// editor#selected が None のときは何もしない (scene file (top-level) クリック等で
    /// editor#selected がリセットされる前のフレームに、user の tree 選択を消してしまう
    /// race condition を避けるため)
    def syncTreeSelectionFromEditor(state: IdeState.IdeState): Unit \ IO = {
        match Array.get(0, state#widgets#sceneTree) {
            case None       => ()
            case Some(tree) => {
                let model: MultipleSelectionModel[TreeItem[String]] = tree.getSelectionModel();
                let selOpt = Array.get(0, state#inspector#currentSelection);
                match selOpt {
                    case None => ()
                    case Some(sel) => {
                        let sceneFiles = Array.get(0, state#sceneFilesRef);
                        let target = sel#jsonPath;
                        let matched = List.find(p -> fst(p) == target, sceneFiles);
                        match matched {
                            case None    => ()
                            case Some(p) => {
                                let rel = snd(p);
                                let root: TreeItem[String] = tree.getRoot();
                                if (Object.isNull(root)) ()
                                else {
                                    let targetChain = rel :: sel#nodePath;
                                    let cur: TreeItem[String] = model.getSelectedItem();
                                    let curChain = if (Object.isNull(cur)) Nil
                                                   else collectFromTopLevel(cur);
                                    if (curChain == targetChain) ()
                                    else {
                                        match findTreeItem(root, rel, sel#nodePath) {
                                            case None         => ()
                                            case Some(item)   => model.$select(item)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// root の children から scene file 行を見つけ、そこから node path で深く辿る
    def findTreeItem(root: TreeItem[String], sceneRel: String, nodePath: List[String]):
            Option[TreeItem[String]] \ IO = {
        let kids = root.getChildren();
        match findChildByName(kids, kids.size(), 0i32, sceneRel) {
            case None    => None
            case Some(s) => walkNodePath(s, nodePath)
        }
    }

    def walkNodePath(item: TreeItem[String], path: List[String]):
            Option[TreeItem[String]] \ IO =
        match path {
            case Nil          => Some(item)
            case name :: rest => {
                let kids = item.getChildren();
                match findChildByName(kids, kids.size(), 0i32, name) {
                    case None    => None
                    case Some(c) => walkNodePath(c, rest)
                }
            }
        }

    def findChildByName(kids: ObservableList[TreeItem[String]],
                         n: Int32, i: Int32, name: String):
            Option[TreeItem[String]] \ IO =
        if (i >= n) None
        else {
            let c = kids.get(i);
            if (c.getValue() == name) Some(c)
            else findChildByName(kids, n, i + 1i32, name)
        }

    /// scene path は project root 込みで長いので、表示用に末尾の rel 部分だけ残す
    def shortenPath(absPath: String): String =
        match String.indexOfRight({substr = "/src/"}, absPath) {
            case Some(i) => String.sliceRight(start = i + 1, absPath)
            case None    => absPath
        }

    /// World position Label を更新する (read-only な特別行)
    def updateWorldPosLabel(state: IdeState.IdeState): Unit \ IO =
        PropertyWidgets.withRef(state#inspector#posLabel, lbl -> {
            let txt = match Array.get(0, state#inspector#worldPos) {
                case Some((x, y)) =>
                    let ix = Float64.tryToInt32(x) |> Option.getWithDefault(0i32);
                    let iy = Float64.tryToInt32(y) |> Option.getWithDefault(0i32);
                    "(${ix}, ${iy})"
                case None => "-"
            };
            lbl.setText(txt)
        })

    /// Inspector pane の中身を再構築する。selection が変わったときだけ呼ばれる。
    /// schema (state#inspector#schema) を辿って widget を生成し、widgetUpdaters に
    /// 値更新クロージャを登録する。commit listener は state#inspector#pendingEdits に積む
    def rebuildInspector(state: IdeState.IdeState, selDisplay: String): Unit \ IO = {
        match Array.get(0, state#inspector#content) {
            case None => ()
            case Some(box) => {
                let children = box.getChildren();
                children.clear();
                Array.put((None: Option[Label]), 0, state#inspector#posLabel);
                Array.put((Map.empty(): Map[String, Json.JsonElement -> Unit \ IO]),
                          0, state#inspector#widgetUpdaters);
                if (selDisplay == "-") {
                    let placeholder = new Label("(nothing selected)");
                    placeholder.getStyleClass().add("inspector-empty");
                    let placeholderNode: Node = checked_cast(placeholder);
                    discard children.add(placeholderNode)
                } else {
                    // 「選択中ノードのパス」 + 「World position」は schema 外の固定行
                    let pathLabel = new Label(selDisplay);
                    pathLabel.setWrapText(true);
                    let pathNode: Node = checked_cast(pathLabel);
                    PropertyWidgets.addPropertyRow(children, "Selected:", pathNode);

                    let worldPosValue = new Label("-");
                    let worldPosNode: Node = checked_cast(worldPosValue);
                    PropertyWidgets.addPropertyRow(children, "World position:", worldPosNode);
                    Array.put(Some(worldPosValue), 0, state#inspector#posLabel);

                    // schema 駆動: 継承階層の各セクション (Node2D / Sprite2D / ...) ごとに
                    // header label + common fields + Advanced disclosure (advanced fields) を描画
                    let sections = Array.get(0, state#inspector#schema);
                    let values = Array.get(0, state#inspector#currentValues);
                    let selOpt = Array.get(0, state#inspector#currentSelection);
                    List.forEach(section -> {
                        addSectionHeader(children, section#typeName);
                        match selOpt {
                            case None      => ()
                            case Some(sel) => {
                                List.forEach(fd -> addSchemaRow(state, children, fd, values, sel),
                                             section#common);
                                if (not List.isEmpty(section#advanced))
                                    addAdvancedDisclosure(state, children, section#advanced, values, sel)
                                else ()
                            }
                        }
                    }, sections)
                }
            }
        }
    }

    /// 継承階層の 1 段ぶんの header label を追加する (Swing 版の見出し相当)
    def addSectionHeader(children: ObservableList[Node], typeName: String): Unit \ IO = {
        let lbl = new Label(typeName);
        lbl.getStyleClass().add("node-class-header");
        let n: Node = checked_cast(lbl);
        discard children.add(n)
    }

    /// Advanced disclosure を section の末尾に追加する。
    /// TitledPane で展開可能にし、初期状態は折りたたみ (普段は隠したいフィールド用)
    def addAdvancedDisclosure(state: IdeState.IdeState, children: ObservableList[Node],
                               advancedFields: List[NodeInspector.FieldDef],
                               currentValues: Map[String, Json.JsonElement],
                               sel: Editor.Selection): Unit \ IO = {
        let inner = new VBox(4.0);
        let innerKids = inner.getChildren();
        List.forEach(fd -> addSchemaRow(state, innerKids, fd, currentValues, sel), advancedFields);
        let innerNode: Node = checked_cast(inner);
        let pane = new TitledPane();
        pane.setText("Advanced");
        pane.setExpanded(false);
        pane.setContent(innerNode);
        pane.getStyleClass().add("inspector-advanced");
        let n: Node = checked_cast(pane);
        discard children.add(n)
    }

    /// 1 FieldDef を Inspector に追加する
    def addSchemaRow(state: IdeState.IdeState, children: ObservableList[Node],
                      fd: NodeInspector.FieldDef,
                      currentValues: Map[String, Json.JsonElement],
                      sel: Editor.Selection): Unit \ IO = {
        let currentJson = Map.get(fd#name, currentValues);
        let applyFn = fd#apply;
        let commit: PropertyWidgets.Commit = json -> {
            let pe: NodeInspector.PendingEdit = { perform = () -> applyFn(sel, json) };
            let existing = Array.get(0, state#inspector#pendingEdits);
            Array.put(List.append(existing, pe :: Nil), 0, state#inspector#pendingEdits)
        };
        let textureNames = Array.get(0, state#textureNamesRef);
        let (widget, updater) = buildWidgetForKind(fd#kind, currentJson, textureNames, commit);
        PropertyWidgets.addPropertyRow(children, "${fd#label}:", widget);
        let map = Array.get(0, state#inspector#widgetUpdaters);
        Array.put(Map.insert(fd#name, updater, map), 0, state#inspector#widgetUpdaters)
    }

    /// FieldKind に応じた widget を生成し、(widget, 値更新 closure) を返す
    def buildWidgetForKind(kind: NodeInspector.FieldKind,
                           current: Option[Json.JsonElement],
                           textureNames: List[String],
                           commit: PropertyWidgets.Commit):
            (Node, Json.JsonElement -> Unit \ IO) \ IO =
        match kind {
            case NodeInspector.FieldKind.Vec2T => {
                let isInt = true;
                let widget = PropertyWidgets.buildVec2Widget(current, isInt, commit);
                let updater = (json: Json.JsonElement) -> updateVec2Widget(widget, json, isInt);
                (widget, updater)
            }
            case NodeInspector.FieldKind.FloatT => {
                let widget = PropertyWidgets.buildFloatWidget(current, commit);
                let updater = (json: Json.JsonElement) -> updateFloatSpinner(widget, json);
                (widget, updater)
            }
            case NodeInspector.FieldKind.IntT => {
                let widget = PropertyWidgets.buildIntWidget(current, commit);
                let updater = (json: Json.JsonElement) -> updateIntSpinner(widget, json);
                (widget, updater)
            }
            case NodeInspector.FieldKind.TextT => {
                let widget = PropertyWidgets.buildTextWidget(current, commit);
                let updater = (json: Json.JsonElement) -> updateTextField(widget, json);
                (widget, updater)
            }
            case NodeInspector.FieldKind.TexturePathT => {
                let widget = PropertyWidgets.buildTexturePathWidget(current, textureNames, commit);
                let updater = (json: Json.JsonElement) -> updateComboBox(widget, json);
                (widget, updater)
            }
            case NodeInspector.FieldKind.BoolT => {
                let widget = PropertyWidgets.buildBoolWidget(current, commit);
                let updater = (json: Json.JsonElement) -> updateCheckBox(widget, json);
                (widget, updater)
            }
            case NodeInspector.FieldKind.ColorT => {
                let widget = PropertyWidgets.buildColorWidget(current, commit);
                // ColorPicker は per-frame で setValue しない。snapshot が user pick より
                // ラグするタイミングで古い色を上書きしてしまうため。
                // rebuildInspector (選択変更時) で picker が再生成されて値が同期する
                let updater = (j: Json.JsonElement) -> {
                    let _ = j;
                    let _: Array[Int32, Static] = Array#{0i32} @ Static;
                    ()
                };
                (widget, updater)
            }
            case NodeInspector.FieldKind.EnumT(options) => {
                let widget = PropertyWidgets.buildEnumWidget(current, options, commit);
                let updater = (json: Json.JsonElement) -> updateEnumCombo(widget, json);
                (widget, updater)
            }
        }

    /// Vec2 widget (VBox の 2 行、各行 HBox(Label, Spinner)) を JSON から復元する。
    /// PropertyWidgets.buildVec2Widget の構造に合わせて X / Y Spinner を引き直す
    def updateVec2Widget(widget: Node, json: Json.JsonElement, isInt: Bool): Unit \ IO = {
        let box: VBox = unchecked_cast(widget as VBox);
        let rows = box.getChildren();
        let xRow: HBox = unchecked_cast(rows.get(0i32) as HBox);
        let yRow: HBox = unchecked_cast(rows.get(1i32) as HBox);
        let xn = xRow.getChildren().get(1i32);
        let yn = yRow.getChildren().get(1i32);
        match NodeInspector.jsonToVec2(json) {
            case None => ()
            case Some(v) =>
                if (isInt) {
                    let xs: Spinner[Integer] = unchecked_cast(xn as Spinner[Integer]);
                    let ys: Spinner[Integer] = unchecked_cast(yn as Spinner[Integer]);
                    let ix = Float64.tryToInt32(v#x) |> Option.getWithDefault(0i32);
                    let iy = Float64.tryToInt32(v#y) |> Option.getWithDefault(0i32);
                    if (not xs.getEditor().isFocused()) {
                        xs.getValueFactory().setValue(Integer.valueOf(ix))
                    } else ();
                    if (not ys.getEditor().isFocused()) {
                        ys.getValueFactory().setValue(Integer.valueOf(iy))
                    } else ()
                } else {
                    let xs: Spinner[Double] = unchecked_cast(xn as Spinner[Double]);
                    let ys: Spinner[Double] = unchecked_cast(yn as Spinner[Double]);
                    if (not xs.getEditor().isFocused()) {
                        xs.getValueFactory().setValue(Double.valueOf(v#x))
                    } else ();
                    if (not ys.getEditor().isFocused()) {
                        ys.getValueFactory().setValue(Double.valueOf(v#y))
                    } else ()
                }
        }
    }

    def updateFloatSpinner(widget: Node, json: Json.JsonElement): Unit \ IO = {
        let sp: Spinner[Double] = unchecked_cast(widget as Spinner[Double]);
        match NodeInspector.jsonToFloat(json) {
            case None => ()
            case Some(v) =>
                if (not sp.getEditor().isFocused()) {
                    sp.getValueFactory().setValue(Double.valueOf(v))
                } else ()
        }
    }

    def updateIntSpinner(widget: Node, json: Json.JsonElement): Unit \ IO = {
        let sp: Spinner[Integer] = unchecked_cast(widget as Spinner[Integer]);
        match NodeInspector.jsonToInt(json) {
            case None => ()
            case Some(v) =>
                if (not sp.getEditor().isFocused()) {
                    sp.getValueFactory().setValue(Integer.valueOf(v))
                } else ()
        }
    }

    def updateTextField(widget: Node, json: Json.JsonElement): Unit \ IO = {
        let tf: TextField = unchecked_cast(widget as TextField);
        match NodeInspector.jsonToString(json) {
            case None    => ()
            case Some(s) => if (not tf.isFocused()) tf.setText(s) else ()
        }
    }

    def updateComboBox(widget: Node, json: Json.JsonElement): Unit \ IO = {
        let cb: ComboBox[String] = unchecked_cast(widget as ComboBox[String]);
        match NodeInspector.jsonToString(json) {
            case None    => ()
            case Some(s) => cb.setValue(s)
        }
    }

    def updateCheckBox(widget: Node, json: Json.JsonElement): Unit \ IO = {
        let cb: CheckBox = unchecked_cast(widget as CheckBox);
        match NodeInspector.jsonToBool(json) {
            case None    => ()
            case Some(b) => cb.setSelected(b)
        }
    }

    def updateEnumCombo(widget: Node, json: Json.JsonElement): Unit \ IO = {
        let cb: ComboBox[String] = unchecked_cast(widget as ComboBox[String]);
        match NodeInspector.jsonToString(json) {
            case None    => ()
            case Some(s) => cb.setValue(s)
        }
    }

}
