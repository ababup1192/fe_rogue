// SchemaWidgets — Resource.ResourceSchema を walk して widget を組み立てる
//
// レイアウト方針 (Godot Inspector を参考):
//   - 各 widget 行は高さ ~24px に詰める
//   - Slider + Spinner を組合せ、現在値表示と直接数値入力を両立
//   - Nested は createSectionHeader (Inspector の "Node2D" 区切りと同じ bg(60,60,70) +
//     上下 matte border) で見出しを出し、その下に子 panel
//   - top-level (single レコード or catalog の sub-entry) も "Properties" の section header
//
// 全ての build* / widget 関数は JPanel を返す (Flix の Java interop で subtype を扱わないため、
// 各 widget は 1 セルの JPanel に包む)。

mod SchemaWidgets {
    import javax.swing.JComponent
    import javax.swing.JPanel
    import javax.swing.JLabel
    import javax.swing.JSpinner
    import javax.swing.SpinnerNumberModel
    import javax.swing.JSlider
    import javax.swing.JTextField
    import javax.swing.JCheckBox
    import javax.swing.JComboBox
    import javax.swing.BoxLayout
    import javax.swing.Box
    import javax.swing.BorderFactory
    import javax.swing.SwingConstants
    import javax.swing.event.ChangeListener
    import javax.swing.event.ChangeEvent
    import javax.swing.event.DocumentListener
    import javax.swing.event.DocumentEvent
    import java.awt.BorderLayout
    import java.awt.Color
    import java.awt.Dimension
    import java.awt.FlowLayout
    import java.awt.event.ActionListener
    import java.awt.event.ActionEvent
    import java.math.{BigDecimal => JBigDecimal}

    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonString, JsonNumber, JsonBool, JsonNull}
    use Resource.{ResourceSchema, FieldEntry, FieldSchema, FieldType, FieldHint}

    pub type alias IdeState = IdeState.IdeState

    /// 1 行の標準高さ。Inspector の Slider+Spinner 行と揃える。
    def rowHeight(): Int32 = 24

    /// ラベル列の幅。Inspector のフィールド名カラム幅と揃える。
    def labelWidth(): Int32 = 90

    /// JLabel に渡すテキストを HTML mode で包む。
    ///
    /// Swing JLabel の **plain text レンダリング** は、 macOS の一部 JDK / フォント設定で
    /// ASCII の特定グリフ（特に "HP" や "P" を含む短い文字列）が空白で描画されることがある
    /// （フォントフォールバック失敗が原因と思われる Swing の既知挙動）。
    /// JLabel が "<html>" 始まりの文字列を受け取った場合は内部で HTMLDocument を使い、
    /// 別のフォント解決パスを通るのでこの問題を回避できる。
    ///
    /// `&` / `<` / `>` は HTML 特殊文字なのでエスケープする。 plain text として渡された
    /// 「HP」「最大HP」「&」 等が全て正しく表示される。
    def htmlLabel(text: String): String =
        let escaped = text
            |> String.replace(src = "&", dst = "&amp;")
            |> String.replace(src = "<", dst = "&lt;")
            |> String.replace(src = ">", dst = "&gt;");
        "<html>" + escaped + "</html>"

    /// Spinner 列の幅 (Slider の右に表示する数値入力)。
    def spinnerWidth(): Int32 = 64

    /// 背景色。Inspector の Property panel と揃える。
    def panelBg(): Color \ IO = new Color(45, 45, 45)

    /// schema を walk して 1 つの縦並び panel を作る。
    /// keyPathPrefix: catalog 時は `[containerKey, subEntryKey]`、single 時は空。
    pub def buildPanel(state: IdeState, schema: ResourceSchema, keyPathPrefix: List[String]):
            JPanel \ IO =
        let panel = new JPanel();
        panel.setLayout(new BoxLayout(panel, BoxLayout.Y_AXIS));
        panel.setBackground(panelBg());

        // top-level の全フィールドを「Properties」セクションとして出す
        let topHeader = createSectionHeader("Properties");
        panel.add(topHeader);

        let fields = Resource.fieldsOf(schema);
        List.forEach(pair -> {
            let (name, entry) = pair;
            let row = buildEntry(state, name, entry, keyPathPrefix);
            row.setAlignmentX(0.0f32);
            panel.add(row);
            ()
        }, sortedFields(fields));
        // 残りの縦スペースを吸収。これがないと各 widget が BoxLayout に拡大配置されて
        // 1 行の高さが異常に伸び、後続の widget が画面外に押し出される。
        panel.add(Box.createVerticalGlue());
        panel

    /// Inspector の「Node2D」区切り行と同じスタイルのセクションヘッダ。
    /// bg(60,60,70)、上下 matte border、中央寄せ。
    pub def createSectionHeader(title: String): JPanel \ IO =
        let row = new JPanel(new BorderLayout());
        row.setBackground(new Color(60, 60, 70));
        row.setBorder(BorderFactory.createCompoundBorder(
            BorderFactory.createMatteBorder(1, 0, 1, 0, new Color(35, 35, 40)),
            BorderFactory.createEmptyBorder(4, 10, 4, 10)
        ));
        row.setMaximumSize(new Dimension(9999, 26));
        row.setAlignmentX(0.0f32);
        let lbl = new JLabel(htmlLabel(title));
        lbl.setForeground(new Color(220, 220, 230));
        lbl.setHorizontalAlignment(SwingConstants.CENTER);
        row.add(lbl, BorderLayout.CENTER);
        row

    /// Map のキーは alphabetical で iterate されるため UI 順序が「フレーム → 横分割 → テクスチャ
    /// → 縦分割」のように直感に反する。フィールドの type/hint に基づく優先度で並べ替えて、
    /// 「素材選択 → 寸法 → 細かな選択 → サブセクション」という汎用的な順序にする。
    def sortedFields(fields: Map[String, FieldEntry]): List[(String, FieldEntry)] =
        Map.toList(fields)
            |> List.sortWith(pair -> other -> compareEntries(pair, other))

    /// 並び比較。 schema で `order` が指定されたフィールドを最優先に並べ（小さい値が先頭）、
    /// 指定なしの集団はその後ろに priority + alphabetical で続ける。
    /// これで designer が schema 側で「自然な並び」（名前→レベル→HP→...）を宣言できる。
    def compareEntries(a: (String, FieldEntry), b: (String, FieldEntry)): Comparison =
        let (k1, e1) = a;
        let (k2, e2) = b;
        match (orderOf(e1), orderOf(e2)) {
            case (Some(n1), Some(n2)) =>
                if (n1 < n2) Comparison.LessThan
                else if (n1 > n2) Comparison.GreaterThan
                else Comparison.EqualTo
            case (Some(_), None) => Comparison.LessThan
            case (None, Some(_)) => Comparison.GreaterThan
            case (None, None)    =>
                let p1 = priorityOf(e1);
                let p2 = priorityOf(e2);
                if (p1 < p2) Comparison.LessThan
                else if (p1 > p2) Comparison.GreaterThan
                else if (k1 < k2) Comparison.LessThan
                else if (k1 > k2) Comparison.GreaterThan
                else Comparison.EqualTo
        }

    /// FieldEntry から order 指定を取り出す。 Nested は順序情報を持たないので常に None。
    def orderOf(entry: FieldEntry): Option[Int32] =
        match entry {
            case FieldEntry.Field(fs) => fs#order
            case FieldEntry.Nested(_) => None
        }

    /// フィールドの並び順優先度。小さい値が先頭。
    ///   0: TexturePathT       (素材選択を最初に)
    ///   2: IntT + Spinner     (次元: hframes, vframes など)
    ///   3: 通常の数値 (Slider) (戦闘ステータスなど)
    ///   4: TextT
    ///   5: BoolT
    ///   9: FrameGrid          (texture/dimensions を決めた後の細かな選択)
    ///   10: Nested            (サブセクションは最後)
    def priorityOf(entry: FieldEntry): Int32 = match entry {
        case FieldEntry.Field(fs) =>
            match fs#ftype {
                case FieldType.TexturePathT => 0
                case FieldType.TextT        => 4
                case FieldType.BoolT        => 5
                case _ =>
                    match fs#hint {
                        case FieldHint.FrameGrid(_) => 9
                        case FieldHint.Spinner(_)   => 2
                        case _                      => 3
                    }
            }
        case FieldEntry.Nested(_) => 10
    }

    def buildEntry(state: IdeState, name: String, entry: FieldEntry, keyPathPrefix: List[String]):
            JPanel \ IO =
        match entry {
            case FieldEntry.Field(fs) =>
                buildField(state, name, fs, keyPathPrefix)
            case FieldEntry.Nested(m) =>
                buildNested(state, name, m, keyPathPrefix)
        }

    /// Nested フィールドは「セクションヘッダ + 子 panel」の構造で表示する。
    /// セクションヘッダは Inspector の Node2D 区切りと同じスタイル。
    def buildNested(state: IdeState, name: String, fields: Map[String, FieldEntry],
                    keyPathPrefix: List[String]): JPanel \ IO =
        let outer = new JPanel();
        outer.setLayout(new BoxLayout(outer, BoxLayout.Y_AXIS));
        outer.setBackground(panelBg());
        outer.setAlignmentX(0.0f32);

        let header = createSectionHeader(name);
        outer.add(header);

        let newPrefix = keyPathPrefix ::: (name :: Nil);
        List.forEach(pair -> {
            let (childName, childEntry) = pair;
            let row = buildEntry(state, childName, childEntry, newPrefix);
            row.setAlignmentX(0.0f32);
            outer.add(row);
            ()
        }, sortedFields(fields));
        outer

    /// 1 フィールド分の行。`[label (90px) | widget (flex)]` のシンプル横並び。
    /// 行の最大高さを rowHeight() に固定して縦に詰める。
    def buildField(state: IdeState, name: String, fs: FieldSchema, keyPathPrefix: List[String]):
            JPanel \ IO =
        let keyPath = keyPathPrefix ::: (name :: Nil);
        let row = new JPanel(new BorderLayout(6, 0));
        row.setBackground(panelBg());
        row.setBorder(BorderFactory.createEmptyBorder(1, 10, 1, 10));
        row.setMaximumSize(new Dimension(9999, rowHeight()));
        row.setAlignmentX(0.0f32);

        let label = new JLabel(htmlLabel(fs#label));
        label.setForeground(new Color(190, 190, 195));
        label.setPreferredSize(new Dimension(labelWidth(), rowHeight()));
        row.add(label, BorderLayout.WEST);

        let editor = buildWidget(state, fs, keyPath);
        row.add(editor, BorderLayout.CENTER);
        row

    def buildWidget(state: IdeState, fs: FieldSchema, keyPath: List[String]): JPanel \ IO =
        match (fs#ftype, fs#hint) {
            case (FieldType.IntT,         FieldHint.Slider(s))     => intSlider(state, keyPath, s)
            case (FieldType.IntT,         FieldHint.Spinner(s))    => intSpinner(state, keyPath, s)
            case (FieldType.IntT,         FieldHint.FrameGrid(_))  => intSpinnerOpen(state, keyPath)
            case (FieldType.IntT,         FieldHint.Plain)         => intSpinnerOpen(state, keyPath)
            case (FieldType.FloatT,       FieldHint.Slider(s))     => floatSlider(state, keyPath, s)
            case (FieldType.FloatT,       FieldHint.Spinner(_))    => floatSpinner(state, keyPath)
            case (FieldType.FloatT,       FieldHint.Plain)         => floatSpinner(state, keyPath)
            case (FieldType.FloatT,       FieldHint.FrameGrid(_))  => floatSpinner(state, keyPath)
            case (FieldType.TextT,        _)                       => textField(state, keyPath)
            case (FieldType.BoolT,        _)                       => boolCheck(state, keyPath)
            case (FieldType.TexturePathT, _)                       => textureDropdown(state, keyPath)
        }

    // ──────────────────────────────────────────────────────
    // 個別 widget
    // ──────────────────────────────────────────────────────

    def currentValue(state: IdeState, keyPath: List[String]): Option[JsonElement] \ IO =
        ResourceState.getEditingJson(state#resource)
            |> Option.flatMap(json -> JsonOps.getAtKeyPath(json, keyPath))

    /// IntT + Slider: スライダー + 右に Spinner で値表示 + 直接入力。
    /// 両者を ChangeListener で双方向同期する。
    def intSlider(state: IdeState, keyPath: List[String],
                  spec: {min = Float64, max = Float64, step = Float64}): JPanel \ IO =
        let minI = Float64.tryToInt32(spec#min) |> Option.getWithDefault(0);
        let maxI = Float64.tryToInt32(spec#max) |> Option.getWithDefault(100);
        let raw = currentValue(state, keyPath) |> Option.flatMap(jsonToInt) |> Option.getWithDefault(minI);
        let current = clampInt(raw, minI, maxI);

        let slider = new JSlider(minI, maxI, current);
        slider.setBackground(panelBg());
        slider.setOpaque(false);

        let model = new SpinnerNumberModel(current, minI, maxI, 1);
        let spinner = new JSpinner(model);
        spinner.setPreferredSize(new Dimension(spinnerWidth(), rowHeight()));

        // ChangeListener の再入を防ぐためのフラグ
        let updating = Array#{false} @ Static;
        slider.addChangeListener(new ChangeListener {
            def stateChanged(_this: ChangeListener, _e: ChangeEvent): Unit \ IO = {
                if (Array.get(0, updating)) ()
                else {
                    Array.put(true, 0, updating);
                    let v = slider.getValue();
                    spinner.setValue(v);
                    commitInt(state, keyPath, v);
                    Array.put(false, 0, updating)
                }
            }
        });
        spinner.addChangeListener(new ChangeListener {
            def stateChanged(_this: ChangeListener, _e: ChangeEvent): Unit \ IO = {
                if (Array.get(0, updating)) ()
                else {
                    Array.put(true, 0, updating);
                    let v = model.getNumber().intValue();
                    slider.setValue(v);
                    commitInt(state, keyPath, v);
                    Array.put(false, 0, updating)
                }
            }
        });

        let p = new JPanel(new BorderLayout(4, 0));
        p.setBackground(panelBg());
        p.add(slider, BorderLayout.CENTER);
        p.add(spinner, BorderLayout.EAST);
        p

    def intSpinner(state: IdeState, keyPath: List[String],
                   spec: {min = Int32, max = Int32}): JPanel \ IO =
        let raw = currentValue(state, keyPath) |> Option.flatMap(jsonToInt) |> Option.getWithDefault(spec#min);
        let current = clampInt(raw, spec#min, spec#max);
        let model = new SpinnerNumberModel(current, spec#min, spec#max, 1);
        let spinner = new JSpinner(model);
        spinner.setPreferredSize(new Dimension(spinnerWidth(), rowHeight()));
        spinner.addChangeListener(new ChangeListener {
            def stateChanged(_this: ChangeListener, _e: ChangeEvent): Unit \ IO = {
                let v = model.getNumber().intValue();
                commitInt(state, keyPath, v)
            }
        });
        let p = new JPanel(new BorderLayout());
        p.setBackground(panelBg());
        p.add(spinner, BorderLayout.EAST);
        p

    def intSpinnerOpen(state: IdeState, keyPath: List[String]): JPanel \ IO =
        let raw = currentValue(state, keyPath) |> Option.flatMap(jsonToInt) |> Option.getWithDefault(0);
        let current = clampInt(raw, -10000, 10000);
        let model = new SpinnerNumberModel(current, -10000, 10000, 1);
        let spinner = new JSpinner(model);
        spinner.setPreferredSize(new Dimension(spinnerWidth(), rowHeight()));
        spinner.addChangeListener(new ChangeListener {
            def stateChanged(_this: ChangeListener, _e: ChangeEvent): Unit \ IO = {
                let v = model.getNumber().intValue();
                commitInt(state, keyPath, v)
            }
        });
        let p = new JPanel(new BorderLayout());
        p.setBackground(panelBg());
        p.add(spinner, BorderLayout.EAST);
        p

    def floatSlider(state: IdeState, keyPath: List[String],
                    spec: {min = Float64, max = Float64, step = Float64}): JPanel \ IO =
        let steps = 1000;
        let raw = currentValue(state, keyPath)
            |> Option.flatMap(jsonToFloat)
            |> Option.getWithDefault(spec#min);
        let current = clampFloat(raw, spec#min, spec#max);
        let span = spec#max - spec#min;
        let toSliderVal = (v: Float64) -> {
            let ratio = (v - spec#min) / span;
            Float64.tryToInt32(ratio * Int32.toFloat64(steps)) |> Option.getWithDefault(0)
        };
        let fromSliderVal = (s: Int32) -> {
            let ratio = Int32.toFloat64(s) / Int32.toFloat64(steps);
            spec#min + span * ratio
        };

        let slider = new JSlider(0, steps, toSliderVal(current));
        slider.setBackground(panelBg());
        slider.setOpaque(false);

        let model = new SpinnerNumberModel(current, spec#min, spec#max, spec#step);
        let spinner = new JSpinner(model);
        spinner.setPreferredSize(new Dimension(spinnerWidth(), rowHeight()));

        let updating = Array#{false} @ Static;
        slider.addChangeListener(new ChangeListener {
            def stateChanged(_this: ChangeListener, _e: ChangeEvent): Unit \ IO = {
                if (Array.get(0, updating)) ()
                else {
                    Array.put(true, 0, updating);
                    let v = fromSliderVal(slider.getValue());
                    spinner.setValue(v);
                    commitFloat(state, keyPath, v);
                    Array.put(false, 0, updating)
                }
            }
        });
        spinner.addChangeListener(new ChangeListener {
            def stateChanged(_this: ChangeListener, _e: ChangeEvent): Unit \ IO = {
                if (Array.get(0, updating)) ()
                else {
                    Array.put(true, 0, updating);
                    let v = model.getNumber().doubleValue();
                    slider.setValue(toSliderVal(v));
                    commitFloat(state, keyPath, v);
                    Array.put(false, 0, updating)
                }
            }
        });

        let p = new JPanel(new BorderLayout(4, 0));
        p.setBackground(panelBg());
        p.add(slider, BorderLayout.CENTER);
        p.add(spinner, BorderLayout.EAST);
        p

    def floatSpinner(state: IdeState, keyPath: List[String]): JPanel \ IO =
        let raw = currentValue(state, keyPath)
            |> Option.flatMap(jsonToFloat)
            |> Option.getWithDefault(0.0);
        let current = clampFloat(raw, -100000.0, 100000.0);
        let model = new SpinnerNumberModel(current, -100000.0, 100000.0, 0.1);
        let spinner = new JSpinner(model);
        spinner.setPreferredSize(new Dimension(spinnerWidth(), rowHeight()));
        spinner.addChangeListener(new ChangeListener {
            def stateChanged(_this: ChangeListener, _e: ChangeEvent): Unit \ IO = {
                let v = model.getNumber().doubleValue();
                commitFloat(state, keyPath, v)
            }
        });
        let p = new JPanel(new BorderLayout());
        p.setBackground(panelBg());
        p.add(spinner, BorderLayout.EAST);
        p

    def textField(state: IdeState, keyPath: List[String]): JPanel \ IO =
        let current = currentValue(state, keyPath) |> Option.flatMap(jsonToString) |> Option.getWithDefault("");
        let field = new JTextField(current);
        let doc = field.getDocument();
        doc.addDocumentListener(new DocumentListener {
            def insertUpdate(_this: DocumentListener, _e: DocumentEvent): Unit \ IO =
                commitString(state, keyPath, field.getText())
            def removeUpdate(_this: DocumentListener, _e: DocumentEvent): Unit \ IO =
                commitString(state, keyPath, field.getText())
            def changedUpdate(_this: DocumentListener, _e: DocumentEvent): Unit \ IO =
                commitString(state, keyPath, field.getText())
        });
        let p = new JPanel(new BorderLayout());
        p.setBackground(panelBg());
        p.add(field, BorderLayout.CENTER);
        p

    def boolCheck(state: IdeState, keyPath: List[String]): JPanel \ IO =
        let current = currentValue(state, keyPath) |> Option.flatMap(jsonToBool) |> Option.getWithDefault(false);
        let check = new JCheckBox("", current);
        check.setBackground(panelBg());
        check.addActionListener(new ActionListener {
            def actionPerformed(_this: ActionListener, _e: ActionEvent): Unit \ IO =
                commitBool(state, keyPath, check.isSelected())
        });
        let p = new JPanel(new BorderLayout());
        p.setBackground(panelBg());
        p.add(check, BorderLayout.WEST);
        p

    def textureDropdown(state: IdeState, keyPath: List[String]): JPanel \ IO =
        let map = IdeState.getTexturePathMap(state);
        let names = Map.keysOf(map) |> Set.toList;
        let current = currentValue(state, keyPath) |> Option.flatMap(jsonToString);
        let combo: JComboBox[String] = new JComboBox();
        // JComboBox は Mac の Aqua LAF で native コントロールが大きいため明示的にサイズ制限。
        // preferredSize の width=0 は BoxLayout のサイズ計算を壊して後続 widget が消えるので
        // 妥当な値 (220) を指定する。
        combo.setPreferredSize(new Dimension(220, rowHeight()));
        combo.setMaximumSize(new Dimension(9999, rowHeight()));
        combo.setMinimumSize(new Dimension(50, rowHeight()));
        List.forEach(n -> { combo.addItem(n); () }, names);
        match current {
            case Some(s) => combo.setSelectedItem(s)
            case None    => ()
        };
        combo.addActionListener(new ActionListener {
            def actionPerformed(_this: ActionListener, _e: ActionEvent): Unit \ IO = {
                let obj = combo.getSelectedItem();
                if (Object.isNull(obj)) ()
                else commitString(state, keyPath, obj.toString())
            }
        });
        let p = new JPanel(new BorderLayout());
        p.setBackground(panelBg());
        p.add(combo, BorderLayout.CENTER);
        p

    // ──────────────────────────────────────────────────────
    // commit ヘルパ
    // ──────────────────────────────────────────────────────

    def commitInt(state: IdeState, keyPath: List[String], v: Int32): Unit \ IO =
        commitJson(state, keyPath, JsonNumber(intToBd(v)))

    def commitFloat(state: IdeState, keyPath: List[String], v: Float64): Unit \ IO =
        commitJson(state, keyPath, JsonNumber(floatToBd(v)))

    def commitString(state: IdeState, keyPath: List[String], s: String): Unit \ IO =
        commitJson(state, keyPath, JsonString(s))

    def commitBool(state: IdeState, keyPath: List[String], b: Bool): Unit \ IO =
        commitJson(state, keyPath, JsonBool(b))

    def commitJson(state: IdeState, keyPath: List[String], newValue: JsonElement): Unit \ IO =
        match ResourceState.getEditingJson(state#resource) {
            case None => ()
            case Some(json) =>
                let updated = JsonOps.setAtKeyPath(json, keyPath, newValue);
                ResourceState.setEditingJson(state#resource, Some(updated));
                ResourceState.setDirty(state#resource, true);
                SpritePreview.refresh(state)
        }

    // ──────────────────────────────────────────────────────
    // JSON 値の取り出し / クランプ
    // ──────────────────────────────────────────────────────

    def clampInt(v: Int32, lo: Int32, hi: Int32): Int32 =
        if (v < lo) lo else if (v > hi) hi else v

    def clampFloat(v: Float64, lo: Float64, hi: Float64): Float64 =
        if (v < lo) lo else if (v > hi) hi else v

    def jsonToInt(elem: JsonElement): Option[Int32] = match elem {
        case JsonNumber(bd) => BigDecimal.tryToFloat64(bd) |> Option.flatMap(Float64.tryToInt32)
        case _              => None
    }

    def jsonToFloat(elem: JsonElement): Option[Float64] = match elem {
        case JsonNumber(bd) => BigDecimal.tryToFloat64(bd)
        case _              => None
    }

    def jsonToString(elem: JsonElement): Option[String] = match elem {
        case JsonString(s) => Some(s)
        case _             => None
    }

    def jsonToBool(elem: JsonElement): Option[Bool] = match elem {
        case JsonBool(b) => Some(b)
        case _           => None
    }

    def intToBd(value: Int32): BigDecimal =
        unsafe IO {
            let stripped = JBigDecimal.valueOf(Int32.toFloat64(value)).stripTrailingZeros();
            if (stripped.scale() < 0) stripped.setScale(0) else stripped
        }

    def floatToBd(value: Float64): BigDecimal =
        unsafe IO {
            let stripped = JBigDecimal.valueOf(value).stripTrailingZeros();
            if (stripped.scale() < 0) stripped.setScale(0) else stripped
        }
}
