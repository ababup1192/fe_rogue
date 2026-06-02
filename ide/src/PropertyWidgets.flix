// PropertyWidgets — Property Panel / Inspector で使う schema 駆動の編集 widget 群と
// 共通ヘルパーを集めた module。
//
// 設計方針:
//   - widget 自体は ResourceState / NodeInspector のような上位の意味を知らない
//   - 編集確定時の処理は `onCommit` callback で呼び出し側が決める
//   - 結果として ResourcePanel (data path に書き戻す) と ScenePanel (pending queue に積む)
//     双方が同じ widget を再利用できる
//
// 提供するもの:
//   - addPropertyRow / addPropertyPlaceholder: property-row.fxml を使う行テンプレ
//   - withRef: Option Ref の Some 時だけ action を実行する小ヘルパー
//   - buildXxxWidget: kind ごとの編集 widget。すべて (value, onCommit) を取る
//   - buildVec2Widget: Vec2 (X, Y の Spinner ペア) widget。Inspector で使う
//   - addFieldRow + buildFieldWidget: Resource.FieldEntry に応じて行を組み立てる
//   - updateSpritePreview / findFirstSpriteRef: TexturePath 値から画像 preview を描く
//     (sprite ブロックの frame/hframes/vframes を見て該当セルだけを切り抜く)

mod PropertyWidgets {
    import java.io.File
    import java.lang.{Object => JObject}
    import java.math.{BigDecimal => JBigDecimal}
    import java.math.RoundingMode
    import javafx.util.StringConverter
    import javafx.collections.ObservableList
    import javafx.fxml.FXMLLoader
    import javafx.scene.Node
    import javafx.scene.image.Image
    import javafx.scene.canvas.Canvas
    import javafx.scene.canvas.GraphicsContext
    import javafx.scene.control.Button
    import javafx.scene.control.Label
    import javafx.scene.control.TextField
    import javafx.scene.control.TextArea
    import javafx.scene.control.CheckBox
    import javafx.scene.control.ColorPicker
    import javafx.scene.control.ComboBox
    import javafx.scene.control.ListView
    import javafx.scene.control.Spinner
    import javafx.scene.control.ToggleButton
    import javafx.scene.control.ToggleGroup
    import javafx.scene.control.Toggle
    import javafx.scene.paint.{Color => FxColor}
    import javafx.scene.layout.HBox
    import javafx.scene.layout.StackPane
    import javafx.scene.layout.VBox
    import javafx.geometry.Pos
    import javafx.event.ActionEvent
    import javafx.event.EventHandler
    import javafx.scene.input.MouseEvent
    import javafx.scene.input.ZoomEvent
    import javafx.beans.value.ChangeListener
    import javafx.beans.value.ObservableValue
    import java.lang.Double
    import java.lang.Integer
    import java.lang.Boolean

    /// 編集確定時の callback。受け取る側 (ResourcePanel / ScenePanel) が
    /// JSON を消費して書き戻し or pending queue に積む
    pub type alias Commit = Json.JsonElement -> Unit \ IO

    /// Resources タブ Preview の拡大モード。
    /// ネイティブピクセル基準のパーセント表示倍率（Float64 で連続値）。
    ///   100.0 = 1 image pixel = 1 logical screen pixel (IDE プレビュー上の等倍)、
    ///   200.0 = 2 倍拡大、50.0 = 半分縮小
    /// 注意: 「ゲームでの実際の見え方」は Sprite2D.scale / Camera2D.zoom /
    /// Viewport (design → window) の合成で決まるため、Resource (texture/frame/
    /// hframes/vframes) 単独では再現できない。この preview は texture アトラスの
    /// ピクセル自体を確認する用途
    pub enum ZoomMode with Eq, ToString {
        case Percent(Float64)
    }

