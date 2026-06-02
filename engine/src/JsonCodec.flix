/// JSON encode/decode 用の汎用ヘルパ。各 catalog / resource の Codec mod がコピーしていた
/// 小関数を 1 箇所に集約する。
///
/// **設計の柱**: decode 系は完全 pure (`JsonElement -> Option[T]`)、encode 用の BigDecimal
/// 変換 (`floatToBd` / `intToBd`) は内部 `unsafe IO {}` で副作用を隠蔽し、戻り型は `BigDecimal`
/// (pure)。これにより呼び出し側の `Saveable.toJson` / `fromJson` は両方 pure シグネチャに保てる。
/// 既存 `engine/src/Resource.flix:322-333` の `ResourceCodec.floatToBd / intToBd` と同方針。
///
/// 各 Codec mod から段階的に重複 helper を取り除き、本 mod への参照に切り替える
/// (engine 内ドッグフード)。
mod JsonCodec {
    import java.math.{BigDecimal => JBigDecimal}

    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonString, JsonNumber, JsonBool, JsonArray}

    // ════════════════════════════════════════════════════════
    // 値の取り出し: 期待型ならその中身を、そうでなければ None を返す
    // ════════════════════════════════════════════════════════

    /// JSON object なら中身の Map を、そうでなければ None を返す。
    pub def expectObject(element: JsonElement): Option[Map[String, JsonElement]] =
        match element {
            case JsonObject(map) => Some(map)
            case _               => None
        }

    /// JSON 文字列なら中身を返す。
    pub def expectString(element: JsonElement): Option[String] =
        match element {
            case JsonString(text) => Some(text)
            case _                => None
        }

    /// JSON 数値を Int32 として取り出す。`BigDecimal -> Float64 -> Int32` の 2 段変換。
    /// 範囲外 / 小数 / 数値以外は None。
    pub def expectInt(element: JsonElement): Option[Int32] =
        match element {
            case JsonNumber(bd) =>
                BigDecimal.tryToFloat64(bd) |> Option.flatMap(Float64.tryToInt32)
            case _              => None
        }

    /// JSON 数値を Float64 として取り出す。数値以外は None。
    pub def expectFloat(element: JsonElement): Option[Float64] =
        match element {
            case JsonNumber(bd) => BigDecimal.tryToFloat64(bd)
            case _              => None
        }

    /// JSON 真偽値を取り出す。真偽値以外は None。
    pub def expectBool(element: JsonElement): Option[Bool] =
        match element {
            case JsonBool(value) => Some(value)
            case _               => None
        }

    // ════════════════════════════════════════════════════════
    // 数値変換: 内部 unsafe IO で副作用を隠蔽し pure シグネチャで提供
    // ════════════════════════════════════════════════════════

    /// `Float64` を `BigDecimal` に。trailing zero 除去で「100」(「100.0」ではなく) として書き出す。
    /// scale が負になった場合 (= 「1E+2」のような指数表記になるケース) は 0 に補正して
    /// 通常表記「100」を維持する。内部 `unsafe IO` で隠蔽するため呼び出し側は pure として扱える。
    pub def floatToBd(value: Float64): BigDecimal =
        unsafe IO {
            let stripped = JBigDecimal.valueOf(value).stripTrailingZeros();
            if (stripped.scale() < 0) stripped.setScale(0) else stripped
        }

    /// `Int32` を `BigDecimal` に。trailing zero 除去で「100」として書き出す。
    /// scale が負になる場合は 0 に補正して「100」表記を維持する。
    pub def intToBd(value: Int32): BigDecimal =
        unsafe IO {
            let stripped = JBigDecimal.valueOf(Int32.toFloat64(value)).stripTrailingZeros();
            if (stripped.scale() < 0) stripped.setScale(0) else stripped
        }

    // ════════════════════════════════════════════════════════
    // Map[String, T] の round-trip
    // ════════════════════════════════════════════════════════

    /// `Map[String, T]` を JSON object として encode する。`encodeEntry` は 1 要素 encoder。
    pub def encodeStringMap(encodeEntry: t -> JsonElement, entries: Map[String, t]): JsonElement =
        let inner = entries |> Map.foldLeftWithKey(
            (acc, key, entry) -> Map.insert(key, encodeEntry(entry), acc),
            Map.empty()
        );
        JsonObject(inner)

    /// JSON object を `Map[String, T]` として decode する。要素のいずれかが None なら全体 None。
    /// schema 不整合の検出は全体 None で受けるため、部分成功を許さない設計。
    pub def decodeStringMap(decodeEntry: JsonElement -> Option[t], element: JsonElement):
            Option[Map[String, t]] =
        match element {
            case JsonObject(map) =>
                Map.foldLeftWithKey(
                    (acc, key, entryJson) ->
                        Option.flatMap(soFar ->
                            decodeEntry(entryJson)
                                |> Option.map(decoded -> Map.insert(key, decoded, soFar)),
                            acc),
                    Some(Map.empty()),
                    map)
            case _ => None
        }

    // ════════════════════════════════════════════════════════
    // List[T] の round-trip
    // ════════════════════════════════════════════════════════

    /// `List[T]` を JSON array として encode する。
    pub def encodeList(encodeEntry: t -> JsonElement, entries: List[t]): JsonElement =
        JsonArray(List.map(encodeEntry, entries) |> List.toVector)

    /// JSON array を `List[T]` として decode する。要素のいずれかが None なら全体 None。
    pub def decodeList(decodeEntry: JsonElement -> Option[t], element: JsonElement):
            Option[List[t]] =
        match element {
            case JsonArray(items) =>
                List.foldRight(item -> acc ->
                    Option.flatMap(soFar ->
                        decodeEntry(item) |> Option.map(decoded -> decoded :: soFar),
                        acc),
                    Some(Nil),
                    Vector.toList(items))
            case _ => None
        }

    // ════════════════════════════════════════════════════════
    // Vec2 の round-trip (offset / scale の defensive default を含む)
    // ════════════════════════════════════════════════════════

    /// `{x: Float, y: Float}` の Vec2 を JSON object に encode する。
    pub def encodeVec2(vec: Vec2.Vec2): JsonElement =
        JsonObject(Map#{
            "x" => JsonNumber(floatToBd(vec#x)),
            "y" => JsonNumber(floatToBd(vec#y))
        })

    /// JSON object を Vec2 に decode する。x/y どちらか欠落でも 0.0 で補完。
    pub def decodeVec2(element: JsonElement): Option[Vec2.Vec2] =
        match element {
            case JsonObject(obj) =>
                let x = Map.get("x", obj) |> Option.flatMap(expectFloat)
                          |> Option.getWithDefault(0.0);
                let y = Map.get("y", obj) |> Option.flatMap(expectFloat)
                          |> Option.getWithDefault(0.0);
                Some({x = x, y = y})
            case _ => None
        }

    /// `Option[JsonElement]` を Vec2 に。欠落 / 不正なら `(defaultValue, defaultValue)`。
    /// `offset` (default 0.0) / `scale` (default 1.0) の defensive default で使う。
    pub def decodeVec2OrDefault(optElement: Option[JsonElement], defaultValue: Float64):
            Vec2.Vec2 =
        match optElement {
            case None          => {x = defaultValue, y = defaultValue}
            case Some(element) => match decodeVec2(element) {
                case Some(value) => value
                case None        => {x = defaultValue, y = defaultValue}
            }
        }
}
