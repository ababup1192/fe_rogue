/// Godot Resource 風の汎用「データ + UI ヒント」抽象。
///
/// 各ゲームは独自のデータ型（例: `UnitCatalog`）を持ち、その値は JSON で永続化される。
/// 加えて IDE が編集 UI を組み立てるための `_schema.json` をサイドカーとして配置する。
/// このモジュールは schema 側の規格と最小限のロード/検査ヘルパだけを提供する。
///
/// 設計方針:
///   - schema は **どんなフィールドが存在し、どう編集すべきか** だけを記述する
///     （catalog / single など「ファイル全体の形」は data の構造で示し、schema には含めない）
///   - schema は `Saveable` 経由で round-trip 可能 → IDE で編集 → ファイルに書き戻し可能
///   - Flix 型 ↔ schema の同期はゲーム側責任。`checkConsistency` で起動時に検査する
///
/// 別ジャンルの Resource を追加するときは `_schema.json` をこの規格で書き、
/// 自前の data 型に `instance Saveable[T]` を実装するだけで engine の機構に乗る。
mod Resource {
    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonString, JsonNumber, JsonBool, JsonArray, JsonNull}

    /// フィールドの値型。IDE はこれと `FieldHint` の組から widget を選ぶ。
    ///   RefT(target) : 値が別 catalog の sub-entry id を指す（例: 武器 id）。IDE は
    ///                  `target` 配下の sub-entries を ComboBox 候補に並べる。
    ///                  schema JSON では `{"type": "ref", "to": target}` で表す。
    ///   RefPercentListT(target) : 値が `[{id, percent}]` の object 配列。各要素は
    ///                  `target` catalog の sub-entry id への ref と 0-100 整数のペア。
    ///                  fe_rogue の floor spawn テーブル等に使う。
    ///                  schema JSON では `{"type": "refPercentList", "to": target}` で表す。
    pub enum FieldType {
        case TextT
        case IntT
        case FloatT
        case BoolT
        case TexturePathT      // プロジェクト登録済みテクスチャから選択
        case RefT(String)      // 別 catalog (containerKey = target) の sub-entry id
        case RefPercentListT(String)  // [{id: ref, percent: 0-100}] の動的長配列
        case EnumT(List[String])      // 有限の文字列選択肢（Godot @export_enum 相当）。
                                       // IDE は 2 値なら ToggleGroup、3 値以上なら ComboBox を出す。
                                       // schema JSON では `{"type": "enum", "values": ["A", "B"]}` で表す。
    }

    /// 編集 UI のヒント。`Plain` は型相応の素直な入力欄（数値スピナー / テキスト等）。
    /// `Multiline` は TextT に対して使うと複数行 TextArea で編集できる。
    /// 各 payload は anonymous record なので Eq / ToString 自動 derive はせず、
    /// 必要なら手動 instance を定義する方針。
    pub enum FieldHint {
        case Plain
        case Multiline
        case Slider({min = Float64, max = Float64, step = Float64})
        case Spinner({min = Int32, max = Int32})
        case FrameGrid({hframesField = String, vframesField = String})
    }

    /// 1 フィールドぶんの完全記述。
    /// `order` は IDE での表示順を明示するための補助フィールド（小さい値が先頭）。
    /// 指定なし（`None`）なら IDE 側のデフォルト並び（priority + alphabetical）が使われる。
    /// Godot の @export_group / @export_subgroup と同じく、デザイナの意図する自然な並びを
    /// schema 側で宣言できるようにするための拡張。
    pub type alias FieldSchema = {
        ftype = FieldType,
        hint  = FieldHint,
        label = String,
        order = Option[Int32]
    }

    /// レコード 1 件のフィールド木。`Field` は葉、`Nested` はサブレコード。
    pub enum FieldEntry {
        case Field(FieldSchema)
        case Nested(Map[String, FieldEntry])
    }

    /// catalog 外のトップレベル array (例: `players: ["knight", ...]`) の編集 UI を決めるヒント。
    ///   Ref(target)  : 要素が `target` という catalog コンテナの sub-entry id を指す。
    ///                  IDE は data の `target` 配下の sub-entries を dropdown 候補に並べる。
    ///                  例: `Ref("units")` なら units 配下の knight/archer/... が候補。
    ///   Text         : 要素が任意の文字列 (catalog id ではない)。IDE は JTextField で自由入力。
    /// schema 表記:
    ///   {"type": "ref", "to": "units"}  → Ref("units")
    ///   {"type": "text"}                → Text
    pub enum MetaHint with Eq, ToString {
        case Ref(String)
        case Text
    }

    /// ファイル単位の schema。fields は catalog 子レコードのフィールド構造、metaHints は data top の
    /// catalog 外フィールド (= メタ array) の編集 UI ヒント。
    /// metaHints は省略可能 (デコード時に欠落していれば空 Map になる) → 後方互換。
    pub enum ResourceSchema {
        case ResourceSchema({
            fields    = Map[String, FieldEntry],
            metaHints = Map[String, MetaHint]
        })
    }

    /// `ResourceSchema` の中身（フィールド集合）を取り出す。
    pub def fieldsOf(schema: ResourceSchema): Map[String, FieldEntry] =
        let ResourceSchema.ResourceSchema(payload) = schema;
        payload#fields

    /// メタフィールドの編集ヒントを取り出す。指定されていなければ空 Map。
    pub def metaHintsOf(schema: ResourceSchema): Map[String, MetaHint] =
        let ResourceSchema.ResourceSchema(payload) = schema;
        payload#metaHints

    /// `Map[String, FieldEntry]` から `ResourceSchema` を作るコンストラクタ。
    /// metaHints は空 Map で初期化する。
    pub def mkSchema(fields: Map[String, FieldEntry]): ResourceSchema =
        ResourceSchema.ResourceSchema({fields = fields, metaHints = Map.empty()})

    /// fields と metaHints を両方指定するコンストラクタ。
    pub def mkSchemaWithMeta(fields: Map[String, FieldEntry], metaHints: Map[String, MetaHint]):
            ResourceSchema =
        ResourceSchema.ResourceSchema({fields = fields, metaHints = metaHints})

    /// `_schema.json` をパースして `ResourceSchema` を返す。形式不一致は `None`。
    /// 失敗ハンドリングは呼び出し側に任せる（panic にしたい場合は `Option.getWithDefault(?bug(...))`）。
    pub def loadSchema(path: String): Option[ResourceSchema] \ Fs.FileRead =
        Persistence.load(path)

    /// `loadSchema` の診断つきバリアント。失敗の段階を文字列で返す。
    /// `Game.start` から呼んで起動時に panic させるとファイル不在 / JSON parse / decode の
    /// どこで失敗したかが一目でわかる。
    pub def loadSchemaDiagnostic(path: String): Result[String, ResourceSchema] \ Fs.FileRead =
        let readResult = run {
            Fs.ReadFile.read(path)
        } with Fs.ReadFile.runWithFileRead;
        match readResult {
            case Err(e) => Err("file read failed (${path}): ${e}")
            case Ok(content) =>
                match Json.Parse.parse(content) {
                    case None => Err("JSON parse failed (${path})")
                    case Some(json) =>
                        let decoded: Option[ResourceSchema] = Saveable.fromJson(json);
                        match decoded {
                            case None    => Err("ResourceSchema decode failed (${path}) — schema JSON does not match engine spec")
                            case Some(s) => Ok(s)
                        }
                }
        }

    /// 整合性検査。schema の **トップレベルフィールド集合** が `expected` の部分集合か検証する。
    /// 過剰フィールド（schema にあるが Flix 型にない）は `Err` を返す。
    /// 不足フィールド（Flix 型にあるが schema にない）は警告として `Err` に含める。
    ///
    /// IDE が schema に頼って widget を出すため、両者がズレるとデザイナが「触れないフィールド」を
    /// 編集できないなどの不整合が起きる。CI / 起動時に必ず通すこと。
    pub def checkConsistency(expected: Set[String], schema: ResourceSchema):
            Result[String, Unit] =
        let actual  = Map.keysOf(fieldsOf(schema));
        let extras  = Set.difference(actual, expected);
        let missing = Set.difference(expected, actual);
        if (Set.isEmpty(extras) and Set.isEmpty(missing)) Ok(())
        else
            let extrasMsg  = if (Set.isEmpty(extras))  "" else "extra fields in schema: ${extras}; ";
            let missingMsg = if (Set.isEmpty(missing)) "" else "missing fields in schema: ${missing}";
            Err("${extrasMsg}${missingMsg}")
}