    /// プロジェクト起動時 / ResourceState 初期化時のデフォルトズーム。
    /// 100% = ネイティブピクセル等倍 (1 image px = 1 logical px)
    pub def defaultZoom(): ZoomMode =
        ZoomMode.Percent(100.0)

    /// ZoomMode を UI 表示用の短い文字列にする ("100%" / "200%" ...)
    /// 小数倍率は整数に丸めて表示する（"103.5%" は冗長なので "104%"）。
    pub def zoomModeLabel(mode: ZoomMode): String =
        match mode {
            case ZoomMode.Percent(p) =>
                let rounded = Float64.tryToInt32(p) |> Option.getWithDefault(100i32);
                "${rounded}%"
        }

    /// ピンチズームの incremental factor（macOS trackpad の `ZoomEvent.getZoomFactor()`）
    /// を現倍率に乗算して新 ZoomMode を返す。範囲 [25%, 1600%] にクランプ。
    /// `Percent` は Float64 なので、小さな factor（1.01 程度）でも丸められず連続的に拡縮できる。
    pub def pinchZoom(mode: ZoomMode, factor: Float64): ZoomMode =
        match mode {
            case ZoomMode.Percent(p) => {
                let next = p * factor;
                let clamped =
                    if (next < 25.0) 25.0
                    else if (next > 1600.0) 1600.0
                    else next;
                ZoomMode.Percent(clamped)
            }
        }

    /// 共通テンプレ property-row.fxml をロードして「key Label + 値 slot」の HBox を返す
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

    /// 値の代わりに 1 行のプレースホルダ Label を追加する (例: "(no schema)")
    pub def addPropertyPlaceholder(children: ObservableList[Node], text: String): Unit \ IO = {
        let l = new Label(text);
        l.getStyleClass().add("inspector-empty");
        let n: Node = checked_cast(l);
        discard children.add(n)
    }

    /// Option Ref 共通: Some なら action を実行。None は no-op
    pub def withRef(ref: Array[Option[t], Static], action: t -> Unit \ ef): Unit \ ef + IO =
        match Array.get(0, ref) {
            case None    => ()
            case Some(v) => action(v)
        }

