// JsonCompat — flix-json 形式の JSON 呼び出しを、標準ライブラリ `Util.Json` の API へそのまま委譲する。
// これで既存コードの呼び出しサイトを書き換えずに、標準の JSON 実装を使える。
// 利用例: `getAtKey(Root, key, map)` でキーを引く / `parse(text)` で文字列を JSON にする。
// 注意: flix-json はエラーにパス接頭辞 (`Root`) を持たせるが、`Util.Json` は decode 時に内部で
//   パスを構築するため、呼び出し側が渡す接頭辞は捨てる。
//
// 対応する呼び出し形:
//   - `getAtKey(Root, key, map)` / `getAtKeyOpt(...)`
//   - `jsonError(Root, Set#{...})`
//   - `parse(text)` (Option 返し)
mod JsonCompat {
    use Util.Json.Json
    use Util.Json.Json.JObject
    use Util.Json.JsonError
    use Util.Json.JsonError.JsonError.Decode
    use Util.Json.JsonError.DecodeErrorKind.TypeMismatch
    use Util.Json.JsonPath
    use Util.Json.FromJson.FromJson

    /// flix-json `Json.Path.Path.Root` の代替。`Util.Json` ではパス接頭辞を使わないので
    /// 値としては無意味だが、呼び出し形 `(Root, key, map)` を保つためのプレースホルダ。
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

    /// エラーにノードの名前パス（例: "gallery/row1/box"）を前置する。ドキュメント木のパーサが
    /// 「どのノードで失敗したか」を編集者へ伝える口。子のエラーは子が既にタグ済みなので、
    /// 呼び側はノード自身のフィールド解析だけを包むこと（二重前置を避ける）。
    pub def atNode(path: String, r: Result[JsonError, a]): Result[JsonError, a] =
        Result.mapErr(e -> Decode(JsonPath.empty(), TypeMismatch("at ${path}: ${e}")), r)
}
