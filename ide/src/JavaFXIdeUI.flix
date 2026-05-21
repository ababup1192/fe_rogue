// JavaFXIdeUI — IDE シェルのトップレベル orchestrator。
//
// 役割は以下の 3 つに限定:
//   - customize: JavaFXLayer.withJavaFX に渡される FXML ロードと widget 配線
//   - showOpenProjectChooser: File メニューから DirectoryChooser を出す
//   - schedulePopulateTree / scheduleSetTitle: Main から呼ばれる FX thread への dispatch
//
// 具体的な panel ロジックは ResourcePanel / ScenePanel / PropertyWidgets に分散。
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
    import javafx.fxml.FXMLLoader
    import javafx.scene.Parent
    import javafx.scene.Scene
    import javafx.scene.image.ImageView
    import javafx.scene.image.WritableImage
    import javafx.scene.control.Button
    import javafx.scene.control.CheckBox
    import javafx.scene.control.Label
    import javafx.scene.control.MenuItem
    import javafx.scene.control.TreeView
    import javafx.scene.control.ListView
    import javafx.scene.layout.StackPane
    import javafx.scene.layout.VBox
    import javafx.application.Platform
    import javafx.event.ActionEvent
    import javafx.event.EventHandler
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
        let probe = new Label("");
        loader.setClassLoader(probe.getClass().getClassLoader());

        let rootObj: JObject = loader.load();
        let root: Parent = unchecked_cast(rootObj as Parent);
        let ns = loader.getNamespace();

        // FXML 宣言済みの canvasView に Layer 生成の WritableImage を流し込む
        let canvasView: ImageView = unchecked_cast(ns.get("canvasView") as ImageView);
        canvasView.setImage(initialImage);

        // Scenes TreeView と Resources の各 widget を取得し state に stash
        let scenesTree: TreeView[String] = unchecked_cast(ns.get("scenesTree") as TreeView[String]);
        let resourcesList: ListView[String] = unchecked_cast(ns.get("resourcesList") as ListView[String]);
        let subEntriesList: ListView[String] = unchecked_cast(ns.get("subEntriesList") as ListView[String]);
        let propertyPanel: VBox = unchecked_cast(ns.get("propertyPanel") as VBox);
        let resourcePreviewPane: StackPane = unchecked_cast(ns.get("resourcePreviewPane") as StackPane);
        let previewZoomLabel: Label = unchecked_cast(ns.get("previewZoomLabel") as Label);
        let previewZoomOut:   Button = unchecked_cast(ns.get("previewZoomOut") as Button);
        let previewZoomIn:    Button = unchecked_cast(ns.get("previewZoomIn") as Button);
        let previewGridCheck: CheckBox = unchecked_cast(ns.get("previewGridCheck") as CheckBox);
        Array.put(Some(scenesTree),          0, state#widgets#sceneTree);
        Array.put(Some(resourcesList),       0, state#widgets#resourcesList);
        Array.put(Some(subEntriesList),      0, state#widgets#subEntriesList);
        Array.put(Some(propertyPanel),       0, state#widgets#propertyPanel);
        Array.put(Some(resourcePreviewPane), 0, state#widgets#resourcePreviewPane);
        Array.put(Some(previewZoomLabel),    0, state#widgets#resourcePreviewZoomLbl);
        Array.put(Some(previewGridCheck),    0, state#widgets#resourcePreviewGridChk);
        Array.put(Some(stage),               0, state#widgets#stage);

        // Resources タブの wiring (ListView 選択 → schema/data ロード → property panel)
        ResourcePanel.wireResourceSelection(state, resourcesList, subEntriesList);
        ResourcePanel.wireSubEntrySelection(state, subEntriesList);
        ResourcePanel.wireZoomButtons(state, previewZoomOut, previewZoomIn);
        ResourcePanel.wireGridCheckbox(state, previewGridCheck);
        ResourcePanel.updateZoomLabel(state);

        // ステータスバー Label を取得
        let statusScene:     Label = unchecked_cast(ns.get("statusScene") as Label);
        let statusMouse:     Label = unchecked_cast(ns.get("statusMouse") as Label);
        let statusSelection: Label = unchecked_cast(ns.get("statusSelection") as Label);
        let statusFps:       Label = unchecked_cast(ns.get("statusFps") as Label);
        Array.put(Some(statusScene),     0, state#statusBar#sceneLabel);
        Array.put(Some(statusMouse),     0, state#statusBar#mouseLabel);
        Array.put(Some(statusSelection), 0, state#statusBar#selectionLabel);
        Array.put(Some(statusFps),       0, state#statusBar#fpsLabel);

        // Inspector pane
        let inspectorContent: VBox = unchecked_cast(ns.get("inspectorContent") as VBox);
        Array.put(Some(inspectorContent), 0, state#inspector#content);

        // Scene tree 配線 + 60Hz status bar + Inspector AnimationTimer
        ScenePanel.wireTreeSelection(state, scenesTree);
        ScenePanel.startStatusBarTimer(state, canvasView);

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

    /// Main thread の renderLoop からプロジェクト切替後に呼ぶ。
    /// FX thread で TreeView の root を差し替える。sceneFilesRef は既に新値が入っている前提
    pub def schedulePopulateTree(state: IdeState.IdeState): Unit \ IO = {
        Platform.runLater(new Runnable {
            def $run(_this: Runnable): Unit \ IO = {
                ScenePanel.populateSceneTree(state);
                ResourcePanel.populateResourcesList(state)
            }
        })
    }

    /// Stage title を更新する (Project ロード完了時に呼ばれる)
    pub def scheduleSetTitle(state: IdeState.IdeState, title: String): Unit \ IO = {
        Platform.runLater(new Runnable {
            def $run(_this: Runnable): Unit \ IO = {
                match Array.get(0, state#widgets#stage) {
                    case Some(stage) => stage.setTitle(title)
                    case None => ()
                }
            }
        })
    }
}
