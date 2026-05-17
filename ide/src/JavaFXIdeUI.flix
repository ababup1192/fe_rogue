// JavaFXIdeUI — JavaFXLayer の customizeStage に渡される関数群。
// FXML (ide.fxml) を読み込み、fx:id 付き UI ノードに Flix 側ロジックを bind する。
//
// 設計方針:
//   - 見た目の宣言は **ide.fxml に集約**
//   - Flix はノード参照を引いて handler を貼るだけ
//   - 重い処理 (loadProject など Fs.FileRead を要するもの) は FX thread でやらず、
//     pendingProjectRef を Main の renderLoop に拾わせて main thread でロード
//   - main thread が完了したあと populate* を Platform.runLater で呼び FX thread に戻す

mod JavaFXIdeUI {
    import java.io.File
    import java.lang.{Object => JObject}
    import java.lang.Runnable
    import javafx.collections.ObservableList
    import javafx.fxml.FXMLLoader
    import javafx.animation.AnimationTimer
    import javafx.scene.Parent
    import javafx.scene.Scene
    import javafx.scene.image.ImageView
    import javafx.scene.image.WritableImage
    import javafx.scene.control.Label
    import javafx.scene.control.TextField
    import javafx.event.ActionEvent
    import javafx.scene.input.MouseEvent
    import javafx.scene.control.MenuBar
    import javafx.scene.control.MenuItem
    import javafx.scene.control.TreeView
    import javafx.scene.control.TreeItem
    import javafx.scene.control.ListView
    import javafx.scene.control.SelectionModel
    import javafx.scene.Node
    import javafx.scene.layout.HBox
    import javafx.scene.layout.StackPane
    import javafx.scene.layout.VBox
    import javafx.application.Platform
    import javafx.event.ActionEvent
    import javafx.event.EventHandler
    import javafx.beans.value.ChangeListener
    import javafx.beans.value.ObservableValue
    import javafx.stage.DirectoryChooser
    import javafx.stage.Stage

