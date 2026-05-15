// ResourceEditorUI — Resources タブのレイアウト構築
//
// レイアウト:
//   左カラム (250px):
//     - Resource 一覧 (resources/*.json のうち schema 付き)
//     - 区切り
//     - Sub-entry 一覧 (catalog 形式時のみ)
//     - [+ Add] / [− Del] ボタン (catalog 時のみ)
//     - 区切り
//     - Meta セクション (catalog 以外のフィールド、v1 では read-only ラベルのみ)
//   中央カラム (280px):
//     - Sprite Preview (placeholder、SpritePreview で実装)
//     - Save ボタン
//     - status ラベル
//   右カラム (残り):
//     - Property Panel (SchemaWidgets で実装、v1 では placeholder)

mod ResourceEditorUI {
    import javax.swing.JPanel
    import javax.swing.JLabel
    import javax.swing.JList
    import javax.swing.JButton
    import javax.swing.JScrollPane
    import javax.swing.DefaultListModel
    import javax.swing.ListSelectionModel
    import javax.swing.BoxLayout
    import javax.swing.BorderFactory
    import javax.swing.SwingConstants
    import javax.swing.event.ListSelectionListener
    import javax.swing.event.ListSelectionEvent
    import java.awt.BorderLayout
    import java.awt.Color
    import java.awt.Dimension
    import java.awt.FlowLayout
    import java.awt.event.ActionListener
    import java.awt.event.ActionEvent
    import javax.swing.JOptionPane
    import java.math.{BigDecimal => JBigDecimal}

    use ResourceDiscovery.ResourceEntry

    pub type alias IdeState = IdeState.IdeState

    /// Resources タブの本体 JPanel を組み立てる。IdeUI.customize から JTabbedPane に addTab される。
    pub def buildTab(state: IdeState): JPanel \ IO =
        let root = new JPanel(new BorderLayout());
        root.setBackground(new Color(28, 28, 28));
        root.setBorder(BorderFactory.createEmptyBorder(8, 8, 8, 8));

        let westCol   = buildLeftColumn(state);
        let centerCol = buildCenterColumn(state);
        let eastCol   = buildRightColumn(state);

        westCol.setPreferredSize(new Dimension(250, 0));
        centerCol.setPreferredSize(new Dimension(280, 0));

        root.add(westCol, BorderLayout.WEST);
        root.add(centerCol, BorderLayout.CENTER);
        root.add(eastCol, BorderLayout.EAST);
        root

    // ──────────────────────────────────────────────────────
    // 左カラム: Resource 一覧 + Sub-entry 一覧
    // ──────────────────────────────────────────────────────

    def buildLeftColumn(state: IdeState): JPanel \ IO =
        let panel = new JPanel(new BorderLayout());
        panel.setBackground(new Color(40, 40, 40));

        // 上半分: Resource 一覧
        let resourcesPanel = buildResourcesList(state);

        // 下半分: Sub-entry 一覧 (catalog 時のみ中身が出る)
        let subEntriesPanel = buildSubEntriesPanel(state);

        // Save ボタンと status ラベルを左カラム最下部に置く。
        // 中央カラム (preview) に置くと heavyweight canvas との mixing で透けて見えるため。
        let saveSection = new JPanel(new FlowLayout(FlowLayout.CENTER, 4, 4));
        saveSection.setBackground(new Color(40, 40, 40));
        let saveBtn = new JButton("Save");
        let status = new JLabel(" ");
        status.setForeground(new Color(140, 200, 140));
        saveBtn.addActionListener(new ActionListener {
            def actionPerformed(_this: ActionListener, _e: ActionEvent): Unit \ IO = {
                run {
                    onSaveClicked(state, status)
                } with Fs.FileWrite.runWithIO
            }
        });
        saveSection.add(saveBtn);
        saveSection.add(status);

        // 縦並び (上から: Resources 一覧 / Sub-entries / Save)
        let stacked = new JPanel(new BorderLayout());
        stacked.setBackground(new Color(40, 40, 40));
        resourcesPanel.setPreferredSize(new Dimension(0, 180));
        stacked.add(resourcesPanel, BorderLayout.NORTH);
        stacked.add(subEntriesPanel, BorderLayout.CENTER);
        stacked.add(saveSection, BorderLayout.SOUTH);

        panel.add(stacked, BorderLayout.CENTER);
        panel

