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
    import javax.swing.JTextArea
    import javax.swing.JTextField
    import javax.swing.JComboBox
    import java.math.{BigDecimal => JBigDecimal}

    use ResourceDiscovery.ResourceEntry
    use ResourceCatalog.MetaHint

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

        // schema の生 JSON も別途保存。IDE 内で metaHints を直接 parse する用途。
        let schemaJson = loadJsonElement(entry#schemaPath);
        ResourceState.setEditingSchemaJson(state#resource, schemaJson);

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
                // schema が None: 「未選択」または「schema 違反」の 2 通り。
                // editingJson が Some なら schema 違反 (data はある)、None なら未選択。
                match ResourceState.getEditingJson(state#resource) {
                    case None =>
                        let l = new JLabel("(select a resource)");
                        l.setForeground(new Color(120, 120, 120));
                        l.setAlignmentX(0.0f32);
                        content.add(l);
                        ()
                    case Some(json) =>
                        // schema 違反: 赤い警告ヘッダ + 生 JSON read-only 表示
                        let errorBanner = createErrorBanner("Schema invalid or missing — read-only");
                        errorBanner.setAlignmentX(0.0f32);
                        content.add(errorBanner);

                        let pretty = Json.Write.toPrettyString(2, json);
                        let textArea = new JTextArea(pretty);
                        textArea.setEditable(false);
                        textArea.setBackground(new Color(30, 30, 30));
                        textArea.setForeground(new Color(200, 200, 200));
                        let scroll = new JScrollPane(textArea);
                        scroll.setPreferredSize(new Dimension(0, 400));
                        scroll.setAlignmentX(0.0f32);
                        content.add(scroll);
                        ()
                }
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
                                // メタフィールド (catalog 外の data top フィールド) を続けて表示
                                match c {
                                    case ResourceCatalog.Classification.CatalogIn(info) =>
                                        if (not List.isEmpty(info#metaKeys)) {
                                            let meta = buildMetaPanel(state, info#metaKeys);
                                            meta.setAlignmentX(0.0f32);
                                            content.add(meta);
                                            ()
                                        } else ()
                                    case _ => ()
                                }
                        }
                }
        }

    // ──────────────────────────────────────────────────────
    // 異常系のフォールバック (MVP10)
    // ──────────────────────────────────────────────────────

    /// 赤背景のエラー警告バナー。schema 違反など、編集を許してはいけない状態を強く示す。
    def createErrorBanner(message: String): JPanel \ IO =
        let row = new JPanel(new BorderLayout());
        row.setBackground(new Color(120, 40, 40));
        row.setBorder(BorderFactory.createCompoundBorder(
            BorderFactory.createMatteBorder(1, 0, 1, 0, new Color(60, 20, 20)),
            BorderFactory.createEmptyBorder(6, 10, 6, 10)
        ));
        row.setMaximumSize(new Dimension(9999, 32));
        let lbl = new JLabel(message);
        lbl.setForeground(new Color(255, 220, 220));
        lbl.setHorizontalAlignment(SwingConstants.CENTER);
        row.add(lbl, BorderLayout.CENTER);
        row

    // ──────────────────────────────────────────────────────
    // メタフィールド UI (MVP9)
    // ──────────────────────────────────────────────────────

    /// catalog の外側にあるフィールド (例: pools) を表示する panel を組み立てる。
    /// 各 meta key に対し、値の構造に応じて以下を出す:
    ///   - JsonObject  : 子キーを section header + JList で表示
    ///   - JsonArray of JsonString : JList + 追加/削除ボタン
    ///   - その他       : read-only テキスト
    def buildMetaPanel(state: IdeState, metaKeys: List[String]): JPanel \ IO =
        let panel = new JPanel();
        panel.setLayout(new BoxLayout(panel, BoxLayout.Y_AXIS));
        panel.setBackground(new Color(45, 45, 45));
        panel.setAlignmentX(0.0f32);

        match ResourceState.getEditingJson(state#resource) {
            case None => ()
            case Some(json) =>
                List.forEach(metaKey -> {
                    let header = SchemaWidgets.createSectionHeader(metaKey);
                    header.setAlignmentX(0.0f32);
                    panel.add(header);
                    match JsonOps.getAtKeyPath(json, metaKey :: Nil) {
                        case Some(Json.JsonElement.JsonObject(m)) =>
                            Map.forEach((subKey, subVal) -> {
                                renderMetaField(state, metaKey :: subKey :: Nil, subKey, subVal, panel)
                            }, m)
                        case Some(other) =>
                            renderMetaField(state, metaKey :: Nil, metaKey, other, panel)
                        case None => ()
                    }
                }, metaKeys)
        };
        panel

    def renderMetaField(state: IdeState, keyPath: List[String], name: String,
                         value: Json.JsonElement, parent: JPanel): Unit \ IO =
        match value {
            case Json.JsonElement.JsonArray(items) =>
                renderStringArray(state, keyPath, name, Vector.toList(items), parent)
            case _ =>
                // read-only: 値の文字列化
                let row = new JPanel(new BorderLayout(6, 0));
                row.setBackground(new Color(45, 45, 45));
                row.setBorder(BorderFactory.createEmptyBorder(2, 10, 2, 10));
                row.setMaximumSize(new Dimension(9999, 24));
                row.setAlignmentX(0.0f32);
                let label = new JLabel(name);
                label.setForeground(new Color(190, 190, 195));
                label.setPreferredSize(new Dimension(90, 24));
                row.add(label, BorderLayout.WEST);
                let valueLabel = new JLabel(Json.Write.toCompactString(value));
                valueLabel.setForeground(new Color(150, 150, 150));
                row.add(valueLabel, BorderLayout.CENTER);
                parent.add(row);
                ()
        }

    /// JsonArray of JsonString を JList で表示。下に [+ Add] / [- Del] ボタン。
    /// 追加: catalog の sub-entry 一覧から JComboBox で選択。
    /// 削除: 選択行を JList から取り除き、JSON を更新。
    def renderStringArray(state: IdeState, keyPath: List[String], name: String,
                           items: List[Json.JsonElement], parent: JPanel): Unit \ IO =
        let _ = name;
        let container = new JPanel(new BorderLayout());
        container.setBackground(new Color(40, 40, 40));
        container.setBorder(BorderFactory.createEmptyBorder(2, 10, 2, 10));
        container.setMaximumSize(new Dimension(9999, 140));
        container.setAlignmentX(0.0f32);

        let model: DefaultListModel[String] = new DefaultListModel();
        List.forEach(v -> {
            match v {
                case Json.JsonElement.JsonString(s) => { model.addElement(s); () }
                case _ => ()
            }
        }, items);

        let list: JList[String] = new JList(model);
        list.setBackground(new Color(30, 30, 30));
        list.setForeground(Color.LIGHT_GRAY);
        list.setSelectionMode(ListSelectionModel.SINGLE_SELECTION);
        let scroll = new JScrollPane(list);
        scroll.setPreferredSize(new Dimension(0, 100));
        container.add(scroll, BorderLayout.CENTER);

        let buttons = new JPanel(new FlowLayout(FlowLayout.LEFT, 4, 2));
        buttons.setBackground(new Color(40, 40, 40));
        let addBtn = new JButton("+");
        let delBtn = new JButton("-");
        addBtn.addActionListener(new ActionListener {
            def actionPerformed(_this: ActionListener, _e: ActionEvent): Unit \ IO =
                onMetaArrayAdd(state, keyPath, model)
        });
        delBtn.addActionListener(new ActionListener {
            def actionPerformed(_this: ActionListener, _e: ActionEvent): Unit \ IO =
                onMetaArrayDel(state, keyPath, model, list)
        });
        buttons.add(addBtn);
        buttons.add(delBtn);
        container.add(buttons, BorderLayout.SOUTH);
        parent.add(container);
        ()

    /// メタ配列に新しい要素を追加。
    /// schema の `metaHints` を最初に参照:
    ///   - `Ref(target)` → 純粋 JComboBox。`target` キーの catalog コンテナの
    ///                     sub-entries を候補に並べる (例: target="units" なら knight/archer/...)
    ///   - `Text`        → JTextField (自由文字列入力)
    /// metaHints に指定がない場合は、`ResourceCatalog.isCatalogRefArray` で既存要素から
    /// hint をヒューリスティック判定する (catalog 参照ならアクティブ catalog の sub-entries を使う)。
    def onMetaArrayAdd(state: IdeState, keyPath: List[String], model: DefaultListModel[String]):
            Unit \ IO =
        match ResourceState.getEditingJson(state#resource) {
            case Some(json) =>
                let topKey = List.head(keyPath) |> Option.getWithDefault("");
                let hint = resolveMetaHint(state, json, keyPath, topKey);
                let chosen = promptForArrayElement(state, hint, json);
                match chosen {
                    case Some(value) =>
                        if (value == "") ()
                        else {
                            model.addElement(value);
                            rebuildMetaJsonFromModel(state, keyPath, model)
                        }
                    case None => ()
                }
            case None => ()
        }

    /// schema の metaHints から hint を引く。ヒットしなければヒューリスティック判定。
    /// schema の metaHints は IDE 内で schema 生 JSON から直接 parse する
    /// (engine 側 fpkg の MetaHint 拡張に依存しない)。
    def resolveMetaHint(state: IdeState, json: Json.JsonElement,
                          keyPath: List[String], topKey: String): ResourceCatalog.MetaHint \ IO =
        let metaHints = match ResourceState.getEditingSchemaJson(state#resource) {
            case Some(schemaJson) => ResourceCatalog.parseMetaHints(schemaJson)
            case None             => Map.empty()
        };
        match Map.get(topKey, metaHints) {
            case Some(h) => h
            case None =>
                // ヒューリスティック: アクティブ catalog の sub-entries と既存要素を比較
                match ResourceCatalog.classify(json) {
                    case ResourceCatalog.Classification.CatalogIn(info) =>
                        let items = match JsonOps.getAtKeyPath(json, keyPath) {
                            case Some(Json.JsonElement.JsonArray(v)) => Vector.toList(v)
                            case _                                   => Nil
                        };
                        if (ResourceCatalog.isCatalogRefArray(items, info#subEntries))
                            ResourceCatalog.MetaHint.Ref(info#containerKey)
                        else
                            ResourceCatalog.MetaHint.Text
                    case _ => ResourceCatalog.MetaHint.Text
                }
        }

    /// hint に応じてダイアログを出す。
    ///   Ref(target) → data の `target` 配下を見て sub-entries を候補に JComboBox
    ///   Text        → JOptionPane.showInputDialog (自由テキスト)
    /// 返り値: Some(選択値) または None (キャンセル)
    def promptForArrayElement(state: IdeState, hint: ResourceCatalog.MetaHint, json: Json.JsonElement):
            Option[String] \ IO =
        match hint {
            case ResourceCatalog.MetaHint.Ref(target) =>
                let candidates = subEntriesOf(json, target);
                if (List.isEmpty(candidates)) {
                    let _ = JOptionPane.showInputDialog(
                        "No entries to choose from. Add entries to '${target}' first.");
                    None
                }
                else
                    showComboPicker(state, candidates)
            case ResourceCatalog.MetaHint.Text =>
                let result = JOptionPane.showInputDialog("Enter value:");
                if (Object.isNull(result)) None
                else Some(result.toString())
        }

    /// data 配下の `target` キーが JsonObject なら、そのキー集合 (= catalog sub-entries) を返す。
    /// target が存在しなければ、または JsonObject でなければ空リスト。
    def subEntriesOf(json: Json.JsonElement, target: String): List[String] =
        match JsonOps.getAtKeyPath(json, target :: Nil) {
            case Some(Json.JsonElement.JsonObject(m)) => Map.keysOf(m) |> Set.toList
            case _                                     => Nil
        }

    /// JComboBox を入れたモーダルダイアログを出して、選択された文字列を返す。
    /// parent は ResourceState から取り出したメイン frame を使う (null parent を避ける)。
    def showComboPicker(state: IdeState, candidates: List[String]): Option[String] \ IO =
        let combo: JComboBox[String] = new JComboBox();
        List.forEach(c -> { combo.addItem(c); () }, candidates);
        combo.setEditable(false);

        let label = new JLabel("Select entry:");
        let panel = new JPanel(new BorderLayout(0, 6));
        panel.add(label, BorderLayout.NORTH);
        panel.add(combo, BorderLayout.CENTER);

        let parent = match ResourceState.getMainFrame(state#resource) {
            case Some(f) => f
            case None    => bug!("ResourceEditorUI: mainFrame not set (IdeUI.customize 内で setMainFrame を呼ぶ必要あり)")
        };
        let result = JOptionPane.showConfirmDialog(
            parent, panel, "Add to array", JOptionPane.OK_CANCEL_OPTION);
        if (result == JOptionPane.OK_OPTION) {
            let sel = combo.getSelectedItem();
            if (Object.isNull(sel)) None
            else Some(sel.toString())
        } else None

    def onMetaArrayDel(state: IdeState, keyPath: List[String],
                        model: DefaultListModel[String], list: JList[String]): Unit \ IO =
        let idx = list.getSelectedIndex();
        if (idx < 0) ()
        else {
            model.removeElementAt(idx);
            rebuildMetaJsonFromModel(state, keyPath, model)
        }

    /// JList の現在の content を JSON 配列にして JsonOps.setAtKeyPath で editingJson を更新。
    def rebuildMetaJsonFromModel(state: IdeState, keyPath: List[String],
                                   model: DefaultListModel[String]): Unit \ IO =
        match ResourceState.getEditingJson(state#resource) {
            case None => ()
            case Some(json) =>
                let size = model.getSize();
                let items = collectListItems(model, 0, size, Nil);
                let arr = Json.JsonElement.JsonArray(
                    List.toVector(List.map(s -> Json.JsonElement.JsonString(s), items)));
                let newJson = JsonOps.setAtKeyPath(json, keyPath, arr);
                ResourceState.setEditingJson(state#resource, Some(newJson));
                ResourceState.setDirty(state#resource, true)
        }

    def collectListItems(model: DefaultListModel[String], i: Int32, n: Int32, acc: List[String]):
            List[String] \ IO =
        if (i >= n) List.reverse(acc)
        else collectListItems(model, i + 1, n, model.getElementAt(i) :: acc)

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
