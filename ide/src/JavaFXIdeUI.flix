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
    import javafx.scene.canvas.Canvas
    import javafx.scene.control.Tab
    import javafx.scene.Node
    import java.lang.Integer
    import javafx.scene.control.Button
    import javafx.scene.control.ToggleButton
    import javafx.scene.control.ToggleGroup
    import javafx.scene.control.Tooltip
    import javafx.scene.control.CheckBox
    import javafx.scene.control.ComboBox
    import javafx.scene.control.Spinner
    import javafx.scene.control.Label
    import javafx.scene.control.TextArea
    import javafx.scene.control.TextField
    import javafx.scene.control.MenuItem
    import javafx.scene.control.ProgressBar
    import javafx.scene.control.TreeView
    import javafx.scene.control.ListView
    import javafx.scene.layout.StackPane
    import javafx.scene.layout.VBox
    import javafx.scene.layout.HBox
    import javafx.scene.control.TabPane
    import javafx.scene.layout.GridPane
    import javafx.application.Platform
    import javafx.animation.AnimationTimer
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
        let subEntryAddBtn: Button = unchecked_cast(ns.get("subEntryAddBtn") as Button);
        let subEntryRemoveBtn: Button = unchecked_cast(ns.get("subEntryRemoveBtn") as Button);
        let propertyPanel: VBox = unchecked_cast(ns.get("propertyPanel") as VBox);
        let resourcePreviewPane: StackPane = unchecked_cast(ns.get("resourcePreviewPane") as StackPane);
        // 拡縮ボタン・ラベルは廃止（canvas へのピンチで操作）
        let previewGridCheck: CheckBox = unchecked_cast(ns.get("previewGridCheck") as CheckBox);
        let previewFrameAdjustCheck: CheckBox =
            unchecked_cast(ns.get("previewFrameAdjustCheck") as CheckBox);
        let resourceStatusLabel: Label =
            unchecked_cast(ns.get("resourceStatusLabel") as Label);
        let sceneDescriptionArea: TextArea =
            unchecked_cast(ns.get("sceneDescriptionArea") as TextArea);
        Array.put(Some(scenesTree),          0, state#widgets#sceneTree);
        Array.put(Some(resourcesList),       0, state#widgets#resourcesList);
        Array.put(Some(subEntriesList),      0, state#widgets#subEntriesList);
        Array.put(Some(subEntryAddBtn),      0, state#widgets#subEntryAddBtn);
        Array.put(Some(subEntryRemoveBtn),   0, state#widgets#subEntryRemoveBtn);
        Array.put(Some(propertyPanel),       0, state#widgets#propertyPanel);
        Array.put(Some(resourcePreviewPane), 0, state#widgets#resourcePreviewPane);
        Array.put(Some(previewGridCheck),    0, state#widgets#resourcePreviewGridChk);
        Array.put(Some(previewFrameAdjustCheck), 0, state#widgets#resourcePreviewFrameAdjustChk);
        Array.put(Some(resourceStatusLabel), 0, state#widgets#resourceStatusLabel);
        Array.put(Some(sceneDescriptionArea), 0, state#widgets#sceneDescriptionArea);
        // フォーカス外しで scene.json の description を書き戻す
        ScenePanel.wireSceneDescriptionArea(state, sceneDescriptionArea);
        Array.put(Some(stage),               0, state#widgets#stage);

        // Project ロード進捗 overlay。reloadProject の各フェーズで Platform.runLater 経由で更新する
        let loadingOverlay: VBox = unchecked_cast(ns.get("loadingOverlay") as VBox);
        let loadingLabel:   Label = unchecked_cast(ns.get("loadingLabel") as Label);
        let loadingBar:     ProgressBar = unchecked_cast(ns.get("loadingBar") as ProgressBar);
        Array.put(Some(loadingOverlay), 0, state#widgets#loadingOverlay);
        Array.put(Some(loadingLabel),   0, state#widgets#loadingLabel);
        Array.put(Some(loadingBar),     0, state#widgets#loadingBar);

        // Resources タブの wiring (ListView 選択 → schema/data ロード → property panel)
        ResourcePanel.wireResourceSelection(state, resourcesList, subEntriesList);
        ResourcePanel.wireSubEntrySelection(state, subEntriesList);
        ResourcePanel.wireSubEntryButtons(state, subEntriesList, subEntryAddBtn, subEntryRemoveBtn);
        ResourcePanel.wireGridCheckbox(state, previewGridCheck);
        ResourcePanel.wireFrameAdjustCheckbox(state, previewFrameAdjustCheck);
        // pane の幅高変化 (window resize / divider 移動) で preview canvas を作り直す
        ResourcePanel.wirePreviewResize(state, resourcePreviewPane);
        // ピンチズームは永続 pane に 1 回だけ登録 (canvas 再生成と無関係に gesture が続く)
        ResourcePanel.wirePreviewPinchZoom(state, resourcePreviewPane);

        // Maps タブの中身は map-editor.fxml に分離。
        // fx:include だと inner fx:id が親 namespace から見えないため、別 FXMLLoader で
        // ロードして Tab.setContent + 専用 namespace から widget を引く。
        let mapsTab: Tab = unchecked_cast(ns.get("mapsTab") as Tab);
        let mapFxmlUrl = new File("src/map-editor.fxml").toURI().toURL();
        let mapLoader = new FXMLLoader(mapFxmlUrl);
        mapLoader.setClassLoader(probe.getClass().getClassLoader());
        let mapRootObj: JObject = mapLoader.load();
        let mapRoot: Node = unchecked_cast(mapRootObj as Node);
        mapsTab.setContent(mapRoot);
        let mapNs = mapLoader.getNamespace();
        let mapsList: TreeView[String] = unchecked_cast(mapNs.get("mapsList") as TreeView[String]);
        let mapGridCanvas: Canvas = unchecked_cast(mapNs.get("mapGridCanvas") as Canvas);
        Array.put(Some(mapsList), 0, state#widgets#mapsList);
        Array.put(Some(mapGridCanvas), 0, state#widgets#mapGridCanvas);
        // Layer リスト (Floor/Walls/Entities) + tile パレット + identifier 入力 + 新規ボタン
        let mapLayerRowFloor: HBox = unchecked_cast(mapNs.get("mapLayerRowFloor") as HBox);
        let mapLayerRowWalls: HBox = unchecked_cast(mapNs.get("mapLayerRowWalls") as HBox);
        let mapLayerRowEntities: HBox = unchecked_cast(mapNs.get("mapLayerRowEntities") as HBox);
        let mapLayerVisibleFloor: ToggleButton =
            unchecked_cast(mapNs.get("mapLayerVisibleFloor") as ToggleButton);
        let mapLayerVisibleWalls: ToggleButton =
            unchecked_cast(mapNs.get("mapLayerVisibleWalls") as ToggleButton);
        let mapLayerVisibleEntities: ToggleButton =
            unchecked_cast(mapNs.get("mapLayerVisibleEntities") as ToggleButton);
        let mapPaletteCanvas: Canvas = unchecked_cast(mapNs.get("mapPaletteCanvas") as Canvas);
        let mapPaletteStatus: Label = unchecked_cast(mapNs.get("mapPaletteStatus") as Label);
        let mapPaletteLabel: Label = unchecked_cast(mapNs.get("mapPaletteLabel") as Label);
        let mapPaletteTextureCombo: ComboBox[String] =
            unchecked_cast(mapNs.get("mapPaletteTextureCombo") as ComboBox[String]);
        let mapPaletteCellWSpinner: Spinner[Integer] =
            unchecked_cast(mapNs.get("mapPaletteCellWSpinner") as Spinner[Integer]);
        let mapPaletteCellHSpinner: Spinner[Integer] =
            unchecked_cast(mapNs.get("mapPaletteCellHSpinner") as Spinner[Integer]);
        let mapPaletteMarginXSpinner: Spinner[Integer] =
            unchecked_cast(mapNs.get("mapPaletteMarginXSpinner") as Spinner[Integer]);
        let mapPaletteMarginYSpinner: Spinner[Integer] =
            unchecked_cast(mapNs.get("mapPaletteMarginYSpinner") as Spinner[Integer]);
        let mapEntityIdField: TextField =
            unchecked_cast(mapNs.get("mapEntityIdField") as TextField);
        let mapNewBtn: Button = unchecked_cast(mapNs.get("mapNewBtn") as Button);
        let mapDeleteBtn: Button = unchecked_cast(mapNs.get("mapDeleteBtn") as Button);
        let mapDuplicateBtn: Button = unchecked_cast(mapNs.get("mapDuplicateBtn") as Button);
        let mapToolPencilBtn: ToggleButton =
            unchecked_cast(mapNs.get("mapToolPencilBtn") as ToggleButton);
        let mapToolRangeBtn: ToggleButton =
            unchecked_cast(mapNs.get("mapToolRangeBtn") as ToggleButton);
        let mapPreviewToggleBtn: ToggleButton =
            unchecked_cast(mapNs.get("mapPreviewToggleBtn") as ToggleButton);
        let mapPaletteSection: VBox = unchecked_cast(mapNs.get("mapPaletteSection") as VBox);
        let mapEntitySection: VBox = unchecked_cast(mapNs.get("mapEntitySection") as VBox);
        let mapRightTabs: TabPane = unchecked_cast(mapNs.get("mapRightTabs") as TabPane);
        let mapMaterialsWallMapBox: VBox =
            unchecked_cast(mapNs.get("mapMaterialsWallMapBox") as VBox);
        let mapMaterialsStatus: Label =
            unchecked_cast(mapNs.get("mapMaterialsStatus") as Label);
        let mapMaterialsTilesetCanvas: Canvas =
            unchecked_cast(mapNs.get("mapMaterialsTilesetCanvas") as Canvas);
        let mapRuleAddBtn: Button =
            unchecked_cast(mapNs.get("mapRuleAddBtn") as Button);
        let mapRuleRemoveBtn: Button =
            unchecked_cast(mapNs.get("mapRuleRemoveBtn") as Button);
        let mapRuleList: ComboBox[String] =
            unchecked_cast(mapNs.get("mapRuleList") as ComboBox[String]);
        let mapRuleEditor: VBox =
            unchecked_cast(mapNs.get("mapRuleEditor") as VBox);
        let mapRuleNameField: TextField =
            unchecked_cast(mapNs.get("mapRuleNameField") as TextField);
        let mapRulePatternGrid: GridPane =
            unchecked_cast(mapNs.get("mapRulePatternGrid") as GridPane);
        let mapRulePaletteBox: VBox =
            unchecked_cast(mapNs.get("mapRulePaletteBox") as VBox);
        let mapRuleTileLabel: Label =
            unchecked_cast(mapNs.get("mapRuleTileLabel") as Label);
        let mapRuleTilesetCanvas: Canvas =
            unchecked_cast(mapNs.get("mapRuleTilesetCanvas") as Canvas);
        let mapRuleSizeCombo: ComboBox[String] =
            unchecked_cast(mapNs.get("mapRuleSizeCombo") as ComboBox[String]);
        let mapSettingsTab: Tab =
            unchecked_cast(mapNs.get("mapSettingsTab") as Tab);
        let mapSettingsNameField: TextField =
            unchecked_cast(mapNs.get("mapSettingsNameField") as TextField);
        let mapSettingsWidthSpinner: Spinner[Integer] =
            unchecked_cast(mapNs.get("mapSettingsWidthSpinner") as Spinner[Integer]);
        let mapSettingsHeightSpinner: Spinner[Integer] =
            unchecked_cast(mapNs.get("mapSettingsHeightSpinner") as Spinner[Integer]);
        let mapSettingsResizeInfo: Label =
            unchecked_cast(mapNs.get("mapSettingsResizeInfo") as Label);
        let mapSettingsRenameWarning: Label =
            unchecked_cast(mapNs.get("mapSettingsRenameWarning") as Label);
        let mapSettingsApplyBtn: Button =
            unchecked_cast(mapNs.get("mapSettingsApplyBtn") as Button);
        let mapSettingsStatus: Label =
            unchecked_cast(mapNs.get("mapSettingsStatus") as Label);
        Array.put(Some(mapLayerRowFloor), 0, state#widgets#mapLayerRowFloor);
        Array.put(Some(mapLayerRowWalls), 0, state#widgets#mapLayerRowWalls);
        Array.put(Some(mapLayerRowEntities), 0, state#widgets#mapLayerRowEntities);
        Array.put(Some(mapLayerVisibleFloor), 0, state#widgets#mapLayerVisibleFloor);
        Array.put(Some(mapLayerVisibleWalls), 0, state#widgets#mapLayerVisibleWalls);
        Array.put(Some(mapLayerVisibleEntities), 0, state#widgets#mapLayerVisibleEntities);
        Array.put(Some(mapPaletteCanvas), 0, state#widgets#mapPaletteCanvas);
        Array.put(Some(mapPaletteStatus), 0, state#widgets#mapPaletteStatus);
        Array.put(Some(mapPaletteLabel), 0, state#widgets#mapPaletteLabel);
        Array.put(Some(mapPaletteTextureCombo), 0, state#widgets#mapPaletteTextureCombo);
        Array.put(Some(mapPaletteCellWSpinner), 0, state#widgets#mapPaletteCellWSpinner);
        Array.put(Some(mapPaletteCellHSpinner), 0, state#widgets#mapPaletteCellHSpinner);
        Array.put(Some(mapPaletteMarginXSpinner), 0, state#widgets#mapPaletteMarginXSpinner);
        Array.put(Some(mapPaletteMarginYSpinner), 0, state#widgets#mapPaletteMarginYSpinner);
        Array.put(Some(mapEntityIdField), 0, state#widgets#mapEntityIdField);
        Array.put(Some(mapNewBtn), 0, state#widgets#mapNewBtn);
        Array.put(Some(mapDeleteBtn), 0, state#widgets#mapDeleteBtn);
        Array.put(Some(mapDuplicateBtn), 0, state#widgets#mapDuplicateBtn);
        Array.put(Some(mapToolPencilBtn), 0, state#widgets#mapToolPencilBtn);
        Array.put(Some(mapToolRangeBtn), 0, state#widgets#mapToolRangeBtn);
        Array.put(Some(mapPreviewToggleBtn), 0, state#widgets#mapPreviewToggleBtn);
        Array.put(Some(mapPaletteSection), 0, state#widgets#mapPaletteSection);
        Array.put(Some(mapEntitySection), 0, state#widgets#mapEntitySection);
        Array.put(Some(mapRightTabs), 0, state#widgets#mapRightTabs);
        Array.put(Some(mapMaterialsWallMapBox), 0, state#widgets#mapMaterialsWallMapBox);
        Array.put(Some(mapMaterialsStatus), 0, state#widgets#mapMaterialsStatus);
        Array.put(Some(mapMaterialsTilesetCanvas), 0, state#widgets#mapMaterialsTilesetCanvas);
        Array.put(Some(mapRuleAddBtn), 0, state#widgets#mapRuleAddBtn);
        Array.put(Some(mapRuleRemoveBtn), 0, state#widgets#mapRuleRemoveBtn);
        Array.put(Some(mapRuleList), 0, state#widgets#mapRuleList);
        Array.put(Some(mapRuleEditor), 0, state#widgets#mapRuleEditor);
        Array.put(Some(mapRuleNameField), 0, state#widgets#mapRuleNameField);
        Array.put(Some(mapRulePatternGrid), 0, state#widgets#mapRulePatternGrid);
        Array.put(Some(mapRulePaletteBox), 0, state#widgets#mapRulePaletteBox);
        Array.put(Some(mapRuleTileLabel), 0, state#widgets#mapRuleTileLabel);
        Array.put(Some(mapRuleTilesetCanvas), 0, state#widgets#mapRuleTilesetCanvas);
        Array.put(Some(mapRuleSizeCombo), 0, state#widgets#mapRuleSizeCombo);
        Array.put(Some(mapSettingsTab), 0, state#widgets#mapSettingsTab);
        Array.put(Some(mapSettingsNameField), 0, state#widgets#mapSettingsNameField);
        Array.put(Some(mapSettingsWidthSpinner), 0, state#widgets#mapSettingsWidthSpinner);
        Array.put(Some(mapSettingsHeightSpinner), 0, state#widgets#mapSettingsHeightSpinner);
        Array.put(Some(mapSettingsResizeInfo), 0, state#widgets#mapSettingsResizeInfo);
        Array.put(Some(mapSettingsRenameWarning), 0, state#widgets#mapSettingsRenameWarning);
        Array.put(Some(mapSettingsApplyBtn), 0, state#widgets#mapSettingsApplyBtn);
        Array.put(Some(mapSettingsStatus), 0, state#widgets#mapSettingsStatus);
        // Map canvas: クリック・ピンチズーム・Ctrl/Cmd+Z undo を 1 か所で配線
        MapGridCanvas.wireMapCanvas(state, mapGridCanvas);
        MapEditorPanel.wireToolButtons(state, mapToolPencilBtn, mapToolRangeBtn);
        MapEditorPanel.wirePreviewToggle(state);
        MapEditorPanel.wireLayerList(state);
        MapEditorPanel.initPaletteWidgets(state);
        MapEditorPanel.wirePaletteClick(state, mapPaletteCanvas);
        MapEditorPanel.wireNewLevelButton(state, mapNewBtn);
        MapEditorPanel.wireDeleteLevelButton(state, mapDeleteBtn);
        MapEditorPanel.wireDuplicateLevelButton(state, mapDuplicateBtn);
        MapEditorPanel.wireMapSelection(state, mapsList);
        MapEditorPanel.initMaterialsTab(state);
        MapEditorPanel.initSettingsTab(state);

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
        ScenePanel.wireSceneContextMenu(state, scenesTree);
        ScenePanel.wireTreeDeleteKey(state, scenesTree);
        ScenePanel.startStatusBarTimer(state, canvasView);

        // 編集ツールバー: 選択ツール / 手のひら(パン)ツールの切替。toolModeRef に書き、Editor が読む。
        let toolSelect: ToggleButton = unchecked_cast(ns.get("toolSelect") as ToggleButton);
        let toolHand:   ToggleButton = unchecked_cast(ns.get("toolHand") as ToggleButton);
        let toolGroup = new ToggleGroup();
        toolSelect.setToggleGroup(toolGroup);
        toolHand.setToggleGroup(toolGroup);
        toolSelect.setSelected(true);
        toolSelect.setTooltip(new Tooltip("選択ツール: ドラッグでノード選択・移動"));
        toolHand.setTooltip(new Tooltip("手のひらツール: ドラッグでビューをパン (中ボタンdrag/ホイールズームは常時)"));
        toolSelect.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO =
                Array.put(0i32, 0, state#toolModeRef)
        });
        toolHand.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO =
                Array.put(1i32, 0, state#toolModeRef)
        });

        // グリッドスナップ: トグルで ON/OFF (snapEnabledRef)、コンボで間隔 (snapStepRef)。
        // Editor がこれらを読み、ドラッグ移動の確定値を格子へ吸着する。
        let toolSnap: ToggleButton = unchecked_cast(ns.get("toolSnap") as ToggleButton);
        toolSnap.setTooltip(new Tooltip("グリッドスナップ: ドラッグ移動を間隔の格子点へ吸着"));
        toolSnap.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO =
                Array.put(toolSnap.isSelected(), 0, state#snapEnabledRef)
        });
        let snapCombo: ComboBox[String] = unchecked_cast(ns.get("snapStepCombo") as ComboBox[String]);
        let snapItems = snapCombo.getItems();
        discard snapItems.add("4");
        discard snapItems.add("8");
        discard snapItems.add("16");
        discard snapItems.add("32");
        snapCombo.setValue("16");
        snapCombo.setTooltip(new Tooltip("スナップ間隔 (px)"));
        snapCombo.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO = {
                let v = snapCombo.getValue();
                if (Object.isNull(v)) ()
                else match Float64.fromString(v) {
                    case Some(f) => Array.put(f, 0, state#snapStepRef)
                    case None    => ()
                }
            }
        });

        // canvas 左上のズーム HUD (Godot 風)。− / ＋ で zoomCommandRef に積み、
        // % 表示は AnimationTimer が zoomDisplayRef を読んで毎フレーム更新する。
        let zoomOutHud: Button = unchecked_cast(ns.get("zoomOutHud") as Button);
        let zoomInHud:  Button = unchecked_cast(ns.get("zoomInHud") as Button);
        let zoomLabel:  Label  = unchecked_cast(ns.get("zoomLabel") as Label);
        zoomOutHud.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO =
                Array.put(-1i32, 0, state#zoomCommandRef)
        });
        zoomInHud.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO =
                Array.put(1i32, 0, state#zoomCommandRef)
        });
        let zoomTimer = new AnimationTimer {
            def handle(_this: AnimationTimer, _now: Int64): Unit \ IO =
                zoomLabel.setText(formatZoomPct(Array.get(0, state#zoomDisplayRef)))
        };
        zoomTimer.start();

        // メニュー項目を wire
        // New Scene はプロジェクト未オープン時は無効 (グレーアウト)。Open Project で
        // ディレクトリが選ばれた時点で有効化する (Godot/Unity と同じ contextual enable)。
        let newSceneItem: MenuItem = unchecked_cast(ns.get("menuNewScene") as MenuItem);
        newSceneItem.setDisable(true);
        newSceneItem.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO =
                ScenePanel.showNewSceneDialog(state)
        });

        // Project メニュー: プロジェクトを開くまで無効。Open Project で有効化する。
        let projectSettingsItem: MenuItem =
            unchecked_cast(ns.get("menuProjectSettings") as MenuItem);
        projectSettingsItem.setDisable(true);
        projectSettingsItem.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO =
                ScenePanel.showProjectSettingsDialog(state)
        });

        let openItem: MenuItem = unchecked_cast(ns.get("menuOpenProject") as MenuItem);
        openItem.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO =
                if (showOpenProjectChooser(state, stage)) {
                    newSceneItem.setDisable(false);
                    projectSettingsItem.setDisable(false)
                } else ()
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
    /// ディレクトリが選ばれて project ロードを予約したら true、キャンセルなら false。
    /// 呼び出し側は true のとき New Scene メニューを有効化する。
    def showOpenProjectChooser(state: IdeState.IdeState, stage: Stage): Bool \ IO = {
        let chooser = new DirectoryChooser();
        chooser.setTitle("Open Project");
        let chosen = chooser.showDialog(stage);
        if (Object.isNull(chosen)) false
        else {
            let path = chosen.getAbsolutePath();
            println("[IdeUI] Open Project selected: ${path}");
            // 次フレームの reloadProject が走るまでの体感ラグを埋めるため、
            // overlay を 0% で先に出しておく
            Array.put(true, 0, state#loadingActiveRef);
            showLoadingOverlay(state, "プロジェクトを読み込み中...", 0.05f64);
            Array.put(Some(path), 0, state#pendingProjectRef);
            true
        }
    }

    /// FX EDT に飛ばさず直接 widget を更新するヘルパー。
    /// showOpenProjectChooser は FX EDT 上で呼ばれるためそのまま update してよい
    def showLoadingOverlay(state: IdeState.IdeState, label: String, frac: Float64): Unit \ IO = {
        match Array.get(0, state#widgets#loadingOverlay) {
            case Some(box) => {
                box.setVisible(true);
                box.setManaged(true)
            }
            case None => ()
        };
        match Array.get(0, state#widgets#loadingLabel) {
            case Some(lbl) => lbl.setText(label)
            case None      => ()
        };
        match Array.get(0, state#widgets#loadingBar) {
            case Some(bar) => bar.setProgress(clampFrac(frac))
            case None      => ()
        }
    }

    def clampFrac(f: Float64): Float64 =
        if (f < 0.0f64) 0.0f64
        else if (f > 1.0f64) 1.0f64
        else f

    /// ズーム倍率を "84.4 %" のように小数 1 桁のパーセント文字列にする。
    def formatZoomPct(z: Float64): String =
        let tenths = Float64.truncateToInt32(Float64.round(z * 1000.0));
        let whole = tenths / 10i32;
        let frac = Int32.modulo(tenths, 10i32);
        "${whole}.${frac} %"

    /// Main thread の renderLoop からプロジェクト切替後に呼ぶ。
    /// FX thread で TreeView の root を差し替える。sceneFilesRef は既に新値が入っている前提
    pub def schedulePopulateTree(state: IdeState.IdeState): Unit \ IO = {
        Platform.runLater(new Runnable {
            def $run(_this: Runnable): Unit \ IO = {
                ScenePanel.populateSceneTree(state);
                ResourcePanel.populateResourcesList(state);
                MapEditorPanel.populateMapList(state);
                MapEditorPanel.populatePaletteTextureCombo(state);
                MapEditorPanel.drawPalette(state)
            }
        })
    }

    /// Project ロード進捗 overlay を表示・更新する。Main の reloadProject が各フェーズで呼ぶ
    pub def scheduleSetLoadingProgress(state: IdeState.IdeState, label: String, frac: Float64):
            Unit \ IO = {
        Platform.runLater(new Runnable {
            def $run(_this: Runnable): Unit \ IO = showLoadingOverlay(state, label, frac)
        })
    }

    /// Project ロード進捗 overlay を非表示にする。先頭シーン描画完了時に Main が呼ぶ
    pub def scheduleHideLoading(state: IdeState.IdeState): Unit \ IO = {
        Platform.runLater(new Runnable {
            def $run(_this: Runnable): Unit \ IO = {
                match Array.get(0, state#widgets#loadingOverlay) {
                    case Some(box) => {
                        box.setVisible(false);
                        box.setManaged(false)
                    }
                    case None => ()
                }
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
