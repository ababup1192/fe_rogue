/// flix-json → 標準ライブラリ `Util.Json` 移行用の互換シム (engine PoC)。
///
/// 旧 `mlutze/flix-json` の呼び出し形
///   - `Json.FromJson.getAtKey(Root, key, map)` / `getAtKeyOpt(...)`
///   - `JsonError(Root, Set#{...})`
///   - `Json.Parse.parse(text)` (Option 返し)
/// を、標準 `Util.Json` の API へそのまま委譲する。これにより engine 側コードの
/// 呼び出しサイトをほぼ無改変のまま移行できる。
///
/// flix-json はエラーに `Json.Path` 接頭辞を持たせていたが、`Util.Json` は decode 時に
/// 内部でパスを構築するため、呼び出し側が渡すパス接頭辞 (`Root`) は捨てる。
mod JsonCompat {
    use Util.Json.Json
    use Util.Json.Json.JObject
    use Util.Json.JsonError
    use Util.Json.JsonError.JsonError.Decode
    use Util.Json.JsonError.DecodeErrorKind.TypeMismatch
    use Util.Json.JsonPath
    use Util.Json.FromJson.FromJson

    /// flix-json `Json.Path.Path.Root` の代替。`Util.Json` ではパス接頭辞を使わないので
    /// 値としては無意味だが、旧呼び出し形 `(Root, key, map)` を保つためのプレースホルダ。
    pub enum PathTag { case Root }

    /// `Json.FromJson.getAtKey(Root, key, map)` 互換。map を JObject に包んで委譲。
    /// キーが無ければ `Err`（MissingKey）。
    pub def getAtKey(_p: PathTag, key: String, m: Map[String, Json]): Result[JsonError, a] \ {} with FromJson[a] =
        Util.Json.FromJson.decodeAtKey(key, JObject(m))

    /// `Json.FromJson.getAtKeyOpt(Root, key, map)` 互換。
    /// キー欠落で `Ok(None)`・存在&デコード可で `Ok(Some)`・型不一致で `Err`
    /// （flix-json と同セマンティクス）。
    pub def getAtKeyOpt(_p: PathTag, key: String, m: Map[String, Json]): Result[JsonError, Option[a]] \ {} with FromJson[a] =
        Util.Json.FromJson.decodeAtKeyOpt(key, JObject(m))

    /// `JsonError(Root, Set#{...})` 互換。説明文字列群を 1 つの TypeMismatch にまとめる。
    pub def jsonError(_p: PathTag, msgs: Set[String]): JsonError =
        Decode(JsonPath.empty(), TypeMismatch(String.intercalate("; ", Set.toList(msgs))))

    /// flix-json `Json.Parse.parse` 互換（Option 返し）。
    /// `Util.Json.parse` は `Result` 返しなので Option に変換する。
    pub def parse(s: String): Option[Json] =
        Util.Json.parse(s) |> Result.toOption
}
