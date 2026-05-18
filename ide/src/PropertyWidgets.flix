// PropertyWidgets — Property Panel / Inspector で使う schema 駆動の編集 widget 群と
// 共通ヘルパーを集めた module。
//
// 提供するもの:
//   - addPropertyRow / addPropertyPlaceholder: property-row.fxml を使う行テンプレ
//   - withRef: Option Ref の Some 時だけ action を実行する小ヘルパー (effect polymorphic)
//   - wireNumericField: 数値 TextField に Enter / ↑↓ で commit を仕掛ける
//   - addFieldRow + buildFieldWidget: Resource.FieldEntry に応じて行を組み立てる
//   - updateSpritePreview / findFirstTexture: TexturePath 値から画像 preview を描く
//
// Resource Panel と Scene Inspector の双方から呼ばれる。

mod PropertyWidgets {
    import java.io.File
    import java.lang.{Object => JObject}
    import javafx.collections.ObservableList
    import javafx.fxml.FXMLLoader
    import javafx.scene.Node
    import javafx.scene.image.Image
    import javafx.scene.image.ImageView
    import javafx.scene.control.Label
    import javafx.scene.control.TextField
    import javafx.scene.control.CheckBox
    import javafx.scene.control.ComboBox
    import javafx.scene.control.Spinner
    import javafx.scene.input.KeyEvent
    import javafx.scene.layout.HBox
    import javafx.scene.layout.StackPane
    import javafx.event.ActionEvent
    import javafx.event.EventHandler
    import javafx.beans.value.ChangeListener
    import javafx.beans.value.ObservableValue
    import java.lang.Double
    import java.lang.Integer
    import java.nio.file.Files
    import java.nio.file.Paths
    import java.math.{BigDecimal => JBigDecimal}

    /// 共通テンプレ property-row.fxml をロードして「key Label + 値 slot」の HBox を返す。
    /// レイアウト・スタイルは FXML / CSS 側で完結させ、Flix はデータ注入のみ
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

    /// Option Ref 共通: Some なら action を実行。None は no-op。
    /// effect polymorphic で各種ハンドラから使える
    pub def withRef(ref: Array[Option[t], Static], action: t -> Unit \ ef): Unit \ ef + IO =
        match Array.get(0, ref) {
            case None    => ()
            case Some(v) => action(v)
        }

