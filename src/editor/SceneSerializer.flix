// SceneSerializer — scene.json の特定ノードのフィールド（"pos" / "scale" など）を書き戻す
//
// 全 Scene を JSON にシリアライズし直すのではなく、ファイルから JSON を再パースし、
// 指定 NodePath を辿って当該ノードの該当フィールドだけを書き換えてから書き戻す。
// この方針なら NodeTag や状態を持つノード（Bird など）の特殊扱いを考えなくて済む。
//
// 対応するルート JSON 形:
//   - 単一オブジェクト（MenuScene 等）
//   - 配列ルート（複数ルートノード）
//
// NodePath は List[String] で、各要素はノードの "name" と一致する必要がある。
// ルート要素の name から始まり、子は "children" 配列の中から name 一致で辿る。

mod SceneSerializer {
    import java.math.BigDecimal

    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonArray, JsonNumber}

    /// 書き換え対象 1 件: フィールド名 + 上書きする Vec2 値（[x, y] として書き出す）
    pub type alias FieldUpdate = {key = String, value = Vec2.Vec2}

    // ========================================================================
    // 公開 API
    // ========================================================================

    /// 指定 JSON ファイルの NodePath にあるノードの "pos" を newPos で上書きして書き戻す
    pub def updatePos(jsonPath: String, nodePath: NodePath, newPos: Vec2.Vec2):
            Unit \ {Fs.FileRead, Fs.FileWrite} =
        updateFields(jsonPath, nodePath, {key = "pos", value = newPos} :: Nil)

    /// 指定 JSON ファイルの NodePath にあるノードの "scale" を newScale で上書きして書き戻す
    pub def updateScale(jsonPath: String, nodePath: NodePath, newScale: Vec2.Vec2):
            Unit \ {Fs.FileRead, Fs.FileWrite} =
        updateFields(jsonPath, nodePath, {key = "scale", value = newScale} :: Nil)

    /// "pos" と "scale" を同時に上書きする（マウスドラッグでのリサイズ書き戻しで利用）
    pub def updatePosAndScale(jsonPath: String, nodePath: NodePath,
                              newPos: Vec2.Vec2, newScale: Vec2.Vec2):
            Unit \ {Fs.FileRead, Fs.FileWrite} =
        updateFields(jsonPath, nodePath,
            {key = "pos", value = newPos} ::
            {key = "scale", value = newScale} :: Nil)

    /// 指定 JSON ファイルの NodePath にあるノードに対し、複数フィールドを一括で上書きする。
    /// 失敗時は bug! でクラッシュする（エディタ操作で起きるなら開発時に潰すべき）
    pub def updateFields(jsonPath: String, nodePath: NodePath,
                         updates: List[FieldUpdate]):
            Unit \ {Fs.FileRead, Fs.FileWrite} =
        let readResult = run { Fs.ReadFile.read(jsonPath) } with Fs.ReadFile.runWithFileRead;
        let textResult = readResult |> Result.mapErr(error -> "read failed: ${error}");
        let updated = forM (
            text     <- textResult;
            json     <- Json.Parse.parse(String.trim(text)) |> Option.toOk("JSON parse failed");
            replaced <- replaceFieldsAtRoot(nodePath, updates, json)
        ) yield replaced;
        match updated {
            case Ok(newJson) =>
                let pretty = Json.Write.toPrettyString(2, newJson);
                let writeResult = run {
                    Fs.WriteFile.write({str = pretty}, jsonPath)
                } with Fs.WriteFile.runWithFileWrite;
                match writeResult {
                    case Ok(_)    => ()
                    case Err(error) => bug!("SceneSerializer.updateFields: write failed: ${error}")
                }
            case Err(message) => bug!("SceneSerializer.updateFields: ${jsonPath}: ${message}")
        }

    // ========================================================================
    // JSON 走査と書き換え
    // ========================================================================

    /// ルート（配列 or オブジェクト）に対して NodePath の先頭名と一致するノードを探し、
    /// その先のパスでフィールド更新を続行する
    def replaceFieldsAtRoot(nodePath: NodePath, updates: List[FieldUpdate],
                            json: JsonElement): Result[String, JsonElement] =
        match nodePath {
            case Nil => Err("empty NodePath")
            case rootName :: rest =>
                match json {
                    case JsonObject(_) =>
                        replaceFieldsInNode(rootName, rest, updates, json)
                            |> Option.toOk("root node not found: ${rootName}")
                    case JsonArray(arr) =>
                        replaceInArray(rootName, rest, updates, arr)
                            |> Option.toOk("root node not found in array: ${rootName}")
                            |> Result.map(JsonArray)
                    case _ =>
                        Err("root JSON must be object or array")
                }
        }

    /// 配列の各要素を走査し、name が一致するものを置換する。
    /// 一致するものが見つかれば置換した配列を返す。見つからなければ None
    def replaceInArray(targetName: String, restPath: NodePath, updates: List[FieldUpdate],
                       arr: Vector[JsonElement]): Option[Vector[JsonElement]] =
        let list = Vector.toList(arr);
        let (found, replaced) = List.foldLeft((acc, element) -> {
            let (foundFlag, accList) = acc;
            if (foundFlag) (true, List.append(accList, element :: Nil))
            else match replaceFieldsInNode(targetName, restPath, updates, element) {
                case Some(newElement) => (true, List.append(accList, newElement :: Nil))
                case None             => (foundFlag, List.append(accList, element :: Nil))
            }
        }, (false, Nil), list);
        if (found) Some(List.toVector(replaced)) else None

    /// 単一ノード（JsonObject）の "name" を確認し、一致すれば指定フィールドを置換する。
    /// 一致しない場合は None
    def replaceFieldsInNode(targetName: String, restPath: NodePath,
                            updates: List[FieldUpdate],
                            element: JsonElement): Option[JsonElement] =
        match element {
            case JsonObject(map) =>
                let nameOpt: Option[String] = match Map.get("name", map) {
                    case Some(Json.JsonElement.JsonString(s)) => Some(s)
                    case _                                    => None
                };
                match nameOpt {
                    case Some(name) if name == targetName =>
                        Some(applyPathFromHere(restPath, updates, map))
                    case _ => None
                }
            case _ => None
        }

    /// 末端ノード（このノードが目的のノードか、子を辿る必要があるか）に応じて
    /// 指定フィールドを置換 or children を辿る
    def applyPathFromHere(restPath: NodePath, updates: List[FieldUpdate],
                          nodeMap: Map[String, JsonElement]): JsonElement =
        match restPath {
            case Nil =>
                JsonObject(applyUpdates(updates, nodeMap))
            case nextName :: deeper =>
                match Map.get("children", nodeMap) {
                    case Some(JsonArray(childArr)) =>
                        match replaceInArray(nextName, deeper, updates, childArr) {
                            case Some(newArr) =>
                                JsonObject(Map.insert("children", JsonArray(newArr), nodeMap))
                            case None =>
                                JsonObject(nodeMap)
                        }
                    case _ => JsonObject(nodeMap)
                }
        }

    /// updates をマージしてノードの Map を返す。フィールドが既に存在しても上書きする
    def applyUpdates(updates: List[FieldUpdate],
                     nodeMap: Map[String, JsonElement]): Map[String, JsonElement] =
        List.foldLeft((acc, update) ->
            Map.insert(update#key, vec2ToJson(update#value), acc),
            nodeMap, updates)

    /// Vec2.Vec2 を JSON の [x, y] 配列に変換する。
    /// 整数座標は "144" のように整数として書き出すため stripTrailingZeros を通す。
    /// 端数があるときは "144.5" のように小数点付きで書き出される
    def vec2ToJson(v: Vec2.Vec2): JsonElement =
        JsonArray(Vector#{
            JsonNumber(floatToBd(v#x)),
            JsonNumber(floatToBd(v#y))
        })

    /// Float64 を BigDecimal に変換する。整数値の場合は trailing zero を取り除き
    /// "144.0" ではなく "144" として書き出されるようにする。
    /// 値ベースの Java 静的呼び出しなので副作用はないが、Flix の型検査上 IO 扱いになるため
    /// unsafe IO で包む
    def floatToBd(value: Float64): BigDecimal =
        unsafe IO { BigDecimal.valueOf(value).stripTrailingZeros() }
}
