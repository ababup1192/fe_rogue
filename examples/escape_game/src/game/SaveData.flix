/// Yarn 用セーブデータの型と、その `Saveable` インスタンス。
///
/// 「現在ノード名 + 全変数」を 1 セットにした Yarn 固有のドメイン型 `SaveData`
/// と、それを `Json.JsonElement` に往復させるエンコーダ／デコーダを提供する。
/// I/O 自体は `engine/SaveManager.flix` の `SaveManager.write` /
/// `SaveManager.read` が `Saveable` 経由で行う。
///
/// Value 表現は `yarn/output.json` の `initialValues` と同形式
/// （`{"boolValue":..}` / `{"floatValue":..}` / `{"stringValue":..}`）。
///
/// 別ジャンルのデータを永続化したいときは、独自の型と
/// `instance Saveable[MyType]` を別ファイルで定義すれば `SaveManager` を
/// そのまま流用できる。
mod Game.SaveData {
    use Yarn.Types.Value

    /// セーブファイル 1 つ分の中身。`(NodeName, Variables)` の tuple を 1 ケース
    /// enum に包む。Flix の record は Eq derive 不可なので位置引数で持つ。
    /// アクセサ `nodeName` / `variables` を別途公開する。
    pub enum SaveData with Eq, ToString {
        case SaveData(NodeName, Variables)
    }

    /// セーブ復元時に再開する Yarn ノードの名前。
    pub type alias NodeName = String

    /// セーブ時点での Yarn 変数スナップショット（変数名 → 値）。
    pub type alias Variables = Map[String, Value]

    /// `SaveData` の `nodeName` を取り出す。
    pub def nodeName(data: SaveData): NodeName =
        let SaveData.SaveData(name, _) = data;
        name

    /// `SaveData` の `variables` を取り出す。
    pub def variables(data: SaveData): Variables =
        let SaveData.SaveData(_, vars) = data;
        vars
}

// ════════════════════════════════════════════════════════════════════════
// Saveable インスタンス（Yarn SaveData ↔ JSON）
// ════════════════════════════════════════════════════════════════════════
//
// engine 側 SaveManager / Persistence から呼ばれるエンコード／デコード本体。
// Yarn の Value 表現を含むため Yarn ランタイムを知っているが、永続化の I/O
// 自体は engine 側の汎用機構に委ねている（責務分離）。

instance Saveable[Game.SaveData.SaveData] {
    pub def toJson(data: Game.SaveData.SaveData): Json.JsonElement =
        SaveDataCodec.encode(data)

    pub def fromJson(element: Json.JsonElement): Option[Game.SaveData.SaveData] =
        SaveDataCodec.decode(element)
}

/// SaveData の JSON エンコード／デコード実装。
/// 外部からは `Saveable[Game.SaveData.SaveData]` 経由でしか触らない想定。
mod SaveDataCodec {
    import java.math.{BigDecimal => JBigDecimal}

