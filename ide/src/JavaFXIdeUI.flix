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
    import javafx.scene.image.Image
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
    import javafx.scene.control.CheckBox
    import javafx.scene.control.ComboBox
    import javafx.scene.control.Spinner
    import javafx.scene.control.SelectionModel
    import javafx.scene.input.KeyEvent
    import java.lang.Double
    import java.lang.Integer
    import java.nio.file.Files
    import java.nio.file.Paths
    import java.math.{BigDecimal => JBigDecimal}
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

        // Scenes TreeView と Resources の各 widget を取得し state に stash
        let scenesTree: TreeView[String] = unchecked_cast(ns.get("scenesTree") as TreeView[String]);
        let resourcesList: ListView[String] = unchecked_cast(ns.get("resourcesList") as ListView[String]);
        let subEntriesList: ListView[String] = unchecked_cast(ns.get("subEntriesList") as ListView[String]);
        let propertyPanel: VBox = unchecked_cast(ns.get("propertyPanel") as VBox);
        let resourcePreviewPane: StackPane = unchecked_cast(ns.get("resourcePreviewPane") as StackPane);
        Array.put(Some(scenesTree),         0, state#fxSceneTreeRef);
        Array.put(Some(resourcesList),      0, state#fxResourcesListRef);
        Array.put(Some(subEntriesList),     0, state#fxSubEntriesListRef);
        Array.put(Some(propertyPanel),      0, state#fxPropertyPanelRef);
        Array.put(Some(resourcePreviewPane), 0, state#fxResourcePreviewPaneRef);
        Array.put(Some(stage),              0, state#fxStageRef);

        // Resource クリック → data + schema をロードして ResourceState に書き、
        // Sub-entries list を埋める (Swing 版 onResourceSelected と同等)
        wireResourceSelection(state, resourcesList, subEntriesList);
        // Sub-entry クリック → Property Panel を schema から組み立てる (read-only)
        wireSubEntrySelection(state, subEntriesList);

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

    /// Resources ListView 選択 → displayName から ResourceEntry を引き、
    /// data + schema を Fs.FileRead 経由で読み、Sub-entries を埋める
    def wireResourceSelection(state: IdeState.IdeState,
                                listView: ListView[String],
                                subEntriesList: ListView[String]): Unit \ IO = {
        let prop = listView.getSelectionModel().selectedItemProperty();
        let listener = new ChangeListener[String] {
            def changed(_cThis: ChangeListener[String],
                         _obs: ObservableValue[JObject],
                         _old: String, newSel: String): Unit \ IO = {
                if (Object.isNull(newSel)) ()
                else {
                    let target = newSel;
                    let entries = Array.get(0, state#resource#discoveredRef);
                    match List.find(e -> { let n = e#displayName; n == target }, entries) {
                        case None       => ()
                        case Some(entry) =>
                            run {
                                onResourceSelected(state, entry, subEntriesList)
                            } with Fs.FileRead.runWithIO
                    }
                }
            }
        };
        prop.addListener(listener)
    }

    /// data + schema をロードして ResourceState に書き、Sub-entries list を埋める。
    /// 失敗 (file 不在 / parse 失敗) はログだけ出して空状態にする
    def onResourceSelected(state: IdeState.IdeState,
                            entry: ResourceDiscovery.ResourceEntry,
                            subEntriesList: ListView[String]):
            Unit \ {IO, Fs.FileRead} = {
        ResourceState.setSelectedDataPath(state#resource, Some(entry#dataPath));
        ResourceState.setSelectedSubEntry(state#resource, None);
        ResourceState.setDirty(state#resource, false);

        let dataJson = loadJsonElement(entry#dataPath);
        ResourceState.setEditingJson(state#resource, dataJson);

        match Resource.loadSchemaDiagnostic(entry#schemaPath) {
            case Ok(s)    => ResourceState.setEditingSchema(state#resource, Some(s))
            case Err(msg) => {
                println("[Resources] Schema load failed for ${entry#displayName}: ${msg}");
                ResourceState.setEditingSchema(state#resource, None)
            }
        };

        let schemaJson = loadJsonElement(entry#schemaPath);
        ResourceState.setEditingSchemaJson(state#resource, schemaJson);

        rebuildSubEntries(state, subEntriesList)
    }

    /// JSON ファイルを読んで JsonElement にパース。失敗は None
    def loadJsonElement(path: String): Option[Json.JsonElement] \ Fs.FileRead =
        let readResult = run {
            Fs.ReadFile.read(path)
        } with Fs.ReadFile.runWithFileRead;
        readResult
            |> Result.toOption
            |> Option.flatMap(s -> Json.Parse.parse(String.trim(s)))

    /// CatalogIn 形式なら sub-entries の key 一覧を ListView に並べる。
    /// Single 形式なら Property Panel をすぐ build する (sub-entry を介さず top の record そのもの)
    def rebuildSubEntries(state: IdeState.IdeState,
                           subEntriesList: ListView[String]): Unit \ IO = {
        let items = subEntriesList.getItems();
        items.clear();
        match ResourceState.getEditingJson(state#resource) {
            case None => rebuildPropertyPanel(state)
            case Some(json) =>
                match ResourceCatalog.classify(json) {
                    case ResourceCatalog.Classification.CatalogIn(info) => {
                        List.forEach(k -> discard items.add(k), info#subEntries);
                        rebuildPropertyPanel(state)
                    }
                    case _ => rebuildPropertyPanel(state)
                }
        }
    }

    /// Sub-entries ListView 選択 → selectedSubEntry を更新し Property Panel 再構築
    def wireSubEntrySelection(state: IdeState.IdeState,
                                subList: ListView[String]): Unit \ IO = {
        let prop = subList.getSelectionModel().selectedItemProperty();
        let listener = new ChangeListener[String] {
            def changed(_cThis: ChangeListener[String],
                         _obs: ObservableValue[JObject],
                         _old: String, newSel: String): Unit \ IO = {
                if (Object.isNull(newSel)) ()
                else {
                    ResourceState.setSelectedSubEntry(state#resource, Some(newSel));
                    rebuildPropertyPanel(state)
                }
            }
        };
        prop.addListener(listener)
    }

    /// Property Panel を schema 駆動で再構築する。各フィールドは型に応じた編集 widget
    /// (TextField / CheckBox 等) を生成し、Enter で editingJson 更新 + ファイル書き戻し
    def rebuildPropertyPanel(state: IdeState.IdeState): Unit \ IO = {
        match Array.get(0, state#fxPropertyPanelRef) {
            case None => ()
            case Some(panel) => {
                let children = panel.getChildren();
                children.clear();
                match (ResourceState.getEditingSchema(state#resource),
                       ResourceState.getEditingJson(state#resource)) {
                    case (Some(schema), Some(json)) =>
                        match currentRecordJson(state, json) {
                            case None => {
                                addPropertyPlaceholder(children, "(select a sub-entry)");
                                updateSpritePreview(state, None)
                            }
                            case Some(record) => {
                                // record までの key path (catalog の場合 [container, subEntry]、
                                // single の場合 []) を計算し、各フィールド書込時に
                                // path ++ [fieldKey] を JsonOps.setAtKeyPath に渡す
                                let basePath = recordKeyPath(state, json);
                                let fields = Resource.fieldsOf(schema);
                                // schema の order で昇順、未指定は末尾。同順位は key 名で安定
                                let sorted = Map.toList(fields)
                                    |> List.sortBy(p -> fieldOrderKey(p));
                                List.forEach(p -> {
                                    let (k, e) = p;
                                    addFieldRow(state, children, k, e, record, basePath)
                                }, sorted);
                                // Preview: record から最初の TexturePath っぽい値を探して表示
                                updateSpritePreview(state, findFirstTexture(state, record))
                            }
                        }
                    case (None, Some(_)) =>
                        addPropertyPlaceholder(children, "(no schema)")
                    case _ =>
                        addPropertyPlaceholder(children, "(select a resource)")
                }
            }
        }
    }

    /// 編集対象 record への JSON key path を返す。
    /// Single → [] (top の JSON 自身が record)
    /// CatalogIn → [containerKey, subEntry]
    def recordKeyPath(state: IdeState.IdeState, json: Json.JsonElement): List[String] \ IO =
        match ResourceCatalog.classify(json) {
            case ResourceCatalog.Classification.Single => Nil
            case ResourceCatalog.Classification.CatalogIn(info) =>
                match ResourceState.getSelectedSubEntry(state#resource) {
                    case None         => Nil
                    case Some(subKey) => info#containerKey :: subKey :: Nil
                }
            case _ => Nil
        }

    /// 編集対象 record の JsonElement を返す。
    /// Single → json そのもの、CatalogIn → json[containerKey][selectedSubEntry]
    def currentRecordJson(state: IdeState.IdeState, json: Json.JsonElement):
            Option[Json.JsonElement] \ IO =
        match ResourceCatalog.classify(json) {
            case ResourceCatalog.Classification.Single => Some(json)
            case ResourceCatalog.Classification.CatalogIn(info) =>
                match ResourceState.getSelectedSubEntry(state#resource) {
                    case None => None
                    case Some(subKey) =>
                        match json {
                            case Json.JsonElement.JsonObject(topMap) =>
                                match Map.get(info#containerKey, topMap) {
                                    case Some(Json.JsonElement.JsonObject(subMap)) =>
                                        Map.get(subKey, subMap)
                                    case _ => None
                                }
                            case _ => None
                        }
                }
            case _ => None
        }

    /// 1 フィールドぶんを Property Panel に追加。型に応じて編集 widget を生成し、
    /// commit (Enter / CheckBox toggle) で editingJson + ファイルを更新する。
    /// Nested は section header (太字 Label) を入れて内側を order 順で再帰展開する
    def addFieldRow(state: IdeState.IdeState, children: ObservableList[Node],
                    key: String, entry: Resource.FieldEntry,
                    record: Json.JsonElement, basePath: List[String]): Unit \ IO =
        match entry {
            case Resource.FieldEntry.Field(fs) => {
                let value = jsonFieldOf(record, key);
                let keyPath = List.append(basePath, key :: Nil);
                let widget = buildFieldWidget(state, fs, value, keyPath);
                addPropertyRow(children, "${fs#label}:", widget)
            }
            case Resource.FieldEntry.Nested(innerMap) => {
                // section header (ネストの境目を視認しやすくする)
                let header = new Label(key);
                header.getStyleClass().add("nested-header");
                let headerNode: Node = checked_cast(header);
                discard children.add(headerNode);

                let innerRecord = jsonFieldOf(record, key)
                                   |> Option.getWithDefault(Json.JsonElement.JsonObject(Map.empty()));
                let innerBasePath = List.append(basePath, key :: Nil);
                let sortedInner = Map.toList(innerMap)
                                   |> List.sortBy(p -> fieldOrderKey(p));
                List.forEach(p -> {
                    let (k, e) = p;
                    addFieldRow(state, children, k, e, innerRecord, innerBasePath)
                }, sortedInner)
            }
        }

    /// FieldType に応じた編集 widget を返す
    def buildFieldWidget(state: IdeState.IdeState, fs: Resource.FieldSchema,
                         value: Option[Json.JsonElement], keyPath: List[String]): Node \ IO =
        match fs#ftype {
            case Resource.FieldType.TextT         => buildTextWidget(state, value, keyPath)
            case Resource.FieldType.IntT          => buildIntWidget(state, value, keyPath)
            case Resource.FieldType.FloatT        => buildFloatWidget(state, value, keyPath)
            case Resource.FieldType.BoolT         => buildBoolWidget(state, value, keyPath)
            case Resource.FieldType.TexturePathT  => buildTexturePathWidget(state, value, keyPath)
        }

    /// TexturePathT フィールド: ComboBox<String> で project 登録 texture から選択。
    /// textureNamesRef は reloadProject で project.json の textureManifest を読んで populate 済み
    def buildTexturePathWidget(state: IdeState.IdeState, value: Option[Json.JsonElement],
                                keyPath: List[String]): Node \ IO = {
        let current = match value {
            case Some(Json.JsonElement.JsonString(s)) => s
            case _                                    => ""
        };
        let combo: ComboBox[String] = new ComboBox();
        let items = combo.getItems();
        let textureNames = Array.get(0, state#textureNamesRef);
        List.forEach(name -> discard items.add(name), textureNames);
        combo.setEditable(false);
        combo.setValue(current);
        combo.setPrefWidth(160.0);
        combo.setMaxWidth(160.0);
        combo.valueProperty().addListener(new ChangeListener[String] {
            def changed(_cThis: ChangeListener[String], _obs: ObservableValue[JObject],
                         _old: String, newVal: String): Unit \ IO = {
                if (Object.isNull(newVal)) ()
                else {
                    commitFieldJson(state, keyPath, Json.JsonElement.JsonString(newVal));
                    updateSpritePreview(state, Some(newVal))
                }
            }
        });
        checked_cast(combo)
    }

    /// record JSON を DFS で walk して、textureNamesRef に含まれる文字列値を探す。
    /// 見つかれば texture 名を返す。"sprite.texture" のような典型ケースを拾える
    def findFirstTexture(state: IdeState.IdeState, record: Json.JsonElement):
            Option[String] \ IO = {
        let textureNames = Array.get(0, state#textureNamesRef) |> List.toSet;
        scanForTexture(record, textureNames)
    }

    def scanForTexture(elem: Json.JsonElement, textureNames: Set[String]):
            Option[String] \ IO =
        match elem {
            case Json.JsonElement.JsonString(s) =>
                if (Set.memberOf(s, textureNames)) Some(s) else None
            case Json.JsonElement.JsonObject(m) =>
                Map.foldLeftWithKey((acc, _k, v) -> match acc {
                    case Some(_) => acc
                    case None    => scanForTexture(v, textureNames)
                }, None, m)
            case _ => None
        }

    /// texture name (textureNamesRef のキー) から絶対パスを引いて JavaFX Image をロードし、
    /// resourcePreviewPane に ImageView として乗せる。None なら "(no preview)" 表示
    def updateSpritePreview(state: IdeState.IdeState, textureName: Option[String]): Unit \ IO =
        withRef(state#fxResourcePreviewPaneRef, pane -> {
            let children = pane.getChildren();
            children.clear();
            match textureName {
                case None => {
                    let l = new Label("(no preview)");
                    l.getStyleClass().add("inspector-empty");
                    let n: Node = checked_cast(l);
                    discard children.add(n)
                }
                case Some(name) => {
                    let pathMap = Array.get(0, state#texturePathMapRef);
                    match Map.get(name, pathMap) {
                        case None => {
                            let l = new Label("(path unknown: ${name})");
                            l.getStyleClass().add("inspector-empty");
                            let n: Node = checked_cast(l);
                            discard children.add(n)
                        }
                        case Some(absPath) => {
                            let url = new File(absPath).toURI().toString();
                            let image = new Image(url);
                            let view = new ImageView(image);
                            view.setPreserveRatio(true);
                            view.setFitWidth(220.0);
                            view.setFitHeight(220.0);
                            let n: Node = checked_cast(view);
                            discard children.add(n)
                        }
                    }
                }
            }
        })

    def buildTextWidget(state: IdeState.IdeState, value: Option[Json.JsonElement],
                         keyPath: List[String]): Node \ IO = {
        let current = match value {
            case Some(Json.JsonElement.JsonString(s)) => s
            case _                                    => ""
        };
        let field = new TextField(current);
        field.setPrefWidth(160.0);
        field.setMaxWidth(160.0);
        field.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO =
                commitFieldJson(state, keyPath, Json.JsonElement.JsonString(field.getText()))
        });
        checked_cast(field)
    }

    /// Int フィールド: Spinner<Integer> (HTML input[type=number] 相当の上下ボタン付き)
    def buildIntWidget(state: IdeState.IdeState, value: Option[Json.JsonElement],
                        keyPath: List[String]): Node \ IO = {
        let current: Int32 = match value {
            case Some(Json.JsonElement.JsonNumber(bd)) =>
                BigDecimal.tryToFloat64(bd)
                  |> Option.flatMap(Float64.tryToInt32)
                  |> Option.getWithDefault(0i32)
            case _ => 0i32
        };
        let spinner: Spinner[Integer] = new Spinner(-999999i32, 999999i32, current);
        spinner.setEditable(true);
        spinner.setPrefWidth(110.0);
        spinner.setMaxWidth(110.0);
        spinner.valueProperty().addListener(new ChangeListener[Integer] {
            def changed(_cThis: ChangeListener[Integer], _obs: ObservableValue[JObject],
                         _old: Integer, newVal: Integer): Unit \ IO = {
                let v: Int32 = newVal.intValue();
                commitFieldJson(state, keyPath,
                                 Json.JsonElement.JsonNumber(intToBd(v)))
            }
        });
        checked_cast(spinner)
    }

    /// Float フィールド: Spinner<Double> (step 0.1)
    def buildFloatWidget(state: IdeState.IdeState, value: Option[Json.JsonElement],
                          keyPath: List[String]): Node \ IO = {
        let current: Float64 = match value {
            case Some(Json.JsonElement.JsonNumber(bd)) =>
                BigDecimal.tryToFloat64(bd) |> Option.getWithDefault(0.0)
            case _ => 0.0
        };
        let spinner: Spinner[Double] = new Spinner(-999999.0, 999999.0, current, 0.1);
        spinner.setEditable(true);
        spinner.setPrefWidth(110.0);
        spinner.setMaxWidth(110.0);
        spinner.valueProperty().addListener(new ChangeListener[Double] {
            def changed(_cThis: ChangeListener[Double], _obs: ObservableValue[JObject],
                         _old: Double, newVal: Double): Unit \ IO = {
                let v: Float64 = newVal.doubleValue();
                commitFieldJson(state, keyPath,
                                 Json.JsonElement.JsonNumber(floatToBd(v)))
            }
        });
        checked_cast(spinner)
    }

    def buildBoolWidget(state: IdeState.IdeState, value: Option[Json.JsonElement],
                         keyPath: List[String]): Node \ IO = {
        let current = match value {
            case Some(Json.JsonElement.JsonBool(b)) => b
            case _                                  => false
        };
        let check = new CheckBox();
        check.setSelected(current);
        check.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO =
                commitFieldJson(state, keyPath,
                                 Json.JsonElement.JsonBool(check.isSelected()))
        });
        checked_cast(check)
    }

    /// 編集を editingJson に反映 + dirty フラグ + 即ファイル書き戻し。
    /// Swing 版は Save ボタンで一括書込だが、Phase 10f では即書きで HotReload に任せる
    def commitFieldJson(state: IdeState.IdeState, keyPath: List[String],
                         newValue: Json.JsonElement): Unit \ IO =
        match ResourceState.getEditingJson(state#resource) {
            case None => ()
            case Some(json) => {
                let updated = JsonOps.setAtKeyPath(json, keyPath, newValue);
                ResourceState.setEditingJson(state#resource, Some(updated));
                ResourceState.setDirty(state#resource, true);
                match ResourceState.getSelectedDataPath(state#resource) {
                    case None => ()
                    case Some(path) => {
                        let pretty = Json.Write.toPrettyString(2i32, updated);
                        discard Files.writeString(Paths.get(path), pretty);
                        println("[Resources] saved field at ${keyPath}")
                    }
                }
            }
        }

    def intToBd(value: Int32): BigDecimal =
        unsafe IO {
            let stripped = JBigDecimal.valueOf(Int32.toFloat64(value)).stripTrailingZeros();
            if (stripped.scale() < 0) stripped.setScale(0) else stripped
        }

    def floatToBd(value: Float64): BigDecimal =
        JBigDecimal.valueOf(value)

    /// FieldEntry の sort key: (order の値, key 名)。order が None なら最大値で末尾に
    def fieldOrderKey(p: (String, Resource.FieldEntry)): (Int32, String) =
        let (key, entry) = p;
        let ord = match entry {
            case Resource.FieldEntry.Field(fs) => Option.getWithDefault(Int32.maxValue(), fs#order)
            case _                             => Int32.maxValue()
        };
        (ord, key)

    /// 数値 TextField に Enter / ↑↓ で commit するハンドラを仕掛ける。
    /// ↑ で +step / ↓ で -step、commit lambda は最新の field.getText() を読んで処理
    def wireNumericField(field: TextField, isInt: Bool, commit: Unit -> Unit \ IO): Unit \ IO = {
        field.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO = commit()
        });
        field.setOnKeyPressed(new EventHandler[KeyEvent] {
            def handle(_this: EventHandler[KeyEvent], e: KeyEvent): Unit \ IO = {
                let name = e.getCode().toString();
                if (name == "UP" or name == "DOWN") {
                    let delta = if (name == "UP") 1.0 else -1.0;
                    let current = Float64.fromString(field.getText())
                                   |> Option.getWithDefault(0.0);
                    let newVal = current + delta;
                    if (isInt) {
                        let iv = Float64.tryToInt32(newVal)
                                  |> Option.getWithDefault(0i32);
                        field.setText("${iv}")
                    } else {
                        field.setText("${newVal}")
                    };
                    commit();
                    e.consume()
                } else ()
            }
        })
    }

    def jsonFieldOf(record: Json.JsonElement, key: String): Option[Json.JsonElement] =
        match record {
            case Json.JsonElement.JsonObject(m) => Map.get(key, m)
            case _                              => None
        }

    def addPropertyPlaceholder(children: ObservableList[Node], text: String): Unit \ IO = {
        let l = new Label(text);
        l.getStyleClass().add("inspector-empty");
        let n: Node = checked_cast(l);
        discard children.add(n)
    }

    /// Option Ref 共通: Some なら action を実行。None は no-op。
    /// effect polymorphic で各種ハンドラから使える
    def withRef(ref: Array[Option[t], Static], action: t -> Unit \ ef): Unit \ ef + IO =
        match Array.get(0, ref) {
            case None    => ()
            case Some(v) => action(v)
        }

    /// 共通テンプレ property-row.fxml をロードして「key Label + 値 slot」の HBox を返す。
    /// レイアウト・スタイルは FXML / CSS 側で完結させ、Flix はデータ注入のみ
    pub def addPropertyRow(children: ObservableList[Node], keyText: String, valueNode: Node):
            Unit \ IO = {
        let url = new File("src/property-row.fxml").toURI().toURL();
        let loader = new FXMLLoader(url);
        let probe = new Label("");
        loader.setClassLoader(probe.getClass().getClassLoader());
        let rootObj: JObject = loader.load();
        let row: HBox = unchecked_cast(rootObj as HBox);
        let ns = loader.getNamespace();
        let keyLabel: Label = unchecked_cast(ns.get("keyLabel") as Label);
        let valueSlot: StackPane = unchecked_cast(ns.get("valueSlot") as StackPane);
        keyLabel.setText(keyText);
        discard valueSlot.getChildren().add(valueNode);
        let rowNode: Node = checked_cast(row);
        discard children.add(rowNode)
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
                        withRef(state#fxStatusFpsLabelRef, lbl ->
                            lbl.setText("${frames} fps"));
                        Array.put(0i32, 0, frameCountRef);
                        Array.put(now, 0, lastTimeRef)
                    } else {
                        Array.put(frames, 0, frameCountRef)
                    }
                };

                // Scene path
                withRef(state#fxStatusSceneLabelRef, lbl -> {
                    let txt = match Array.get(0, state#currentScenePathRef) {
                        case Some(p) => "Scene: ${shortenPath(p)}"
                        case None    => "(no scene)"
                    };
                    lbl.setText(txt)
                });

                // Mouse: ImageView local 座標 (FBO は ImageView と同サイズなのでこれが design 座標)
                withRef(state#fxStatusMouseLabelRef, lbl -> {
                    let mx = Float64.tryToInt32(Array.get(0, mouseXRef))
                              |> Option.getWithDefault(0i32);
                    let my = Float64.tryToInt32(Array.get(0, mouseYRef))
                              |> Option.getWithDefault(0i32);
                    lbl.setText("mouse: ${mx}, ${my}")
                });

                // Selection: renderLoop が editor 状態を直接書き込んだ表示文字列を使う
                // (selectedNodePathRef 経由は currentSceneJsonRef のセットが必要)
                let curSel = Array.get(0, state#fxEditorSelDisplayRef);
                withRef(state#fxStatusSelectionLabelRef, lbl ->
                    lbl.setText("sel: ${curSel}"));

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
                if (selDisplay == "-") {
                    let placeholder = new Label("(nothing selected)");
                    placeholder.getStyleClass().add("inspector-empty");
                    let placeholderNode: Node = checked_cast(placeholder);
                    discard children.add(placeholderNode)
                } else {
                    let pathLabel = new Label(selDisplay);
                    pathLabel.setWrapText(true);
                    let pathNode: Node = checked_cast(pathLabel);
                    addPropertyRow(children, "Selected:", pathNode);

                    let worldPosValue = new Label("-");
                    let worldPosNode: Node = checked_cast(worldPosValue);
                    addPropertyRow(children, "World position:", worldPosNode);
                    Array.put(Some(worldPosValue), 0, state#fxInspectorPosLabelRef);

                    // Local position / Scale / Rotation はいずれも編集可能 TextField で表示。
                    // pos / rotation は整数刻み、scale は実数刻み (↑↓ で 1.0 ずつ)
                    addEditableVec2Row(state, children, "Local position:", true,
                                        state#fxInspectorLocalXFieldRef,
                                        state#fxInspectorLocalYFieldRef,
                                        state#fxPendingLocalPosEditRef);
                    addEditableVec2Row(state, children, "Scale:", false,
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
        withRef(valRef, pair -> {
            let (x, y) = pair;
            let ix = Float64.tryToInt32(x) |> Option.getWithDefault(0i32);
            let iy = Float64.tryToInt32(y) |> Option.getWithDefault(0i32);
            withRef(xRef, f -> if (not f.isFocused()) f.setText("${ix}") else ());
            withRef(yRef, f -> if (not f.isFocused()) f.setText("${iy}") else ())
        })

    /// Vec2 (Float64×2) 値 Ref → Label.setText の共通処理
    def updateVec2Label(lblRef: Array[Option[Label], Static],
                         valRef: Array[Option[(Float64, Float64)], Static]): Unit \ IO =
        withRef(lblRef, lbl -> {
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
        wireNumericField(xField, isInt, commitBoth);
        wireNumericField(yField, isInt, commitBoth);
        Array.put(Some(xField), 0, xFieldRef);
        Array.put(Some(yField), 0, yFieldRef);
        let group = new HBox(4.0);
        let xNode: Node = checked_cast(xField);
        let yNode: Node = checked_cast(yField);
        discard group.getChildren().add(xNode);
        discard group.getChildren().add(yNode);
        let groupNode: Node = checked_cast(group);
        addPropertyRow(children, keyText, groupNode)
    }

    /// Rotation 行 (度入力 → ラジアン保存)。単一 TextField、↑↓ で 1度刻み
    def addEditableRotationRow(state: IdeState.IdeState, children: ObservableList[Node]):
            Unit \ IO = {
        let field = new TextField("0");
        field.setPrefWidth(80.0);
        wireNumericField(field, true, () -> {
            let deg = Float64.fromString(field.getText()) |> Option.getWithDefault(0.0);
            let rad = deg * 3.14159265358979 / 180.0;
            Array.put(Some(rad), 0, state#fxPendingRotationEditRef)
        });
        Array.put(Some(field), 0, state#fxInspectorRotationFieldRef);
        let fieldNode: Node = checked_cast(field);
        addPropertyRow(children, "Rotation (°):", fieldNode)
    }
}
