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
    import java.lang.Number
    import java.nio.file.Files
    import java.nio.file.Paths
    import java.util.Optional
    import javafx.collections.ObservableList
    import javafx.scene.Node
    import javafx.scene.control.Button
    import javafx.scene.control.CheckBox
    import javafx.scene.control.Label
    import javafx.scene.control.ListView
    import javafx.scene.control.TextInputDialog
    import javafx.scene.canvas.Canvas
    import javafx.scene.layout.StackPane
    import javafx.beans.value.ChangeListener
    import javafx.beans.value.ObservableValue
    import javafx.event.ActionEvent
    import javafx.event.EventHandler
    import javafx.scene.input.ZoomEvent

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
                    // sub-entry が変わったら frame-adjust pan を初期位置に戻す
                    // (前 entry のドラッグ位置を引きずらない)
                    ResourceState.resetPreviewPan(state#resource);
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
        // 新しいリソースに切り替えるとき、フレーム調整 pan はリセット
        ResourceState.resetPreviewPan(state#resource);

        let dataJson = loadJson(entry#dataPath);
        ResourceState.setEditingJson(state#resource, dataJson);

        match Resource.loadSchemaDiagnostic(entry#schemaPath) {
            case Ok(s)    => ResourceState.setEditingSchema(state#resource, Some(s))
            case Err(msg) => {
                println("[Resources] Schema load failed for ${entry#displayName}: ${msg}");
                ResourceState.setEditingSchema(state#resource, None)
            }
        };

        let schemaJson = loadJson(entry#schemaPath);
        ResourceState.setEditingSchemaJson(state#resource, schemaJson);

        rebuildSubEntries(state, subEntriesList)
    }

    /// JSON ファイルを読んで Json にパース。失敗は None
    def loadJson(path: String): Option[Util.Json.Json] \ Fs.FileRead =
        let readResult = run {
            Fs.ReadFile.read(path)
        } with Fs.ReadFile.runWithFileRead;
        readResult
            |> Result.toOption
            |> Option.flatMap(s -> JsonCompat.parse(String.trim(s)))

    /// 全 discovered resources をその場で読み直し、`{catalog containerKey → sub-entry id 一覧}`
    /// の Map を作る。`Resource.FieldType.RefT(target)` の widget が ComboBox 候補を
    /// 引くために使う。読み込み失敗 / 非 CatalogIn のリソースは単にスキップする。
    /// `IO` は Static Array 読み取り (state#resource#discoveredRef) に必要。
    def collectRefOptions(state: IdeState.IdeState):
            Map[String, List[String]] \ {Fs.FileRead, IO} =
        let entries = Array.get(0, state#resource#discoveredRef);
        let base = List.foldLeft((acc, e) ->
            match loadJson(e#dataPath) {
                case Some(json) =>
                    match ResourceCatalog.classify(json) {
                        case ResourceCatalog.Classification.CatalogIn(info) =>
                            Map.insert(info#containerKey, info#subEntries, acc)
                        case _ => acc
                    }
                case None => acc
            },
            Map.empty(), entries);
        // 擬似カタログ "maps": assets/maps/*.map.json の stem を候補にする。
        // schema の `refPercentList(to:"maps")` 用（floors.json のマッププール編集）。
        // projectRoot は discovered resource (絶対パス) の `<root>/resources/<name>.json` から導出。
        match projectRootOf(entries) {
            case Some(root) =>
                let stems = run {
                    MapEditorPanel.findMapStems(root)
                } with Fs.Glob.runWithIO;
                Map.insert("maps", stems, base)
            case None => base
        }

    /// discovered resource の絶対 dataPath（`<root>/resources/<name>.json`）から
    /// projectRoot を導出する。親ディレクトリを 2 段上る（… → resources → root）。
    /// 1 件も無ければ None。
    def projectRootOf(entries: List[ResourceDiscovery.ResourceEntry]): Option[String] =
        List.head(entries)
            |> Option.map(e -> parentDir(parentDir(e#dataPath)))

    /// パス末尾の `/<segment>` を 1 段落とす。区切りが無ければ入力をそのまま返す。
    def parentDir(path: String): String =
        parentDirRec(path, String.length(path) - 1)

    def parentDirRec(path: String, idx: Int32): String =
        if (idx < 0) path
        else if (String.charAt(idx, path) == '/') path.substring(0, idx)
        else parentDirRec(path, idx - 1)

    /// `collectRefOptions` を 1 回計算して ResourceState の cache に格納する。
    /// resource 一覧ロード完了時 (`populateResourcesList`) と、sub-entries が変化しうる
    /// commit 後に呼ぶ。Property Panel 再構築のたびのフル走査を避けるための入口。
    pub def refreshRefOptions(state: IdeState.IdeState): Unit \ IO =
        let options = run {
            collectRefOptions(state)
        } with Fs.FileRead.runWithIO;
        ResourceState.setRefOptions(state#resource, options)

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
                                // ─── implicit description (sub-entry のメモ。schema 宣言不要、
                                //     全 catalog で常に sub-entry 先頭に表示) ───
                                let descValue = match record {
                                    case Util.Json.Json.JObject(m) => Map.get("description", m)
                                    case _                              => None
                                };
                                let descKeyPath = List.append(basePath, "description" :: Nil);
                                let descCommit =
                                    (json2: Util.Json.Json) -> commitToResource(state, descKeyPath, json2);
                                let descWidget =
                                    PropertyWidgets.buildMultilineTextWidget(descValue, descCommit);
                                PropertyWidgets.addPropertyRow(children, "メモ:", descWidget);
                                // ─── schema-driven フィールド ───
                                let fields = Resource.fieldsOf(schema);
                                let sorted = Map.toList(fields)
                                    |> List.sortBy(p -> PropertyWidgets.fieldOrderKey(p));
                                let textureNames = Array.get(0, state#textureNamesRef);
                                let texturePathMap = Array.get(0, state#texturePathMapRef);
                                // collectRefOptions のフル走査を避け、cache を参照する。
                                // cache は populateResourcesList と sub-entries 変化 commit で更新される。
                                // 未計算 (None) のときは呼出順序に依存せず lazy に 1 回計算してから取る。
                                let refOptions = match ResourceState.getRefOptions(state#resource) {
                                    case Some(cached) => cached
                                    case None         =>
                                        refreshRefOptions(state);
                                        ResourceState.getRefOptions(state#resource)
                                            |> Option.getWithDefault(Map.empty())
                                };
                                let mkCommit = kp -> { (json2: Util.Json.Json) ->
                                    commitToResource(state, kp, json2)
                                };
                                // ─── 効果 DSL 合成エディタ（日本語ドロップダウンで効果を組み立てる）───
                                // effect を持つカタログのとき、いつ/誰に/何を/量/継続 を選んで
                                // effectRule オブジェクトを組み立て、日本語1文プレビューを表示する。
                                EffectComposerPanel.appendComposer(children, basePath, record, mkCommit);
                                // sprite.frame 行の「Previewから選択」ボタン: フレーム調整モードを
                                // ON にする (= アトラス全体表示にして preview クリックで拾える状態にする)。
                                let onFramePick = () -> {
                                    ResourceState.setPreviewFrameAdjust(state#resource, true);
                                    PropertyWidgets.withRef(state#widgets#resourcePreviewFrameAdjustChk,
                                        chk -> chk.setSelected(true));
                                    repaintPreview(state)
                                };
                                List.forEach(p -> {
                                    let (k, e) = p;
                                    // effectRule は専用の合成エディタ（EffectComposerPanel）が扱うので
                                    // schema 駆動フィールドとしては描画しない。
                                    if (k == "effectRule") () else
                                    PropertyWidgets.addFieldRow(children, k, e, record, basePath,
                                                                  textureNames, texturePathMap,
                                                                  refOptions, mkCommit, onFramePick)
                                }, sorted);
                                // floors の sub-entry なら「ドロップ試算」セクションを末尾に足す
                                // (floors 以外では no-op)。schema 駆動フィールドの後・preview の前。
                                DropSimPanel.appendSection(children, state, record, basePath, refOptions);
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
                          newValue: Util.Json.Json): Unit \ IO =
        match ResourceState.getEditingJson(state#resource) {
            case None => ()
            case Some(json) => {
                let updated = JsonOps.setAtKeyPath(json, keyPath, newValue);
                ResourceState.setEditingJson(state#resource, Some(updated));
                ResourceState.setDirty(state#resource, true);
                match ResourceState.getSelectedDataPath(state#resource) {
                    case None => ()
                    case Some(path) => {
                        let pretty = Util.Json.toPrettyString(2i32, updated);
                        discard Files.writeString(Paths.get(path), pretty);
                        // sub-entries が変化しうるので Ref widget 候補 cache を再計算する。
                        // （差分計算は難しいため全再計算。古い候補を残さないための無効化）
                        refreshRefOptions(state);
                        println("[Resources] saved field at ${keyPath}")
                    }
                };
                // プレビュー: 編集後の record で texture を再探索
                match currentRecordJson(state, updated) {
                    case Some(rec) => refreshPreview(state, rec)
                    case None      => clearPreview(state)
                };
                // sprite.hframes / vframes / texture を変更したときは、それを sibling
                // 参照する spriteFrames widget が古い snapshot を持っているので、
                // Property Panel ごと作り直して最新の sibling を反映させる。
                // 頻繁には変更しないフィールドなので focus 喪失は許容範囲。
                if (isGridSiblingPath(keyPath)) rebuildPropertyPanel(state)
                else ()
            }
        }

    /// sprite.hframes / sprite.vframes / sprite.texture（および将来の同階層 sibling）
    /// を編集する keyPath か判定する。spriteFrames widget の表示パラメータに影響する
    /// フィールドのみ true にする。
    def isGridSiblingPath(keyPath: List[String]): Bool =
        match List.reverse(keyPath) {
            case "hframes" :: _ => true
            case "vframes" :: _ => true
            case "texture" :: _ => true
            case _              => false
        }

    /// 編集対象 record への JSON key path を返す
    def recordKeyPath(state: IdeState.IdeState, json: Util.Json.Json): List[String] \ IO =
        match ResourceCatalog.classify(json) {
            case ResourceCatalog.Classification.Single => Nil
            case ResourceCatalog.Classification.CatalogIn(info) =>
                match ResourceState.getSelectedSubEntry(state#resource) {
                    case None         => Nil
                    case Some(subKey) => info#containerKey :: subKey :: Nil
                }
            case _ => Nil
        }

    /// 編集対象 record の Json を返す
    def currentRecordJson(state: IdeState.IdeState, json: Util.Json.Json):
            Option[Util.Json.Json] \ IO =
        match ResourceCatalog.classify(json) {
            case ResourceCatalog.Classification.Single => Some(json)
            case ResourceCatalog.Classification.CatalogIn(info) =>
                match ResourceState.getSelectedSubEntry(state#resource) {
                    case None => None
                    case Some(subKey) =>
                        match json {
                            case Util.Json.Json.JObject(topMap) =>
                                match Map.get(info#containerKey, topMap) {
                                    case Some(Util.Json.Json.JObject(subMap)) =>
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
                List.forEach(e -> discard items.add(e#displayName), entries);
                // discovered resources が確定したこの時点で Ref widget 候補 cache を
                // 1 回だけ計算する。以降の Property Panel 再構築は cache を読むだけ
                refreshRefOptions(state)
            }
        }
    }

    /// record の中から texture 名 + 同居する frame/hframes/vframes を探し、
    /// sprite preview pane に該当セルだけを切り抜いて表示する
    def refreshPreview(state: IdeState.IdeState, record: Util.Json.Json): Unit \ IO = {
        let textureNames = Array.get(0, state#textureNamesRef);
        let pathMap = Array.get(0, state#texturePathMapRef);
        // SpriteRef とその sprite ブロックへの相対パスを同時に取得する。
        // path は frame の keyPath (basePath ++ spritePath ++ ["frame"]) を組むのに使う。
        let spriteWithPath = SpritePreview.findFirstSpriteRefWithPath(record, textureNames);
        let spriteRef = Option.map(fst, spriteWithPath);
        let spritePath = Option.map(snd, spriteWithPath) |> Option.getWithDefault(Nil);
        let basePath = match ResourceState.getEditingJson(state#resource) {
            case Some(json) => recordKeyPath(state, json)
            case None       => Nil
        };
        let frameKeyPath = List.append(basePath, List.append(spritePath, "frame" :: Nil));
        // Preview のセルをクリックしたとき: frame を確定し、spinner 表示も更新するため
        // Property Panel を作り直す (pan はリセットしないので視点は保たれる)。
        let onFrameSelect = newFrame -> {
            commitToResource(state, frameKeyPath, NodeInspector.intToJson(newFrame));
            rebuildPropertyPanel(state)
        };
        let zoomMode = ResourceState.getPreviewZoom(state#resource);
        let showGrid = ResourceState.getPreviewGrid(state#resource);
        let frameAdjust = ResourceState.getPreviewFrameAdjust(state#resource);
        let pan = ResourceState.getPreviewPan(state#resource);
        let getPan = () -> ResourceState.getPreviewPan(state#resource);
        let onPan = newPan -> ResourceState.setPreviewPan(state#resource, newPan);
        let onStatus = txt -> setStatusLabel(state, txt);
        match (Array.get(0, state#widgets#resourcePreviewPane),
                Array.get(0, state#widgets#resourcePreviewCanvas)) {
            case (Some(pane), Some(canvas)) =>
                SpritePreview.updateSpritePreview(pane, canvas, pathMap, spriteRef, zoomMode,
                                                     showGrid, frameAdjust, pan, getPan, onPan,
                                                     onFrameSelect, onStatus)
            case _       => ()
        }
    }

    def clearPreview(state: IdeState.IdeState): Unit \ IO = {
        let zoomMode = ResourceState.getPreviewZoom(state#resource);
        let showGrid = ResourceState.getPreviewGrid(state#resource);
        let frameAdjust = ResourceState.getPreviewFrameAdjust(state#resource);
        let pan = ResourceState.getPreviewPan(state#resource);
        let getPan = () -> ResourceState.getPreviewPan(state#resource);
        let onPan = newPan -> ResourceState.setPreviewPan(state#resource, newPan);
        // 空 preview ではクリック選択は無効。spriteRef=None でハンドラ自体が配線されないため
        // 呼ばれないが、引数の効果を IO に揃えるため harmless な IO 読み取りを 1 つ挟む。
        let onFrameSelect = _newFrame -> { discard getPan(); () };
        let onStatus = txt -> setStatusLabel(state, txt);
        match (Array.get(0, state#widgets#resourcePreviewPane),
                Array.get(0, state#widgets#resourcePreviewCanvas)) {
            case (Some(pane), Some(canvas)) =>
                SpritePreview.updateSpritePreview(pane, canvas, Map.empty(), None, zoomMode,
                                                     showGrid, frameAdjust, pan, getPan, onPan,
                                                     onFrameSelect, onStatus)
            case _       => ()
        }
    }

    /// 永続 Preview canvas を生成して pane に常駐させ、ピンチハンドラを直接登録する。
    /// updateSpritePreview は以降この canvas の中身を clear + 再描画するだけで、
    /// pane.getChildren() には手を入れない。canvas が scene graph に常駐するため
    /// JavaFX の gesture continuity が切れず、ピンチが滑らかになる。
    /// （MapEditor の mapPaletteCanvas + wireTilesetZoom と同じ流儀）
    pub def wirePreviewPinchZoom(state: IdeState.IdeState, pane: StackPane): Unit \ IO = {
        let paneW = pane.getWidth();
        let paneH = pane.getHeight();
        let canvasW = if (paneW > 16.0) paneW else 220.0;
        let canvasH = if (paneH > 16.0) paneH else 220.0;
        let canvas = new Canvas(canvasW, canvasH);
        Array.put(Some(canvas), 0, state#widgets#resourcePreviewCanvas);
        // 初回は pane に追加。以降 updateSpritePreview は pane を触らない
        let canvasNode: Node = checked_cast(canvas);
        let children = pane.getChildren();
        children.clear();
        discard children.add(canvasNode);
        // ピンチハンドラを canvas に 1 回だけ登録（canvas は永続）
        canvas.setOnZoom(new EventHandler[ZoomEvent] {
            def handle(_this: EventHandler[ZoomEvent], event: ZoomEvent): Unit \ IO = {
                let factor = event.getZoomFactor();
                let cur = ResourceState.getPreviewZoom(state#resource);
                let next = PropertyWidgets.pinchZoom(cur, factor);
                ResourceState.setPreviewZoom(state#resource, next);
                repaintPreview(state);
                event.consume()
            }
        })
    }

    /// Preview 下の resourceStatusLabel に文字列を書き込む。
    /// label が未配線なら no-op
    def setStatusLabel(state: IdeState.IdeState, text: String): Unit \ IO =
        match Array.get(0, state#widgets#resourceStatusLabel) {
            case Some(lbl) => lbl.setText(text)
            case None      => ()
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


    /// グリッド表示チェックボックスを配線する。トグルで preview を再描画する。
    pub def wireGridCheckbox(state: IdeState.IdeState,
                              gridChk: CheckBox): Unit \ IO = {
        // 起動時に既定値（false）を反映
        gridChk.setSelected(ResourceState.getPreviewGrid(state#resource));
        gridChk.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO = {
                ResourceState.setPreviewGrid(state#resource, gridChk.isSelected());
                repaintPreview(state)
            }
        })
    }

    /// フレーム調整モードのチェックボックスを配線する。ON で texture 全体表示 +
    /// 選択フレーム以外ディマー、OFF で 1 セル切り抜き表示 (現状動作)。
    /// グリッドとは独立に併用可能
    /// Preview ペインのサイズ変化に追従して canvas を作り直す。
    /// SplitPane divider の移動や window resize で pane の幅高が変わるたびに
    /// repaintPreview を呼び、`updateSpritePreview` の中で pane.getWidth/Height を
    /// 読み直して新しい canvas を生成する仕組み
    pub def wirePreviewResize(state: IdeState.IdeState, pane: StackPane): Unit \ IO = {
        let listener = new ChangeListener[Number] {
            def changed(_this: ChangeListener[Number],
                         _obs: ObservableValue[JObject],
                         _old: Number, _new: Number): Unit \ IO =
                repaintPreview(state)
        };
        pane.widthProperty().addListener(listener);
        pane.heightProperty().addListener(listener)
    }

    pub def wireFrameAdjustCheckbox(state: IdeState.IdeState,
                                     frameAdjustChk: CheckBox): Unit \ IO = {
        frameAdjustChk.setSelected(ResourceState.getPreviewFrameAdjust(state#resource));
        frameAdjustChk.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO = {
                ResourceState.setPreviewFrameAdjust(state#resource, frameAdjustChk.isSelected());
                // モード切替で view 状態をリセット (前モードでの drag pan を持ち越さない)
                ResourceState.resetPreviewPan(state#resource);
                repaintPreview(state)
            }
        })
    }

    /// Sub-entries 横の + / - ボタンを配線する。
    /// + : TextInputDialog で新しい id を聞き、空オブジェクトの sub-entry を catalog に追加
    /// - : 現在選択中の sub-entry を catalog から削除
    /// CatalogIn 形式でない resource では何もしない (silent no-op)
    pub def wireSubEntryButtons(state: IdeState.IdeState,
                                 subEntriesList: ListView[String],
                                 addBtn: Button,
                                 removeBtn: Button): Unit \ IO = {
        addBtn.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO =
                addSubEntryAction(state, subEntriesList)
        });
        removeBtn.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO =
                removeSubEntryAction(state, subEntriesList)
        })
    }

    /// + ボタン押下: 新 sub-entry id を TextInputDialog で受け取り、空 object として
    /// catalog コンテナに挿入する。重複 id は無視 (println で警告)。
    def addSubEntryAction(state: IdeState.IdeState,
                           subEntriesList: ListView[String]): Unit \ IO = {
        match ResourceState.getEditingJson(state#resource) {
            case None => ()  // Resource 未選択
            case Some(json) =>
                match ResourceCatalog.classify(json) {
                    case ResourceCatalog.Classification.CatalogIn(info) => {
                        let dialog = new TextInputDialog("new_entry");
                        dialog.setTitle("Add sub-entry");
                        dialog.setHeaderText("New sub-entry id");
                        dialog.setContentText("ID:");
                        let result = dialog.showAndWait();
                        if (not result.isPresent()) ()
                        else {
                            let rawName = result.get();
                            let name = String.trim(rawName);
                            if (name == "")
                                println("[Resources] add sub-entry skipped: empty id")
                            else if (List.exists(s -> s == name, info#subEntries))
                                println("[Resources] add sub-entry skipped: duplicate id '${name}'")
                            else {
                                let emptyObj = Util.Json.Json.JObject(Map.empty());
                                let keyPath = info#containerKey :: name :: Nil;
                                let updated = JsonOps.setAtKeyPath(json, keyPath, emptyObj);
                                ResourceState.setEditingJson(state#resource, Some(updated));
                                saveEditingJsonToDisk(state);
                                rebuildSubEntries(state, subEntriesList);
                                println("[Resources] added sub-entry '${name}'. クリックで編集できます。")
                            }
                        }
                    }
                    case _ => ()  // Single / Unsupported では何もしない
                }
        }
    }

    /// - ボタン押下: 現在選択中の sub-entry を catalog コンテナから削除する。
    /// 未選択時 / 非 CatalogIn 時は何もしない。
    def removeSubEntryAction(state: IdeState.IdeState,
                              subEntriesList: ListView[String]): Unit \ IO = {
        match (ResourceState.getEditingJson(state#resource),
               ResourceState.getSelectedSubEntry(state#resource)) {
            case (Some(json), Some(subKey)) =>
                match ResourceCatalog.classify(json) {
                    case ResourceCatalog.Classification.CatalogIn(info) =>
                        match removeKeyFromContainer(json, info#containerKey, subKey) {
                            case None => ()  // path mismatch — 何もしない
                            case Some(updated) => {
                                ResourceState.setEditingJson(state#resource, Some(updated));
                                ResourceState.setSelectedSubEntry(state#resource, None);
                                saveEditingJsonToDisk(state);
                                rebuildSubEntries(state, subEntriesList);
                                println("[Resources] removed sub-entry '${subKey}'")
                            }
                        }
                    case _ => ()
                }
            case _ => ()  // 未選択 / 未ロード
        }
    }

    /// 既存 json (top-level JObject) の `[containerKey]` 配下から `subKey` を削除し、
    /// 更新後の Json を返す。型が想定外なら None。
    def removeKeyFromContainer(json: Util.Json.Json, containerKey: String, subKey: String):
            Option[Util.Json.Json] =
        match json {
            case Util.Json.Json.JObject(topMap) =>
                match Map.get(containerKey, topMap) {
                    case Some(Util.Json.Json.JObject(subMap)) => {
                        let newSubMap = Map.remove(subKey, subMap);
                        let newContainer = Util.Json.Json.JObject(newSubMap);
                        Some(Util.Json.Json.JObject(Map.insert(containerKey, newContainer, topMap)))
                    }
                    case _ => None
                }
            case _ => None
        }

    /// editingJson を selectedDataPath に書き戻す。`commitToResource` から save 部分のみ
    /// 切り出した形。+ / - ボタンの直後に呼ぶ
    def saveEditingJsonToDisk(state: IdeState.IdeState): Unit \ IO =
        match (ResourceState.getEditingJson(state#resource),
               ResourceState.getSelectedDataPath(state#resource)) {
            case (Some(json), Some(path)) => {
                let pretty = Util.Json.toPrettyString(2i32, json);
                discard Files.writeString(Paths.get(path), pretty);
                ResourceState.setDirty(state#resource, false);
                // + / - で sub-entries が増減したので Ref widget 候補 cache を再計算する
                refreshRefOptions(state);
                println("[Resources] saved ${path}")
            }
            case _ => ()
        }
}