    use Yarn.Types.Value
    use Yarn.Types.Value.{BoolV, FloatV, StringV}
    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonString, JsonNumber, JsonBool}
    use Game.SaveData.SaveData

    // ── エンコード ──

    /// `SaveData` → `JsonElement`。`{"node":..., "variables":{...}}`。
    pub def encode(data: SaveData): JsonElement =
        let SaveData.SaveData(name, vars) = data;
        let variablesJson = vars
            |> Map.foldLeftWithKey((acc, varName, value) ->
                Map.insert(varName, encodeValue(value), acc),
                Map.empty());
        JsonObject(Map#{
            "node"      => JsonString(name),
            "variables" => JsonObject(variablesJson)
        })

    /// `Value` → `{"boolValue"|"floatValue"|"stringValue": ...}`。
    /// `output.json` の `initialValues` と同じ表現。
    def encodeValue(value: Value): JsonElement = match value {
        case BoolV(b)   => JsonObject(Map#{"boolValue"   => JsonBool(b)})
        case FloatV(n)  => JsonObject(Map#{"floatValue"  => JsonNumber(floatToBd(n))})
        case StringV(s) => JsonObject(Map#{"stringValue" => JsonString(s)})
    }

    /// Float64 → BigDecimal。整数値の trailing zero を取り除いて
    /// `100` (not `100.0`) として書き出す。`output.json` の `initialValues` と同じ書式。
    /// `stripTrailingZeros` 単体だと `50.0` が `5E+1`（scale=-1）になって
    /// 科学技術表記で書かれてしまうので、scale が負なら 0 に戻して
    /// プレーン整数として `50` と書けるようにする。
    /// Java の `BigDecimal.valueOf` を使うため import を `JBigDecimal` で別名化、
    /// 読み込み側の Flix stdlib `BigDecimal` 名前空間と衝突しないようにしている。
    def floatToBd(value: Float64): BigDecimal =
        unsafe IO {
            let stripped = JBigDecimal.valueOf(value).stripTrailingZeros();
            if (stripped.scale() < 0) stripped.setScale(0) else stripped
        }

    // ── デコード ──

    /// `JsonElement` → `Option[SaveData]`。形式不一致は `None`。
    /// forM で「全部 Some なら Some(SaveData)、ひとつでも None なら None」を平らに表現。
    pub def decode(element: JsonElement): Option[SaveData] =
        forM (
            top      <- expectObject(element);
            nodeJson <- Map.get("node", top);
            varsJson <- Map.get("variables", top);
            node     <- expectString(nodeJson);
            varsMap  <- expectObject(varsJson);
            vars     <- traverseVariables(varsMap)
        ) yield SaveData.SaveData(node, vars)

    /// `Map[String, JsonElement]` の全要素を `decodeValue` に通す。
    /// 1 つでも失敗したら全体 `None`。foldLeftWithKey で `Option` を畳む。
    def traverseVariables(map: Map[String, JsonElement]):
                           Option[Map[String, Value]] =
        Map.foldLeftWithKey((acc, name, json) ->
            Option.flatMap(soFar ->
                decodeValue(json) |> Option.map(v -> Map.insert(name, v, soFar)),
                acc),
            Some(Map.empty()),
            map)

    /// 1 変数値の JSON → `Value`。`{kind: payload}` の単一キー判別を
    /// `expectObject |> singleEntry |> matchValueKind` の 3 段パイプで表現。
    def decodeValue(element: JsonElement): Option[Value] =
        expectObject(element)
            |> Option.flatMap(singleEntry)
            |> Option.flatMap(matchValueKind)

    /// `Map` がちょうど 1 エントリなら `(key, value)` を返す。それ以外は `None`。
    def singleEntry(map: Map[String, JsonElement]):
                     Option[(String, JsonElement)] =
        match Map.toList(map) {
            case head :: Nil => Some(head)
            case _           => None
        }

    /// `(kind, payload)` を `Value` のいずれかに対応付ける。
    /// `floatValue` は `tryToFloat64` の None をそのまま伝播させる
    /// （壊れた数値で 0.0 にフォールバックしない）。
    def matchValueKind(pair: (String, JsonElement)): Option[Value] =
        match pair {
            case ("boolValue",   JsonBool(b))   => Some(BoolV(b))
            case ("floatValue",  JsonNumber(n)) =>
                BigDecimal.tryToFloat64(n) |> Option.map(FloatV)
            case ("stringValue", JsonString(s)) => Some(StringV(s))
            case _                               => None
        }

    /// `JsonObject` なら中身の Map を、それ以外は `None`。
    def expectObject(element: JsonElement): Option[Map[String, JsonElement]] =
        match element {
            case JsonObject(map) => Some(map)
            case _               => None
        }

    /// `JsonString` なら中身の文字列、それ以外は `None`。
    def expectString(element: JsonElement): Option[String] =
        match element {
            case JsonString(text) => Some(text)
            case _                => None
        }
}
