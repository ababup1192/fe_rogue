// ResourcePanel — Resources タブ専用の wiring と Property Panel 構築。
//
// JavaFXIdeUI.customize から wireResourceSelection / wireSubEntrySelection が呼ばれ、
// ListView 選択時に schema + data をロードして Property Panel を build する。
// JavaFXIdeUI.schedulePopulateTree から populateResourcesList が呼ばれ、
// プロジェクト切替時にリストを差し替える。
//
// 編集 widget の生成と即時保存は PropertyWidgets module 側に集約してある。

mod ResourcePanel {
    import java.lang.{Object => JObject}
    import javafx.collections.ObservableList
    import javafx.scene.Node
    import javafx.scene.control.Label
    import javafx.scene.control.ListView
    import javafx.beans.value.ChangeListener
    import javafx.beans.value.ObservableValue

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

    /// Property Panel を schema 駆動で再構築する。各フィールドは PropertyWidgets が
    /// 型に応じた編集 widget (TextField / CheckBox 等) を生成し、commit で
    /// editingJson 更新 + ファイル書き戻しまで一気に行う
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
                                PropertyWidgets.updateSpritePreview(state, None)
                            }
                            case Some(record) => {
                                let basePath = recordKeyPath(state, json);
                                let fields = Resource.fieldsOf(schema);
                                let sorted = Map.toList(fields)
                                    |> List.sortBy(p -> PropertyWidgets.fieldOrderKey(p));
                                List.forEach(p -> {
                                    let (k, e) = p;
                                    PropertyWidgets.addFieldRow(state, children, k, e, record, basePath)
                                }, sorted);
                                PropertyWidgets.updateSpritePreview(state,
                                    PropertyWidgets.findFirstTexture(state, record))
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
}
