// SceneJsonIndex — scene.json 群を走査して「ルートノード名 → JSON ファイルパス」索引を作る
//
// エディタが選択したノードを書き戻すとき、どの scene.json に戻すかを判定するために使う。
// Game.start で 1 回だけ呼んで結果を `EditorStateData#rootJsonIndex` に保持する想定
// （毎フレーム glob し直さない）

mod SceneJsonIndex {
    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonArray, JsonString}

    /// src/scenes 配下の *.scene.json をすべて走査し、各ファイルのルートノード名から
    /// JSON ファイルパスを引けるインデックスを作る。
    /// JSON ルートが配列なら配列要素ごとに、オブジェクトならその "name" を採用する。
    /// 同じ root 名が複数の JSON ファイルにあった場合は後勝ち（実害はない想定）
    pub def load(): Map[NodeName, String] \ {Fs.Glob, Fs.FileRead} =
        Fs.Glob.glob("src/scenes", "*.scene.json")
            |> Result.getWithDefault(Nil)
            |> List.foldLeft((acc, path) -> mergeRootsFromFile(path, acc), Map.empty())

    /// JSON ルート（オブジェクト or 配列）から各要素の "name" 文字列を取り出す。
    /// 単体テストしやすいよう pub
    pub def rootNamesOf(json: JsonElement): List[NodeName] =
        match json {
            case JsonObject(_) =>
                nameOf(json) |> Option.toList
            case JsonArray(arr) =>
                Vector.toList(arr) |> List.filterMap(nameOf)
            case _ => Nil
        }

    /// 1 ファイルから root 名を抜き出して acc にマージする
    def mergeRootsFromFile(path: String, acc: Map[NodeName, String]):
            Map[NodeName, String] \ Fs.FileRead =
        let content = run { Fs.ReadFile.read(path) } with Fs.ReadFile.runWithFileRead;
        match content {
            case Err(_) => acc
            case Ok(text) =>
                match Json.Parse.parse(String.trim(text)) {
                    case None => acc
                    case Some(json) =>
                        rootNamesOf(json) |> List.foldLeft((m, name) ->
                            Map.insert(name, path, m), acc)
                }
        }

    /// 単一 JSON オブジェクトの "name" フィールドを取り出す
    def nameOf(json: JsonElement): Option[NodeName] =
        match json {
            case JsonObject(map) =>
                match Map.get("name", map) {
                    case Some(JsonString(s)) => Some(s)
                    case _                   => None
                }
            case _ => None
        }
}