    /// 数値 TextField に Enter / ↑↓ で commit するハンドラを仕掛ける。
    /// ↑ で +step / ↓ で -step、commit lambda は最新の field.getText() を読んで処理
    pub def wireNumericField(field: TextField, isInt: Bool, commit: Unit -> Unit \ IO): Unit \ IO = {
        field.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO = commit()
        });
        field.setOnKeyPressed(new EventHandler[KeyEvent] {
            def handle(_this: EventHandler[KeyEvent], e: KeyEvent): Unit \ IO = {
                let name = e.getCode().toString();
                if (name == "UP" or name == "DOWN") {
                    let delta = if (name == "UP") 1.0 else -1.0;
                    let current = Float64.fromString(field.getText())
                                   |> Option.getWithDefault(0.0);
                    let newVal = current + delta;
                    if (isInt) {
                        let iv = Float64.tryToInt32(newVal)
                                  |> Option.getWithDefault(0i32);
                        field.setText("${iv}")
                    } else {
                        field.setText("${newVal}")
                    };
                    commit();
                    e.consume()
                } else ()
            }
        })
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
    /// commit (Enter / CheckBox toggle) で editingJson + ファイルを更新する。
    /// Nested は section header (太字 Label) を入れて内側を order 順で再帰展開する
    pub def addFieldRow(state: IdeState.IdeState, children: ObservableList[Node],
                        key: String, entry: Resource.FieldEntry,
                        record: Json.JsonElement, basePath: List[String]): Unit \ IO =
        match entry {
            case Resource.FieldEntry.Field(fs) => {
                let value = jsonFieldOf(record, key);
                let keyPath = List.append(basePath, key :: Nil);
                let widget = buildFieldWidget(state, fs, value, keyPath);
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
                    addFieldRow(state, children, k, e, innerRecord, innerBasePath)
                }, sortedInner)
            }
        }

    /// FieldType に応じた編集 widget を返す
    def buildFieldWidget(state: IdeState.IdeState, fs: Resource.FieldSchema,
                         value: Option[Json.JsonElement], keyPath: List[String]): Node \ IO =
        match fs#ftype {
            case Resource.FieldType.TextT         => buildTextWidget(state, value, keyPath)
            case Resource.FieldType.IntT          => buildIntWidget(state, value, keyPath)
            case Resource.FieldType.FloatT        => buildFloatWidget(state, value, keyPath)
            case Resource.FieldType.BoolT         => buildBoolWidget(state, value, keyPath)
            case Resource.FieldType.TexturePathT  => buildTexturePathWidget(state, value, keyPath)
        }

    /// TexturePathT フィールド: ComboBox<String> で project 登録 texture から選択。
    /// textureNamesRef は reloadProject で project.json の textureManifest を読んで populate 済み
    def buildTexturePathWidget(state: IdeState.IdeState, value: Option[Json.JsonElement],
                                keyPath: List[String]): Node \ IO = {
        let current = match value {
            case Some(Json.JsonElement.JsonString(s)) => s
            case _                                    => ""
        };
        let combo: ComboBox[String] = new ComboBox();
        let items = combo.getItems();
        let textureNames = Array.get(0, state#textureNamesRef);
        List.forEach(name -> discard items.add(name), textureNames);
        combo.setEditable(false);
        combo.setValue(current);
        combo.setPrefWidth(160.0);
        combo.setMaxWidth(160.0);
        combo.valueProperty().addListener(new ChangeListener[String] {
            def changed(_cThis: ChangeListener[String], _obs: ObservableValue[JObject],
                         _old: String, newVal: String): Unit \ IO = {
                if (Object.isNull(newVal)) ()
                else {
                    commitFieldJson(state, keyPath, Json.JsonElement.JsonString(newVal));
                    updateSpritePreview(state, Some(newVal))
                }
            }
        });
        checked_cast(combo)
    }

    def buildTextWidget(state: IdeState.IdeState, value: Option[Json.JsonElement],
                         keyPath: List[String]): Node \ IO = {
        let current = match value {
            case Some(Json.JsonElement.JsonString(s)) => s
            case _                                    => ""
        };
        let field = new TextField(current);
        field.setPrefWidth(160.0);
        field.setMaxWidth(160.0);
        field.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO =
                commitFieldJson(state, keyPath, Json.JsonElement.JsonString(field.getText()))
        });
        checked_cast(field)
    }

    /// Int フィールド: Spinner<Integer> (HTML input[type=number] 相当の上下ボタン付き)
    def buildIntWidget(state: IdeState.IdeState, value: Option[Json.JsonElement],
                        keyPath: List[String]): Node \ IO = {
        let current: Int32 = match value {
            case Some(Json.JsonElement.JsonNumber(bd)) =>
                BigDecimal.tryToFloat64(bd)
                  |> Option.flatMap(Float64.tryToInt32)
                  |> Option.getWithDefault(0i32)
            case _ => 0i32
        };
        let spinner: Spinner[Integer] = new Spinner(-999999i32, 999999i32, current);
        spinner.setEditable(true);
        spinner.setPrefWidth(110.0);
        spinner.setMaxWidth(110.0);
        spinner.valueProperty().addListener(new ChangeListener[Integer] {
            def changed(_cThis: ChangeListener[Integer], _obs: ObservableValue[JObject],
                         _old: Integer, newVal: Integer): Unit \ IO = {
                let v: Int32 = newVal.intValue();
                commitFieldJson(state, keyPath,
                                 Json.JsonElement.JsonNumber(intToBd(v)))
            }
        });
        checked_cast(spinner)
    }

    /// Float フィールド: Spinner<Double> (step 0.1)
    def buildFloatWidget(state: IdeState.IdeState, value: Option[Json.JsonElement],
                          keyPath: List[String]): Node \ IO = {
        let current: Float64 = match value {
            case Some(Json.JsonElement.JsonNumber(bd)) =>
                BigDecimal.tryToFloat64(bd) |> Option.getWithDefault(0.0)
            case _ => 0.0
        };
        let spinner: Spinner[Double] = new Spinner(-999999.0, 999999.0, current, 0.1);
        spinner.setEditable(true);
        spinner.setPrefWidth(110.0);
        spinner.setMaxWidth(110.0);
        spinner.valueProperty().addListener(new ChangeListener[Double] {
            def changed(_cThis: ChangeListener[Double], _obs: ObservableValue[JObject],
                         _old: Double, newVal: Double): Unit \ IO = {
                let v: Float64 = newVal.doubleValue();
                commitFieldJson(state, keyPath,
                                 Json.JsonElement.JsonNumber(floatToBd(v)))
            }
        });
        checked_cast(spinner)
    }

    def buildBoolWidget(state: IdeState.IdeState, value: Option[Json.JsonElement],
                         keyPath: List[String]): Node \ IO = {
        let current = match value {
            case Some(Json.JsonElement.JsonBool(b)) => b
            case _                                  => false
        };
        let check = new CheckBox();
        check.setSelected(current);
        check.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO =
                commitFieldJson(state, keyPath,
                                 Json.JsonElement.JsonBool(check.isSelected()))
        });
        checked_cast(check)
    }

    /// 編集を editingJson に反映 + dirty フラグ + 即ファイル書き戻し。
    /// HotReload watcher が拾って次フレームで scene 再 load される
    def commitFieldJson(state: IdeState.IdeState, keyPath: List[String],
                         newValue: Json.JsonElement): Unit \ IO =
        match ResourceState.getEditingJson(state#resource) {
            case None => ()
            case Some(json) => {
                let updated = JsonOps.setAtKeyPath(json, keyPath, newValue);
                ResourceState.setEditingJson(state#resource, Some(updated));
                ResourceState.setDirty(state#resource, true);
                match ResourceState.getSelectedDataPath(state#resource) {
                    case None => ()
                    case Some(path) => {
                        let pretty = Json.Write.toPrettyString(2i32, updated);
                        discard Files.writeString(Paths.get(path), pretty);
                        println("[Resources] saved field at ${keyPath}")
                    }
                }
            }
        }

    def intToBd(value: Int32): BigDecimal =
        unsafe IO {
            let stripped = JBigDecimal.valueOf(Int32.toFloat64(value)).stripTrailingZeros();
            if (stripped.scale() < 0) stripped.setScale(0) else stripped
        }

    def floatToBd(value: Float64): BigDecimal =
        JBigDecimal.valueOf(value)

    def jsonFieldOf(record: Json.JsonElement, key: String): Option[Json.JsonElement] =
        match record {
            case Json.JsonElement.JsonObject(m) => Map.get(key, m)
            case _                              => None
        }

    /// record JSON を DFS で walk して、textureNamesRef に含まれる文字列値を探す。
    /// 見つかれば texture 名を返す。"sprite.texture" のような典型ケースを拾える
    pub def findFirstTexture(state: IdeState.IdeState, record: Json.JsonElement):
            Option[String] \ IO = {
        let textureNames = Array.get(0, state#textureNamesRef) |> List.toSet;
        scanForTexture(record, textureNames)
    }

    def scanForTexture(elem: Json.JsonElement, textureNames: Set[String]):
            Option[String] \ IO =
        match elem {
            case Json.JsonElement.JsonString(s) =>
                if (Set.memberOf(s, textureNames)) Some(s) else None
            case Json.JsonElement.JsonObject(m) =>
                Map.foldLeftWithKey((acc, _k, v) -> match acc {
                    case Some(_) => acc
                    case None    => scanForTexture(v, textureNames)
                }, None, m)
            case _ => None
        }

    /// texture name (textureNamesRef のキー) から絶対パスを引いて JavaFX Image をロードし、
    /// resourcePreviewPane に ImageView として乗せる。None なら "(no preview)" 表示
    pub def updateSpritePreview(state: IdeState.IdeState, textureName: Option[String]): Unit \ IO =
        withRef(state#fxResourcePreviewPaneRef, pane -> {
            let children = pane.getChildren();
            children.clear();
            match textureName {
                case None => {
                    let l = new Label("(no preview)");
                    l.getStyleClass().add("inspector-empty");
                    let n: Node = checked_cast(l);
                    discard children.add(n)
                }
                case Some(name) => {
                    let pathMap = Array.get(0, state#texturePathMapRef);
                    match Map.get(name, pathMap) {
                        case None => {
                            let l = new Label("(path unknown: ${name})");
                            l.getStyleClass().add("inspector-empty");
                            let n: Node = checked_cast(l);
                            discard children.add(n)
                        }
                        case Some(absPath) => {
                            let url = new File(absPath).toURI().toString();
                            let image = new Image(url);
                            let view = new ImageView(image);
                            view.setPreserveRatio(true);
                            view.setFitWidth(220.0);
                            view.setFitHeight(220.0);
                            let n: Node = checked_cast(view);
                            discard children.add(n)
                        }
                    }
                }
            }
        })
}
