// SchemaWidgets — Resource.ResourceSchema を walk して widget を組み立てる
//
// 全ての build* / widget 関数は JPanel を返す (Flix の Java interop で subtype を扱わないため、
// 各 widget は 1 セルの JPanel に包む)。
//
// FieldType × FieldHint の組合せから Swing コンポーネントへディスパッチ。各 widget は
// change event で:
//   1. ResourceState.editingJsonRef を JsonOps.setAtKeyPath で更新
//   2. ResourceState.dirtyRef := true

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
    import javax.swing.BorderFactory
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

    /// schema を walk して 1 つの縦並び panel を作る。
    /// keyPathPrefix: catalog 時は `[containerKey, subEntryKey]`、single 時は空。
    pub def buildPanel(state: IdeState, schema: ResourceSchema, keyPathPrefix: List[String]):
            JPanel \ IO =
        let panel = new JPanel();
        panel.setLayout(new BoxLayout(panel, BoxLayout.Y_AXIS));
        panel.setBackground(new Color(45, 45, 45));

        let fields = Resource.fieldsOf(schema);
        Map.forEach((name, entry) -> {
            let row = buildEntry(state, name, entry, keyPathPrefix);
            row.setAlignmentX(0.0f32);
            panel.add(row);
            ()
        }, fields);
        panel

    def buildEntry(state: IdeState, name: String, entry: FieldEntry, keyPathPrefix: List[String]):
            JPanel \ IO =
        match entry {
            case FieldEntry.Field(fs) =>
                buildField(state, name, fs, keyPathPrefix)
            case FieldEntry.Nested(m) =>
                buildNested(state, name, m, keyPathPrefix)
        }

    def buildNested(state: IdeState, name: String, fields: Map[String, FieldEntry],
                    keyPathPrefix: List[String]): JPanel \ IO =
        let outer = new JPanel(new BorderLayout());
        outer.setBackground(new Color(45, 45, 45));
        outer.setBorder(BorderFactory.createEmptyBorder(8, 4, 4, 4));

        let header = new JLabel("── ${name} ──");
        header.setForeground(new Color(180, 180, 200));
        outer.add(header, BorderLayout.NORTH);

        let inner = new JPanel();
        inner.setLayout(new BoxLayout(inner, BoxLayout.Y_AXIS));
        inner.setBackground(new Color(45, 45, 45));
        let newPrefix = keyPathPrefix ::: (name :: Nil);
        Map.forEach((childName, childEntry) -> {
            let row = buildEntry(state, childName, childEntry, newPrefix);
            row.setAlignmentX(0.0f32);
            inner.add(row);
            ()
        }, fields);
        outer.add(inner, BorderLayout.CENTER);
        outer

    def buildField(state: IdeState, name: String, fs: FieldSchema, keyPathPrefix: List[String]):
            JPanel \ IO =
        let keyPath = keyPathPrefix ::: (name :: Nil);
        let row = new JPanel(new BorderLayout(8, 0));
        row.setBackground(new Color(45, 45, 45));
        row.setBorder(BorderFactory.createEmptyBorder(2, 4, 2, 4));

        let label = new JLabel(fs#label);
        label.setForeground(Color.LIGHT_GRAY);
        label.setPreferredSize(new Dimension(110, 24));
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
    // 個別 widget (全て JPanel に包んで返す)
    // ──────────────────────────────────────────────────────

    def currentValue(state: IdeState, keyPath: List[String]): Option[JsonElement] \ IO =
        ResourceState.getEditingJson(state#resource)
            |> Option.flatMap(json -> JsonOps.getAtKeyPath(json, keyPath))

    /// 値を [min, max] にクランプ。schema の範囲外な data 値や、+ Add で生成された
    /// デフォルト 0 が slider の min=1 を下回るケースで JSlider/SpinnerNumberModel が
    /// IllegalArgumentException を投げるのを防ぐ。
    def clampInt(v: Int32, lo: Int32, hi: Int32): Int32 =
        if (v < lo) lo else if (v > hi) hi else v

    def clampFloat(v: Float64, lo: Float64, hi: Float64): Float64 =
        if (v < lo) lo else if (v > hi) hi else v

    def intSlider(state: IdeState, keyPath: List[String],
                  spec: {min = Float64, max = Float64, step = Float64}): JPanel \ IO =
        let minI = Float64.tryToInt32(spec#min) |> Option.getWithDefault(0);
        let maxI = Float64.tryToInt32(spec#max) |> Option.getWithDefault(100);
        let raw = currentValue(state, keyPath) |> Option.flatMap(jsonToInt) |> Option.getWithDefault(minI);
        let current = clampInt(raw, minI, maxI);
        let slider = new JSlider(minI, maxI, current);
        slider.setBackground(new Color(45, 45, 45));
        slider.addChangeListener(new ChangeListener {
            def stateChanged(_this: ChangeListener, _e: ChangeEvent): Unit \ IO = {
                let v = slider.getValue();
                commitInt(state, keyPath, v)
            }
        });
        let p = new JPanel(new BorderLayout());
        p.setBackground(new Color(45, 45, 45));
        p.add(slider, BorderLayout.CENTER);
        p

    def intSpinner(state: IdeState, keyPath: List[String],
                   spec: {min = Int32, max = Int32}): JPanel \ IO =
        let raw = currentValue(state, keyPath) |> Option.flatMap(jsonToInt) |> Option.getWithDefault(spec#min);
        let current = clampInt(raw, spec#min, spec#max);
        let model = new SpinnerNumberModel(current, spec#min, spec#max, 1);
        let spinner = new JSpinner(model);
        spinner.addChangeListener(new ChangeListener {
            def stateChanged(_this: ChangeListener, _e: ChangeEvent): Unit \ IO = {
                let v = model.getNumber().intValue();
                commitInt(state, keyPath, v)
            }
        });
        let p = new JPanel(new BorderLayout());
        p.setBackground(new Color(45, 45, 45));
        p.add(spinner, BorderLayout.CENTER);
        p

    def intSpinnerOpen(state: IdeState, keyPath: List[String]): JPanel \ IO =
        let raw = currentValue(state, keyPath) |> Option.flatMap(jsonToInt) |> Option.getWithDefault(0);
        let current = clampInt(raw, -10000, 10000);
        let model = new SpinnerNumberModel(current, -10000, 10000, 1);
        let spinner = new JSpinner(model);
        spinner.addChangeListener(new ChangeListener {
            def stateChanged(_this: ChangeListener, _e: ChangeEvent): Unit \ IO = {
                let v = model.getNumber().intValue();
                commitInt(state, keyPath, v)
            }
        });
        let p = new JPanel(new BorderLayout());
        p.setBackground(new Color(45, 45, 45));
        p.add(spinner, BorderLayout.CENTER);
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
        slider.setBackground(new Color(45, 45, 45));
        slider.addChangeListener(new ChangeListener {
            def stateChanged(_this: ChangeListener, _e: ChangeEvent): Unit \ IO = {
                let v = fromSliderVal(slider.getValue());
                commitFloat(state, keyPath, v)
            }
        });
        let p = new JPanel(new BorderLayout());
        p.setBackground(new Color(45, 45, 45));
        p.add(slider, BorderLayout.CENTER);
        p

    def floatSpinner(state: IdeState, keyPath: List[String]): JPanel \ IO =
        let raw = currentValue(state, keyPath)
            |> Option.flatMap(jsonToFloat)
            |> Option.getWithDefault(0.0);
        let current = clampFloat(raw, -100000.0, 100000.0);
        let model = new SpinnerNumberModel(current, -100000.0, 100000.0, 0.1);
        let spinner = new JSpinner(model);
        spinner.addChangeListener(new ChangeListener {
            def stateChanged(_this: ChangeListener, _e: ChangeEvent): Unit \ IO = {
                let v = model.getNumber().doubleValue();
                commitFloat(state, keyPath, v)
            }
        });
        let p = new JPanel(new BorderLayout());
        p.setBackground(new Color(45, 45, 45));
        p.add(spinner, BorderLayout.CENTER);
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
        p.setBackground(new Color(45, 45, 45));
        p.add(field, BorderLayout.CENTER);
        p

    def boolCheck(state: IdeState, keyPath: List[String]): JPanel \ IO =
        let current = currentValue(state, keyPath) |> Option.flatMap(jsonToBool) |> Option.getWithDefault(false);
        let check = new JCheckBox("", current);
        check.setBackground(new Color(45, 45, 45));
        check.addActionListener(new ActionListener {
            def actionPerformed(_this: ActionListener, _e: ActionEvent): Unit \ IO =
                commitBool(state, keyPath, check.isSelected())
        });
        let p = new JPanel(new BorderLayout());
        p.setBackground(new Color(45, 45, 45));
        p.add(check, BorderLayout.CENTER);
        p

    def textureDropdown(state: IdeState, keyPath: List[String]): JPanel \ IO =
        let map = IdeState.getTexturePathMap(state);
        let names = Map.keysOf(map) |> Set.toList;
        let current = currentValue(state, keyPath) |> Option.flatMap(jsonToString);
        let combo: JComboBox[String] = new JComboBox();
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
        p.setBackground(new Color(45, 45, 45));
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
                // sprite-like nested の値が変わった可能性。preview を再描画
                SpritePreview.refresh(state)
        }

    // ──────────────────────────────────────────────────────
    // JSON 値の取り出し
    // ──────────────────────────────────────────────────────

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