    /// FieldEntry の sort key: (order の値, key 名)。order が None なら最大値で末尾に
    pub def fieldOrderKey(p: (String, Resource.FieldEntry)): (Int32, String) =
        let (key, entry) = p;
        let ord = match entry {
            case Resource.FieldEntry.Field(fs) => Option.getWithDefault(Int32.maxValue(), fs#order)
            case _                             => Int32.maxValue()
        };
        (ord, key)

    /// 1 フィールドぶんを Property Panel に追加。型に応じて編集 widget を生成し、
    /// commit (Enter / CheckBox toggle) で `mkCommit(keyPath)` の callback を呼び出す。
    /// Nested は section header (太字 Label) を入れて内側を order 順で再帰展開する。
    /// `textureNames` は TexturePathT widget の ComboBox 候補 (state を参照しないため呼び出し側で渡す)
    /// `refOptions` は RefT widget の ComboBox 候補。key は schema の `{"type":"ref","to":target}` の
    /// `target` (= 参照先 catalog の containerKey)、value はその catalog の sub-entry id 一覧。
    pub def addFieldRow(children: ObservableList[Node],
                        key: String, entry: Resource.FieldEntry,
                        record: Json.JsonElement, basePath: List[String],
                        textureNames: List[String],
                        texturePathMap: Map[String, String],
                        refOptions: Map[String, List[String]],
                        mkCommit: List[String] -> Commit): Unit \ IO =
        addFieldRowWithRoot(children, key, entry, record, record, basePath,
                              textureNames, texturePathMap, refOptions, mkCommit)

    /// `addFieldRow` の内部実装。`rootRecord` は最初に呼ばれたときの「ユニット全体の record」で、
    /// Nested 再帰中も保持して widget 側に渡す（sibling 参照に使う）。
    /// `record` は現在の Nested レベルでの sub-record。
    def addFieldRowWithRoot(children: ObservableList[Node],
                             key: String, entry: Resource.FieldEntry,
                             record: Json.JsonElement, rootRecord: Json.JsonElement,
                             basePath: List[String],
                             textureNames: List[String],
                             texturePathMap: Map[String, String],
                             refOptions: Map[String, List[String]],
                             mkCommit: List[String] -> Commit): Unit \ IO =
        match entry {
            case Resource.FieldEntry.Field(fs) => {
                let value = jsonFieldOf(record, key);
                let keyPath = List.append(basePath, key :: Nil);
                let widget = buildFieldWidget(fs, value, rootRecord, textureNames,
                                                texturePathMap, refOptions, mkCommit(keyPath));
                addPropertyRow(children, "${fs#label}:", widget)
            }
            case Resource.FieldEntry.Nested(innerMap) => {
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
                    addFieldRowWithRoot(children, k, e, innerRecord, rootRecord, innerBasePath,
                                          textureNames, texturePathMap, refOptions, mkCommit)
                }, sortedInner)
            }
        }

    /// FieldType に応じた編集 widget を返す
    /// `rootRecord` はユニット全体の record。spriteFrames widget が sibling
    /// `sprite.hframes / vframes / texture` を引くために必要。
    def buildFieldWidget(fs: Resource.FieldSchema, value: Option[Json.JsonElement],
                         rootRecord: Json.JsonElement,
                         textureNames: List[String],
                         texturePathMap: Map[String, String],
                         refOptions: Map[String, List[String]],
                         commit: Commit): Node \ IO =
        match fs#ftype {
            case Resource.FieldType.TextT         =>
                match fs#hint {
                    case Resource.FieldHint.Multiline => buildMultilineTextWidget(value, commit)
                    case _                            => buildTextWidget(value, commit)
                }
            case Resource.FieldType.IntT          => buildIntWidget(value, commit)
            case Resource.FieldType.FloatT        => buildFloatWidget(value, commit)
            case Resource.FieldType.BoolT         => buildBoolWidget(value, commit)
            case Resource.FieldType.TexturePathT  => buildTexturePathWidget(value, textureNames, commit)
            case Resource.FieldType.SpriteFramesT =>
                SpriteFramesEditor.buildSpriteFramesEditorWidget(value, rootRecord, texturePathMap, commit)
            case Resource.FieldType.RefT(target)  =>
                let options = Map.get(target, refOptions) |> Option.getWithDefault(Nil);
                buildEnumWidget(value, options, commit)
            case Resource.FieldType.RefPercentListT(target) =>
                let options = Map.get(target, refOptions) |> Option.getWithDefault(Nil);
                RefListWidgets.buildRefPercentListWidget(value, options, commit)
            case Resource.FieldType.KindedRefListT(kinds) =>
                RefListWidgets.buildKindedRefListWidget(value, kinds, refOptions, commit)
            case Resource.FieldType.EnumT(values) =>
                // 2 値なら segmented toggle で両ラベル可視、3 値以上は ComboBox にフォールバック
                if (List.length(values) == 2) buildEnumToggleWidget(value, values, commit)
                else buildEnumWidget(value, values, commit)
        }

    /// TexturePathT: project 登録 texture から選択する ComboBox<String>
    pub def buildTexturePathWidget(value: Option[Json.JsonElement], textureNames: List[String],
                                    commit: Commit): Node \ IO = {
        let current = match value {
            case Some(Json.JsonElement.JsonString(s)) => s
            case _                                    => ""
        };
        let combo = makeStringComboBox(textureNames, current, 160.0,
            newVal -> commit(Json.JsonElement.JsonString(newVal)));
        combo.setMaxWidth(160.0);
        checked_cast(combo)
    }

    pub def buildTextWidget(value: Option[Json.JsonElement], commit: Commit): Node \ IO = {
        let current = match value {
            case Some(Json.JsonElement.JsonString(s)) => s
            case _                                    => ""
        };
        let field = new TextField(current);
        field.setPrefWidth(160.0);
        field.setMaxWidth(160.0);
        // Enter キー押下でコミット
        field.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO =
                commit(Json.JsonElement.JsonString(field.getText()))
        });
        // フォーカスを外した瞬間にもコミット (Enter を押し忘れたまま別 widget を
        // 触ったときに入力が消えるのを防ぐ)。値が変わってない場合も無害に再 commit
        field.focusedProperty().addListener(new ChangeListener[Boolean] {
            def changed(_this: ChangeListener[Boolean],
                         _obs: ObservableValue[JObject],
                         _old: Boolean, _new: Boolean): Unit \ IO =
                if (not field.isFocused())
                    commit(Json.JsonElement.JsonString(field.getText()))
                else ()
        });
        checked_cast(field)
    }

    /// Multiline テキスト: 複数行入力可能な TextArea。
    /// 用途: resource sub-entry の `description` 等、自由メモのフィールド。
    /// 単行 TextField と同じく Enter キーでも commit するが、改行を入れるには Shift+Enter
    /// を使う必要がある (TextArea のデフォルト挙動)。フォーカス外しでも commit
    pub def buildMultilineTextWidget(value: Option[Json.JsonElement], commit: Commit): Node \ IO = {
        let current = match value {
            case Some(Json.JsonElement.JsonString(s)) => s
            case _                                    => ""
        };
        let area = new TextArea(current);
        area.setPrefRowCount(3);
        area.setWrapText(true);
        area.setPrefWidth(220.0);
        area.setMaxWidth(220.0);
        // フォーカスを外した瞬間にコミット
        area.focusedProperty().addListener(new ChangeListener[Boolean] {
            def changed(_this: ChangeListener[Boolean],
                         _obs: ObservableValue[JObject],
                         _old: Boolean, _new: Boolean): Unit \ IO =
                if (not area.isFocused())
                    commit(Json.JsonElement.JsonString(area.getText()))
                else ()
        });
        checked_cast(area)
    }

    /// Int フィールド: Spinner<Integer>
    pub def buildIntWidget(value: Option[Json.JsonElement], commit: Commit): Node \ IO = {
        let current: Int32 = NodeInspector.jsonToInt(value |> Option.getWithDefault(Json.JsonElement.JsonNull))
                              |> Option.getWithDefault(0i32);
        let spinner = makeIntSpinner({min = -999999i32, max = 999999i32}, current, 110.0,
            v -> commit(NodeInspector.intToJson(v)));
        spinner.setMaxWidth(110.0);
        checked_cast(spinner)
    }

    /// Float Spinner の表示・入力丸めポリシー。
    /// ドラッグ操作などで `0.6845279517513342` のような過剰精度が混入することを防ぎ、
    /// scene.json にも 3 桁までしか書かれないようにする。
    /// 切り上げではなく HALF_UP (四捨五入) を採用。
    pub def roundTo3(v: Float64): Float64 =
        JBigDecimal.valueOf(v).setScale(3i32, RoundingMode.HALF_UP).doubleValue()

    /// `roundTo3` を通したあと末尾 0 を落として表示文字列にする。
    /// `1.0` → `"1"`、`0.5` → `"0.5"`、`0.6845...` → `"0.685"`。
    def formatRoundedFloat(v: Float64): String =
        unsafe IO {
            JBigDecimal.valueOf(roundTo3(v)).stripTrailingZeros().toPlainString()
        }

    /// Spinner[Double] 用 StringConverter。表示は formatRoundedFloat、
    /// 入力は parseDouble → roundTo3。parse 失敗時は 0.0 にフォールバック
    /// (JavaFX 既定の挙動と違うが、Inspector では Enter 押下時に必ず数値が確定する方が望ましい)。
    pub def roundedDoubleConverter(): StringConverter[Double] \ IO =
        new StringConverter[Double] {
            def toString(_this: StringConverter[Double], value: Double): String =
                if (Object.isNull(value)) ""
                else formatRoundedFloat(value.doubleValue())
            def fromString(_this: StringConverter[Double], s: String): Double = {
                let trimmed = String.trim(s);
                if (String.length(trimmed) == 0) Double.valueOf(0.0)
                else match Float64.fromString(trimmed) {
                    case Some(v) => Double.valueOf(roundTo3(v))
                    case None    => Double.valueOf(0.0)
                }
            }
        }

    /// String 値の ComboBox を生成する具体型固定ヘルパ。
    /// options を getItems().add で追加し、editable=false / setValue(initial) / setPrefWidth を設定。
    /// valueProperty().addListener の ChangeListener[String] は inline で定義し、
    /// null チェック (Object.isNull) を内部に閉じ込め、非 null 時のみ onChanged を呼ぶ。
    /// setMaxWidth が要る呼び出し側は返り値に対して別途設定すること (ここでは設定しない)。
    pub def makeStringComboBox(options: List[String], initial: String, prefWidth: Float64,
                            onChanged: String -> Unit \ IO): ComboBox[String] \ IO = {
        let combo: ComboBox[String] = new ComboBox();
        let items = combo.getItems();
        List.forEach(o -> discard items.add(o), options);
        combo.setEditable(false);
        combo.setValue(initial);
        combo.setPrefWidth(prefWidth);
        combo.valueProperty().addListener(new ChangeListener[String] {
            def changed(_cThis: ChangeListener[String], _obs: ObservableValue[JObject],
                         _old: String, newVal: String): Unit \ IO = {
                if (Object.isNull(newVal)) ()
                else onChanged(newVal)
            }
        });
        combo
    }

    /// Int32 用 Spinner[Integer] を生成する具体型固定ヘルパ。
    /// editable=true / setPrefWidth を設定。valueProperty().addListener の
    /// ChangeListener[Integer] は inline で定義し、newVal.intValue() を onChanged に渡す。
    pub def makeIntSpinner(range: {min = Int32, max = Int32}, initial: Int32, prefWidth: Float64,
                        onChanged: Int32 -> Unit \ IO): Spinner[Integer] \ IO = {
        let spinner: Spinner[Integer] = new Spinner(range#min, range#max, initial);
        spinner.setEditable(true);
        spinner.setPrefWidth(prefWidth);
        spinner.valueProperty().addListener(new ChangeListener[Integer] {
            def changed(_cThis: ChangeListener[Integer], _obs: ObservableValue[JObject],
                         _old: Integer, newVal: Integer): Unit \ IO = {
                let v: Int32 = newVal.intValue();
                onChanged(v)
            }
        });
        spinner
    }

    /// Float64 用 Spinner[Double] を生成する具体型固定ヘルパ。
    /// editable=true / setPrefWidth / 3 桁丸めコンバータ (roundedDoubleConverter) を設定。
    /// valueProperty().addListener の ChangeListener[Double] は inline で定義し、
    /// roundTo3(newVal.doubleValue()) を onChanged に渡す。
    def makeDoubleSpinner(range: {min = Float64, max = Float64, step = Float64}, initial: Float64,
                           prefWidth: Float64, onChanged: Float64 -> Unit \ IO): Spinner[Double] \ IO = {
        let spinner: Spinner[Double] = new Spinner(range#min, range#max, initial, range#step);
        spinner.setEditable(true);
        spinner.setPrefWidth(prefWidth);
        spinner.getValueFactory().setConverter(roundedDoubleConverter());
        spinner.valueProperty().addListener(new ChangeListener[Double] {
            def changed(_cThis: ChangeListener[Double], _obs: ObservableValue[JObject],
                         _old: Double, newVal: Double): Unit \ IO = {
                let v: Float64 = roundTo3(newVal.doubleValue());
                onChanged(v)
            }
        });
        spinner
    }

    /// Float フィールド: Spinner<Double> (step 0.1)。
    /// 表示・入力・commit すべて 3 桁丸めポリシーで統一する (roundedDoubleConverter 参照)。
    pub def buildFloatWidget(value: Option[Json.JsonElement], commit: Commit): Node \ IO = {
        let raw: Float64 = NodeInspector.jsonToFloat(value |> Option.getWithDefault(Json.JsonElement.JsonNull))
                            |> Option.getWithDefault(0.0);
        let current = roundTo3(raw);
        let spinner = makeDoubleSpinner({min = -999999.0, max = 999999.0, step = 0.1}, current, 110.0,
            v -> commit(NodeInspector.floatToJson(v)));
        spinner.setMaxWidth(110.0);
        checked_cast(spinner)
    }

    /// 2 値 enum 用の segmented toggle widget。両ラベルを同時表示し、
    /// クリックでアクティブ側だけ select 状態にする。`ToggleGroup` で
    /// 片方しか押せないことを保証。値は JSON 文字列 (選択中ボタンのラベル) として commit する。
    /// CheckBox の「チェック有無」と違って、未選択側のラベルも常に見えるので
    /// 「ON 時は何で OFF 時は何か」をユーザーが推測する必要がない。
    pub def buildEnumToggleWidget(value: Option[Json.JsonElement], options: List[String],
                                    commit: Commit): Node \ IO = {
        let current = match value {
            case Some(Json.JsonElement.JsonString(s)) => s
            case _ => List.head(options) |> Option.getWithDefault("")
        };
        let group = new ToggleGroup();
        let box = new HBox();
        box.setSpacing(0.0);
        let children = box.getChildren();
        List.forEach(label -> {
            let btn = new ToggleButton(label);
            btn.setToggleGroup(group);
            btn.setPrefWidth(70.0);
            if (label == current) btn.setSelected(true) else ();
            // クリックで commit。`setOnAction` は選択状態変更時に必ず呼ばれる。
            // ただし同じボタンを再クリックして deselect されると null になるため、
            // ToggleGroup.selectedToggleProperty で「現在の選択 toggle」を監視する。
            let btnNode: Node = checked_cast(btn);
            discard children.add(btnNode)
        }, options);
        // ToggleGroup の selectedToggle 変化を subscribe して commit。
        // 同じボタンを再クリックすると newVal が null になり「全 deselect」状態になるが、
        // 2 値選択 UI としては片方が常に選択されているほうが自然なので、その場合は
        // 旧 toggle を再選択して状態を戻す。
        group.selectedToggleProperty().addListener(new ChangeListener[Toggle] {
            def changed(_cThis: ChangeListener[Toggle], _obs: ObservableValue[JObject],
                         oldVal: Toggle, newVal: Toggle): Unit \ IO =
                if (Object.isNull(newVal)) {
                    if (not Object.isNull(oldVal)) {
                        let oldBtn: ToggleButton = unchecked_cast(oldVal as ToggleButton);
                        oldBtn.setSelected(true)
                    } else ()
                } else {
                    let btn: ToggleButton = unchecked_cast(newVal as ToggleButton);
                    commit(Json.JsonElement.JsonString(btn.getText()))
                }
        });
        checked_cast(box)
    }

    /// Enum widget: 有限の選択肢を持つ ComboBox<String>。値は JSON 文字列。
    /// SceneLoader 側が "Left" / "Center" 等のラベルから enum 値を parse する想定
    pub def buildEnumWidget(value: Option[Json.JsonElement], options: List[String],
                             commit: Commit): Node \ IO = {
        let current = match value {
            case Some(Json.JsonElement.JsonString(s)) => s
            case _ => List.head(options) |> Option.getWithDefault("")
        };
        let combo = makeStringComboBox(options, current, 140.0,
            newVal -> commit(Json.JsonElement.JsonString(newVal)));
        combo.setMaxWidth(140.0);
        checked_cast(combo)
    }

    /// Color widget: JavaFX ColorPicker。値は JsonObject{"r","g","b"} (Float64 各 0-1)。
    /// valueProperty listener で newVal を直接受け取る (setOnAction の getValue() は
    /// JavaFX のタイミングで古い値を返すことがあるため)。
    /// 自前の setValue で listener が再発火するのを防ぐため `suppressNextRef` で抑制
    pub def buildColorWidget(value: Option[Json.JsonElement], commit: Commit): Node \ IO = {
        let init = NodeInspector.jsonToColor(value |> Option.getWithDefault(Json.JsonElement.JsonNull))
                    |> Option.getWithDefault({r = 1.0f32, g = 1.0f32, b = 1.0f32});
        let picker: ColorPicker = new ColorPicker(
            FxColor.color(Float32.toFloat64(init#r),
                          Float32.toFloat64(init#g),
                          Float32.toFloat64(init#b)));
        picker.setPrefWidth(140.0);
        picker.valueProperty().addListener(new ChangeListener[FxColor] {
            def changed(_cThis: ChangeListener[FxColor], _obs: ObservableValue[JObject],
                         _old: FxColor, newVal: FxColor): Unit \ IO = {
                if (Object.isNull(newVal)) ()
                else {
                    let r = Float64.tryToFloat32(newVal.getRed())   |> Option.getWithDefault(1.0f32);
                    let g = Float64.tryToFloat32(newVal.getGreen()) |> Option.getWithDefault(1.0f32);
                    let b = Float64.tryToFloat32(newVal.getBlue())  |> Option.getWithDefault(1.0f32);
                    println("[ColorPicker] commit r=${r} g=${g} b=${b}");
                    commit(NodeInspector.colorToJson({r = r, g = g, b = b}))
                }
            }
        });
        checked_cast(picker)
    }

    pub def buildBoolWidget(value: Option[Json.JsonElement], commit: Commit): Node \ IO = {
        let current = NodeInspector.jsonToBool(value |> Option.getWithDefault(Json.JsonElement.JsonNull))
                       |> Option.getWithDefault(false);
        let check = new CheckBox();
        check.setSelected(current);
        check.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO =
                commit(NodeInspector.boolToJson(check.isSelected()))
        });
        checked_cast(check)
    }

    /// Vec2 widget: X / Y 2 つの Spinner を VBox に縦に並べ、軸ラベル付きで表示する。
    /// 1 行に詰めると 3-4 桁数値が欠ける問題を回避する。一方が変わると現在の (X, Y) ペアを
    /// JsonObject{"x":x, "y":y} として commit する。
    /// `isInt` true で整数 Spinner、false で float Spinner (step 0.1)
    pub def buildVec2Widget(value: Option[Json.JsonElement], isInt: Bool,
                             commit: Commit): Node \ IO = {
        let (initX, initY) = NodeInspector.jsonToVec2(value |> Option.getWithDefault(Json.JsonElement.JsonNull))
                              |> Option.map(v -> (v#x, v#y))
                              |> Option.getWithDefault((0.0, 0.0));
        if (isInt) {
            let ix = Float64.tryToInt32(initX) |> Option.getWithDefault(0i32);
            let iy = Float64.tryToInt32(initY) |> Option.getWithDefault(0i32);
            let xs: Spinner[Integer] = new Spinner(-999999i32, 999999i32, ix);
            let ys: Spinner[Integer] = new Spinner(-999999i32, 999999i32, iy);
            xs.setEditable(true); ys.setEditable(true);
            xs.setPrefWidth(140.0); ys.setPrefWidth(140.0);
            let commitBoth = () -> {
                let x: Float64 = Int32.toFloat64(xs.getValue().intValue());
                let y: Float64 = Int32.toFloat64(ys.getValue().intValue());
                commit(NodeInspector.vec2ToJson({x = x, y = y}))
            };
            xs.valueProperty().addListener(new ChangeListener[Integer] {
                def changed(_cThis: ChangeListener[Integer], _obs: ObservableValue[JObject],
                             _old: Integer, _newVal: Integer): Unit \ IO = commitBoth()
            });
            ys.valueProperty().addListener(new ChangeListener[Integer] {
                def changed(_cThis: ChangeListener[Integer], _obs: ObservableValue[JObject],
                             _old: Integer, _newVal: Integer): Unit \ IO = commitBoth()
            });
            assembleVec2Box(checked_cast(xs), checked_cast(ys))
        } else {
            let initXR = roundTo3(initX);
            let initYR = roundTo3(initY);
            // 両成分の Spinner を Static 配列に保持し、片方の変更時に他方の現在値も読んで
            // 同時に commit する (元コードの commitBoth と等価)。配列に入れるのは
            // makeDoubleSpinner 内 listener が両 Spinner 生成前に登録されるため。
            let xsRef: Array[Option[Spinner[Double]], Static] = Array#{(None: Option[Spinner[Double]])} @ Static;
            let ysRef: Array[Option[Spinner[Double]], Static] = Array#{(None: Option[Spinner[Double]])} @ Static;
            let commitBoth = () -> match (Array.get(0, xsRef), Array.get(0, ysRef)) {
                case (Some(xs), Some(ys)) => {
                    let x: Float64 = roundTo3(xs.getValue().doubleValue());
                    let y: Float64 = roundTo3(ys.getValue().doubleValue());
                    commit(NodeInspector.vec2ToJson({x = x, y = y}))
                }
                case _ => ()
            };
            let xs = makeDoubleSpinner({min = -999999.0, max = 999999.0, step = 0.1}, initXR, 140.0,
                _v -> commitBoth());
            let ys = makeDoubleSpinner({min = -999999.0, max = 999999.0, step = 0.1}, initYR, 140.0,
                _v -> commitBoth());
            Array.put(Some(xs), 0, xsRef);
            Array.put(Some(ys), 0, ysRef);
            assembleVec2Box(checked_cast(xs), checked_cast(ys))
        }
    }

    /// Vec2 widget の枠組み (VBox に「X: spinner」「Y: spinner」を縦に並べた構造)。
    /// 更新側 (ScenePanel.updateVec2Widget) もこの構造前提で内側 Spinner を引き直す
    def assembleVec2Box(xSpinner: Node, ySpinner: Node): Node \ IO = {
        let xLabel = new Label("X:");
        let yLabel = new Label("Y:");
        xLabel.getStyleClass().add("vec2-axis");
        yLabel.getStyleClass().add("vec2-axis");
        let xRow = new HBox(4.0);
        let yRow = new HBox(4.0);
        xRow.setAlignment(Pos.CENTER_LEFT);
        yRow.setAlignment(Pos.CENTER_LEFT);
        let xLn: Node = checked_cast(xLabel);
        let yLn: Node = checked_cast(yLabel);
        discard xRow.getChildren().add(xLn);
        discard xRow.getChildren().add(xSpinner);
        discard yRow.getChildren().add(yLn);
        discard yRow.getChildren().add(ySpinner);
        let vbox = new VBox(2.0);
        let xRn: Node = checked_cast(xRow);
        let yRn: Node = checked_cast(yRow);
        discard vbox.getChildren().add(xRn);
        discard vbox.getChildren().add(yRn);
        checked_cast(vbox)
    }

    def jsonFieldOf(record: Json.JsonElement, key: String): Option[Json.JsonElement] =
        match record {
            case Json.JsonElement.JsonObject(m) => Map.get(key, m)
            case _                              => None
        }
}
