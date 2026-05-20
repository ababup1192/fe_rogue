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
    import javafx.beans.value.ChangeListener
    import javafx.beans.value.ObservableValue
    import java.lang.Double
    import java.lang.Integer

    /// 編集確定時の callback。受け取る側 (ResourcePanel / ScenePanel) が
    /// JSON を消費して書き戻し or pending queue に積む
    pub type alias Commit = Json.JsonElement -> Unit \ IO

    /// Sprite preview に渡す表示情報。
    ///   - texture:  textureNames に登録されている texture 名
    ///   - frame / hframes / vframes: 同じオブジェクト内に sibling として並ぶ
    ///     アトラス分割情報。sprite ブロックが無く texture だけの record では
    ///     全て None になり、preview 側で 1, 1, 0 にフォールバックして
    ///     画像全体を表示する。
    pub type alias SpriteRef = {
        texture  = String,
        frame    = Option[Int32],
        hframes  = Option[Int32],
        vframes  = Option[Int32]
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
    pub def addFieldRow(children: ObservableList[Node],
                        key: String, entry: Resource.FieldEntry,
                        record: Json.JsonElement, basePath: List[String],
                        textureNames: List[String],
                        mkCommit: List[String] -> Commit): Unit \ IO =
        match entry {
            case Resource.FieldEntry.Field(fs) => {
                let value = jsonFieldOf(record, key);
                let keyPath = List.append(basePath, key :: Nil);
                let widget = buildFieldWidget(fs, value, textureNames, mkCommit(keyPath));
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
                    addFieldRow(children, k, e, innerRecord, innerBasePath, textureNames, mkCommit)
                }, sortedInner)
            }
        }

    /// FieldType に応じた編集 widget を返す
    def buildFieldWidget(fs: Resource.FieldSchema, value: Option[Json.JsonElement],
                         textureNames: List[String], commit: Commit): Node \ IO =
        match fs#ftype {
            case Resource.FieldType.TextT         => buildTextWidget(value, commit)
            case Resource.FieldType.IntT          => buildIntWidget(value, commit)
            case Resource.FieldType.FloatT        => buildFloatWidget(value, commit)
            case Resource.FieldType.BoolT         => buildBoolWidget(value, commit)
            case Resource.FieldType.TexturePathT  => buildTexturePathWidget(value, textureNames, commit)
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
        field.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO =
                commit(Json.JsonElement.JsonString(field.getText()))
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
                Some({
                    texture = texture,
                    frame   = frame,
                    hframes = hframes,
                    vframes = vframes
                })
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
                                 spriteRef: Option[SpriteRef]): Unit \ IO = {
        let children = pane.getChildren();
        children.clear();
        match spriteRef {
            case None => {
                let l = new Label("(no preview)");
                l.getStyleClass().add("inspector-empty");
                let n: Node = checked_cast(l);
                discard children.add(n)
            }
            case Some(sr) => {
                match Map.get(sr#texture, pathMap) {
                    case None => {
                        let l = new Label("(path unknown: ${sr#texture})");
                        l.getStyleClass().add("inspector-empty");
                        let n: Node = checked_cast(l);
                        discard children.add(n)
                    }
                    case Some(absPath) => {
                        let url = new File(absPath).toURI().toString();
                        let image = new Image(url);

                        // sprite ブロック欠落時は (frame=0, h=1, v=1) で全体表示
                        let hframes = sr#hframes |> Option.getWithDefault(1i32);
                        let vframes = sr#vframes |> Option.getWithDefault(1i32);
                        let frame   = sr#frame   |> Option.getWithDefault(0i32);
                        let imgW = image.getWidth();
                        let imgH = image.getHeight();
                        let (srcX, srcY, srcW, srcH) =
                            if (hframes > 0i32 and vframes > 0i32
                                and imgW > 0.0 and imgH > 0.0) {
                                let cellW = imgW / Int32.toFloat64(hframes);
                                let cellH = imgH / Int32.toFloat64(vframes);
                                let col   = Int32.modulo(frame, hframes);
                                let row   = frame / hframes;
                                (Int32.toFloat64(col) * cellW,
                                 Int32.toFloat64(row) * cellH,
                                 cellW, cellH)
                            } else (0.0, 0.0, imgW, imgH);

                        // ピクセルアートを 220 px 枠に nearest-neighbor で拡大する。
                        // ImageView.setSmooth(false) は Prism レンダラ環境で
                        // 効かないケースがあるので、Canvas + GraphicsContext で
                        // 明示的に setImageSmoothing(false) する。
                        let canvasSize = 220.0;
                        // アスペクト比保持: cell が縦長/横長でも枠内に収める
                        let scale = if (srcW <= 0.0 or srcH <= 0.0) 1.0 else {
                            let sx = canvasSize / srcW;
                            let sy = canvasSize / srcH;
                            if (sx < sy) sx else sy
                        };
                        let dstW = srcW * scale;
                        let dstH = srcH * scale;
                        let dstX = (canvasSize - dstW) / 2.0;
                        let dstY = (canvasSize - dstH) / 2.0;
                        let canvas = new Canvas(canvasSize, canvasSize);
                        let gc: GraphicsContext = canvas.getGraphicsContext2D();
                        gc.setImageSmoothing(false);
                        gc.drawImage(image, srcX, srcY, srcW, srcH, dstX, dstY, dstW, dstH);
                        let n: Node = checked_cast(canvas);
                        discard children.add(n)
                    }
                }
            }
        }
    }
}