// ════════════════════════════════════════════════════════════════════════
// Saveable[Resource.ResourceSchema] — `_schema.json` の round-trip 実装
// ════════════════════════════════════════════════════════════════════════
//
// JSON 形状（例）:
//   {
//     "fields": {
//       "hp":  { "field":  { "ftype": "int", "hint": { "slider": { "min": 1, "max": 100, "step": 5 } }, "label": "HP" } },
//       "sprite": { "nested": { "frame": { "field": {...} }, ... } }
//     }
//   }
//
// FieldEntry は `{"field": ...}` か `{"nested": {...}}` の単一キー判別。
// FieldHint は `"plain"`（文字列）または `{"slider": {...}}` 等の単一キー判別。

instance Saveable[Resource.ResourceSchema] {
    pub def toJson(value: Resource.ResourceSchema): Json.JsonElement =
        ResourceCodec.encodeSchema(value)

    pub def fromJson(element: Json.JsonElement): Option[Resource.ResourceSchema] =
        ResourceCodec.decodeSchema(element)
}

/// `ResourceSchema` の JSON エンコード／デコード本体。
/// 外部からは `Saveable[Resource.ResourceSchema]` 経由でしか触らない想定。
mod ResourceCodec {
    import java.math.{BigDecimal => JBigDecimal}

    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonString, JsonNumber, JsonBool, JsonArray}
    use Resource.{ResourceSchema, FieldEntry, FieldSchema, FieldType, FieldHint, MetaHint}

    // ── エンコード ──

    pub def encodeSchema(s: ResourceSchema): JsonElement =
        let meta = Resource.metaHintsOf(s);
        let base = Map#{"fields" => encodeEntries(Resource.fieldsOf(s))};
        if (Map.isEmpty(meta))
            JsonObject(base)
        else
            JsonObject(Map.insert("metaHints", encodeMetaHints(meta), base))

    def encodeMetaHints(meta: Map[String, MetaHint]): JsonElement =
        let inner = meta
            |> Map.foldLeftWithKey((acc, name, hint) ->
                Map.insert(name, encodeMetaHint(hint), acc),
                Map.empty());
        JsonObject(inner)

    def encodeMetaHint(h: MetaHint): JsonElement = match h {
        case MetaHint.Ref(target) =>
            JsonObject(Map#{
                "type" => JsonString("ref"),
                "to"   => JsonString(target)
            })
        case MetaHint.Text =>
            JsonObject(Map#{"type" => JsonString("text")})
    }

    def encodeEntries(entries: Map[String, FieldEntry]): JsonElement =
        let inner = entries
            |> Map.foldLeftWithKey((acc, name, entry) ->
                Map.insert(name, encodeEntry(entry), acc),
                Map.empty());
        JsonObject(inner)

    def encodeEntry(entry: FieldEntry): JsonElement = match entry {
        case FieldEntry.Field(fs) =>
            JsonObject(Map#{"field" => encodeFieldSchema(fs)})
        case FieldEntry.Nested(m) =>
            JsonObject(Map#{"nested" => encodeEntries(m)})
    }

    def encodeFieldSchema(fs: FieldSchema): JsonElement =
        let base = Map#{
            "ftype" => encodeFieldType(fs#ftype),
            "hint"  => encodeFieldHint(fs#hint),
            "label" => JsonString(fs#label)
        };
        let withOrder = match fs#order {
            case Some(n) => Map.insert("order", JsonNumber(intToBd(n)), base)
            case None    => base
        };
        JsonObject(withOrder)

    def encodeFieldType(t: FieldType): JsonElement = match t {
        case FieldType.TextT         => JsonString("text")
        case FieldType.IntT          => JsonString("int")
        case FieldType.FloatT        => JsonString("float")
        case FieldType.BoolT         => JsonString("bool")
        case FieldType.TexturePathT  => JsonString("texturePath")
        case FieldType.RefT(target)  =>
            JsonObject(Map#{
                "type" => JsonString("ref"),
                "to"   => JsonString(target)
            })
        case FieldType.RefPercentListT(target) =>
            JsonObject(Map#{
                "type" => JsonString("refPercentList"),
                "to"   => JsonString(target)
            })
        case FieldType.EnumT(values) =>
            JsonObject(Map#{
                "type"   => JsonString("enum"),
                "values" => JsonArray(List.map(JsonString, values) |> List.toVector)
            })
    }

    def encodeFieldHint(h: FieldHint): JsonElement = match h {
        case FieldHint.Plain         => JsonString("plain")
        case FieldHint.Multiline     => JsonString("multiline")
        case FieldHint.Slider(s)     =>
            JsonObject(Map#{"slider" => JsonObject(Map#{
                "min"  => JsonNumber(floatToBd(s#min)),
                "max"  => JsonNumber(floatToBd(s#max)),
                "step" => JsonNumber(floatToBd(s#step))
            })})
        case FieldHint.Spinner(s)    =>
            JsonObject(Map#{"spinner" => JsonObject(Map#{
                "min" => JsonNumber(intToBd(s#min)),
                "max" => JsonNumber(intToBd(s#max))
            })})
        case FieldHint.FrameGrid(g)  =>
            JsonObject(Map#{"frameGrid" => JsonObject(Map#{
                "hframesField" => JsonString(g#hframesField),
                "vframesField" => JsonString(g#vframesField)
            })})
    }

    /// Float64 → BigDecimal。整数値の trailing zero を取り除いて
    /// `100` (not `100.0`) として書き出す。SaveDataCodec.floatToBd と同じ手法。
    def floatToBd(value: Float64): BigDecimal =
        unsafe IO {
            let stripped = JBigDecimal.valueOf(value).stripTrailingZeros();
            if (stripped.scale() < 0) stripped.setScale(0) else stripped
        }

    /// Int32 → BigDecimal。trailing zero を取り除いて `100` (not `100.0`) として書き出す。
    def intToBd(value: Int32): BigDecimal =
        unsafe IO {
            let stripped = JBigDecimal.valueOf(Int32.toFloat64(value)).stripTrailingZeros();
            if (stripped.scale() < 0) stripped.setScale(0) else stripped
        }

    // ── デコード ──

    pub def decodeSchema(element: JsonElement): Option[ResourceSchema] =
        forM (
            top         <- expectObject(element);
            fieldsJson  <- Map.get("fields", top);
            fieldsMap   <- expectObject(fieldsJson);
            fields      <- decodeEntries(fieldsMap);
            metaHints   <- decodeMetaHintsOpt(top)
        ) yield Resource.mkSchemaWithMeta(fields, metaHints)

    /// `metaHints` セクションは省略可能。欠落していれば空 Map を返す (後方互換)。
    def decodeMetaHintsOpt(top: Map[String, JsonElement]): Option[Map[String, MetaHint]] =
        match Map.get("metaHints", top) {
            case None         => Some(Map.empty())
            case Some(metaJ)  =>
                expectObject(metaJ) |> Option.flatMap(decodeMetaHints)
        }

    def decodeMetaHints(map: Map[String, JsonElement]): Option[Map[String, MetaHint]] =
        Map.foldLeftWithKey((acc, name, json) ->
            Option.flatMap(soFar ->
                decodeMetaHint(json) |> Option.map(h -> Map.insert(name, h, soFar)),
                acc),
            Some(Map.empty()),
            map)

    def decodeMetaHint(element: JsonElement): Option[MetaHint] =
        forM (
            obj    <- expectObject(element);
            typeJ  <- Map.get("type", obj);
            tName  <- expectString(typeJ);
            hint   <- match tName {
                case "ref"  =>
                    Map.get("to", obj)
                        |> Option.flatMap(expectString)
                        |> Option.map(MetaHint.Ref)
                case "text" => Some(MetaHint.Text)
                case _      => None
            }
        ) yield hint

    def decodeEntries(map: Map[String, JsonElement]): Option[Map[String, FieldEntry]] =
        Map.foldLeftWithKey((acc, name, json) ->
            Option.flatMap(soFar ->
                decodeEntry(json) |> Option.map(e -> Map.insert(name, e, soFar)),
                acc),
            Some(Map.empty()),
            map)

    def decodeEntry(element: JsonElement): Option[FieldEntry] =
        expectObject(element)
            |> Option.flatMap(singleEntry)
            |> Option.flatMap(matchEntryKind)

    def matchEntryKind(pair: (String, JsonElement)): Option[FieldEntry] =
        match pair {
            case ("field", payload) =>
                decodeFieldSchema(payload) |> Option.map(FieldEntry.Field)
            case ("nested", payload) =>
                expectObject(payload)
                    |> Option.flatMap(decodeEntries)
                    |> Option.map(FieldEntry.Nested)
            case _ => None
        }

    def decodeFieldSchema(element: JsonElement): Option[FieldSchema] =
        forM (
            obj      <- expectObject(element);
            ftypeJ   <- Map.get("ftype", obj);
            hintJ    <- Map.get("hint",  obj);
            labelJ   <- Map.get("label", obj);
            ftype    <- decodeFieldType(ftypeJ);
            hint     <- decodeFieldHint(hintJ);
            label    <- expectString(labelJ);
            order    <- decodeOrderOpt(obj)
        ) yield ({ftype = ftype, hint = hint, label = label, order = order}: FieldSchema)

    /// `order` フィールドは省略可能。欠落時は `None`、値あり時は `Some(n)`。
    def decodeOrderOpt(obj: Map[String, JsonElement]): Option[Option[Int32]] =
        match Map.get("order", obj) {
            case None      => Some(None)
            case Some(orderJ) => expectInt(orderJ) |> Option.map(Some)
        }

    def decodeFieldType(element: JsonElement): Option[FieldType] = match element {
        case JsonString("text")         => Some(FieldType.TextT)
        case JsonString("int")          => Some(FieldType.IntT)
        case JsonString("float")        => Some(FieldType.FloatT)
        case JsonString("bool")         => Some(FieldType.BoolT)
        case JsonString("texturePath")  => Some(FieldType.TexturePathT)
        case JsonObject(obj)            =>
            forM (
                typeJ <- Map.get("type", obj);
                tName <- expectString(typeJ);
                ftype <- match tName {
                    case "ref" =>
                        Map.get("to", obj)
                            |> Option.flatMap(expectString)
                            |> Option.map(FieldType.RefT)
                    case "refPercentList" =>
                        Map.get("to", obj)
                            |> Option.flatMap(expectString)
                            |> Option.map(FieldType.RefPercentListT)
                    case "enum" =>
                        Map.get("values", obj)
                            |> Option.flatMap(decodeStringList)
                            |> Option.map(FieldType.EnumT)
                    case _     => None
                }
            ) yield ftype
        case _                          => None
    }

    /// `["A", "B", ...]` の JsonArray を List[String] に。
    /// EnumT.values の decoding に使う。
    def decodeStringList(element: JsonElement): Option[List[String]] = match element {
        case JsonArray(items) =>
            List.foldRight(item -> acc ->
                Option.flatMap(soFar ->
                    expectString(item) |> Option.map(s -> s :: soFar),
                    acc),
                Some(Nil), Vector.toList(items))
        case _ => None
    }

    def decodeFieldHint(element: JsonElement): Option[FieldHint] = match element {
        case JsonString("plain")     => Some(FieldHint.Plain)
        case JsonString("multiline") => Some(FieldHint.Multiline)
        case JsonObject(_)           =>
            expectObject(element)
                |> Option.flatMap(singleEntry)
                |> Option.flatMap(matchHintKind)
        case _                       => None
    }

    def matchHintKind(pair: (String, JsonElement)): Option[FieldHint] =
        match pair {
            case ("slider", payload)    => decodeSliderHint(payload)
            case ("spinner", payload)   => decodeSpinnerHint(payload)
            case ("frameGrid", payload) => decodeFrameGridHint(payload)
            case _                      => None
        }

    def decodeSliderHint(element: JsonElement): Option[FieldHint] =
        forM (
            obj   <- expectObject(element);
            minJ  <- Map.get("min",  obj);
            maxJ  <- Map.get("max",  obj);
            stepJ <- Map.get("step", obj);
            mn    <- expectFloat(minJ);
            mx    <- expectFloat(maxJ);
            st    <- expectFloat(stepJ)
        ) yield FieldHint.Slider({min = mn, max = mx, step = st})

    def decodeSpinnerHint(element: JsonElement): Option[FieldHint] =
        forM (
            obj  <- expectObject(element);
            minJ <- Map.get("min", obj);
            maxJ <- Map.get("max", obj);
            mn   <- expectInt(minJ);
            mx   <- expectInt(maxJ)
        ) yield FieldHint.Spinner({min = mn, max = mx})

    def decodeFrameGridHint(element: JsonElement): Option[FieldHint] =
        forM (
            obj  <- expectObject(element);
            hfJ  <- Map.get("hframesField", obj);
            vfJ  <- Map.get("vframesField", obj);
            hf   <- expectString(hfJ);
            vf   <- expectString(vfJ)
        ) yield FieldHint.FrameGrid({hframesField = hf, vframesField = vf})

    // ── ヘルパー ──

    def singleEntry(map: Map[String, JsonElement]): Option[(String, JsonElement)] =
        match Map.toList(map) {
            case head :: Nil => Some(head)
            case _           => None
        }

    def expectObject(element: JsonElement): Option[Map[String, JsonElement]] =
        match element {
            case JsonObject(map) => Some(map)
            case _               => None
        }

    def expectString(element: JsonElement): Option[String] =
        match element {
            case JsonString(text) => Some(text)
            case _                => None
        }

    def expectFloat(element: JsonElement): Option[Float64] = match element {
        case JsonNumber(bd) => BigDecimal.tryToFloat64(bd)
        case _              => None
    }

    def expectInt(element: JsonElement): Option[Int32] = match element {
        case JsonNumber(bd) => BigDecimal.tryToFloat64(bd) |> Option.flatMap(Float64.tryToInt32)
        case _              => None
    }
}
