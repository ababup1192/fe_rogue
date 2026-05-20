// ResourcePanel — Resources タブ専用の wiring と Property Panel 構築。
//
// JavaFXIdeUI.customize から wireResourceSelection / wireSubEntrySelection が呼ばれ、
// ListView 選択時に schema + data をロードして Property Panel を build する。
// JavaFXIdeUI.schedulePopulateTree から populateResourcesList が呼ばれ、
// プロジェクト切替時にリストを差し替える。
//
// 編集 widget の生成は PropertyWidgets に委譲。commit 時のファイル書き戻しは本 module の
// `commitToResource` で行う (PropertyWidgets は ResourceState を直接知らない)

mod ResourcePanel {
    import java.lang.{Object => JObject}
    import java.nio.file.Files
    import java.nio.file.Paths
    import javafx.collections.ObservableList
    import javafx.scene.Node
    import javafx.scene.control.Button
    import javafx.scene.control.Label
    import javafx.scene.control.ListView
    import javafx.beans.value.ChangeListener
    import javafx.beans.value.ObservableValue
    import javafx.event.ActionEvent
    import javafx.event.EventHandler

    /// Resources ListView 選択 → displayName から ResourceEntry を引き、
    /// data + schema を Fs.FileRead 経由で読み、Sub-entries を埋める
    pub def wireResourceSelection(state: IdeState.IdeState,
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

    /// Sub-entries ListView 選択 → selectedSubEntry を更新し Property Panel 再構築
    pub def wireSubEntrySelection(state: IdeState.IdeState,
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

    /// data + schema をロードして ResourceState に書き、Sub-entries list を埋める
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

    /// 全 discovered resources をその場で読み直し、`{catalog containerKey → sub-entry id 一覧}`
    /// の Map を作る。`Resource.FieldType.RefT(target)` の widget が ComboBox 候補を
    /// 引くために使う。読み込み失敗 / 非 CatalogIn のリソースは単にスキップする。
    /// `IO` は Static Array 読み取り (state#resource#discoveredRef) に必要。
    def collectRefOptions(state: IdeState.IdeState):
            Map[String, List[String]] \ {Fs.FileRead, IO} =
        let entries = Array.get(0, state#resource#discoveredRef);
        List.foldLeft((acc, e) ->
            match loadJsonElement(e#dataPath) {
                case Some(json) =>
                    match ResourceCatalog.classify(json) {
                        case ResourceCatalog.Classification.CatalogIn(info) =>
                            Map.insert(info#containerKey, info#subEntries, acc)
                        case _ => acc
                    }
                case None => acc
            },
            Map.empty(), entries)

    /// CatalogIn 形式なら sub-entries の key 一覧を ListView に並べる。
    /// Single 形式なら Property Panel をすぐ build する
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

    /// Property Panel を schema 駆動で再構築する。各フィールドは PropertyWidgets が
    /// 型に応じた編集 widget を生成し、commit (callback) でこちらが editingJson 更新 +
    /// ファイル書き戻しまで一気に行う
    def rebuildPropertyPanel(state: IdeState.IdeState): Unit \ IO = {
        match Array.get(0, state#widgets#propertyPanel) {
            case None => ()
            case Some(panel) => {
                let children = panel.getChildren();
                children.clear();
                match (ResourceState.getEditingSchema(state#resource),
                       ResourceState.getEditingJson(state#resource)) {
                    case (Some(schema), Some(json)) =>
                        match currentRecordJson(state, json) {
                            case None => {
                                PropertyWidgets.addPropertyPlaceholder(children, "(select a sub-entry)");
                                clearPreview(state)
                            }
                            case Some(record) => {
                                let basePath = recordKeyPath(state, json);
                                let fields = Resource.fieldsOf(schema);
                                let sorted = Map.toList(fields)
                                    |> List.sortBy(p -> PropertyWidgets.fieldOrderKey(p));
                                let textureNames = Array.get(0, state#textureNamesRef);
                                let refOptions = run {
                                    collectRefOptions(state)
                                } with Fs.FileRead.runWithIO;
                                let mkCommit = kp -> { (json2: Json.JsonElement) ->
                                    commitToResource(state, kp, json2)
                                };
                                List.forEach(p -> {
                                    let (k, e) = p;
                                    PropertyWidgets.addFieldRow(children, k, e, record, basePath,
                                                                  textureNames, refOptions, mkCommit)
                                }, sorted);
                                refreshPreview(state, record)
                            }
                        }
                    case (None, Some(_)) =>
                        PropertyWidgets.addPropertyPlaceholder(children, "(no schema)")
                    case _ =>
                        PropertyWidgets.addPropertyPlaceholder(children, "(select a resource)")
                }
            }
        }
    }

    /// 編集を editingJson に反映 + dirty フラグ + 即ファイル書き戻し +
    /// プレビュー再描画 (texture 変更時に効く)。
    /// HotReload watcher が拾って次フレームで scene 再 load される
    def commitToResource(state: IdeState.IdeState, keyPath: List[String],
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
                };
                // プレビュー: 編集後の record で texture を再探索
                match currentRecordJson(state, updated) {
                    case Some(rec) => refreshPreview(state, rec)
                    case None      => clearPreview(state)
                }
            }
        }

    /// 編集対象 record への JSON key path を返す
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

    /// 編集対象 record の JsonElement を返す
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

    /// Resources ListView を ResourceState.discoveredRef から populate する
    pub def populateResourcesList(state: IdeState.IdeState): Unit \ IO = {
        match Array.get(0, state#widgets#resourcesList) {
            case None => ()
            case Some(listView) => {
                let entries = Array.get(0, state#resource#discoveredRef);
                let items = listView.getItems();
                items.clear();
                List.forEach(e -> discard items.add(e#displayName), entries)
            }
        }
    }

    /// record の中から texture 名 + 同居する frame/hframes/vframes を探し、
    /// sprite preview pane に該当セルだけを切り抜いて表示する
    def refreshPreview(state: IdeState.IdeState, record: Json.JsonElement): Unit \ IO = {
        let textureNames = Array.get(0, state#textureNamesRef);
        let pathMap = Array.get(0, state#texturePathMapRef);
        let spriteRef = PropertyWidgets.findFirstSpriteRef(record, textureNames);
        let zoomMode = ResourceState.getPreviewZoom(state#resource);
        match Array.get(0, state#widgets#resourcePreviewPane) {
            case Some(pane) => PropertyWidgets.updateSpritePreview(pane, pathMap, spriteRef, zoomMode)
            case None       => ()
        }
    }

    def clearPreview(state: IdeState.IdeState): Unit \ IO = {
        let zoomMode = ResourceState.getPreviewZoom(state#resource);
        match Array.get(0, state#widgets#resourcePreviewPane) {
            case Some(pane) =>
                PropertyWidgets.updateSpritePreview(pane, Map.empty(), None, zoomMode)
            case None       => ()
        }
    }

    /// 現在選択中の sub-entry / single record で preview を再描画する。
    /// ズームボタンが押されたときに呼び、Resource 未選択なら no-op。
    pub def repaintPreview(state: IdeState.IdeState): Unit \ IO = {
        match ResourceState.getEditingJson(state#resource) {
            case None      => clearPreview(state)
            case Some(json) =>
                match currentRecordJson(state, json) {
                    case Some(rec) => refreshPreview(state, rec)
                    case None      => clearPreview(state)
                }
        }
    }

    /// previewZoomLabel に "Fit" / "1x" / "2x" 等を反映
    pub def updateZoomLabel(state: IdeState.IdeState): Unit \ IO = {
        let mode = ResourceState.getPreviewZoom(state#resource);
        let text = PropertyWidgets.zoomModeLabel(mode);
        match Array.get(0, state#widgets#resourcePreviewZoomLbl) {
            case Some(label) => label.setText(text)
            case None        => ()
        }
    }

    /// Preview の - / + ボタンを ZoomMode 操作に配線する。
    /// 押下のたびに ResourceState の zoomMode を更新し、ラベルと preview を再描画する。
    pub def wireZoomButtons(state: IdeState.IdeState,
                             zoomOutBtn: Button,
                             zoomInBtn:  Button): Unit \ IO = {
        zoomOutBtn.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO = {
                let current = ResourceState.getPreviewZoom(state#resource);
                ResourceState.setPreviewZoom(state#resource, PropertyWidgets.zoomOut(current));
                updateZoomLabel(state);
                repaintPreview(state)
            }
        });
        zoomInBtn.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO = {
                let current = ResourceState.getPreviewZoom(state#resource);
                ResourceState.setPreviewZoom(state#resource, PropertyWidgets.zoomIn(current));
                updateZoomLabel(state);
                repaintPreview(state)
            }
        })
    }
}
