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
    import javafx.collections.ObservableList
    import javafx.fxml.FXMLLoader
    import javafx.scene.Node
    import javafx.scene.image.Image
    import javafx.scene.canvas.Canvas
    import javafx.scene.canvas.GraphicsContext
    import javafx.scene.control.Label
    import javafx.scene.control.TextField
    import javafx.scene.control.CheckBox
    import javafx.scene.control.ColorPicker
    import javafx.scene.control.ComboBox
    import javafx.scene.control.Spinner
    import javafx.scene.paint.{Color => FxColor}
    import javafx.scene.layout.HBox
    import javafx.scene.layout.StackPane
    import javafx.scene.layout.VBox
    import javafx.geometry.Pos
    import javafx.event.ActionEvent
    import javafx.event.EventHandler
    import javafx.scene.input.MouseEvent
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
    /// ネイティブピクセル基準のパーセント表示倍率。
    ///   100 = 1 image pixel = 1 logical screen pixel (IDE プレビュー上の等倍)、
    ///   200 = 2 倍拡大、50 = 半分縮小
    /// 注意: 「ゲームでの実際の見え方」は Sprite2D.scale / Camera2D.zoom /
    /// Viewport (design → window) の合成で決まるため、Resource (texture/frame/
    /// hframes/vframes) 単独では再現できない。この preview は texture アトラスの
    /// ピクセル自体を確認する用途
    pub enum ZoomMode with Eq, ToString {
        case Percent(Int32)
    }

    /// ズーム段階の昇順リスト (パーセント値)。zoomIn/zoomOut が辿る
    def zoomSteps(): List[Int32] =
        25i32 :: 50i32 :: 75i32 :: 100i32 :: 150i32 :: 200i32 :: 300i32 :: 400i32 :: 600i32 :: 800i32 :: 1600i32 :: Nil

    /// プロジェクト起動時 / ResourceState 初期化時のデフォルトズーム。
    /// 100% = ネイティブピクセル等倍 (1 image px = 1 logical px)
    pub def defaultZoom(): ZoomMode =
        ZoomMode.Percent(100)

    /// ZoomMode を UI 表示用の短い文字列にする ("100%" / "200%" ...)
    pub def zoomModeLabel(mode: ZoomMode): String =
        match mode {
            case ZoomMode.Percent(p) => "${p}%"
        }

    /// "-" ボタン: 段階リストの 1 つ下に降りる。最小 (25%) は no-op
    pub def zoomOut(mode: ZoomMode): ZoomMode =
        match mode {
            case ZoomMode.Percent(p) =>
                let lower = List.filter(s -> s < p, zoomSteps());
                match List.last(lower) {
                    case None       => mode
                    case Some(prev) => ZoomMode.Percent(prev)
                }
        }

    /// "+" ボタン: 段階リストの 1 つ上に上がる。最大 (1600%) は no-op
    pub def zoomIn(mode: ZoomMode): ZoomMode =
        match mode {
            case ZoomMode.Percent(p) =>
                match List.find(s -> s > p, zoomSteps()) {
                    case None       => mode
                    case Some(next) => ZoomMode.Percent(next)
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
                        refOptions: Map[String, List[String]],
                        mkCommit: List[String] -> Commit): Unit \ IO =
        match entry {
            case Resource.FieldEntry.Field(fs) => {
                let value = jsonFieldOf(record, key);
                let keyPath = List.append(basePath, key :: Nil);
                let widget = buildFieldWidget(fs, value, textureNames, refOptions,
                                                mkCommit(keyPath));
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
                    addFieldRow(children, k, e, innerRecord, innerBasePath,
                                  textureNames, refOptions, mkCommit)
                }, sortedInner)
            }
        }

    /// FieldType に応じた編集 widget を返す
    def buildFieldWidget(fs: Resource.FieldSchema, value: Option[Json.JsonElement],
                         textureNames: List[String],
                         refOptions: Map[String, List[String]],
                         commit: Commit): Node \ IO =
        match fs#ftype {
            case Resource.FieldType.TextT         => buildTextWidget(value, commit)
            case Resource.FieldType.IntT          => buildIntWidget(value, commit)
            case Resource.FieldType.FloatT        => buildFloatWidget(value, commit)
            case Resource.FieldType.BoolT         => buildBoolWidget(value, commit)
            case Resource.FieldType.TexturePathT  => buildTexturePathWidget(value, textureNames, commit)
            case Resource.FieldType.RefT(target)  =>
                let options = Map.get(target, refOptions) |> Option.getWithDefault(Nil);
                buildEnumWidget(value, options, commit)
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

    /// Float フィールド: Spinner<Double> (step 0.1)
    pub def buildFloatWidget(value: Option[Json.JsonElement], commit: Commit): Node \ IO = {
        let current: Float64 = NodeInspector.jsonToFloat(value |> Option.getWithDefault(Json.JsonElement.JsonNull))
                                |> Option.getWithDefault(0.0);
        let spinner: Spinner[Double] = new Spinner(-999999.0, 999999.0, current, 0.1);
        spinner.setEditable(true);
        spinner.setPrefWidth(110.0);
        spinner.setMaxWidth(110.0);
        spinner.valueProperty().addListener(new ChangeListener[Double] {
            def changed(_cThis: ChangeListener[Double], _obs: ObservableValue[JObject],
                         _old: Double, newVal: Double): Unit \ IO = {
                let v: Float64 = newVal.doubleValue();
                commit(NodeInspector.floatToJson(v))
            }
        });
        checked_cast(spinner)
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
            let xs: Spinner[Double] = new Spinner(-999999.0, 999999.0, initX, 0.1);
            let ys: Spinner[Double] = new Spinner(-999999.0, 999999.0, initY, 0.1);
            xs.setEditable(true); ys.setEditable(true);
            xs.setPrefWidth(140.0); ys.setPrefWidth(140.0);
            let commitBoth = () -> {
                let x: Float64 = xs.getValue().doubleValue();
                let y: Float64 = ys.getValue().doubleValue();
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
    pub def updateSpritePreview(pane: StackPane, pathMap: Map[String, String],
                                 spriteRef: Option[SpriteRef],
                                 zoomMode: ZoomMode,
                                 showGrid: Bool,
                                 frameAdjust: Bool,
                                 panOffset: (Float64, Float64),
                                 getCurrentPan: Unit -> (Float64, Float64) \ IO,
                                 onPanCommit: ((Float64, Float64)) -> Unit \ IO,
                                 onStatus: String -> Unit \ IO): Unit \ IO = {
        let children = pane.getChildren();
        children.clear();
        match spriteRef {
            case None => {
                let l = new Label("(no preview)");
                l.getStyleClass().add("inspector-empty");
                let n: Node = checked_cast(l);
                discard children.add(n);
                onStatus("")
            }
            case Some(sr) => {
                match Map.get(sr#texture, pathMap) {
                    case None => {
                        let l = new Label("(path unknown: ${sr#texture})");
                        l.getStyleClass().add("inspector-empty");
                        let n: Node = checked_cast(l);
                        discard children.add(n);
                        onStatus("")
                    }
                    case Some(absPath) => {
                        let url = new File(absPath).toURI().toString();
                        let image = new Image(url);
                        let hframes = sr#hframes |> Option.getWithDefault(1i32);
                        let vframes = sr#vframes |> Option.getWithDefault(1i32);
                        let frame   = sr#frame   |> Option.getWithDefault(0i32);
                        let imgW = image.getWidth();
                        let imgH = image.getHeight();
                        // status label: セル native px / 現在 zoom
                        onStatus(formatSpriteStatus(imgW, imgH, hframes, vframes, zoomMode));
                        // canvas サイズは pane の実サイズに追従させて、window resize で
                        // 「見える範囲」が増減するようにする。レイアウト未確定 (= 0) の
                        // フレームでは保守的な 220 にフォールバック
                        let paneW = pane.getWidth();
                        let paneH = pane.getHeight();
                        let canvasW = if (paneW > 16.0) paneW else 220.0;
                        let canvasH = if (paneH > 16.0) paneH else 220.0;
                        let canvas = new Canvas(canvasW, canvasH);
                        let gc: GraphicsContext = canvas.getGraphicsContext2D();
                        gc.setImageSmoothing(false);
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
                        // フレーム調整モードでのみドラッグ pan を有効化。
                        // 同じ canvas 上に直接 redraw して JavaFX のドラッグ追跡を保つ
                        // (canvas を pane から外すと press 後の dragged イベントが届かない)
                        if (fullSheetMode) {
                            wirePanDrag(canvas, gc, image, hframes, vframes, frame,
                                         imgW, imgH, canvasW, canvasH, zoomMode, showGrid,
                                         getCurrentPan, onPanCommit)
                        } else ();
                        let n: Node = checked_cast(canvas);
                        discard children.add(n)
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
                case ZoomMode.Percent(p) => Int32.toFloat64(p) / 100.0
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
            case ZoomMode.Percent(p) => Int32.toFloat64(p) / 100.0
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
}
