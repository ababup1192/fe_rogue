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

    /// Sprite preview に渡す表示情報。
    ///   - texture:  textureNames に登録されている texture 名
    ///   - frame / hframes / vframes: 同じオブジェクト内に sibling として並ぶ
    ///     アトラス分割情報。sprite ブロックが無く texture だけの record では
    ///     全て None になり、preview 側で 1, 1, 0 にフォールバックして
    ///     画像全体を表示する。
    ///   - offsetX / offsetY: 同じ object 内に `"offset": {"x": ..., "y": ...}`
    ///     としてあれば取り出す。preview ではセルクロップ後の描画位置にオフセットを
    ///     image-pixel 単位で加算する（zoom と同じスケールで拡大される）。
    pub type alias SpriteRef = {
        texture  = String,
        frame    = Option[Int32],
        hframes  = Option[Int32],
        vframes  = Option[Int32],
        offsetX  = Float64,
        offsetY  = Float64
    }

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
                buildSpriteFramesEditorWidget(value, rootRecord, texturePathMap, commit)
            case Resource.FieldType.RefT(target)  =>
                let options = Map.get(target, refOptions) |> Option.getWithDefault(Nil);
                buildEnumWidget(value, options, commit)
            case Resource.FieldType.RefPercentListT(target) =>
                let options = Map.get(target, refOptions) |> Option.getWithDefault(Nil);
                buildRefPercentListWidget(value, options, commit)
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
        let combo: ComboBox[String] = new ComboBox();
        let items = combo.getItems();
        List.forEach(name -> discard items.add(name), textureNames);
        combo.setEditable(false);
        combo.setValue(current);
        combo.setPrefWidth(160.0);
        combo.setMaxWidth(160.0);
        combo.valueProperty().addListener(new ChangeListener[String] {
            def changed(_cThis: ChangeListener[String], _obs: ObservableValue[JObject],
                         _old: String, newVal: String): Unit \ IO = {
                if (Object.isNull(newVal)) ()
                else commit(Json.JsonElement.JsonString(newVal))
            }
        });
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
        let spinner: Spinner[Integer] = new Spinner(-999999i32, 999999i32, current);
        spinner.setEditable(true);
        spinner.setPrefWidth(110.0);
        spinner.setMaxWidth(110.0);
        spinner.valueProperty().addListener(new ChangeListener[Integer] {
            def changed(_cThis: ChangeListener[Integer], _obs: ObservableValue[JObject],
                         _old: Integer, newVal: Integer): Unit \ IO = {
                let v: Int32 = newVal.intValue();
                commit(NodeInspector.intToJson(v))
            }
        });
        checked_cast(spinner)
    }

    /// Float Spinner の表示・入力丸めポリシー。
    /// ドラッグ操作などで `0.6845279517513342` のような過剰精度が混入することを防ぎ、
    /// scene.json にも 3 桁までしか書かれないようにする。
    /// 切り上げではなく HALF_UP (四捨五入) を採用。
    def roundTo3(v: Float64): Float64 =
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
    def roundedDoubleConverter(): StringConverter[Double] \ IO =
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

    /// Float フィールド: Spinner<Double> (step 0.1)。
    /// 表示・入力・commit すべて 3 桁丸めポリシーで統一する (roundedDoubleConverter 参照)。
    pub def buildFloatWidget(value: Option[Json.JsonElement], commit: Commit): Node \ IO = {
        let raw: Float64 = NodeInspector.jsonToFloat(value |> Option.getWithDefault(Json.JsonElement.JsonNull))
                            |> Option.getWithDefault(0.0);
        let current = roundTo3(raw);
        let spinner: Spinner[Double] = new Spinner(-999999.0, 999999.0, current, 0.1);
        spinner.setEditable(true);
        spinner.setPrefWidth(110.0);
        spinner.setMaxWidth(110.0);
        spinner.getValueFactory().setConverter(roundedDoubleConverter());
        spinner.valueProperty().addListener(new ChangeListener[Double] {
            def changed(_cThis: ChangeListener[Double], _obs: ObservableValue[JObject],
                         _old: Double, newVal: Double): Unit \ IO = {
                let v: Float64 = roundTo3(newVal.doubleValue());
                commit(NodeInspector.floatToJson(v))
            }
        });
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
        let combo: ComboBox[String] = new ComboBox();
        let items = combo.getItems();
        List.forEach(o -> discard items.add(o), options);
        combo.setEditable(false);
        combo.setValue(current);
        combo.setPrefWidth(140.0);
        combo.setMaxWidth(140.0);
        combo.valueProperty().addListener(new ChangeListener[String] {
            def changed(_cThis: ChangeListener[String], _obs: ObservableValue[JObject],
                         _old: String, newVal: String): Unit \ IO = {
                if (Object.isNull(newVal)) ()
                else commit(Json.JsonElement.JsonString(newVal))
            }
        });
        checked_cast(combo)
    }

    /// RefPercentListT widget: 動的長の `[{id: <ref>, percent: 0-100}]` 配列を編集する。
    /// 行ごとに ComboBox (ref dropdown) + Spinner (percent) + 削除ボタン、最下段に追加ボタン
    /// と合計表示。Add / Remove は VBox を再描画、value 変更は in-place で commit + 合計
    /// ラベル更新のみ (Spinner / ComboBox が壊れないように)
    pub def buildRefPercentListWidget(value: Option[Json.JsonElement],
                                        options: List[String],
                                        commit: Commit): Node \ IO = {
        let initial = parseRefPercentRows(value);
        let rowsRef: Array[List[(String, Int32)], Static] = Array#{initial} @ Static;
        let sumLabelRef: Array[Option[Label], Static] = Array#{(None: Option[Label])} @ Static;
        let outer = new VBox(4.0);
        outer.getStyleClass().add("ref-percent-list");
        renderRefPercentList(outer, rowsRef, sumLabelRef, options, commit);
        checked_cast(outer)
    }

    /// outer の子をクリアして再描画。Add/Remove のたびに呼ぶ
    def renderRefPercentList(outer: VBox,
                              rowsRef: Array[List[(String, Int32)], Static],
                              sumLabelRef: Array[Option[Label], Static],
                              options: List[String],
                              commit: Commit): Unit \ IO = {
        let children = outer.getChildren();
        children.clear();
        let rows = Array.get(0, rowsRef);
        renderRefPercentListRows(0i32, rows, outer, rowsRef, sumLabelRef, options, commit);
        // 追加ボタン
        let addBtn = new Button("＋ 追加");
        addBtn.getStyleClass().add("catalog-btn");
        addBtn.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO = {
                let cur = Array.get(0, rowsRef);
                let firstOpt = List.head(options) |> Option.getWithDefault("");
                let newRows = List.append(cur, (firstOpt, 0i32) :: Nil);
                Array.put(newRows, 0, rowsRef);
                renderRefPercentList(outer, rowsRef, sumLabelRef, options, commit);
                commitRefPercentRows(rowsRef, commit)
            }
        });
        let addNode: Node = checked_cast(addBtn);
        discard children.add(addNode);
        // 合計ラベル
        let sum = sumPercents(rows);
        let lbl = new Label(formatSumLabel(sum));
        lbl.getStyleClass().add("ref-percent-sum");
        Array.put(Some(lbl), 0, sumLabelRef);
        let lblNode: Node = checked_cast(lbl);
        discard children.add(lblNode)
    }

    /// 各行 (HBox) を VBox に append する。idx は再描画のたびに 0 から数え直し
    def renderRefPercentListRows(idx: Int32, remaining: List[(String, Int32)],
                                  outer: VBox,
                                  rowsRef: Array[List[(String, Int32)], Static],
                                  sumLabelRef: Array[Option[Label], Static],
                                  options: List[String],
                                  commit: Commit): Unit \ IO =
        match remaining {
            case Nil => ()
            case (id, pct) :: rest => {
                let row = buildRefPercentRow(idx, id, pct, outer, rowsRef, sumLabelRef,
                                              options, commit);
                let rowNode: Node = checked_cast(row);
                discard outer.getChildren().add(rowNode);
                renderRefPercentListRows(idx + 1i32, rest, outer, rowsRef, sumLabelRef,
                                          options, commit)
            }
        }

    /// 1 行ぶん: [ComboBox] [Spinner] % [✕]
    def buildRefPercentRow(idx: Int32, id: String, pct: Int32, outer: VBox,
                            rowsRef: Array[List[(String, Int32)], Static],
                            sumLabelRef: Array[Option[Label], Static],
                            options: List[String],
                            commit: Commit): HBox \ IO = {
        let row = new HBox(4.0);
        row.setAlignment(Pos.CENTER_LEFT);
        // ComboBox
        let combo: ComboBox[String] = new ComboBox();
        let items = combo.getItems();
        List.forEach(o -> discard items.add(o), options);
        combo.setEditable(false);
        combo.setValue(id);
        combo.setPrefWidth(140.0);
        combo.valueProperty().addListener(new ChangeListener[String] {
            def changed(_this: ChangeListener[String], _obs: ObservableValue[JObject],
                         _old: String, newVal: String): Unit \ IO = {
                if (Object.isNull(newVal)) ()
                else {
                    let cur = Array.get(0, rowsRef);
                    let curPct = nthPercent(idx, cur);
                    Array.put(replaceRowAt(idx, (newVal, curPct), cur), 0, rowsRef);
                    commitRefPercentRows(rowsRef, commit);
                    updateSumLabel(rowsRef, sumLabelRef)
                }
            }
        });
        // Spinner (percent)
        let spinner: Spinner[Integer] = new Spinner(0i32, 100i32, pct);
        spinner.setEditable(true);
        spinner.setPrefWidth(80.0);
        spinner.valueProperty().addListener(new ChangeListener[Integer] {
            def changed(_this: ChangeListener[Integer], _obs: ObservableValue[JObject],
                         _old: Integer, newVal: Integer): Unit \ IO = {
                let v: Int32 = newVal.intValue();
                let cur = Array.get(0, rowsRef);
                let curId = nthId(idx, cur);
                Array.put(replaceRowAt(idx, (curId, v), cur), 0, rowsRef);
                commitRefPercentRows(rowsRef, commit);
                updateSumLabel(rowsRef, sumLabelRef)
            }
        });
        let pctLbl = new Label("%");
        // Remove ボタン
        let removeBtn = new Button("✕");
        removeBtn.getStyleClass().add("catalog-btn");
        removeBtn.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO = {
                let cur = Array.get(0, rowsRef);
                Array.put(removeRowAt(idx, cur), 0, rowsRef);
                renderRefPercentList(outer, rowsRef, sumLabelRef, options, commit);
                commitRefPercentRows(rowsRef, commit)
            }
        });
        let children = row.getChildren();
        let comboNode:  Node = checked_cast(combo);
        let spinNode:   Node = checked_cast(spinner);
        let pctLblNode: Node = checked_cast(pctLbl);
        let rmNode:     Node = checked_cast(removeBtn);
        discard children.add(comboNode);
        discard children.add(spinNode);
        discard children.add(pctLblNode);
        discard children.add(rmNode);
        row
    }

    /// JSON 値 (Option[JsonArray of JsonObject{id, percent}]) を [(id, percent)] にパース。
    /// 不正な要素はスキップ。値無しは空リスト
    def parseRefPercentRows(value: Option[Json.JsonElement]): List[(String, Int32)] =
        match value {
            case Some(Json.JsonElement.JsonArray(items)) =>
                Vector.toList(items)
                    |> List.filterMap(decodeRefPercentRow)
            case _ => Nil
        }

    def decodeRefPercentRow(elem: Json.JsonElement): Option[(String, Int32)] =
        match elem {
            case Json.JsonElement.JsonObject(m) =>
                let idOpt = Map.get("id", m) |> Option.flatMap(j -> match j {
                    case Json.JsonElement.JsonString(s) => Some(s)
                    case _ => None
                });
                let pctOpt = Map.get("percent", m) |> Option.flatMap(NodeInspector.jsonToInt);
                match (idOpt, pctOpt) {
                    case (Some(i), Some(p)) => Some((i, p))
                    case _                  => None
                }
            case _ => None
        }

    /// 内部 state を JSON に書き戻して commit
    def commitRefPercentRows(rowsRef: Array[List[(String, Int32)], Static],
                              commit: Commit): Unit \ IO = {
        let rows = Array.get(0, rowsRef);
        let items = rows |> List.map(p -> {
            let (id, pct) = p;
            Json.JsonElement.JsonObject(Map#{
                "id"      => Json.JsonElement.JsonString(id),
                "percent" => NodeInspector.intToJson(pct)
            })
        });
        commit(Json.JsonElement.JsonArray(List.toVector(items)))
    }

    /// idx 番目の (id, pct) を newPair で置き換えた新リストを返す
    def replaceRowAt(idx: Int32, newPair: (String, Int32),
                      rows: List[(String, Int32)]): List[(String, Int32)] =
        match rows {
            case Nil     => Nil
            case x :: xs =>
                if (idx == 0i32) newPair :: xs
                else x :: replaceRowAt(idx - 1i32, newPair, xs)
        }

    /// idx 番目を取り除いた新リストを返す
    def removeRowAt(idx: Int32, rows: List[(String, Int32)]): List[(String, Int32)] =
        match rows {
            case Nil     => Nil
            case x :: xs =>
                if (idx == 0i32) xs
                else x :: removeRowAt(idx - 1i32, xs)
        }

    def nthPercent(idx: Int32, rows: List[(String, Int32)]): Int32 =
        match List.nth(idx, rows) {
            case Some((_, p)) => p
            case None         => 0i32
        }

    def nthId(idx: Int32, rows: List[(String, Int32)]): String =
        match List.nth(idx, rows) {
            case Some((i, _)) => i
            case None         => ""
        }

    def sumPercents(rows: List[(String, Int32)]): Int32 =
        List.foldLeft((acc, p) -> { let (_, v) = p; acc + v }, 0i32, rows)

    def formatSumLabel(sum: Int32): String =
        if (sum == 100i32) "合計: ${sum}% ✓"
        else "合計: ${sum}% ⚠"

    def updateSumLabel(rowsRef: Array[List[(String, Int32)], Static],
                        sumLabelRef: Array[Option[Label], Static]): Unit \ IO = {
        let sum = sumPercents(Array.get(0, rowsRef));
        match Array.get(0, sumLabelRef) {
            case Some(lbl) => lbl.setText(formatSumLabel(sum))
            case None      => ()
        }
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
            let xs: Spinner[Double] = new Spinner(-999999.0, 999999.0, initXR, 0.1);
            let ys: Spinner[Double] = new Spinner(-999999.0, 999999.0, initYR, 0.1);
            xs.setEditable(true); ys.setEditable(true);
            xs.setPrefWidth(140.0); ys.setPrefWidth(140.0);
            xs.getValueFactory().setConverter(roundedDoubleConverter());
            ys.getValueFactory().setConverter(roundedDoubleConverter());
            let commitBoth = () -> {
                let x: Float64 = roundTo3(xs.getValue().doubleValue());
                let y: Float64 = roundTo3(ys.getValue().doubleValue());
                commit(NodeInspector.vec2ToJson({x = x, y = y}))
            };
            xs.valueProperty().addListener(new ChangeListener[Double] {
                def changed(_cThis: ChangeListener[Double], _obs: ObservableValue[JObject],
                             _old: Double, _newVal: Double): Unit \ IO = commitBoth()
            });
            ys.valueProperty().addListener(new ChangeListener[Double] {
                def changed(_cThis: ChangeListener[Double], _obs: ObservableValue[JObject],
                             _old: Double, _newVal: Double): Unit \ IO = commitBoth()
            });
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

    /// record JSON を DFS で walk して、textureNames に含まれる文字列値を持つ
    /// 最初のオブジェクトを見つけ、その texture と sibling の frame/hframes/vframes
    /// (もし存在すれば) をまとめて SpriteRef として返す。
    /// sprite ブロックを持たない bare texture record では frame 系が全て None に
    /// なり、updateSpritePreview のフォールバックで全体表示と等価になる。
    pub def findFirstSpriteRef(record: Json.JsonElement, textureNames: List[String]):
            Option[SpriteRef] = {
        let names = List.toSet(textureNames);
        scanForSpriteRef(record, names)
    }

    def scanForSpriteRef(elem: Json.JsonElement, textureNames: Set[String]):
            Option[SpriteRef] =
        match elem {
            case Json.JsonElement.JsonObject(m) =>
                // この object 自身が texture フィールドを持っていれば
                // sibling (frame/hframes/vframes) を一緒に拾って即返す
                match extractSpriteRefHere(m, textureNames) {
                    case Some(spriteRef) => Some(spriteRef)
                    case None            =>
                        Map.foldLeftWithKey((acc, _k, v) -> match acc {
                            case Some(_) => acc
                            case None    => scanForSpriteRef(v, textureNames)
                        }, None, m)
                }
            case _ => None
        }

    /// JsonObject 内で「textureNames に含まれる文字列値を持つフィールド」を 1 つ
    /// 見つけたら、その object 自身の frame/hframes/vframes (整数) も sibling
    /// として抜き出して SpriteRef を作る。
    /// texture を保持しているキーの名前は問わない (sprite ブロック内なら "texture"
    /// だが key 名に依存しない設計)。frame/hframes/vframes が無い、または整数で
    /// ない場合はそれぞれ None として返す。
    pub def extractSpriteRefHere(m: Map[String, Json.JsonElement], textureNames: Set[String]):
            Option[SpriteRef] =
        let entries = Map.toList(m);
        let textureOpt = List.findMap(entry -> {
            let (_k, v) = entry;
            match v {
                case Json.JsonElement.JsonString(s) =>
                    if (Set.memberOf(s, textureNames)) Some(s) else None
                case _ => None
            }
        }, entries);
        match textureOpt {
            case None          => None
            case Some(texture) =>
                let frame   = Map.get("frame",   m) |> Option.flatMap(NodeInspector.jsonToInt);
                let hframes = Map.get("hframes", m) |> Option.flatMap(NodeInspector.jsonToInt);
                let vframes = Map.get("vframes", m) |> Option.flatMap(NodeInspector.jsonToInt);
                let (ox, oy) = extractOffset(m);
                Some({
                    texture = texture,
                    frame   = frame,
                    hframes = hframes,
                    vframes = vframes,
                    offsetX = ox,
                    offsetY = oy
                })
        }

    /// `"offset": {"x": Float, "y": Float}` の sibling から (offsetX, offsetY) を抜き出す。
    /// 無ければ (0, 0)。
    def extractOffset(m: Map[String, Json.JsonElement]): (Float64, Float64) =
        match Map.get("offset", m) {
            case Some(Json.JsonElement.JsonObject(om)) =>
                let x = Map.get("x", om) |> Option.flatMap(NodeInspector.jsonToFloat)
                          |> Option.getWithDefault(0.0);
                let y = Map.get("y", om) |> Option.flatMap(NodeInspector.jsonToFloat)
                          |> Option.getWithDefault(0.0);
                (x, y)
            case _ => (0.0, 0.0)
        }

    /// SpriteRef から絶対パスを引いて JavaFX Image をロードし、frame/hframes/vframes
    /// が指定されていればその 1 セル分だけを Canvas にコピーして表示する。
    /// None なら "(no preview)" 表示。`pathMap` は texture 名 → 絶対パスの解決マップ。
    /// 切り抜き式は engine 側の Sprite2D.computeUv と同じ:
    ///   cellW = imgW / hframes, cellH = imgH / vframes,
    ///   col = frame % hframes,  row = frame / hframes,
    ///   srcRect = (col * cellW, row * cellH, cellW, cellH)
    /// frame 系が None または不正値のときは画像全体を表示する (sprite ブロックなしの
    /// bare texture record も同じ経路でフォールバック)。
    /// Canvas を使うのは GraphicsContext.setImageSmoothing(false) で
    /// nearest-neighbor 描画を明示的に効かせるため (ImageView.setSmooth(false) は
    /// JavaFX の Prism レンダラ環境で効かないケースがあるため避ける)。
    /// 永続 canvas に preview を描画する。pane はピンチハンドラの target である canvas を
    /// scene graph に保持させたままにしたいので、ここでは pane.getChildren() を **触らない**。
    /// 「no preview」「path unknown」状態は status label で示す（canvas は空 = 暗背景になる）。
    pub def updateSpritePreview(pane: StackPane, persistentCanvas: Canvas,
                                 pathMap: Map[String, String],
                                 spriteRef: Option[SpriteRef],
                                 zoomMode: ZoomMode,
                                 showGrid: Bool,
                                 frameAdjust: Bool,
                                 panOffset: (Float64, Float64),
                                 getCurrentPan: Unit -> (Float64, Float64) \ IO,
                                 onPanCommit: ((Float64, Float64)) -> Unit \ IO,
                                 onStatus: String -> Unit \ IO): Unit \ IO = {
        // canvas のサイズは pane に追従させる（window resize で見える範囲が増減）
        let paneW = pane.getWidth();
        let paneH = pane.getHeight();
        let canvasW = if (paneW > 16.0) paneW else 220.0;
        let canvasH = if (paneH > 16.0) paneH else 220.0;
        if (Float64.abs(persistentCanvas.getWidth() - canvasW) > 0.5)
            persistentCanvas.setWidth(canvasW)
        else ();
        if (Float64.abs(persistentCanvas.getHeight() - canvasH) > 0.5)
            persistentCanvas.setHeight(canvasH)
        else ();
        let gc: GraphicsContext = persistentCanvas.getGraphicsContext2D();
        gc.setImageSmoothing(false);
        gc.clearRect(0.0, 0.0, canvasW, canvasH);

        match spriteRef {
            case None => onStatus("(no preview)")
            case Some(sr) => {
                match Map.get(sr#texture, pathMap) {
                    case None => onStatus("(path unknown: ${sr#texture})")
                    case Some(absPath) => {
                        let url = new File(absPath).toURI().toString();
                        let image = new Image(url);
                        let hframes = sr#hframes |> Option.getWithDefault(1i32);
                        let vframes = sr#vframes |> Option.getWithDefault(1i32);
                        let frame   = sr#frame   |> Option.getWithDefault(0i32);
                        let imgW = image.getWidth();
                        let imgH = image.getHeight();
                        onStatus(formatSpriteStatus(imgW, imgH, hframes, vframes, zoomMode));
                        let (panX, panY) = panOffset;
                        let fullSheetMode = frameAdjust and hframes > 0i32 and vframes > 0i32
                                              and imgW > 0.0 and imgH > 0.0;
                        if (fullSheetMode) {
                            drawFullSheetWithSelection(gc, image, hframes, vframes, frame,
                                                        imgW, imgH, canvasW, canvasH, zoomMode,
                                                        showGrid, panX, panY)
                        } else {
                            drawSingleCell(gc, image, sr, hframes, vframes, frame,
                                            imgW, imgH, canvasW, canvasH, zoomMode, showGrid)
                        };
                        // フレーム調整モードでのみドラッグ pan を有効化（毎回 set し直す = 直近フレームの座標で更新）。
                        // ピンチハンドラは ResourcePanel.wirePreviewPinchZoom で永続 canvas に 1 回だけ登録済み。
                        if (fullSheetMode) {
                            wirePanDrag(persistentCanvas, gc, image, hframes, vframes, frame,
                                         imgW, imgH, canvasW, canvasH, zoomMode, showGrid,
                                         getCurrentPan, onPanCommit)
                        } else ()
                    }
                }
            }
        }
    }

    /// Preview 下の status label に出す「セル native px / Zoom」文字列。
    /// resource に scale を持たせない方針なので、純粋にアトラスのピクセル情報のみ表示
    def formatSpriteStatus(imgW: Float64, imgH: Float64, hframes: Int32, vframes: Int32,
                            zoomMode: ZoomMode): String = {
        let hfSafe = if (hframes > 0i32) hframes else 1i32;
        let vfSafe = if (vframes > 0i32) vframes else 1i32;
        let cellW = imgW / Int32.toFloat64(hfSafe);
        let cellH = imgH / Int32.toFloat64(vfSafe);
        let cellWi = Float64.tryToInt32(cellW) |> Option.getWithDefault(0i32);
        let cellHi = Float64.tryToInt32(cellH) |> Option.getWithDefault(0i32);
        let zoomStr = zoomModeLabel(zoomMode);
        "セル: ${cellWi}×${cellHi} px ／ Zoom: ${zoomStr}"
    }

    /// フレーム調整モードの canvas にマウスドラッグ pan を貼る。
    /// 押下時の (mouse, pan) を closure-capture した Static Array に記録し、
    /// drag のたびに新 pan を計算して同じ canvas に直接 redraw する。
    /// onPanCommit は ResourceState を更新し、後続の updateSpritePreview 呼び出しが
    /// 新しい pan を反映できるようにする
    def wirePanDrag(canvas: Canvas, gc: GraphicsContext, image: Image,
                     hframes: Int32, vframes: Int32, frame: Int32,
                     imgW: Float64, imgH: Float64,
                     canvasW: Float64, canvasH: Float64,
                     zoomMode: ZoomMode, showGrid: Bool,
                     getCurrentPan: Unit -> (Float64, Float64) \ IO,
                     onPanCommit: ((Float64, Float64)) -> Unit \ IO): Unit \ IO = {
        // ドラッグ起点: 押下時のマウス座標と pan 値を保持する。
        // 初期 0.0 はダミー — 実際の値は MOUSE_PRESSED で setReplace される
        let startMouseX = Array#{0.0} @ Static;
        let startMouseY = Array#{0.0} @ Static;
        let startPanX = Array#{0.0} @ Static;
        let startPanY = Array#{0.0} @ Static;
        canvas.setOnMousePressed(new EventHandler[MouseEvent] {
            def handle(_this: EventHandler[MouseEvent], e: MouseEvent): Unit \ IO = {
                Array.put(e.getX(), 0, startMouseX);
                Array.put(e.getY(), 0, startMouseY);
                // 押下のたびに ResourceState から最新 pan を取り直す。
                // これで 2 回目以降のドラッグストロークでも累積した pan を起点にできる
                let (curX, curY) = getCurrentPan();
                Array.put(curX, 0, startPanX);
                Array.put(curY, 0, startPanY)
            }
        });
        canvas.setOnMouseDragged(new EventHandler[MouseEvent] {
            def handle(_this: EventHandler[MouseEvent], e: MouseEvent): Unit \ IO = {
                let dx = e.getX() - Array.get(0, startMouseX);
                let dy = e.getY() - Array.get(0, startMouseY);
                let newPanX = Array.get(0, startPanX) + dx;
                let newPanY = Array.get(0, startPanY) + dy;
                onPanCommit((newPanX, newPanY));
                // 同じ canvas 上に直接 redraw (children.clear はしない)
                drawFullSheetWithSelection(gc, image, hframes, vframes, frame,
                                            imgW, imgH, canvasW, canvasH, zoomMode, showGrid,
                                            newPanX, newPanY)
            }
        })
    }

    /// 既存挙動: 選択フレーム 1 セルだけを切り抜いて中央描画。offset と zoom を反映。
    /// hframes/vframes が無効値のときは画像全体を表示するフォールバックを兼ねる
    def drawSingleCell(gc: GraphicsContext, image: Image, sr: SpriteRef,
                        hframes: Int32, vframes: Int32, frame: Int32,
                        imgW: Float64, imgH: Float64,
                        canvasW: Float64, canvasH: Float64,
                        zoomMode: ZoomMode, showGrid: Bool): Unit \ IO = {
        gc.clearRect(0.0, 0.0, canvasW, canvasH);
        let (srcX, srcY, srcW, srcH) =
            if (hframes > 0i32 and vframes > 0i32 and imgW > 0.0 and imgH > 0.0) {
                let cellW = imgW / Int32.toFloat64(hframes);
                let cellH = imgH / Int32.toFloat64(vframes);
                let col   = Int32.modulo(frame, hframes);
                let row   = frame / hframes;
                (Int32.toFloat64(col) * cellW,
                 Int32.toFloat64(row) * cellH,
                 cellW, cellH)
            } else (0.0, 0.0, imgW, imgH);
        let scale = if (srcW <= 0.0 or srcH <= 0.0) 1.0 else
            match zoomMode {
                case ZoomMode.Percent(p) => p / 100.0
            };
        let dstW = srcW * scale;
        let dstH = srcH * scale;
        let dstX = (canvasW - dstW) / 2.0 + sr#offsetX * scale;
        let dstY = (canvasH - dstH) / 2.0 + sr#offsetY * scale;
        gc.drawImage(image, srcX, srcY, srcW, srcH, dstX, dstY, dstW, dstH);
        if (showGrid) drawPreviewGrid(gc, canvasW, canvasH, dstW, dstH)
        else ()
    }

    /// フレーム調整モード: texture 全体を fit-scale * zoom% で描画し、選択フレーム以外を
    /// 半透明黒でディマー、選択フレームを再描画して 100% 不透明に戻し、黄色枠でハイライト。
    /// offset は適用しない (アトラス上の物理セル位置を見せる用途のため)
    def drawFullSheetWithSelection(gc: GraphicsContext, image: Image,
                                    hframes: Int32, vframes: Int32, frame: Int32,
                                    imgW: Float64, imgH: Float64,
                                    canvasW: Float64, canvasH: Float64,
                                    zoomMode: ZoomMode, showGrid: Bool,
                                    panX: Float64, panY: Float64): Unit \ IO = {
        gc.clearRect(0.0, 0.0, canvasW, canvasH);
        let fitScale = Float64.min(canvasW / imgW, canvasH / imgH);
        let zoomMul = match zoomMode {
            case ZoomMode.Percent(p) => p / 100.0
        };
        let effScale = fitScale * zoomMul;
        let sheetW = imgW * effScale;
        let sheetH = imgH * effScale;

        let cellW = imgW / Int32.toFloat64(hframes);
        let cellH = imgH / Int32.toFloat64(vframes);
        let safeFrame = if (frame < 0i32) 0i32 else frame;
        let col = Int32.modulo(safeFrame, hframes);
        let row = safeFrame / hframes;
        let srcX = Int32.toFloat64(col) * cellW;
        let srcY = Int32.toFloat64(row) * cellH;
        let cellDstW = cellW * effScale;
        let cellDstH = cellH * effScale;
        // 選択セル中心 + ユーザーの drag pan を canvas 中心に配置する。
        // pan は canvas pixel 単位、zoom に応じて拡縮しない (ドラッグ感覚を保つため)
        let cellCx = (Int32.toFloat64(col) + 0.5) * cellW * effScale;
        let cellCy = (Int32.toFloat64(row) + 0.5) * cellH * effScale;
        let dstX0 = canvasW / 2.0 - cellCx + panX;
        let dstY0 = canvasH / 2.0 - cellCy + panY;
        let cellDstX = dstX0 + srcX * effScale;
        let cellDstY = dstY0 + srcY * effScale;

        // 1. full sheet
        gc.drawImage(image, 0.0, 0.0, imgW, imgH, dstX0, dstY0, sheetW, sheetH);
        // 2. dim overlay (~65% black)
        let dim = FxColor.color(0.0, 0.0, 0.0, 0.65);
        gc.setFill(dim);
        gc.fillRect(dstX0, dstY0, sheetW, sheetH);
        // 3. selected cell at full opacity (frame が grid 内に収まるときだけ)
        let frameInGrid = row < vframes;
        if (frameInGrid) {
            gc.drawImage(image, srcX, srcY, cellW, cellH, cellDstX, cellDstY, cellDstW, cellDstH)
        } else ();
        // 4. atlas grid lines (if showGrid)
        if (showGrid) drawAtlasGrid(gc, dstX0, dstY0, sheetW, sheetH, hframes, vframes)
        else ();
        // 5. selection outline (grid 内のときだけ)
        if (frameInGrid) {
            let yellow = FxColor.color(1.0, 0.85, 0.0);
            gc.setStroke(yellow);
            gc.setLineWidth(2.0);
            gc.strokeRect(cellDstX, cellDstY, cellDstW, cellDstH)
        } else ()
    }

    /// アトラス全体の hframes × vframes セル境界線を半透明白で描く。
    /// drawPreviewGrid (中央十字 + cell 単独) と用途が異なる: フレーム調整モードで
    /// 「全セルの分割位置」を可視化するためのもの
    def drawAtlasGrid(gc: GraphicsContext, dstX0: Float64, dstY0: Float64,
                       sheetW: Float64, sheetH: Float64,
                       hframes: Int32, vframes: Int32): Unit \ IO = {
        let line = FxColor.color(1.0, 1.0, 1.0, 0.4);
        gc.setStroke(line);
        gc.setLineWidth(1.0);
        let cellW = sheetW / Int32.toFloat64(hframes);
        let cellH = sheetH / Int32.toFloat64(vframes);
        // 縦線 (hframes - 1 本)
        List.range(1i32, hframes) |> List.forEach(i -> {
            let x = dstX0 + Int32.toFloat64(i) * cellW;
            gc.strokeLine(x, dstY0, x, dstY0 + sheetH)
        });
        // 横線 (vframes - 1 本)
        List.range(1i32, vframes) |> List.forEach(j -> {
            let y = dstY0 + Int32.toFloat64(j) * cellH;
            gc.strokeLine(dstX0, y, dstX0 + sheetW, y)
        })
    }

    /// プレビュー用の補助グリッド。canvas の中央十字（赤）と「offset=0 のときの
    /// セル矩形」（白）を上に重ねて描く。中央合わせの目視確認に使う。
    def drawPreviewGrid(gc: GraphicsContext, canvasW: Float64, canvasH: Float64,
                         cellW: Float64, cellH: Float64): Unit \ IO = {
        let red   = FxColor.color(1.0, 0.0, 0.0);
        let white = FxColor.color(1.0, 1.0, 1.0);
        let cx = canvasW / 2.0;
        let cy = canvasH / 2.0;
        // 1. cell 矩形（offset=0 で中央寄せした場合の位置）= 白
        gc.setStroke(white);
        gc.setLineWidth(1.0);
        let cellX = cx - cellW / 2.0;
        let cellY = cy - cellH / 2.0;
        gc.strokeRect(cellX, cellY, cellW, cellH);
        // 2. 中央十字 = 赤
        gc.setStroke(red);
        gc.setLineWidth(1.0);
        gc.strokeLine(0.0, cy, canvasW, cy);
        gc.strokeLine(cx, 0.0, cx, canvasH)
    }

    // ════════════════════════════════════════════════════════════════════════
    // SpriteFramesT widget — grid インデックス形式の AnimatedSprite2D エディタ
    //
    // 編集対象 JSON 形式（authoring 形式）:
    //   {
    //     "idle":      { "loop": true, "speed": 4.0,
    //                    "frames": [{ "frame": 0, "duration": 1.0 }] },
    //     "walk_down": { ... }
    //   }
    //
    // 各 frame は `sprite.hframes × sprite.vframes` 分割の格子に対する
    // 0-origin row-major インデックス。texture は sprite.texture を共有。
    // 旧 px region 形式（{texture, region:{pos,size}}）は廃止された。
    //
    // UI 構成:
    //   ┌──────────────────────────────┐
    //   │ アニメ: [idle ▼] [+] [-]        │
    //   │ ループ: ☑   速度: [4.0]          │
    //   │ フレーム: [+] [-]                │
    //   │   ┌──────────────┐              │
    //   │   │ frame 0 (1.0)│              │
    //   │   │ frame 1 (1.0)│              │
    //   │   └──────────────┘              │
    //   │ 選択中: frame [0] duration [1.0]│
    //   │ [Atlas preview: 選択 cell 強調]  │
    //   └──────────────────────────────┘
    //
    // sibling 参照: rootRecord から sprite.{texture, hframes, vframes} を読む。
    // ════════════════════════════════════════════════════════════════════════

    pub def buildSpriteFramesEditorWidget(value: Option[Json.JsonElement],
                                            rootRecord: Json.JsonElement,
                                            texturePathMap: Map[String, String],
                                            commit: Commit): Node \ IO = {
        // sibling sprite.{texture, hframes, vframes} を読む（preview と frame max のため）
        let sib = extractSpriteSiblings(rootRecord);
        let hframes = sib#hframes;
        let vframes = sib#vframes;
        let textureName = sib#texture;
        let maxFrameIdx =
            if (hframes > 0 and vframes > 0) hframes * vframes - 1
            else 9999;

        // 可変 state
        let initialAnims = parseAnimsMap(value);
        let initialNames = Set.toList(Map.keysOf(initialAnims));
        let initialSelected = match List.head(initialNames) {
            case Some(n) => n
            case None    => ""
        };
        let animsRef: Array[Map[String, Json.JsonElement], Static] =
            Array.empty(Static, 1);
        Array.put(initialAnims, 0, animsRef);
        let selectedRef: Array[String, Static] = Array.empty(Static, 1);
        Array.put(initialSelected, 0, selectedRef);

        // UI 構築
        let outer = new VBox(4.0);
        outer.setMaxWidth(280.0);
        // (1) アニメ選択 ComboBox
        let animCombo: ComboBox[String] = new ComboBox();
        let comboItems = animCombo.getItems();
        List.forEach(n -> discard comboItems.add(n), initialNames);
        animCombo.setEditable(false);
        animCombo.setPrefWidth(180.0);
        if (String.length(initialSelected) > 0) animCombo.setValue(initialSelected) else ();
        let animComboNode: Node = checked_cast(animCombo);
        let comboRow = labeledRow("アニメ:", animComboNode);
        let comboRowNode: Node = checked_cast(comboRow);
        discard outer.getChildren().add(comboRowNode);

        // (2) 編集 row: frame index (Spinner[Integer]) + duration (Spinner[Double])
        // 先頭フレーム (frames[0]) のみを GUI で編集する MVP。
        // 多フレームアニメを使いたい場合は JSON を直接編集する。
        let init = currentFirstFrame(initialAnims, initialSelected);
        let frameSpinner: Spinner[Integer] =
            new Spinner(0i32, maxFrameIdx, init#frame);
        frameSpinner.setEditable(true);
        frameSpinner.setPrefWidth(80.0);
        let durSpinner: Spinner[Double] = new Spinner(0.0, 99.0, init#duration, 0.5);
        durSpinner.setEditable(true);
        durSpinner.setPrefWidth(80.0);
        durSpinner.getValueFactory().setConverter(roundedDoubleConverter());

        let editRow = new HBox(6.0);
        editRow.setAlignment(Pos.CENTER_LEFT);
        let editChildren = editRow.getChildren();
        let frameLabelNode: Node = checked_cast(new Label("frame"));
        let frameSpinnerNode: Node = checked_cast(frameSpinner);
        let durLabelNode: Node = checked_cast(new Label("dur"));
        let durSpinnerNode: Node = checked_cast(durSpinner);
        discard editChildren.add(frameLabelNode);
        discard editChildren.add(frameSpinnerNode);
        discard editChildren.add(durLabelNode);
        discard editChildren.add(durSpinnerNode);
        let editRowNode: Node = checked_cast(editRow);
        discard outer.getChildren().add(editRowNode);

        // (3) preview canvas: 選択フレームのセルを黄色枠でハイライト
        let canvas = new Canvas(260.0, 100.0);
        let canvasNode: Node = checked_cast(canvas);
        discard outer.getChildren().add(canvasNode);

        // 描画ヘルパ
        let redraw = () -> {
            let anims = Array.get(0, animsRef);
            let sel   = Array.get(0, selectedRef);
            let f     = currentFirstFrame(anims, sel);
            drawSpriteGridPreview(canvas, texturePathMap, textureName,
                                    hframes, vframes, f#frame)
        };
        // anim 選択変更時: spinner 値を新 anim の先頭 frame に合わせ、canvas 再描画
        animCombo.valueProperty().addListener(new ChangeListener[String] {
            def changed(_t: ChangeListener[String], _o: ObservableValue[JObject],
                         _old: String, newVal: String): Unit \ IO = {
                if (Object.isNull(newVal)) ()
                else {
                    Array.put(newVal, 0, selectedRef);
                    let anims = Array.get(0, animsRef);
                    let f     = currentFirstFrame(anims, newVal);
                    frameSpinner.getValueFactory().setValue(Integer.valueOf(f#frame));
                    durSpinner.getValueFactory().setValue(Double.valueOf(f#duration));
                    redraw()
                }
            }
        });
        // frame index 変更時: 選択 anim の frames[0].frame を書き換え、commit + redraw
        frameSpinner.valueProperty().addListener(new ChangeListener[Integer] {
            def changed(_t: ChangeListener[Integer], _o: ObservableValue[JObject],
                         _old: Integer, newVal: Integer): Unit \ IO = {
                if (Object.isNull(newVal)) ()
                else {
                    let sel = Array.get(0, selectedRef);
                    if (String.length(sel) == 0) ()
                    else {
                        let anims = Array.get(0, animsRef);
                        let v: Int32 = newVal.intValue();
                        let updated = setFrameField(anims, sel, 0i32, "frame",
                                                      Json.JsonElement.JsonNumber(intToBd(v)));
                        Array.put(updated, 0, animsRef);
                        commit(Json.JsonElement.JsonObject(updated));
                        redraw()
                    }
                }
            }
        });
        // duration 変更時: 選択 anim の frames[0].duration を書き換え、commit
        durSpinner.valueProperty().addListener(new ChangeListener[Double] {
            def changed(_t: ChangeListener[Double], _o: ObservableValue[JObject],
                         _old: Double, newVal: Double): Unit \ IO = {
                if (Object.isNull(newVal)) ()
                else {
                    let sel = Array.get(0, selectedRef);
                    if (String.length(sel) == 0) ()
                    else {
                        let anims = Array.get(0, animsRef);
                        let v = roundTo3(newVal.doubleValue());
                        let updated = setFrameField(anims, sel, 0i32, "duration",
                                                      Json.JsonElement.JsonNumber(floatToBdRounded(v)));
                        Array.put(updated, 0, animsRef);
                        commit(Json.JsonElement.JsonObject(updated))
                    }
                }
            }
        });

        // 初回描画
        redraw();
        checked_cast(outer)
    }

    /// HBox に [Label][widget] を並べる小ヘルパー
    def labeledRow(label: String, widget: Node): HBox \ IO = {
        let row = new HBox(6.0);
        row.setAlignment(Pos.CENTER_LEFT);
        let children = row.getChildren();
        let labelNode: Node = checked_cast(new Label(label));
        discard children.add(labelNode);
        discard children.add(widget);
        row
    }

    /// 選択 anim の frames[0] を取り出す。frames が空 / anim が無いなら {frame=0, duration=1.0}。
    def currentFirstFrame(anims: Map[String, Json.JsonElement], sel: String):
            {frame = Int32, duration = Float64} =
        currentFrame(anims, sel, 0i32)

    /// spriteFrames JSON object を anim 名 → JSON の Map に解す。
    /// JsonObject 以外は空 Map (= 編集不能だが widget は表示される)。
    def parseAnimsMap(v: Option[Json.JsonElement]): Map[String, Json.JsonElement] =
        match v {
            case Some(Json.JsonElement.JsonObject(m)) => m
            case _                                     => Map.empty()
        }

    /// rootRecord (ユニット全体の JSON) から `sprite.{texture, hframes, vframes}` を抽出。
    /// 欠落時は空文字列 / 0 を埋める。
    def extractSpriteSiblings(rootRecord: Json.JsonElement):
            {texture = String, hframes = Int32, vframes = Int32} =
        match rootRecord {
            case Json.JsonElement.JsonObject(rec) =>
                match Map.get("sprite", rec) {
                    case Some(Json.JsonElement.JsonObject(sp)) =>
                        let tex = match Map.get("texture", sp) {
                            case Some(Json.JsonElement.JsonString(s)) => s
                            case _ => ""
                        };
                        let hf = match Map.get("hframes", sp) {
                            case Some(Json.JsonElement.JsonNumber(bd)) =>
                                BigDecimal.tryToFloat64(bd)
                                    |> Option.flatMap(Float64.tryToInt32)
                                    |> Option.getWithDefault(0i32)
                            case _ => 0i32
                        };
                        let vf = match Map.get("vframes", sp) {
                            case Some(Json.JsonElement.JsonNumber(bd)) =>
                                BigDecimal.tryToFloat64(bd)
                                    |> Option.flatMap(Float64.tryToInt32)
                                    |> Option.getWithDefault(0i32)
                            case _ => 0i32
                        };
                        {texture = tex, hframes = hf, vframes = vf}
                    case _ => {texture = "", hframes = 0i32, vframes = 0i32}
                }
            case _ => {texture = "", hframes = 0i32, vframes = 0i32}
        }

    /// 選択 anim の frames を `{frame, duration}` のリストとして取り出す。
    def currentFramesList(anims: Map[String, Json.JsonElement], sel: String):
            List[{frame = Int32, duration = Float64}] =
        match Map.get(sel, anims) {
            case Some(Json.JsonElement.JsonObject(animMap)) =>
                match Map.get("frames", animMap) {
                    case Some(Json.JsonElement.JsonArray(arr)) =>
                        Vector.toList(arr) |> List.map(parseFrameJson)
                    case _ => Nil
                }
            case _ => Nil
        }

    def parseFrameJson(frameJson: Json.JsonElement): {frame = Int32, duration = Float64} =
        match frameJson {
            case Json.JsonElement.JsonObject(fm) =>
                let fIdx = match Map.get("frame", fm) {
                    case Some(Json.JsonElement.JsonNumber(bd)) =>
                        BigDecimal.tryToFloat64(bd)
                            |> Option.flatMap(Float64.tryToInt32)
                            |> Option.getWithDefault(0i32)
                    case _ => 0i32
                };
                let dur = match Map.get("duration", fm) {
                    case Some(Json.JsonElement.JsonNumber(bd)) =>
                        BigDecimal.tryToFloat64(bd) |> Option.getWithDefault(1.0)
                    case _ => 1.0
                };
                {frame = fIdx, duration = dur}
            case _ => {frame = 0i32, duration = 1.0}
        }

    /// 選択 anim の frames[idx] を取り出す。範囲外なら {frame=0, duration=1.0}。
    def currentFrame(anims: Map[String, Json.JsonElement], sel: String, idx: Int32):
            {frame = Int32, duration = Float64} =
        let frames = currentFramesList(anims, sel);
        match List.nth(idx, frames) {
            case Some(f) => f
            case None    => {frame = 0i32, duration = 1.0}
        }

    /// 指定 anim の frames[idx].key を上書きする。
    /// 多フレーム対応用に idx 引数を取るが、MVP widget では idx=0 固定で呼ぶ。
    def setFrameField(anims: Map[String, Json.JsonElement], sel: String, idx: Int32,
                        key: String, newVal: Json.JsonElement): Map[String, Json.JsonElement] =
        match Map.get(sel, anims) {
            case Some(Json.JsonElement.JsonObject(animMap)) =>
                match Map.get("frames", animMap) {
                    case Some(Json.JsonElement.JsonArray(arr)) =>
                        if (idx < 0i32 or idx >= Vector.length(arr)) anims
                        else {
                            let frameElem = Vector.get(idx, arr);
                            let newFrame = match frameElem {
                                case Json.JsonElement.JsonObject(fm) =>
                                    Json.JsonElement.JsonObject(Map.insert(key, newVal, fm))
                                case _ => frameElem
                            };
                            let newArr = Vector.update(idx, newFrame, arr);
                            let updatedAnim = Json.JsonElement.JsonObject(
                                Map.insert("frames", Json.JsonElement.JsonArray(newArr), animMap));
                            Map.insert(sel, updatedAnim, anims)
                        }
                    case _ => anims
                }
            case _ => anims
        }

    def intToBd(v: Int32): BigDecimal =
        unsafe IO {
            let stripped = JBigDecimal.valueOf(Int32.toFloat64(v)).stripTrailingZeros();
            if (stripped.scale() < 0) stripped.setScale(0) else stripped
        }

    /// Float64 → BigDecimal。3 桁で四捨五入し末尾 0 を取り除く（`1.0` → `1`、`0.5` → `0.5`）。
    def floatToBdRounded(v: Float64): BigDecimal =
        unsafe IO {
            JBigDecimal.valueOf(roundTo3(v)).stripTrailingZeros()
        }

    /// アトラスを canvas に fit-scale で描画し、`hframes × vframes` の格子線と、
    /// 選択中フレーム index に対応するセルだけを黄色枠でハイライトする。
    /// texture 未登録 / hframes×vframes が 0 のときはプレースホルダ背景のみ。
    def drawSpriteGridPreview(canvas: Canvas, pathMap: Map[String, String],
                                textureName: String,
                                hframes: Int32, vframes: Int32, selFrame: Int32):
                              Unit \ IO = {
        let gc: GraphicsContext = canvas.getGraphicsContext2D();
        let cw = canvas.getWidth();
        let ch = canvas.getHeight();
        gc.setImageSmoothing(false);
        gc.setFill(FxColor.color(0.12, 0.12, 0.12));
        gc.fillRect(0.0, 0.0, cw, ch);
        match Map.get(textureName, pathMap) {
            case None => ()
            case Some(absPath) => {
                let url = new File(absPath).toURI().toString();
                let image = new Image(url);
                let imgW = image.getWidth();
                let imgH = image.getHeight();
                if (imgW <= 0.0 or imgH <= 0.0) ()
                else if (hframes <= 0i32 or vframes <= 0i32) ()
                else {
                    let sx = cw / imgW;
                    let sy = ch / imgH;
                    let s = if (sx < sy) sx else sy;
                    let dstW = imgW * s;
                    let dstH = imgH * s;
                    let dstX0 = (cw - dstW) / 2.0;
                    let dstY0 = (ch - dstH) / 2.0;
                    // アトラス描画
                    gc.drawImage(image, 0.0, 0.0, imgW, imgH, dstX0, dstY0, dstW, dstH);
                    // 格子線（薄いグレー）
                    let cellW = dstW / Int32.toFloat64(hframes);
                    let cellH = dstH / Int32.toFloat64(vframes);
                    gc.setStroke(FxColor.color(0.5, 0.5, 0.5));
                    gc.setLineWidth(1.0);
                    drawGridLines(gc, dstX0, dstY0, dstW, dstH, hframes, vframes, cellW, cellH);
                    // 選択 cell ハイライト
                    let total = hframes * vframes;
                    if (selFrame >= 0i32 and selFrame < total) {
                        let col = Int32.remainder(selFrame, hframes);
                        let row = selFrame / hframes;
                        let rx = dstX0 + Int32.toFloat64(col) * cellW;
                        let ry = dstY0 + Int32.toFloat64(row) * cellH;
                        gc.setStroke(FxColor.color(1.0, 0.9, 0.0));
                        gc.setLineWidth(2.0);
                        gc.strokeRect(rx, ry, cellW, cellH)
                    } else ()
                }
            }
        }
    }

    /// `hframes × vframes` 分の縦横格子線を描画する。
    def drawGridLines(gc: GraphicsContext, x0: Float64, y0: Float64, w: Float64, h: Float64,
                       hframes: Int32, vframes: Int32, cellW: Float64, cellH: Float64): Unit \ IO = {
        drawVerticalLines(gc, x0, y0, h, hframes, cellW, 0i32);
        drawHorizontalLines(gc, x0, y0, w, vframes, cellH, 0i32);
        // 外枠
        gc.strokeRect(x0, y0, w, h)
    }

    def drawVerticalLines(gc: GraphicsContext, x0: Float64, y0: Float64, h: Float64,
                            hframes: Int32, cellW: Float64, i: Int32): Unit \ IO =
        if (i >= hframes) ()
        else {
            let x = x0 + Int32.toFloat64(i) * cellW;
            gc.strokeLine(x, y0, x, y0 + h);
            drawVerticalLines(gc, x0, y0, h, hframes, cellW, i + 1i32)
        }

    def drawHorizontalLines(gc: GraphicsContext, x0: Float64, y0: Float64, w: Float64,
                             vframes: Int32, cellH: Float64, i: Int32): Unit \ IO =
        if (i >= vframes) ()
        else {
            let y = y0 + Int32.toFloat64(i) * cellH;
            gc.strokeLine(x0, y, x0 + w, y);
            drawHorizontalLines(gc, x0, y0, w, vframes, cellH, i + 1i32)
        }
}