    /// JavaFXLayer.withJavaFX に渡す customize callback。
    /// Stage は title が set 済みで scene 未設定の状態で渡される。
    /// 初期 WritableImage は Layer 側で生成済みで、FXML 内の canvasView ImageView に
    /// setImage で流し込む。戻り値の ImageView は Layer が入力 listener と resize 時の
    /// setImage に使う
    pub def customize(state: IdeState.IdeState, stage: Stage, initialImage: WritableImage):
            ImageView \ IO = {
        let url = new File("src/ide.fxml").toURI().toURL();
        let loader = new FXMLLoader(url);
        // JavaFX classpath モードでは FXMLLoader 自身の ClassLoader が JavaFX コントロール
        // クラスを見つけられないため、既存 Label インスタンスから取った ClassLoader を渡す
        // (この trick は javafx_hello spike で確立済)
        let probe = new Label("");
        loader.setClassLoader(probe.getClass().getClassLoader());

        let rootObj: JObject = loader.load();
        let root: Parent = unchecked_cast(rootObj as Parent);
        let ns = loader.getNamespace();

        // FXML 宣言済みの canvasView に Layer 生成の WritableImage を流し込む。
        // fitWidth/Height/scaleY/preserveRatio はすべて FXML 属性で設定済み
        let canvasView: ImageView = unchecked_cast(ns.get("canvasView") as ImageView);
        canvasView.setImage(initialImage);

        // Scenes TreeView と Resources ListView を取得し state に stash
        // (main thread からの populate 用)
        let scenesTree: TreeView[String] = unchecked_cast(ns.get("scenesTree") as TreeView[String]);
        let resourcesList: ListView[String] = unchecked_cast(ns.get("resourcesList") as ListView[String]);
        Array.put(Some(scenesTree),    0, state#fxSceneTreeRef);
        Array.put(Some(resourcesList), 0, state#fxResourcesListRef);
        Array.put(Some(stage),         0, state#fxStageRef);

        // ステータスバー Label を取得
        let statusScene:     Label = unchecked_cast(ns.get("statusScene") as Label);
        let statusMouse:     Label = unchecked_cast(ns.get("statusMouse") as Label);
        let statusSelection: Label = unchecked_cast(ns.get("statusSelection") as Label);
        let statusFps:       Label = unchecked_cast(ns.get("statusFps") as Label);
        Array.put(Some(statusScene),     0, state#fxStatusSceneLabelRef);
        Array.put(Some(statusMouse),     0, state#fxStatusMouseLabelRef);
        Array.put(Some(statusSelection), 0, state#fxStatusSelectionLabelRef);
        Array.put(Some(statusFps),       0, state#fxStatusFpsLabelRef);

        // Inspector pane
        let inspectorContent: VBox = unchecked_cast(ns.get("inspectorContent") as VBox);
        Array.put(Some(inspectorContent), 0, state#fxInspectorContentRef);

        // ステータスバー更新タイマー (FX thread 60Hz)。state Refs を読んで Label.setText するだけ
        startStatusBarTimer(state, canvasView);

        // TreeView の選択を pendingSceneRef に伝える
        wireTreeSelection(state, scenesTree);

        // メニュー項目を wire
        let openItem: MenuItem = unchecked_cast(ns.get("menuOpenProject") as MenuItem);
        openItem.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO =
                showOpenProjectChooser(state, stage)
        });

        let quitItem: MenuItem = unchecked_cast(ns.get("menuQuit") as MenuItem);
        quitItem.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO = {
                println("[IdeUI] Quit clicked");
                JavaFXLayer.halt()
            }
        });

        let scene = new Scene(root);
        stage.setScene(scene);
        canvasView
    }

    /// DirectoryChooser を出し、選ばれたパスを pendingProjectRef に積む。
    /// 実際の ProjectLoader.loadProject は main thread の renderLoop が消費する
    /// (FX thread には Fs.FileRead effect handler が無いため)
    def showOpenProjectChooser(state: IdeState.IdeState, stage: Stage): Unit \ IO = {
        let chooser = new DirectoryChooser();
        chooser.setTitle("Open Project");
        let chosen = chooser.showDialog(stage);
        if (Object.isNull(chosen)) ()
        else {
            let path = chosen.getAbsolutePath();
            println("[IdeUI] Open Project selected: ${path}");
            Array.put(Some(path), 0, state#pendingProjectRef)
        }
    }

    /// TreeView の選択変更を pendingSceneRef に伝える。
    /// 表示文字列は relative path で持っているため、sceneFilesRef の (abs, rel) リストから
    /// マッチする absolute path を引き直して pendingSceneRef に積む
    def wireTreeSelection(state: IdeState.IdeState, tree: TreeView[String]): Unit \ IO = {
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

    /// Main thread の renderLoop からプロジェクト切替後に呼ぶ。
    /// FX thread で TreeView の root を差し替える。sceneFilesRef は既に新値が入っている前提
    pub def schedulePopulateTree(state: IdeState.IdeState): Unit \ IO = {
        Platform.runLater(new Runnable {
            def $run(_this: Runnable): Unit \ IO = populateTree(state)
        })
    }

    /// 現在 FX thread にいる前提で TreeView を再構築する。
    /// sceneFilesRef の rel path 一覧を root の子として並べる。
    /// 同時に Resources ListView も再構築する (state.resource.discoveredRef から)
    def populateTree(state: IdeState.IdeState): Unit \ IO = {
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
        };
        // Resources ListView は ResourceState.discoveredRef から build
        match Array.get(0, state#fxResourcesListRef) {
            case None => ()
            case Some(listView) => {
                let entries = Array.get(0, state#resource#discoveredRef);
                let items = listView.getItems();
                items.clear();
                List.forEach(e -> discard items.add(e#displayName), entries)
            }
        }
    }

    /// Stage title を更新する (Project ロード完了時に呼ばれる)
    pub def scheduleSetTitle(state: IdeState.IdeState, title: String): Unit \ IO = {
        Platform.runLater(new Runnable {
            def $run(_this: Runnable): Unit \ IO = {
                match Array.get(0, state#fxStageRef) {
                    case Some(stage) => stage.setTitle(title)
                    case None => ()
                }
            }
        })
    }

    /// ステータスバー更新タイマーを起動する。FX thread で 60Hz で発火し、state の各 Ref を
    /// 読んで Label.setText するだけ。Label 更新は FX thread でしか許されないので Timer 内で完結
    def startStatusBarTimer(state: IdeState.IdeState, canvasView: ImageView): Unit \ IO = {
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
                        match Array.get(0, state#fxStatusFpsLabelRef) {
                            case Some(lbl) => lbl.setText("${frames} fps")
                            case None => ()
                        };
                        Array.put(0i32, 0, frameCountRef);
                        Array.put(now, 0, lastTimeRef)
                    } else {
                        Array.put(frames, 0, frameCountRef)
                    }
                };

                // Scene path
                match Array.get(0, state#fxStatusSceneLabelRef) {
                    case None => ()
                    case Some(lbl) => {
                        let txt = match Array.get(0, state#currentScenePathRef) {
                            case Some(p) => "Scene: ${shortenPath(p)}"
                            case None    => "(no scene)"
                        };
                        lbl.setText(txt)
                    }
                };

                // Mouse: ImageView local 座標 (FBO は ImageView と同サイズなのでこれが design 座標)
                match Array.get(0, state#fxStatusMouseLabelRef) {
                    case None => ()
                    case Some(lbl) =>
                        let mx = Float64.tryToInt32(Array.get(0, mouseXRef))
                                  |> Option.getWithDefault(0i32);
                        let my = Float64.tryToInt32(Array.get(0, mouseYRef))
                                  |> Option.getWithDefault(0i32);
                        lbl.setText("mouse: ${mx}, ${my}")
                };

                // Selection: renderLoop が editor 状態を直接書き込んだ表示文字列を使う
                // (selectedNodePathRef 経由は currentSceneJsonRef のセットが必要)
                let curSel = Array.get(0, state#fxEditorSelDisplayRef);
                match Array.get(0, state#fxStatusSelectionLabelRef) {
                    case None      => ()
                    case Some(lbl) => lbl.setText("sel: ${curSel}")
                };

                // Inspector: 選択文字列が前回と変わったら再構築
                let prevSel = Array.get(0, state#fxInspectorLastSelRef);
                if (curSel != prevSel) {
                    rebuildInspector(state, curSel);
                    Array.put(curSel, 0, state#fxInspectorLastSelRef)
                } else ();
                // Inspector の各プロパティを毎フレーム更新 (ドラッグ・リサイズ中も live に追従)。
                // TextField は focus 中はユーザー入力を上書きしない
                updateVec2Label(state#fxInspectorPosLabelRef, state#fxInspectorWorldPosRef);
                updateVec2TextField(state#fxInspectorLocalXFieldRef, state#fxInspectorLocalYFieldRef,
                                     state#fxInspectorLocalPosRef);
                updateVec2TextField(state#fxInspectorScaleXFieldRef, state#fxInspectorScaleYFieldRef,
                                     state#fxInspectorScaleRef);
                // Rotation: 内部 ラジアン → 表示 度
                match (Array.get(0, state#fxInspectorRotationFieldRef),
                       Array.get(0, state#fxInspectorRotationRef)) {
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
        // "src/scenes/..." 以降があればそこから、無ければそのまま (Phase 5 暫定)
        match String.indexOfRight({substr = "/src/"}, absPath) {
            case Some(i) => String.sliceRight(start = i + 1, absPath)
            case None    => absPath
        }

    /// Inspector pane の中身を再構築する。selection が変わったときだけ呼ばれる。
    /// プロパティ値は毎フレーム更新するため、生成した Label の参照を state に保存しておき
    /// AnimationTimer が setText するだけにする (rebuild は selection 変化時のみ)
    def rebuildInspector(state: IdeState.IdeState, selDisplay: String): Unit \ IO = {
        match Array.get(0, state#fxInspectorContentRef) {
            case None => ()
            case Some(box) => {
                let children = box.getChildren();
                children.clear();
                Array.put((None: Option[Label]), 0, state#fxInspectorPosLabelRef);
                Array.put((None: Option[Label]), 0, state#fxInspectorLocalPosLabelRef);
                Array.put((None: Option[Label]), 0, state#fxInspectorScaleLabelRef);
                Array.put((None: Option[Label]), 0, state#fxInspectorRotationLabelRef);
                if (selDisplay == "-") {
                    let placeholder = new Label("(nothing selected)");
                    placeholder.getStyleClass().add("inspector-empty");
                    let placeholderNode: Node = checked_cast(placeholder);
                    discard children.add(placeholderNode)
                } else {
                    let nameKey = new Label("Selected:");
                    nameKey.getStyleClass().add("inspector-row-key");
                    let pathLabel = new Label(selDisplay);
                    pathLabel.setWrapText(true);
                    let nameKeyNode: Node = checked_cast(nameKey);
                    let pathNode: Node = checked_cast(pathLabel);
                    discard children.add(nameKeyNode);
                    discard children.add(pathNode);

                    let worldPosValue = addInspectorRow(children, "World position:");
                    Array.put(Some(worldPosValue), 0, state#fxInspectorPosLabelRef);

                    // Local position / Scale / Rotation はいずれも編集可能 TextField で表示
                    addEditableVec2Row(state, children, "Local position:",
                                        state#fxInspectorLocalXFieldRef,
                                        state#fxInspectorLocalYFieldRef,
                                        state#fxPendingLocalPosEditRef);
                    addEditableVec2Row(state, children, "Scale:",
                                        state#fxInspectorScaleXFieldRef,
                                        state#fxInspectorScaleYFieldRef,
                                        state#fxPendingScaleEditRef);
                    addEditableRotationRow(state, children)
                }
            }
        }
    }

    /// 2 つの TextField (X, Y) を Vec2 ref から更新する。focus 中はユーザー入力を上書きしない
    def updateVec2TextField(xRef: Array[Option[TextField], Static],
                             yRef: Array[Option[TextField], Static],
                             valRef: Array[Option[(Float64, Float64)], Static]): Unit \ IO =
        match Array.get(0, valRef) {
            case None => ()
            case Some((x, y)) => {
                let ix = Float64.tryToInt32(x) |> Option.getWithDefault(0i32);
                let iy = Float64.tryToInt32(y) |> Option.getWithDefault(0i32);
                match Array.get(0, xRef) {
                    case Some(f) => if (not f.isFocused()) f.setText("${ix}") else ()
                    case None    => ()
                };
                match Array.get(0, yRef) {
                    case Some(f) => if (not f.isFocused()) f.setText("${iy}") else ()
                    case None    => ()
                }
            }
        }

    /// Vec2 (Float64×2) 値 Ref → Label.setText の共通処理
    def updateVec2Label(lblRef: Array[Option[Label], Static],
                         valRef: Array[Option[(Float64, Float64)], Static]): Unit \ IO =
        match Array.get(0, lblRef) {
            case None => ()
            case Some(lbl) =>
                let txt = match Array.get(0, valRef) {
                    case Some((x, y)) =>
                        let ix = Float64.tryToInt32(x) |> Option.getWithDefault(0i32);
                        let iy = Float64.tryToInt32(y) |> Option.getWithDefault(0i32);
                        "(${ix}, ${iy})"
                    case None => "-"
                };
                lbl.setText(txt)
        }

    /// Inspector 内に "Key: -" 形式の 1 行を追加し、値ラベルを返す
    def addInspectorRow(children: ObservableList[Node], keyText: String): Label \ IO = {
        let key = new Label(keyText);
        key.getStyleClass().add("inspector-row-key");
        let value = new Label("-");
        let keyNode: Node = checked_cast(key);
        let valueNode: Node = checked_cast(value);
        discard children.add(keyNode);
        discard children.add(valueNode);
        value
    }

    /// Vec2 (Float64×2) 編集用の汎用行追加。X / Y の TextField と pending ref を受け取り、
    /// Enter で pending ref に新値を積む
    def addEditableVec2Row(state: IdeState.IdeState, children: ObservableList[Node],
                            keyText: String,
                            xFieldRef: Array[Option[TextField], Static],
                            yFieldRef: Array[Option[TextField], Static],
                            pendingRef: Array[Option[(Float64, Float64)], Static]):
            Unit \ IO = {
        let _ = state;
        let key = new Label(keyText);
        key.getStyleClass().add("inspector-row-key");
        let xField = new TextField("0");
        let yField = new TextField("0");
        xField.setPrefWidth(60.0);
        yField.setPrefWidth(60.0);
        let commitHandler = new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO = {
                let x = Float64.fromString(xField.getText()) |> Option.getWithDefault(0.0);
                let y = Float64.fromString(yField.getText()) |> Option.getWithDefault(0.0);
                Array.put(Some((x, y)), 0, pendingRef)
            }
        };
        xField.setOnAction(commitHandler);
        yField.setOnAction(commitHandler);
        Array.put(Some(xField), 0, xFieldRef);
        Array.put(Some(yField), 0, yFieldRef);

        let row = new HBox(4.0);
        let xNode: Node = checked_cast(xField);
        let yNode: Node = checked_cast(yField);
        discard row.getChildren().add(xNode);
        discard row.getChildren().add(yNode);

        let keyNode: Node = checked_cast(key);
        let rowNode: Node = checked_cast(row);
        discard children.add(keyNode);
        discard children.add(rowNode)
    }

    /// Rotation 行 (度入力 → ラジアン保存)。単一 TextField
    def addEditableRotationRow(state: IdeState.IdeState, children: ObservableList[Node]):
            Unit \ IO = {
        let key = new Label("Rotation (°):");
        key.getStyleClass().add("inspector-row-key");
        let field = new TextField("0");
        field.setPrefWidth(80.0);
        let commitHandler = new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO = {
                let deg = Float64.fromString(field.getText()) |> Option.getWithDefault(0.0);
                let rad = deg * 3.14159265358979 / 180.0;
                Array.put(Some(rad), 0, state#fxPendingRotationEditRef)
            }
        };
        field.setOnAction(commitHandler);
        Array.put(Some(field), 0, state#fxInspectorRotationFieldRef);
        let keyNode: Node = checked_cast(key);
        let fieldNode: Node = checked_cast(field);
        discard children.add(keyNode);
        discard children.add(fieldNode)
    }
}