    def buildResourcesList(state: IdeState): JPanel \ IO =
        let panel = new JPanel(new BorderLayout());
        panel.setBackground(new Color(40, 40, 40));

        let header = new JLabel("  Resources");
        header.setForeground(Color.LIGHT_GRAY);
        panel.add(header, BorderLayout.NORTH);

        let model: DefaultListModel[String] = new DefaultListModel();
        let entries = ResourceState.getDiscovered(state#resource);
        List.forEach(e -> {
            model.addElement(e#displayName);
            ()
        }, entries);

        let list: JList[String] = new JList(model);
        list.setSelectionMode(ListSelectionModel.SINGLE_SELECTION);
        list.setBackground(new Color(30, 30, 30));
        list.setForeground(Color.LIGHT_GRAY);

        // 選択リスナ: Resource を選んだら data + schema をロードして ResourceState に書き、
        // sub-entry / property panel を再描画する。
        // Fs.FileRead は ListSelectionListener の境界で IO に閉じ込める。
        let listener = new ListSelectionListener {
            def valueChanged(_this: ListSelectionListener, evt: ListSelectionEvent): Unit \ IO = {
                if (evt.getValueIsAdjusting()) ()
                else {
                    let idx = list.getSelectedIndex();
                    if (idx < 0) ()
                    else {
                        let entries2 = ResourceState.getDiscovered(state#resource);
                        match List.nth(idx, entries2) {
                            case Some(e) =>
                                run {
                                    onResourceSelected(state, e)
                                } with Fs.FileRead.runWithIO
                            case None    => ()
                        }
                    }
                }
            }
        };
        list.addListSelectionListener(listener);

        ResourceState.setListRef(state#resource, Some(list));
        ResourceState.setListModelRef(state#resource, Some(model));

        let scroll = new JScrollPane(list);
        panel.add(scroll, BorderLayout.CENTER);
        panel

    def buildSubEntriesPanel(state: IdeState): JPanel \ IO =
        let panel = new JPanel(new BorderLayout());
        panel.setBackground(new Color(40, 40, 40));

        // 下部: + Add / - Del ボタン (catalog 形式時のみ意味を持つ)
        let buttons = new JPanel(new FlowLayout(FlowLayout.CENTER, 4, 2));
        buttons.setBackground(new Color(40, 40, 40));
        let addBtn = new JButton("+ Add");
        let delBtn = new JButton("- Del");
        addBtn.addActionListener(new ActionListener {
            def actionPerformed(_this: ActionListener, _e: ActionEvent): Unit \ IO =
                onAddEntry(state)
        });
        delBtn.addActionListener(new ActionListener {
            def actionPerformed(_this: ActionListener, _e: ActionEvent): Unit \ IO =
                onDelEntry(state)
        });
        buttons.add(addBtn);
        buttons.add(delBtn);
        panel.add(buttons, BorderLayout.SOUTH);

        let header = new JLabel("  Sub-entries");
        header.setForeground(Color.LIGHT_GRAY);
        panel.add(header, BorderLayout.NORTH);

        let model: DefaultListModel[String] = new DefaultListModel();
        let list: JList[String] = new JList(model);
        list.setSelectionMode(ListSelectionModel.SINGLE_SELECTION);
        list.setBackground(new Color(30, 30, 30));
        list.setForeground(Color.LIGHT_GRAY);

        let listener = new ListSelectionListener {
            def valueChanged(_this: ListSelectionListener, evt: ListSelectionEvent): Unit \ IO = {
                if (evt.getValueIsAdjusting()) ()
                else {
                    let idx = list.getSelectedIndex();
                    if (idx < 0) ()
                    else {
                        let key = model.getElementAt(idx);
                        ResourceState.setSelectedSubEntry(state#resource, Some(key));
                        rebuildPropertyPanel(state);
                        SpritePreview.refresh(state)
                    }
                }
            }
        };
        list.addListSelectionListener(listener);

        ResourceState.setSubListRef(state#resource, Some(list));
        ResourceState.setSubListModelRef(state#resource, Some(model));

        let scroll = new JScrollPane(list);
        panel.add(scroll, BorderLayout.CENTER);
        panel

    // ──────────────────────────────────────────────────────
    // 中央カラム: Sprite Preview + Save
    // ──────────────────────────────────────────────────────

    def buildCenterColumn(state: IdeState): JPanel \ IO =
        let panel = new JPanel(new BorderLayout());
        panel.setBackground(new Color(35, 35, 35));
        panel.setBorder(BorderFactory.createEmptyBorder(8, 8, 8, 8));

        // preview placeholder (Save は左カラム最下部に移動済み)
        let previewLabel = new JLabel("(no preview)", SwingConstants.CENTER);
        previewLabel.setForeground(new Color(120, 120, 120));
        previewLabel.setPreferredSize(new Dimension(0, 200));
        ResourceState.setPreviewLabelRef(state#resource, Some(previewLabel));
        panel.add(previewLabel, BorderLayout.CENTER);
        panel

    // ──────────────────────────────────────────────────────
    // 右カラム: Property Panel
    // ──────────────────────────────────────────────────────

    def buildRightColumn(state: IdeState): JPanel \ IO =
        let outer = new JPanel(new BorderLayout());
        outer.setPreferredSize(new Dimension(380, 0));
        outer.setBackground(new Color(45, 45, 45));
        // Properties セクションヘッダは SchemaWidgets が出すため、ここでは外枠 padding なし。

        let content = new JPanel();
        content.setLayout(new BoxLayout(content, BoxLayout.Y_AXIS));
        content.setBackground(new Color(45, 45, 45));
        ResourceState.setPropertyPanelRef(state#resource, Some(content));

        let placeholder = new JLabel("(select a resource)");
        placeholder.setForeground(new Color(120, 120, 120));
        placeholder.setAlignmentX(0.0f32);
        content.add(placeholder);

        let scroll = new JScrollPane(content);
        outer.add(scroll, BorderLayout.CENTER);
        outer

    // ──────────────────────────────────────────────────────
    // イベント処理
    // ──────────────────────────────────────────────────────

    /// Resource クリック時: data + schema をロードして ResourceState に書き、sub-entry / property panel を更新する。
    /// 呼び出し側で `run { ... } with Fs.ReadFile.runWithFileRead` 済みなので、
    /// この関数は `\ {IO, Fs.FileRead}` を持つ。
    def onResourceSelected(state: IdeState, entry: ResourceEntry): Unit \ {IO, Fs.FileRead} =
        ResourceState.setSelectedDataPath(state#resource, Some(entry#dataPath));
        ResourceState.setSelectedSubEntry(state#resource, None);
        ResourceState.setDirty(state#resource, false);

        // data JSON をロード
        let dataJson = loadJsonElement(entry#dataPath);
        ResourceState.setEditingJson(state#resource, dataJson);

        // schema をロード
        match Resource.loadSchemaDiagnostic(entry#schemaPath) {
            case Ok(s)    => ResourceState.setEditingSchema(state#resource, Some(s))
            case Err(msg) =>
                println("[Resources] Schema load failed for ${entry#displayName}: ${msg}");
                ResourceState.setEditingSchema(state#resource, None)
        };

        rebuildSubEntries(state);
        rebuildPropertyPanel(state)

    /// ファイルから JsonElement を読む。失敗 (file 不在 / parse error) は None。
    /// effect は `Fs.FileRead` (Persistence.load や Resource.loadSchemaDiagnostic と同じ流儀)。
    def loadJsonElement(path: String): Option[Json.JsonElement] \ Fs.FileRead =
        let readResult = run {
            Fs.ReadFile.read(path)
        } with Fs.ReadFile.runWithFileRead;
        readResult
            |> Result.toOption
            |> Option.flatMap(s -> Json.Parse.parse(String.trim(s)))

    /// data 構造を分類し、CatalogIn なら sub-entry 一覧を埋める。Single なら空にする。
    def rebuildSubEntries(state: IdeState): Unit \ IO =
        match ResourceState.getSubListModelRef(state#resource) {
            case None => ()
            case Some(model) =>
                model.clear();
                match ResourceState.getEditingJson(state#resource) {
                    case None => ()
                    case Some(json) =>
                        match ResourceCatalog.classify(json) {
                            case ResourceCatalog.Classification.CatalogIn(info) =>
                                List.forEach(k -> { model.addElement(k); () }, info#subEntries)
                            case _ => ()
                        }
                }
        }

    /// 右カラムの Property Panel を再構築する。
    /// schema が未ロード or 選択未確定の時は placeholder を出す。
    /// catalog 形式で sub-entry 選択時、または single 形式の時に SchemaWidgets で widget を組む。
    def rebuildPropertyPanel(state: IdeState): Unit \ IO =
        match ResourceState.getPropertyPanelRef(state#resource) {
            case None => ()
            case Some(content) =>
                content.removeAll();
                buildPropertyContent(state, content);
                content.revalidate();
                content.repaint()
        }

    def buildPropertyContent(state: IdeState, content: JPanel): Unit \ IO =
        match ResourceState.getEditingSchema(state#resource) {
            case None =>
                let l = new JLabel("(select a resource or schema invalid)");
                l.setForeground(new Color(180, 100, 100));
                l.setAlignmentX(0.0f32);
                content.add(l);
                ()
            case Some(schema) =>
                let classification = ResourceState.getEditingJson(state#resource)
                    |> Option.map(ResourceCatalog.classify);
                match classification {
                    case None =>
                        let l = new JLabel("(data JSON not loaded)");
                        l.setForeground(new Color(180, 100, 100));
                        l.setAlignmentX(0.0f32);
                        content.add(l);
                        ()
                    case Some(c) =>
                        let prefix = computeKeyPathPrefix(state, c);
                        match prefix {
                            case None =>
                                let l = new JLabel("(select a sub-entry)");
                                l.setForeground(new Color(120, 120, 120));
                                l.setAlignmentX(0.0f32);
                                content.add(l);
                                ()
                            case Some(p) =>
                                let panel = SchemaWidgets.buildPanel(state, schema, p);
                                panel.setAlignmentX(0.0f32);
                                content.add(panel);
                                ()
                        }
                }
        }

    /// catalog 形式: sub-entry 選択時のみ Some([container, subEntry])、未選択は None
    /// single 形式 : 常に Some([])
    /// unsupported: None
    def computeKeyPathPrefix(state: IdeState, c: ResourceCatalog.Classification):
            Option[List[String]] \ IO =
        match c {
            case ResourceCatalog.Classification.CatalogIn(info) =>
                match ResourceState.getSelectedSubEntry(state#resource) {
                    case Some(key) => Some(info#containerKey :: key :: Nil)
                    case None      => None
                }
            case ResourceCatalog.Classification.Single        => Some(Nil)
            case ResourceCatalog.Classification.Unsupported(_) => None
        }

    // ──────────────────────────────────────────────────────
    // catalog エントリの追加・削除 (MVP8)
    // ──────────────────────────────────────────────────────

    /// + Add ボタン: showInputDialog でキー入力、衝突チェック、schema からデフォルト値生成、
    /// setAtKeyPath で catalog コンテナに追加、選択状態を新エントリに切替、property panel 再描画。
    /// catalog 形式でない時は何もしない (single には適用不可)。
    def onAddEntry(state: IdeState): Unit \ IO =
        match (ResourceState.getEditingJson(state#resource),
               ResourceState.getEditingSchema(state#resource)) {
            case (Some(json), Some(schema)) =>
                match ResourceCatalog.classify(json) {
                    case ResourceCatalog.Classification.CatalogIn(info) =>
                        let userInput = JOptionPane.showInputDialog("New entry name:");
                        if (Object.isNull(userInput)) ()
                        else {
                            let key = userInput.toString();
                            if (key == "") ()
                            else if (List.memberOf(key, info#subEntries)) {
                                println("[Resources] Add aborted: key already exists: ${key}");
                                ()
                            }
                            else {
                                let defaultVal = generateDefault(schema);
                                let newJson = JsonOps.setAtKeyPath(
                                    json, info#containerKey :: key :: Nil, defaultVal);
                                ResourceState.setEditingJson(state#resource, Some(newJson));
                                ResourceState.setDirty(state#resource, true);
                                ResourceState.setSelectedSubEntry(state#resource, Some(key));
                                rebuildSubEntries(state);
                                selectSubEntryInList(state, key);
                                rebuildPropertyPanel(state);
                                SpritePreview.refresh(state)
                            }
                        }
                    case _ => ()
                }
            case _ => ()
        }

    /// - Del ボタン: 現在選択中の sub-entry を catalog から削除。
    /// pools 等の参照は v1 では検知のみで自動同期しない (将来 MVP9 で組み込み予定)。
    def onDelEntry(state: IdeState): Unit \ IO =
        match (ResourceState.getEditingJson(state#resource),
               ResourceState.getSelectedSubEntry(state#resource)) {
            case (Some(json), Some(key)) =>
                match ResourceCatalog.classify(json) {
                    case ResourceCatalog.Classification.CatalogIn(info) =>
                        // v1: 確認ダイアログは省略 (Save 前なら git で復元可能)
                        println("[Resources] Deleting entry: ${key}");
                        let newJson = removeKeyAt(json, info#containerKey :: Nil, key);
                        ResourceState.setEditingJson(state#resource, Some(newJson));
                        ResourceState.setDirty(state#resource, true);
                        ResourceState.setSelectedSubEntry(state#resource, None);
                        rebuildSubEntries(state);
                        rebuildPropertyPanel(state);
                        SpritePreview.refresh(state)
                    case _ => ()
                }
            case _ => ()
        }

    /// JsonElement の `keyPath` で指す JsonObject から `keyToRemove` を消した新 root を返す。
    /// keyPath が存在しないか、JsonObject でない場合は元の root を返す。
    def removeKeyAt(root: Json.JsonElement, keyPath: List[String], keyToRemove: String):
            Json.JsonElement =
        match JsonOps.getAtKeyPath(root, keyPath) {
            case Some(Json.JsonElement.JsonObject(m)) =>
                let newMap = Map.remove(keyToRemove, m);
                JsonOps.setAtKeyPath(root, keyPath, Json.JsonElement.JsonObject(newMap))
            case _ => root
        }

    /// schema を walk してデフォルト値の JsonObject を生成する。
    /// IntT=0, FloatT=0, BoolT=false, TextT="", TexturePathT=空文字 (後で dropdown で選択)、Nested=再帰
    def generateDefault(schema: Resource.ResourceSchema): Json.JsonElement =
        let fields = Resource.fieldsOf(schema);
        Json.JsonElement.JsonObject(
            Map.foldLeftWithKey((acc, name, entry) ->
                Map.insert(name, defaultForEntry(entry), acc),
                Map.empty(), fields))

    def defaultForEntry(entry: Resource.FieldEntry): Json.JsonElement = match entry {
        case Resource.FieldEntry.Field(fs) => defaultForType(fs#ftype)
        case Resource.FieldEntry.Nested(m) =>
            Json.JsonElement.JsonObject(
                Map.foldLeftWithKey((acc, name, e) ->
                    Map.insert(name, defaultForEntry(e), acc),
                    Map.empty(), m))
    }

    def defaultForType(t: Resource.FieldType): Json.JsonElement =
        match t {
            case Resource.FieldType.IntT         =>
                Json.JsonElement.JsonNumber(JBigDecimal.valueOf(0i64))
            case Resource.FieldType.FloatT       =>
                Json.JsonElement.JsonNumber(JBigDecimal.valueOf(0i64))
            case Resource.FieldType.BoolT        => Json.JsonElement.JsonBool(false)
            case Resource.FieldType.TextT        => Json.JsonElement.JsonString("")
            case Resource.FieldType.TexturePathT => Json.JsonElement.JsonString("")
        }

    /// sub-entry リストの中で指定キーを選択状態にする (rebuild 後の UI 同期)。
    def selectSubEntryInList(state: IdeState, key: String): Unit \ IO =
        match ResourceState.getSubListModelRef(state#resource) {
            case None => ()
            case Some(model) =>
                let idx = model.indexOf(key);
                match ResourceState.getSubListRef(state#resource) {
                    case Some(list) => list.setSelectedIndex(idx)
                    case None       => ()
                }
        }

    /// Save ボタン押下時の処理。
    /// 1. editingJson と selected path が両方 Some であることを確認
    /// 2. ResourceWriter.writeJson でファイルに書き戻し
    /// 3. dirty クリア、status ラベル更新
    def onSaveClicked(state: IdeState, status: JLabel): Unit \ {IO, Fs.FileWrite} =
        match (ResourceState.getSelectedDataPath(state#resource),
               ResourceState.getEditingJson(state#resource)) {
            case (Some(path), Some(json)) =>
                match ResourceWriter.writeJson(path, json) {
                    case Ok(_) =>
                        ResourceState.setDirty(state#resource, false);
                        status.setText("Saved");
                        status.setForeground(new Color(140, 200, 140));
                        ()
                    case Err(msg) =>
                        status.setText("Save failed: ${msg}");
                        status.setForeground(new Color(220, 100, 100));
                        ()
                }
            case _ =>
                status.setText("Nothing to save");
                status.setForeground(new Color(180, 180, 100));
                ()
        }
}
