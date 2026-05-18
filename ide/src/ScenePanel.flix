// ScenePanel — Scenes タブ専用 (Scene TreeView + Inspector + Status bar)
//
// JavaFXIdeUI.customize から wireTreeSelection / startStatusBarTimer が呼ばれる。
// startStatusBarTimer は AnimationTimer を起動して 60Hz で:
//   - status bar の各 Label (Scene path / Mouse / Selection / FPS) を更新
//   - selection 文字列が変わったら rebuildInspector を呼んで Inspector を再構築
//   - Inspector の World position / Local position / Scale / Rotation を毎フレーム最新化
// する。
//
// Inspector の編集 widget は PropertyWidgets.wireNumericField を使い、commit 時に
// pendingXxxEditRef に値を積む。Main.applyInspectorEdits がそれを消費して JSON 書き戻し。

mod ScenePanel {
    import java.lang.{Object => JObject}
    import javafx.animation.AnimationTimer
    import javafx.collections.ObservableList
    import javafx.scene.Node
    import javafx.scene.control.Label
    import javafx.scene.control.TextField
    import javafx.scene.control.TreeView
    import javafx.scene.control.TreeItem
    import javafx.scene.image.ImageView
    import javafx.scene.input.MouseEvent
    import javafx.scene.layout.HBox
    import javafx.event.EventHandler
    import javafx.beans.value.ChangeListener
    import javafx.beans.value.ObservableValue

