// SceneSerializer — scene.json の特定ノードのフィールド（"pos" / "scale" など）を書き戻す
//
// 全 Scene を JSON にシリアライズし直すのではなく、ファイルから JSON を再パースし、
// 指定 NodePath を辿って当該ノードの該当フィールドだけを書き換えてから書き戻す。
// この方針なら NodeTag や状態を持つノードの特殊扱いを考えなくて済む。
//
// 対応するルート JSON 形:
//   - 単一オブジェクト（DialogueScene 等）
//   - 配列ルート（複数ルートノード）
//
// NodePath は List[String] で、各要素はノードの "name" と一致する必要がある。
// ルート要素の name から始まり、子は "children" 配列の中から name 一致で辿る。

mod SceneSerializer {
    import java.math.BigDecimal

    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonArray, JsonNumber}

    /// 書き換え値の種類。
    /// - VecValue:   `[x, y]` の JSON 配列
    /// - ScalarValue: 単一数値
    /// - ShapeValue:  CollisionShape2D を `{"kind": ..., ...}` の JSON オブジェクトに変換 (Area2D shape 用)
    pub enum FieldValue {
        case VecValue(Vec2.Vec2)
        case ScalarValue(Float64)
        case ShapeValue(CollisionShape2D)
    }

    /// 書き換え対象 1 件: フィールド名 + 上書きする値
    pub type alias FieldUpdate = {key = String, value = FieldValue}

    /// 1 ノード分の更新指示（cascade で複数ノードを 1 ファイル書込で更新するときに使う）
    pub type alias NodeUpdate = {nodePath = NodePath, updates = List[FieldUpdate]}

    // ========================================================================
    // 公開 API — 単一フィールド更新（Vec2）
    // ========================================================================

    /// 指定 JSON ファイルの NodePath にあるノードの "pos" を newPos で上書きして書き戻す
    pub def updatePos(jsonPath: String, nodePath: NodePath, newPos: Vec2.Vec2):
            Unit \ {Fs.FileRead, Fs.FileWrite} =
        updateFields(jsonPath, nodePath,
            {key = "pos", value = FieldValue.VecValue(newPos)} :: Nil)

    /// 指定 JSON ファイルの NodePath にあるノードの "scale" を newScale で上書きして書き戻す
    pub def updateScale(jsonPath: String, nodePath: NodePath, newScale: Vec2.Vec2):
            Unit \ {Fs.FileRead, Fs.FileWrite} =
        updateFields(jsonPath, nodePath,
            {key = "scale", value = FieldValue.VecValue(newScale)} :: Nil)

    /// 指定 JSON ファイルの NodePath にあるノードの "size" を newSize で上書きして書き戻す。
    /// ColorRect / TextureButton のリサイズ用
    pub def updateSize(jsonPath: String, nodePath: NodePath, newSize: Vec2.Vec2):
            Unit \ {Fs.FileRead, Fs.FileWrite} =
        updateFields(jsonPath, nodePath,
            {key = "size", value = FieldValue.VecValue(newSize)} :: Nil)

    /// "pos" と "scale" を同時に上書きする（後方互換用）
    pub def updatePosAndScale(jsonPath: String, nodePath: NodePath,
                              newPos: Vec2.Vec2, newScale: Vec2.Vec2):
            Unit \ {Fs.FileRead, Fs.FileWrite} =
        updateFields(jsonPath, nodePath,
            {key = "pos", value = FieldValue.VecValue(newPos)} ::
            {key = "scale", value = FieldValue.VecValue(newScale)} :: Nil)

    // ========================================================================
    // 公開 API — 単一フィールド更新（Scalar）
    // ========================================================================

    /// 指定ノードの "fontSize" を上書きする（Label2D のリサイズ用）
    pub def updateFontSize(jsonPath: String, nodePath: NodePath, newFontSize: Float64):
            Unit \ {Fs.FileRead, Fs.FileWrite} =
        updateFields(jsonPath, nodePath,
            {key = "fontSize", value = FieldValue.ScalarValue(newFontSize)} :: Nil)

    /// 指定ノードの "rotation" を上書きする（radians）。回転編集用
    pub def updateRotation(jsonPath: String, nodePath: NodePath, newRotation: Float64):
            Unit \ {Fs.FileRead, Fs.FileWrite} =
        updateFields(jsonPath, nodePath,
            {key = "rotation", value = FieldValue.ScalarValue(newRotation)} :: Nil)

    // ========================================================================
    // 公開 API — 複数フィールド・複数ノード一括更新
    // ========================================================================

    /// 指定 JSON ファイルの NodePath にあるノードに対し、複数フィールドを一括で上書きする。
    /// 失敗時は bug! でクラッシュする（エディタ操作で起きるなら開発時に潰すべき）
    pub def updateFields(jsonPath: String, nodePath: NodePath,
                         updates: List[FieldUpdate]):
            Unit \ {Fs.FileRead, Fs.FileWrite} =
        updateMany(jsonPath, {nodePath = nodePath, updates = updates} :: Nil)

    /// 同一 JSON ファイル内の複数ノードを 1 回の読み書きで一括更新する。
    /// CanvasLayer のリサイズで子ノード全部を更新するときに使う。
    /// 失敗時は bug! でクラッシュ
    pub def updateMany(jsonPath: String, nodeUpdates: List[NodeUpdate]):
            Unit \ {Fs.FileRead, Fs.FileWrite} =
        if (List.isEmpty(nodeUpdates)) ()
        else {
            let readResult = run { Fs.ReadFile.read(jsonPath) }
                with Fs.ReadFile.runWithFileRead;
            let textResult = readResult |> Result.mapErr(error -> "read failed: ${error}");
            let updated = forM (
                text <- textResult;
                json <- Json.Parse.parse(String.trim(text)) |> Option.toOk("JSON parse failed")
            ) yield {
                List.foldLeft((acc, nu) ->
                    match replaceFieldsAtRoot(nu#nodePath, nu#updates, acc) {
                        case Ok(newJson) => newJson
                        case Err(_)      => acc  // 該当ノードが見つからなければスキップ
                    }, json, nodeUpdates)
            };
            match updated {
                case Ok(newJson) =>
                    let pretty = Json.Write.toPrettyString(2, newJson);
                    let writeResult = run {
                        Fs.WriteFile.write({str = pretty}, jsonPath)
                    } with Fs.WriteFile.runWithFileWrite;
                    match writeResult {
                        case Ok(_)    => ()
                        case Err(error) => bug!("SceneSerializer.updateMany: write failed: ${error}")
                    }
                case Err(message) => bug!("SceneSerializer.updateMany: ${jsonPath}: ${message}")
            }
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
            Map.insert(update#key, valueToJson(update#value), acc),
            nodeMap, updates)

    /// FieldValue を JSON 値に変換する
    def valueToJson(v: FieldValue): JsonElement =
        match v {
            case FieldValue.VecValue(v2) =>
                JsonArray(Vector#{
                    JsonNumber(floatToBd(v2#x)),
                    JsonNumber(floatToBd(v2#y))
                })
            case FieldValue.ScalarValue(f) =>
                JsonNumber(floatToBd(f))
            case FieldValue.ShapeValue(shape) =>
                shapeToJson(shape)
        }

    /// CollisionShape2D を scene.json の `"shape"` フィールドの形式に変換する。
    /// `{"kind": "RectShape2D", "width": ..., "height": ...}` の規約に揃える。
    def shapeToJson(shape: CollisionShape2D): JsonElement =
        use Json.JsonElement.{JsonString, JsonBool};
        match shape {
            case CollisionShape2D.RectShape2D(r) =>
                JsonObject(Map#{
                    "kind"   => JsonString("RectShape2D"),
                    "width"  => JsonNumber(floatToBd(r#width)),
                    "height" => JsonNumber(floatToBd(r#height))
                })
            case CollisionShape2D.CircleShape2D(c) =>
                JsonObject(Map#{
                    "kind"   => JsonString("CircleShape2D"),
                    "radius" => JsonNumber(floatToBd(c#radius))
                })
            case CollisionShape2D.CapsuleShape2D(c) =>
                JsonObject(Map#{
                    "kind"     => JsonString("CapsuleShape2D"),
                    "radius"   => JsonNumber(floatToBd(c#radius)),
                    "height"   => JsonNumber(floatToBd(c#height)),
                    "vertical" => JsonBool(c#vertical)
                })
        }

    /// Float64 を BigDecimal に変換する。整数値の場合は trailing zero を取り除き
    /// "144.0" ではなく "144" として書き出されるようにする。
    def floatToBd(value: Float64): BigDecimal =
        unsafe IO { BigDecimal.valueOf(value).stripTrailingZeros() }
}
