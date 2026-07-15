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

    /// version が無いか 1 なら OK。それ以外は docName 入りの文で断る。
    pub def checkVersion(docName: String, top: Map[String, Json]): Result[JsonError, Unit] =
        match (getAtKeyOpt(PathTag.Root, "version", top): Result[JsonError, Option[Int32]]) {
            case Err(e)      => Err(e)
            case Ok(None)    => Ok(())
            case Ok(Some(1)) => Ok(())
            case Ok(Some(v)) => Err(jsonError(PathTag.Root, Set#{"unsupported ${docName} version ${v} (supported: 1)"}))
        }

    /// path のファイルを読んで JSON にする。読めない・崩れているときは Err で返す。
    pub def readJson(path: String): Result[JsonError, Json] \ Fs.FileRead =
        let content = run { Fs.ReadFile.read(path) } with Fs.ReadFile.runWithFileRead;
        content
            |> Result.mapErr(readError -> jsonError(PathTag.Root, Set#{"failed to read: ${readError}"}))
            |> Result.flatMap(text -> parse(String.trim(text))
                |> Option.toOk(jsonError(PathTag.Root, Set#{"JSON parse failed: ${path}"})))

    /// JSON オブジェクトなら中身の Map を返す。違えば label 入りの文で断る。
    pub def asObject(label: String, json: Json): Result[JsonError, Map[String, Json]] =
        match json {
            case JObject(m) => Ok(m)
            case _          => Err(jsonError(PathTag.Root, Set#{"${label} must be a JSON object"}))
        }

    /// key の数値（必須）。
    pub def numAt(key: String, m: Map[String, Json]): Result[JsonError, Float64] =
        (getAtKey(PathTag.Root, key, m): Result[JsonError, Float64])

    /// key の数値（無ければ fallback）。
    pub def numOr(key: String, fallback: Float64, m: Map[String, Json]): Result[JsonError, Float64] =
        (getAtKeyOpt(PathTag.Root, key, m): Result[JsonError, Option[Float64]])
            |> Result.map(Option.getWithDefault(fallback))

    /// エラーにノードの名前パス（例: "gallery/row1/box"）を前置する。ドキュメント木のパーサが
    /// 「どのノードで失敗したか」を編集者へ伝える口。子のエラーは子が既にタグ済みなので、
    /// 呼び側はノード自身のフィールド解析だけを包むこと（二重前置を避ける）。
    pub def atNode(path: String, r: Result[JsonError, a]): Result[JsonError, a] =
        Result.mapErr(e -> Decode(JsonPath.empty(), TypeMismatch("at ${path}: ${describe(e)}")), r)

    /// エラーを編集者向けの一文にする。jsonError / atNode が詰めた文章は `TypeMismatch` の器を
    /// 借りているだけなので、器の定型句（"type mismatch: expected"）を剥がして中身だけ返す。
    /// Util.Json 由来の本物の型不一致（メッセージが "Float64" 等の型名 1 語）まで裸にすると
    /// 文脈が消えるので、空白を含む文章のときだけ剥がす。
    pub def describe(e: JsonError): String =
        match e {
            case Decode(_, TypeMismatch(msg)) =>
                if (String.contains(substr = " ", msg)) msg else "${e}"
            case other => "${other}"
        }
}