    /// TreeView の選択変更を pendingSceneRef に伝える。
    /// 表示文字列は relative path で持っているため、sceneFilesRef の (abs, rel) リストから
    /// マッチする absolute path を引き直して pendingSceneRef に積む
    pub def wireTreeSelection(state: IdeState.IdeState, tree: TreeView[String]): Unit \ IO = {
        let selectionModel = tree.getSelectionModel();
        let prop = selectionModel.selectedItemProperty();
        let listener = new ChangeListener[TreeItem[String]] {
            def changed(_cThis: ChangeListener[TreeItem[String]],
                         _obs: ObservableValue[JObject],
                         _old: TreeItem[String], newSel: TreeItem[String]): Unit \ IO = {
                if (Object.isNull(newSel)) ()
                else {
                    let rel = newSel.getValue();
                    let pairs = Array.get(0, state#sceneFilesRef);
                    let target = rel;
                    match List.find(p -> { let r = snd(p); r == target }, pairs) {
                        case Some((abs, _)) =>
                            println("[IdeUI] Scene selected: ${rel}");
                            Array.put(Some(abs), 0, state#pendingSceneRef)
                        case None => ()
                    }
                }
            }
        };
        prop.addListener(listener)
    }

    /// Scenes TreeView を sceneFilesRef から populate する
    pub def populateSceneTree(state: IdeState.IdeState): Unit \ IO = {
        match Array.get(0, state#fxSceneTreeRef) {
            case None => ()
            case Some(tree) => {
                let pairs = Array.get(0, state#sceneFilesRef);
                let root: TreeItem[String] = new TreeItem("Scenes");
                root.setExpanded(true);
                List.forEach(p -> {
                    let item: TreeItem[String] = new TreeItem(snd(p));
                    discard root.getChildren().add(item)
                }, pairs);
                tree.setRoot(root);
                tree.setShowRoot(false)
            }
        }
    }

    /// ステータスバー更新タイマーを起動する。FX thread で 60Hz で発火し、state の各 Ref を
    /// 読んで Label.setText するだけ。Label 更新は FX thread でしか許されないので Timer 内で完結
    pub def startStatusBarTimer(state: IdeState.IdeState, canvasView: ImageView): Unit \ IO = {
        let lastTimeRef = Array#{0i64} @ Static;
        let frameCountRef = Array#{0i32} @ Static;
        let mouseXRef = Array#{0.0} @ Static;
        let mouseYRef = Array#{0.0} @ Static;
        // canvas hover でマウス座標を追跡。JavaFXLayer の input handler とは別経路 (addEventHandler
        // で複数 listener を共存させる)
        canvasView.addEventHandler(MouseEvent.MOUSE_MOVED,
            new EventHandler[MouseEvent] {
                def handle(_this: EventHandler[MouseEvent], e: MouseEvent): Unit \ IO = {
                    Array.put(e.getX(), 0, mouseXRef);
                    Array.put(e.getY(), 0, mouseYRef)
                }
            });

        let timer = new AnimationTimer {
            def handle(_this: AnimationTimer, now: Int64): Unit \ IO = {
                // FPS 計測: 1 秒に 1 回 Label 更新
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

                // Mouse: ImageView local 座標 (FBO は ImageView と同サイズなのでこれが design 座標)
                PropertyWidgets.withRef(state#statusBar#mouseLabel, lbl -> {
                    let mx = Float64.tryToInt32(Array.get(0, mouseXRef))
                              |> Option.getWithDefault(0i32);
                    let my = Float64.tryToInt32(Array.get(0, mouseYRef))
                              |> Option.getWithDefault(0i32);
                    lbl.setText("mouse: ${mx}, ${my}")
                });

                // Selection: renderLoop が editor 状態を直接書き込んだ表示文字列を使う
                let curSel = Array.get(0, state#fxEditorSelDisplayRef);
                PropertyWidgets.withRef(state#statusBar#selectionLabel, lbl ->
                    lbl.setText("sel: ${curSel}"));

                // Inspector: 選択文字列が前回と変わったら再構築
                let prevSel = Array.get(0, state#inspector#lastSel);
                if (curSel != prevSel) {
                    rebuildInspector(state, curSel);
                    Array.put(curSel, 0, state#inspector#lastSel)
                } else ();
                // Inspector の各プロパティを毎フレーム更新 (ドラッグ・リサイズ中も live に追従)。
                // TextField は focus 中はユーザー入力を上書きしない
                updateVec2Label(state#inspector#posLabel, state#inspector#worldPos);
                updateVec2TextField(state#inspector#localXField, state#inspector#localYField,
                                     state#inspector#localPos);
                updateVec2TextField(state#inspector#scaleXField, state#inspector#scaleYField,
                                     state#inspector#scale);
                // Rotation: 内部 ラジアン → 表示 度
                match (Array.get(0, state#inspector#rotationField),
                       Array.get(0, state#inspector#rotation)) {
                    case (Some(f), Some(rad)) =>
                        if (not f.isFocused()) {
                            let deg = rad * 180.0 / 3.14159265358979;
                            let ideg = Float64.tryToInt32(deg) |> Option.getWithDefault(0i32);
                            f.setText("${ideg}")
                        } else ()
                    case _ => ()
                }
            }
        };
        timer.start()
    }

    /// scene path は project root 込みで長いので、表示用に末尾の rel 部分だけ残す
    def shortenPath(absPath: String): String =
        match String.indexOfRight({substr = "/src/"}, absPath) {
            case Some(i) => String.sliceRight(start = i + 1, absPath)
            case None    => absPath
        }

    /// Inspector pane の中身を再構築する。selection が変わったときだけ呼ばれる。
    /// プロパティ値は毎フレーム更新するため、生成した Label の参照を state に保存しておき
    /// AnimationTimer が setText するだけにする (rebuild は selection 変化時のみ)
    def rebuildInspector(state: IdeState.IdeState, selDisplay: String): Unit \ IO = {
        match Array.get(0, state#inspector#content) {
            case None => ()
            case Some(box) => {
                let children = box.getChildren();
                children.clear();
                Array.put((None: Option[Label]), 0, state#inspector#posLabel);
                if (selDisplay == "-") {
                    let placeholder = new Label("(nothing selected)");
                    placeholder.getStyleClass().add("inspector-empty");
                    let placeholderNode: Node = checked_cast(placeholder);
                    discard children.add(placeholderNode)
                } else {
                    let pathLabel = new Label(selDisplay);
                    pathLabel.setWrapText(true);
                    let pathNode: Node = checked_cast(pathLabel);
                    PropertyWidgets.addPropertyRow(children, "Selected:", pathNode);

                    let worldPosValue = new Label("-");
                    let worldPosNode: Node = checked_cast(worldPosValue);
                    PropertyWidgets.addPropertyRow(children, "World position:", worldPosNode);
                    Array.put(Some(worldPosValue), 0, state#inspector#posLabel);

                    // Local position / Scale / Rotation はいずれも編集可能 TextField で表示。
                    // pos / rotation は整数刻み、scale は実数刻み (↑↓ で 1.0 ずつ)
                    addEditableVec2Row(state, children, "Local position:", true,
                                        state#inspector#localXField,
                                        state#inspector#localYField,
                                        state#inspector#pendingLocalPos);
                    addEditableVec2Row(state, children, "Scale:", false,
                                        state#inspector#scaleXField,
                                        state#inspector#scaleYField,
                                        state#inspector#pendingScale);
                    addEditableRotationRow(state, children)
                }
            }
        }
    }

    /// 2 つの TextField (X, Y) を Vec2 ref から更新する。focus 中はユーザー入力を上書きしない
    def updateVec2TextField(xRef: Array[Option[TextField], Static],
                             yRef: Array[Option[TextField], Static],
                             valRef: Array[Option[(Float64, Float64)], Static]): Unit \ IO =
        PropertyWidgets.withRef(valRef, pair -> {
            let (x, y) = pair;
            let ix = Float64.tryToInt32(x) |> Option.getWithDefault(0i32);
            let iy = Float64.tryToInt32(y) |> Option.getWithDefault(0i32);
            PropertyWidgets.withRef(xRef, f -> if (not f.isFocused()) f.setText("${ix}") else ());
            PropertyWidgets.withRef(yRef, f -> if (not f.isFocused()) f.setText("${iy}") else ())
        })

    /// Vec2 (Float64×2) 値 Ref → Label.setText の共通処理
    def updateVec2Label(lblRef: Array[Option[Label], Static],
                         valRef: Array[Option[(Float64, Float64)], Static]): Unit \ IO =
        PropertyWidgets.withRef(lblRef, lbl -> {
            let txt = match Array.get(0, valRef) {
                case Some((x, y)) =>
                    let ix = Float64.tryToInt32(x) |> Option.getWithDefault(0i32);
                    let iy = Float64.tryToInt32(y) |> Option.getWithDefault(0i32);
                    "(${ix}, ${iy})"
                case None => "-"
            };
            lbl.setText(txt)
        })

    /// Vec2 (Float64×2) 編集用の汎用行。X / Y の TextField を HBox に並べ、
    /// property-row テンプレに valueSlot として乗せる
    def addEditableVec2Row(state: IdeState.IdeState, children: ObservableList[Node],
                            keyText: String, isInt: Bool,
                            xFieldRef: Array[Option[TextField], Static],
                            yFieldRef: Array[Option[TextField], Static],
                            pendingRef: Array[Option[(Float64, Float64)], Static]):
            Unit \ IO = {
        let _ = state;
        let xField = new TextField("0");
        let yField = new TextField("0");
        xField.setPrefWidth(60.0);
        yField.setPrefWidth(60.0);
        let commitBoth = () -> {
            let x = Float64.fromString(xField.getText()) |> Option.getWithDefault(0.0);
            let y = Float64.fromString(yField.getText()) |> Option.getWithDefault(0.0);
            Array.put(Some((x, y)), 0, pendingRef)
        };
        PropertyWidgets.wireNumericField(xField, isInt, commitBoth);
        PropertyWidgets.wireNumericField(yField, isInt, commitBoth);
        Array.put(Some(xField), 0, xFieldRef);
        Array.put(Some(yField), 0, yFieldRef);
        let group = new HBox(4.0);
        let xNode: Node = checked_cast(xField);
        let yNode: Node = checked_cast(yField);
        discard group.getChildren().add(xNode);
        discard group.getChildren().add(yNode);
        let groupNode: Node = checked_cast(group);
        PropertyWidgets.addPropertyRow(children, keyText, groupNode)
    }

    /// Rotation 行 (度入力 → ラジアン保存)。単一 TextField、↑↓ で 1度刻み
    def addEditableRotationRow(state: IdeState.IdeState, children: ObservableList[Node]):
            Unit \ IO = {
        let field = new TextField("0");
        field.setPrefWidth(80.0);
        PropertyWidgets.wireNumericField(field, true, () -> {
            let deg = Float64.fromString(field.getText()) |> Option.getWithDefault(0.0);
            let rad = deg * 3.14159265358979 / 180.0;
            Array.put(Some(rad), 0, state#inspector#pendingRotation)
        });
        Array.put(Some(field), 0, state#inspector#rotationField);
        let fieldNode: Node = checked_cast(field);
        PropertyWidgets.addPropertyRow(children, "Rotation (°):", fieldNode)
    }
}
