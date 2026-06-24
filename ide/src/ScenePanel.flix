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
    import java.lang.Boolean
    import java.lang.Runnable
    import java.nio.file.Files
    import java.nio.file.Paths
    import javafx.application.Platform
    import javafx.animation.AnimationTimer
    import javafx.collections.ObservableList
    import javafx.scene.Node
    import javafx.scene.control.Button
    import javafx.scene.control.Label
    import javafx.scene.control.TextField
    import javafx.scene.control.TextArea
    import javafx.scene.control.CheckBox
    import javafx.scene.control.ColorPicker
    import javafx.scene.control.ComboBox
    import javafx.scene.control.Spinner
    import javafx.scene.paint.{Color => FxColor}
    import javafx.scene.control.TitledPane
    import javafx.scene.control.TreeView
    import javafx.scene.control.TreeItem
    import javafx.scene.control.TreeCell
    import javafx.scene.control.MultipleSelectionModel
    import javafx.scene.control.ContextMenu
    import javafx.scene.control.Menu
    import javafx.scene.control.MenuItem
    import javafx.scene.control.Dialog
    import javafx.scene.control.DialogPane
    import javafx.scene.control.ButtonType
    import javafx.scene.layout.GridPane
    import javafx.util.Callback
    import javafx.scene.image.ImageView
    import javafx.scene.input.MouseEvent
    import javafx.scene.input.ContextMenuEvent
    import javafx.scene.layout.HBox
    import javafx.scene.layout.VBox
    import javafx.event.EventHandler
    import javafx.event.ActionEvent
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

    /// Scenes ツリーにセル単位のコンテキストメニューを付ける。
    /// JavaFXIdeUI.customize から wireTreeSelection の隣で呼ぶ。
    ///   - 行 (シーン/ノード) を右クリック → Rename / Delete (その行の所属シーンに作用)
    ///   - 何もない空白を右クリック       → New Scene
    /// セルに menu を持たせることで「右クリックした行」が確実に対象になる
    /// (TreeView 全体に 1 つの menu を貼ると右クリックで選択が変わらず対象が曖昧になる)。
    /// 実際のファイル操作は pendingSceneOpRef / pendingNewSceneRef 経由で main thread が行う。
    pub def wireSceneContextMenu(state: IdeState.IdeState, tree: TreeView[String]): Unit \ IO = {
        // 右クリックされた行の所属シーン (abs, rel) を一時保持する Ref。
        // onContextMenuRequested (= セルが行にバインドされている瞬間) に確定し、
        // メニュー項目のアクションはこの Ref を読む。
        // (クリック時に cell.getTreeItem() を読むと、セル仮想化で再利用され null になることが
        //  あるため。選択モデル経由だと右クリック選択が scene 再ロード→ツリー再生成を誘発して
        //  メニューが消えるため、いずれも使わない)
        let ctxRef: Array[Option[(String, String, List[String])], Static] =
            Array#{(None: Option[(String, String, List[String])])} @ Static;
        tree.setCellFactory(new Callback[TreeView[String], TreeCell[String]] {
            def call(_cThis: Callback[TreeView[String], TreeCell[String]],
                      _tv: TreeView[String]): TreeCell[String] \ IO =
                makeSceneTreeCell(state, ctxRef)
        })
    }

    /// Scenes ツリーの 1 セル。itemProperty を listen して text を同期し、
    /// 空セルかどうかで context menu を Row 用 / 空白用に切り替える。
    /// (Flix では updateItem を直接 override できず、emptyProperty の ChangeListener[Bool]
    ///  は VerifyError になるため、itemProperty の null 判定で代替する)
    def makeSceneTreeCell(state: IdeState.IdeState,
                          ctxRef: Array[Option[(String, String, List[String])], Static]):
            TreeCell[String] \ IO = {
        let cell: TreeCell[String] = new TreeCell();
        let rowMenu = buildRowMenu(state, ctxRef);
        let emptyMenu = buildEmptyMenu(state);
        // 既定は空セル扱い (空白右クリックで New Scene)
        cell.setContextMenu(emptyMenu);
        cell.itemProperty().addListener(new ChangeListener[String] {
            def changed(_cThis: ChangeListener[String],
                          _obs: ObservableValue[JObject],
                          _old: String, newVal: String): Unit \ IO =
                if (Object.isNull(newVal)) {
                    cell.setText("");
                    cell.setContextMenu(emptyMenu)
                } else {
                    cell.setText(newVal);
                    cell.setContextMenu(rowMenu)
                }
        });
        // メニュー要求の瞬間 = このセルが行にバインドされている。ここで対象を確定して保存する。
        cell.setOnContextMenuRequested(new EventHandler[ContextMenuEvent] {
            def handle(_t: EventHandler[ContextMenuEvent], _e: ContextMenuEvent): Unit \ IO =
                Array.put(sceneOfCell(state, cell), 0, ctxRef)
        });
        cell
    }

    def buildRowMenu(state: IdeState.IdeState,
                     ctxRef: Array[Option[(String, String, List[String])], Static]):
            ContextMenu \ IO = {
        let menu = new ContextMenu();
        let addChildMenu = buildAddChildMenu(state, ctxRef);
        let renameItem = new MenuItem("Rename Scene...");
        renameItem.setOnAction(new EventHandler[ActionEvent] {
            def handle(_t: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO =
                onRenameTarget(state, ctxRef)
        });
        let deleteItem = new MenuItem("Delete Scene");
        deleteItem.setOnAction(new EventHandler[ActionEvent] {
            def handle(_t: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO =
                onDeleteTarget(state, ctxRef)
        });
        discard menu.getItems().add(unchecked_cast(addChildMenu as MenuItem));
        discard menu.getItems().add(renameItem);
        discard menu.getItems().add(deleteItem);
        menu
    }

    /// "Add Child Node" サブメニュー。型ごとに MenuItem を並べ、クリックで pendingAddChildRef に
    /// 積む (型名で自動命名。名前入力なし)。テクスチャ不要な型に限定。
    def buildAddChildMenu(state: IdeState.IdeState,
                          ctxRef: Array[Option[(String, String, List[String])], Static]):
            Menu \ IO = {
        let sub = new Menu("Add Child Node");
        let types = "StaticBody2D" :: "RigidBody2D" :: "CharacterBody2D" ::
                    "Area2D" :: "ColorRect" :: "Marker2D" :: Nil;
        List.forEach(t -> {
            let item = new MenuItem(t);
            item.setOnAction(new EventHandler[ActionEvent] {
                def handle(_th: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO =
                    onAddChild(state, ctxRef, t)
            });
            discard sub.getItems().add(item)
        }, types);
        sub
    }

    def onAddChild(state: IdeState.IdeState,
                   ctxRef: Array[Option[(String, String, List[String])], Static],
                   childType: String): Unit \ IO =
        match Array.get(0, ctxRef) {
            case None => ()
            case Some((abs, _rel, nodePath)) =>
                if (List.isEmpty(nodePath))
                    println("[Scenes] Add Child: ノード行で実行してください (ファイル行ではなく)")
                else {
                    println("[Scenes] Add child queued: ${childType} under ${nodePath}");
                    Array.put(Some((abs, nodePath, childType)), 0, state#pendingAddChildRef)
                }
        }

    def buildEmptyMenu(state: IdeState.IdeState): ContextMenu \ IO = {
        let menu = new ContextMenu();
        let newItem = new MenuItem("New Scene...");
        newItem.setOnAction(new EventHandler[ActionEvent] {
            def handle(_t: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO =
                showNewSceneDialog(state)
        });
        discard menu.getItems().add(newItem);
        menu
    }

    /// セルが保持する TreeItem から、(シーン絶対パス, 表示用相対パス, ノード NodePath) を返す。
    /// nodePath は chain の rest (= シーン内のノードパス)。ファイル行なら空、root ノード行なら
    /// [rootName]。onContextMenuRequested 内で呼ぶ (このときセルは行にバインドされている)。
    def sceneOfCell(state: IdeState.IdeState, cell: TreeCell[String]):
            Option[(String, String, List[String])] \ IO = {
        let item = cell.getTreeItem();
        if (Object.isNull(item)) None
        else {
            let chain = collectFromTopLevel(item);
            match chain {
                case Nil                => None
                case sceneRel :: rest   =>
                    let pairs = Array.get(0, state#sceneFilesRef);
                    match List.find(p -> snd(p) == sceneRel, pairs) {
                        case Some((abs, rel)) => Some((abs, rel, rest))
                        case None             => None
                    }
            }
        }
    }

    /// "src/scenes/Foo.scene.json" → "Foo"。ディレクトリと .scene.json 拡張子を落とす。
    def sceneBaseName(rel: String): String =
        let afterSlash = match String.indexOfRight({substr = "/"}, rel) {
            case Some(i) => String.sliceRight(start = i + 1, rel)
            case None    => rel
        };
        if (String.endsWith({suffix = ".scene.json"}, afterSlash))
            String.slice(start = 0, end = String.length(afterSlash) - 11, afterSlash)
        else afterSlash

    def onRenameTarget(state: IdeState.IdeState,
                       ctxRef: Array[Option[(String, String, List[String])], Static]): Unit \ IO =
        match Array.get(0, ctxRef) {
            case None                  => println("[Scenes] Rename: 対象シーンを特定できませんでした")
            case Some((abs, rel, _np)) => promptRenameScene(state, abs, sceneBaseName(rel))
        }

    def promptRenameScene(state: IdeState.IdeState, abs: String, currentName: String): Unit \ IO = {
        let dialog: Dialog[ButtonType] = new Dialog();
        dialog.setTitle("Rename Scene");
        dialog.setHeaderText("新しいシーン名を入力");
        let pane: DialogPane = dialog.getDialogPane();
        let buttonTypes = pane.getButtonTypes();
        discard buttonTypes.add(ButtonType.OK);
        discard buttonTypes.add(ButtonType.CANCEL);
        let nameField = new TextField(currentName);
        let grid = new GridPane();
        grid.setHgap(8.0);
        grid.setVgap(8.0);
        grid.add(unchecked_cast(new Label("名前:") as Node), 0i32, 0i32);
        grid.add(unchecked_cast(nameField as Node),         1i32, 0i32);
        pane.setContent(unchecked_cast(grid as Node));
        let result = dialog.showAndWait();
        let okBt = ButtonType.OK;
        if (result.isPresent() and okBt.equals(result.get())) {
            let name = nameField.getText();
            if (Object.isNull(name) or name == "" or name == currentName)
                ()
            else {
                println("[Scenes] Rename queued: ${currentName} -> ${name}");
                Array.put(Some(IdeState.SceneOp.RenameScene(abs, name)), 0, state#pendingSceneOpRef)
            }
        } else ()
    }

    def onDeleteTarget(state: IdeState.IdeState,
                       ctxRef: Array[Option[(String, String, List[String])], Static]): Unit \ IO =
        match Array.get(0, ctxRef) {
            case None                  => println("[Scenes] Delete: 対象シーンを特定できませんでした")
            case Some((abs, rel, _np)) => confirmDeleteScene(state, abs, rel)
        }

    def confirmDeleteScene(state: IdeState.IdeState, abs: String, rel: String): Unit \ IO = {
        let dialog: Dialog[ButtonType] = new Dialog();
        dialog.setTitle("Delete Scene");
        dialog.setHeaderText("シーンを削除しますか？\n${rel}");
        let pane: DialogPane = dialog.getDialogPane();
        let buttonTypes = pane.getButtonTypes();
        discard buttonTypes.add(ButtonType.OK);
        discard buttonTypes.add(ButtonType.CANCEL);
        let result = dialog.showAndWait();
        let okBt = ButtonType.OK;
        if (result.isPresent() and okBt.equals(result.get())) {
            println("[Scenes] Delete queued: ${rel}");
            Array.put(Some(IdeState.SceneOp.DeleteScene(abs)), 0, state#pendingSceneOpRef)
        } else ()
    }

    /// New Scene のダイアログ。File メニューと Scenes パネルの空白右クリックの両方から呼ぶ。
    /// シーン名とルート型を取得して pendingNewSceneRef に積む (生成は main thread)。
    pub def showNewSceneDialog(state: IdeState.IdeState): Unit \ IO =
        match IdeState.getCurrentProjectRoot(state) {
            case None    => println("[Scenes] New Scene: プロジェクトが開かれていません")
            case Some(_) => promptNewScene(state)
        }

    def promptNewScene(state: IdeState.IdeState): Unit \ IO = {
        let dialog: Dialog[ButtonType] = new Dialog();
        dialog.setTitle("New Scene");
        dialog.setHeaderText("新規シーンの名前とルートノード型を入力");
        let pane: DialogPane = dialog.getDialogPane();
        let buttonTypes = pane.getButtonTypes();
        discard buttonTypes.add(ButtonType.OK);
        discard buttonTypes.add(ButtonType.CANCEL);
        let nameField = new TextField("NewScene");
        let rootCombo: ComboBox[String] = new ComboBox();
        let items = rootCombo.getItems();
        discard items.add("Marker2D");
        discard items.add("CanvasLayer");
        rootCombo.setValue("Marker2D");
        let grid = new GridPane();
        grid.setHgap(8.0);
        grid.setVgap(8.0);
        grid.add(unchecked_cast(new Label("シーン名:") as Node), 0i32, 0i32);
        grid.add(unchecked_cast(nameField as Node),             1i32, 0i32);
        grid.add(unchecked_cast(new Label("ルート型:") as Node), 0i32, 1i32);
        grid.add(unchecked_cast(rootCombo as Node),             1i32, 1i32);
        pane.setContent(unchecked_cast(grid as Node));
        let result = dialog.showAndWait();
        let okBt = ButtonType.OK;
        if (result.isPresent() and okBt.equals(result.get())) {
            let name = nameField.getText();
            let rootType = rootCombo.getValue();
            if (Object.isNull(name) or name == "")
                println("[Scenes] New Scene: 名前を入力してください")
            else {
                println("[Scenes] New Scene queued: ${name} (root=${rootType})");
                Array.put(Some((name, rootType)), 0, state#pendingNewSceneRef)
            }
        } else ()
    }

    /// Project メニューの Project Settings... ダイアログ。design 解像度を編集して
    /// pendingProjectSettingsRef に積む (project.json 書き戻し + 再ロードは main thread)。
    pub def showProjectSettingsDialog(state: IdeState.IdeState): Unit \ IO = {
        let (curW, curH) = IdeState.getCurrentDesign(state);
        let dialog: Dialog[ButtonType] = new Dialog();
        dialog.setTitle("Project Settings");
        dialog.setHeaderText("デザイン解像度 (ゲーム画面サイズ)");
        let pane: DialogPane = dialog.getDialogPane();
        let buttonTypes = pane.getButtonTypes();
        discard buttonTypes.add(ButtonType.OK);
        discard buttonTypes.add(ButtonType.CANCEL);
        let wField = new TextField("${curW}");
        let hField = new TextField("${curH}");
        let grid = new GridPane();
        grid.setHgap(8.0);
        grid.setVgap(8.0);
        grid.add(unchecked_cast(new Label("幅 (px):") as Node),   0i32, 0i32);
        grid.add(unchecked_cast(wField as Node),                 1i32, 0i32);
        grid.add(unchecked_cast(new Label("高さ (px):") as Node), 0i32, 1i32);
        grid.add(unchecked_cast(hField as Node),                 1i32, 1i32);
        pane.setContent(unchecked_cast(grid as Node));
        let result = dialog.showAndWait();
        let okBt = ButtonType.OK;
        if (result.isPresent() and okBt.equals(result.get()))
            match (Int32.fromString(wField.getText()), Int32.fromString(hField.getText())) {
                case (Some(w), Some(h)) =>
                    if (w > 0i32 and h > 0i32) {
                        println("[Project] design size queued: ${w}x${h}");
                        Array.put(Some((w, h)), 0, state#pendingProjectSettingsRef)
                    } else println("[Project] サイズは正の数で入力してください")
                case _ => println("[Project] 数値を入力してください")
            }
        else ()
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
                Array.put((Map.empty(): Map[String, Util.Json.Json -> Unit \ IO]),
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
                        };
                        // AudioStreamPlayer セクションには preview 用 Play/Stop ボタンを足す。
                        // (autoplay は runtime のみで反応するため、preview で聴くにはこのボタンが必要)
                        if (section#typeName == "AudioStreamPlayer")
                            addAudioPreviewButtons(state, children, values)
                        else ()
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
                               currentValues: Map[String, Util.Json.Json],
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

    /// AudioStreamPlayer セクションの末尾に "▶ Play" / "⏹ Stop" ボタン行を追加する。
    /// クリック時に最新の state#inspector#currentValues から stream / volume / loop を読んで
    /// IdeState.enqueueAudioCommand する (button 作成時 capture だと編集直後の値を見落とす)。
    /// renderLoop が `consumePendingAudioCommand` で GameEngine.Audio に流す。
    def addAudioPreviewButtons(state: IdeState.IdeState, children: ObservableList[Node],
                                 _currentValues: Map[String, Util.Json.Json]): Unit \ IO = {
        let row = new HBox(6.0);
        let playBtn = new Button("▶ Play");
        let stopBtn = new Button("⏹ Stop");
        playBtn.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO = {
                let cur = Array.get(0, state#inspector#currentValues);
                let streamOpt = Map.get("stream", cur) |> Option.flatMap(NodeInspector.jsonToString);
                let volume = Map.get("volume", cur) |> Option.flatMap(NodeInspector.jsonToFloat)
                              |> Option.flatMap(Float64.tryToFloat32)
                              |> Option.getWithDefault(1.0f32);
                let loop = Map.get("loop", cur) |> Option.flatMap(NodeInspector.jsonToBool)
                            |> Option.getWithDefault(false);
                match streamOpt {
                    case Some(s) => IdeState.enqueueAudioCommand(state,
                                      IdeState.AudioCommand.Play(s, volume, loop))
                    case None    => ()
                }
            }
        });
        stopBtn.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO = {
                let cur = Array.get(0, state#inspector#currentValues);
                let streamOpt = Map.get("stream", cur) |> Option.flatMap(NodeInspector.jsonToString);
                match streamOpt {
                    case Some(s) => IdeState.enqueueAudioCommand(state, IdeState.AudioCommand.Stop(s))
                    case None    => ()
                }
            }
        });
        let rowKids = row.getChildren();
        let playNode: Node = checked_cast(playBtn);
        let stopNode: Node = checked_cast(stopBtn);
        discard rowKids.add(playNode);
        discard rowKids.add(stopNode);
        let rowNode: Node = checked_cast(row);
        PropertyWidgets.addPropertyRow(children, "Preview:", rowNode)
    }

    /// 1 FieldDef を Inspector に追加する
    def addSchemaRow(state: IdeState.IdeState, children: ObservableList[Node],
                      fd: NodeInspector.FieldDef,
                      currentValues: Map[String, Util.Json.Json],
                      sel: Editor.Selection): Unit \ IO = {
        let currentJson = Map.get(fd#name, currentValues);
        let applyFn = fd#apply;
        let commit: PropertyWidgets.Commit = json -> {
            let pe: NodeInspector.PendingEdit = { perform = () -> applyFn(sel, json) };
            let existing = Array.get(0, state#inspector#pendingEdits);
            Array.put(List.append(existing, pe :: Nil), 0, state#inspector#pendingEdits)
        };
        let textureNames = Array.get(0, state#textureNamesRef);
        let soundNames = Array.get(0, state#soundNamesRef);
        let (widget, updater) = buildWidgetForKind(fd#kind, currentJson, textureNames, soundNames, commit);
        PropertyWidgets.addPropertyRow(children, "${fd#label}:", widget);
        let map = Array.get(0, state#inspector#widgetUpdaters);
        Array.put(Map.insert(fd#name, updater, map), 0, state#inspector#widgetUpdaters)
    }

    /// FieldKind に応じた widget を生成し、(widget, 値更新 closure) を返す
    def buildWidgetForKind(kind: NodeInspector.FieldKind,
                           current: Option[Util.Json.Json],
                           textureNames: List[String],
                           soundNames: List[String],
                           commit: PropertyWidgets.Commit):
            (Node, Util.Json.Json -> Unit \ IO) \ IO =
        match kind {
            case NodeInspector.FieldKind.Vec2T => {
                let isInt = false;
                let widget = PropertyWidgets.buildVec2Widget(current, isInt, commit);
                let updater = (json: Util.Json.Json) -> updateVec2Widget(widget, json, isInt);
                (widget, updater)
            }
            case NodeInspector.FieldKind.Vec2IntT => {
                let isInt = true;
                let widget = PropertyWidgets.buildVec2Widget(current, isInt, commit);
                let updater = (json: Util.Json.Json) -> updateVec2Widget(widget, json, isInt);
                (widget, updater)
            }
            case NodeInspector.FieldKind.FloatT => {
                let widget = PropertyWidgets.buildFloatWidget(current, commit);
                let updater = (json: Util.Json.Json) -> updateFloatSpinner(widget, json);
                (widget, updater)
            }
            case NodeInspector.FieldKind.IntT => {
                let widget = PropertyWidgets.buildIntWidget(current, commit);
                let updater = (json: Util.Json.Json) -> updateIntSpinner(widget, json);
                (widget, updater)
            }
            case NodeInspector.FieldKind.TextT => {
                let widget = PropertyWidgets.buildTextWidget(current, commit);
                let updater = (json: Util.Json.Json) -> updateTextField(widget, json);
                (widget, updater)
            }
            case NodeInspector.FieldKind.TexturePathT => {
                let widget = PropertyWidgets.buildTexturePathWidget(current, textureNames, commit);
                let updater = (json: Util.Json.Json) -> updateComboBox(widget, json);
                (widget, updater)
            }
            case NodeInspector.FieldKind.BoolT => {
                let widget = PropertyWidgets.buildBoolWidget(current, commit);
                let updater = (json: Util.Json.Json) -> updateCheckBox(widget, json);
                (widget, updater)
            }
            case NodeInspector.FieldKind.ColorT => {
                let widget = PropertyWidgets.buildColorWidget(current, commit);
                // ColorPicker は per-frame で setValue しない。snapshot が user pick より
                // ラグするタイミングで古い色を上書きしてしまうため。
                // rebuildInspector (選択変更時) で picker が再生成されて値が同期する
                let updater = (j: Util.Json.Json) -> {
                    let _ = j;
                    let _: Array[Int32, Static] = Array#{0i32} @ Static;
                    ()
                };
                (widget, updater)
            }
            case NodeInspector.FieldKind.EnumT(options) => {
                let widget = PropertyWidgets.buildEnumWidget(current, options, commit);
                let updater = (json: Util.Json.Json) -> updateEnumCombo(widget, json);
                (widget, updater)
            }
            case NodeInspector.FieldKind.SoundNameT => {
                // texture と同じ ComboBox 系。候補リストだけ soundNames から渡す
                let widget = PropertyWidgets.buildTexturePathWidget(current, soundNames, commit);
                let updater = (json: Util.Json.Json) -> updateComboBox(widget, json);
                (widget, updater)
            }
        }

    /// Vec2 widget (VBox の 2 行、各行 HBox(Label, Spinner)) を JSON から復元する。
    /// PropertyWidgets.buildVec2Widget の構造に合わせて X / Y Spinner を引き直す
    def updateVec2Widget(widget: Node, json: Util.Json.Json, isInt: Bool): Unit \ IO = {
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

    def updateFloatSpinner(widget: Node, json: Util.Json.Json): Unit \ IO = {
        let sp: Spinner[Double] = unchecked_cast(widget as Spinner[Double]);
        match NodeInspector.jsonToFloat(json) {
            case None => ()
            case Some(v) =>
                if (not sp.getEditor().isFocused()) {
                    sp.getValueFactory().setValue(Double.valueOf(v))
                } else ()
        }
    }

    def updateIntSpinner(widget: Node, json: Util.Json.Json): Unit \ IO = {
        let sp: Spinner[Integer] = unchecked_cast(widget as Spinner[Integer]);
        match NodeInspector.jsonToInt(json) {
            case None => ()
            case Some(v) =>
                if (not sp.getEditor().isFocused()) {
                    sp.getValueFactory().setValue(Integer.valueOf(v))
                } else ()
        }
    }

    def updateTextField(widget: Node, json: Util.Json.Json): Unit \ IO = {
        let tf: TextField = unchecked_cast(widget as TextField);
        match NodeInspector.jsonToString(json) {
            case None    => ()
            case Some(s) => if (not tf.isFocused()) tf.setText(s) else ()
        }
    }

    def updateComboBox(widget: Node, json: Util.Json.Json): Unit \ IO = {
        let cb: ComboBox[String] = unchecked_cast(widget as ComboBox[String]);
        match NodeInspector.jsonToString(json) {
            case None    => ()
            case Some(s) => cb.setValue(s)
        }
    }

    def updateCheckBox(widget: Node, json: Util.Json.Json): Unit \ IO = {
        let cb: CheckBox = unchecked_cast(widget as CheckBox);
        match NodeInspector.jsonToBool(json) {
            case None    => ()
            case Some(b) => cb.setSelected(b)
        }
    }

    def updateEnumCombo(widget: Node, json: Util.Json.Json): Unit \ IO = {
        let cb: ComboBox[String] = unchecked_cast(widget as ComboBox[String]);
        match NodeInspector.jsonToString(json) {
            case None    => ()
            case Some(s) => cb.setValue(s)
        }
    }

    // ─── シーン description (画面下部のメモ欄) ─────────────────────

    /// シーンメモ TextArea にフォーカス外しリスナーを貼る。
    /// blur で内容を現在のシーン .scene.json の `"description"` フィールドに書き戻す。
    /// HotReload watcher が次フレームで scene を再 load するが、TextArea は他のフィールドと
    /// 違って表示と保存が独立しているので問題ない
    pub def wireSceneDescriptionArea(state: IdeState.IdeState, area: TextArea): Unit \ IO =
        area.focusedProperty().addListener(new ChangeListener[Boolean] {
            def changed(_this: ChangeListener[Boolean], _obs: ObservableValue[JObject],
                         _old: Boolean, _new: Boolean): Unit \ IO =
                if (not area.isFocused())
                    saveSceneDescription(state, area.getText())
                else ()
        })

    /// 現在 TextArea に表示中の description が由来するシーンの scene.json を読んで
    /// `"description"` を上書き保存する。
    /// シーン切替直後は currentScenePathRef が先に新シーンへ進むため、ここで
    /// currentScenePathRef を参照すると「新シーンに前シーンの内容を書き込む」事故が起きる。
    /// 代わりに `widgets#sceneDescriptionEditingPath` を使う (setText 完了時に更新される)。
    /// JSON parse 失敗・scene 未選択なら no-op。
    /// FileRead 効果は内側で IO に discharge する (listener context は IO のみ持つため)
    def saveSceneDescription(state: IdeState.IdeState, text: String): Unit \ IO =
        match Array.get(0, state#widgets#sceneDescriptionEditingPath) {
            case None       => ()
            case Some(path) =>
                run {
                    let readResult = run {
                        Fs.ReadFile.read(path)
                    } with Fs.ReadFile.runWithFileRead;
                    match readResult {
                        case Err(_) => ()
                        case Ok(content) =>
                            match JsonCompat.parse(String.trim(content)) {
                                case None       => ()
                                case Some(json) => {
                                    let updated = JsonOps.setAtKeyPath(json,
                                        "description" :: Nil,
                                        Util.Json.Json.JString(text));
                                    let pretty = Util.Json.toPrettyString(2i32, updated);
                                    discard Files.writeString(Paths.get(path), pretty);
                                    println("[Scenes] saved description: ${path}")
                                }
                            }
                    }
                } with Fs.FileRead.runWithIO
        }

    /// 現在シーンの scene.json から `description` を読み、TextArea にセットする。
    /// scene 切替時に Main の renderLoop から呼ぶ。TextArea がフォーカス中なら
    /// ユーザーの入力を消さないよう更新を skip する
    pub def refreshSceneDescription(state: IdeState.IdeState): Unit \ {IO, Fs.FileRead} =
        match IdeState.getCurrentScenePath(state) {
            case None       => ()
            case Some(path) => {
                let readResult = run {
                    Fs.ReadFile.read(path)
                } with Fs.ReadFile.runWithFileRead;
                let desc = match readResult {
                    case Err(_)      => ""
                    case Ok(content) => extractDescription(content)
                };
                scheduleSetSceneDescription(state, path, desc)
            }
        }

    def extractDescription(content: String): String =
        match JsonCompat.parse(String.trim(content)) {
            case Some(Util.Json.Json.JObject(m)) =>
                match Map.get("description", m) {
                    case Some(Util.Json.Json.JString(s)) => s
                    case _                                    => ""
                }
            case _ => ""
        }

    /// `path` は TextArea にセットしようとしている description が由来するシーンの絶対パス。
    /// setText 成功時に `editingPath` も同期して更新するので、blur listener はその後
    /// このパスへ書き戻すことになる (シーン切替直後のレース防止)。
    /// area が focused 中ならユーザー入力を消さないよう setText も editingPath 更新も skip
    def scheduleSetSceneDescription(state: IdeState.IdeState, path: String, text: String):
            Unit \ IO =
        Platform.runLater(new Runnable {
            def $run(_this: Runnable): Unit \ IO =
                match Array.get(0, state#widgets#sceneDescriptionArea) {
                    case None       => ()
                    case Some(area) =>
                        if (not area.isFocused()) {
                            area.setText(text);
                            Array.put(Some(path), 0, state#widgets#sceneDescriptionEditingPath)
                        } else ()
                }
        })

}
