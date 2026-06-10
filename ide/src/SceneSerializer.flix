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


    /// 書き換え値の種類。
    /// - VecValue:   `[x, y]` の JSON 配列
    /// - ScalarValue: 単一数値 (Float)
    /// - IntValue:   単一数値 (整数)。display 用に小数点無しで書き出す
    /// - StringValue: 文字列 (texture / text 等)
    /// - BoolValue:   真偽値 (visible 等)
    /// - ShapeValue:  CollisionShape2D を `{"kind": ..., ...}` の JSON オブジェクトに変換 (Area2D shape 用)
    pub enum FieldValue {
        case VecValue(Vec2.Vec2)
        case ScalarValue(Float64)
        case IntValue(Int32)
        case StringValue(String)
        case BoolValue(Bool)
        case ColorValue(Color)
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
    // 公開 API — 汎用フィールド更新 (String / Bool / Int)
    // ========================================================================

    /// 指定ノードの 任意フィールドを文字列で上書きする (texture / text 等)
    pub def updateString(jsonPath: String, nodePath: NodePath, key: String, value: String):
            Unit \ {Fs.FileRead, Fs.FileWrite} =
        updateFields(jsonPath, nodePath,
            {key = key, value = FieldValue.StringValue(value)} :: Nil)

    /// 指定ノードの 任意フィールドを真偽値で上書きする (visible 等)
    pub def updateBool(jsonPath: String, nodePath: NodePath, key: String, value: Bool):
            Unit \ {Fs.FileRead, Fs.FileWrite} =
        updateFields(jsonPath, nodePath,
            {key = key, value = FieldValue.BoolValue(value)} :: Nil)

    /// 指定ノードの 任意フィールドを整数で上書きする (zIndex / hframes 等)
    pub def updateInt(jsonPath: String, nodePath: NodePath, key: String, value: Int32):
            Unit \ {Fs.FileRead, Fs.FileWrite} =
        updateFields(jsonPath, nodePath,
            {key = key, value = FieldValue.IntValue(value)} :: Nil)

    /// 指定ノードの 任意フィールドを Color で上書きする (modulate 等)
    pub def updateColor(jsonPath: String, nodePath: NodePath, key: String, value: Color):
            Unit \ {Fs.FileRead, Fs.FileWrite} =
        updateFields(jsonPath, nodePath,
            {key = key, value = FieldValue.ColorValue(value)} :: Nil)

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
    /// 失敗時は bug! でクラッシュ。
    ///
    /// JSON のキー順と配列スタイル (inline / block) は元ファイルの状態を維持する
    /// （Util.Json.toPrettyString を使わず JsonOrdered 経由で書き出すため）。
    pub def updateMany(jsonPath: String, nodeUpdates: List[NodeUpdate]):
            Unit \ {Fs.FileRead, Fs.FileWrite} =
        if (List.isEmpty(nodeUpdates)) ()
        else {
            let readResult = run { Fs.ReadFile.read(jsonPath) }
                with Fs.ReadFile.runWithFileRead;
            let textResult = readResult |> Result.mapErr(error -> "read failed: ${error}");
            let updated = forM (
                text <- textResult;
                json <- JsonOrdered.parse(String.trim(text))
            ) yield {
                List.foldLeft((acc, nu) ->
                    match replaceFieldsAtRoot(nu#nodePath, nu#updates, acc) {
                        case Ok(newJson) => newJson
                        case Err(_)      => acc  // 該当ノードが見つからなければスキップ
                    }, json, nodeUpdates)
            };
            match updated {
                case Ok(newJson) =>
                    let pretty = JsonOrdered.writePretty(2, newJson);
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
    // JSON 走査と書き換え（OrderedJson ベース、キー順を保持）
    // ========================================================================

    /// ルート（配列 or オブジェクト）に対して NodePath の先頭名と一致するノードを探し、
    /// その先のパスでフィールド更新を続行する
    def replaceFieldsAtRoot(nodePath: NodePath, updates: List[FieldUpdate],
                            json: JsonOrdered.OrderedJson):
                           Result[String, JsonOrdered.OrderedJson] =
        match nodePath {
            case Nil => Err("empty NodePath")
            case rootName :: rest =>
                match json {
                    case JsonOrdered.OrderedJson.OObject(_, _) =>
                        replaceFieldsInNode(rootName, rest, updates, json)
                            |> Option.toOk("root node not found: ${rootName}")
                    case JsonOrdered.OrderedJson.OArray(items, style) =>
                        replaceInArray(rootName, rest, updates, items)
                            |> Option.toOk("root node not found in array: ${rootName}")
                            |> Result.map(newItems ->
                                JsonOrdered.OrderedJson.OArray(newItems, style))
                    case _ =>
                        Err("root JSON must be object or array")
                }
        }

    /// 配列の各要素を走査し、name が一致するものを置換する。
    /// 一致するものが見つかれば置換したリストを返す。見つからなければ None
    def replaceInArray(targetName: String, restPath: NodePath, updates: List[FieldUpdate],
                       items: List[JsonOrdered.OrderedJson]):
                      Option[List[JsonOrdered.OrderedJson]] =
        let (found, replaced) = List.foldLeft((acc, element) -> {
            let (foundFlag, accList) = acc;
            if (foundFlag) (true, List.append(accList, element :: Nil))
            else match replaceFieldsInNode(targetName, restPath, updates, element) {
                case Some(newElement) => (true, List.append(accList, newElement :: Nil))
                case None             => (foundFlag, List.append(accList, element :: Nil))
            }
        }, (false, Nil), items);
        if (found) Some(replaced) else None

    /// 単一ノード（OObject）の "name" を確認し、一致すれば指定フィールドを置換する。
    /// 一致しない場合は None。
    ///
    /// 例外:
    ///   - `"type": "Container"` (load-time directive) は実 node ではなく
    ///     `layout` フィールドの中に children を持つ。layout 経由で descend して target を探す
    ///   - `"kind": "..."` のみ持つ Layout primitive (Panel / HBoxContainer / VBoxContainer /
    ///     CenterContainer / MarginContainer) も `children` / `child` 経由で descend する
    def replaceFieldsInNode(targetName: String, restPath: NodePath,
                            updates: List[FieldUpdate],
                            element: JsonOrdered.OrderedJson):
                           Option[JsonOrdered.OrderedJson] =
        match element {
            case JsonOrdered.OrderedJson.OObject(entries, objStyle) =>
                let typeStrOpt = findEntryValue("type", entries) |> Option.flatMap(v ->
                    match v {
                        case JsonOrdered.OrderedJson.OString(s) => Some(s)
                        case _                                  => None
                    });
                let hasKind = match findEntryValue("kind", entries) {
                    case Some(_) => true
                    case None    => false
                };
                match typeStrOpt {
                    case Some("Container") =>
                        // Container: layout 配下を再帰探索
                        match findEntryValue("layout", entries) {
                            case Some(layoutJson) =>
                                replaceInLayout(targetName, restPath, updates, layoutJson)
                                    |> Option.map(newLayout ->
                                        JsonOrdered.OrderedJson.OObject(
                                            replaceEntryValue("layout", newLayout, entries),
                                            objStyle))
                            case None => None
                        }
                    case _ =>
                        if (hasKind and Option.isEmpty(typeStrOpt)) {
                            // Layout primitive (Panel / VBoxContainer / 等)
                            replaceInLayout(targetName, restPath, updates, element)
                        } else {
                            let nameOpt = findEntryValue("name", entries) |> Option.flatMap(v ->
                                match v {
                                    case JsonOrdered.OrderedJson.OString(s) => Some(s)
                                    case _                                  => None
                                });
                            match nameOpt {
                                case Some(name) if name == targetName =>
                                    Some(applyPathFromHere(restPath, updates, entries, objStyle))
                                case _ => None
                            }
                        }
                }
            case _ => None
        }

    /// Layout primitive (`{"kind": "Panel", "children": [...]}` 等) の中を再帰的に探索。
    /// `children` (Panel/Box) または `child` (MarginContainer/CenterContainer) を辿る。
    /// children の各要素は更に Layout primitive または node 定義
    def replaceInLayout(targetName: String, restPath: NodePath, updates: List[FieldUpdate],
                        layoutJson: JsonOrdered.OrderedJson):
                       Option[JsonOrdered.OrderedJson] =
        match layoutJson {
            case JsonOrdered.OrderedJson.OObject(entries, objStyle) =>
                match findEntryValue("children", entries) {
                    case Some(JsonOrdered.OrderedJson.OArray(items, arrStyle)) =>
                        match replaceInArray(targetName, restPath, updates, items) {
                            case Some(newItems) =>
                                Some(JsonOrdered.OrderedJson.OObject(
                                    replaceEntryValue("children",
                                        JsonOrdered.OrderedJson.OArray(newItems, arrStyle),
                                        entries),
                                    objStyle))
                            case None => None
                        }
                    case _ =>
                        match findEntryValue("child", entries) {
                            case Some(childJson) =>
                                match replaceFieldsInNode(targetName, restPath, updates, childJson) {
                                    case Some(newChild) =>
                                        Some(JsonOrdered.OrderedJson.OObject(
                                            replaceEntryValue("child", newChild, entries),
                                            objStyle))
                                    case None => None
                                }
                            case None => None
                        }
                }
            case _ => None
        }

    /// 末端ノード（このノードが目的のノードか、子を辿る必要があるか）に応じて
    /// 指定フィールドを置換 or children を辿る。objStyle は元の object スタイルを引き継ぐ。
    ///
    /// 合成 path 拡張:
    ///   - `"@@layout"` : 現 node の `layout` フィールドへ降りる (Container 用)
    ///   - `"@@child"`  : 現 node の `child` フィールドへ降りる (Center/MarginContainer)
    ///   - `"@@N"`      : 現 node の `children[N]` へ降りる (layout primitive の Nth child)
    def applyPathFromHere(restPath: NodePath, updates: List[FieldUpdate],
                          entries: List[(String, JsonOrdered.OrderedJson)],
                          objStyle: JsonOrdered.ObjectStyle):
                         JsonOrdered.OrderedJson =
        match restPath {
            case Nil =>
                JsonOrdered.OrderedJson.OObject(applyUpdates(updates, entries), objStyle)
            case nextName :: deeper =>
                if (String.startsWith({prefix = "@@"}, nextName))
                    handleSyntheticStep(nextName, deeper, updates, entries, objStyle)
                else
                    match findEntryValue("children", entries) {
                        case Some(JsonOrdered.OrderedJson.OArray(childItems, style)) =>
                            match replaceInArray(nextName, deeper, updates, childItems) {
                                case Some(newItems) =>
                                    let newChildren =
                                        JsonOrdered.OrderedJson.OArray(newItems, style);
                                    JsonOrdered.OrderedJson.OObject(
                                        replaceEntryValue("children", newChildren, entries),
                                        objStyle)
                                case None =>
                                    JsonOrdered.OrderedJson.OObject(entries, objStyle)
                            }
                        case _ => JsonOrdered.OrderedJson.OObject(entries, objStyle)
                    }
        }

    /// 合成 path セグメント (`@@N` / `@@layout` / `@@child`) を処理する
    def handleSyntheticStep(seg: String, deeper: NodePath, updates: List[FieldUpdate],
                             entries: List[(String, JsonOrdered.OrderedJson)],
                             objStyle: JsonOrdered.ObjectStyle):
                            JsonOrdered.OrderedJson =
        if (seg == "@@layout") {
            match findEntryValue("layout", entries) {
                case Some(layoutJson) =>
                    let updated = applyToObjectField(layoutJson, deeper, updates);
                    JsonOrdered.OrderedJson.OObject(
                        replaceEntryValue("layout", updated, entries), objStyle)
                case None => JsonOrdered.OrderedJson.OObject(entries, objStyle)
            }
        } else if (seg == "@@child") {
            match findEntryValue("child", entries) {
                case Some(childJson) =>
                    let updated = applyToObjectField(childJson, deeper, updates);
                    JsonOrdered.OrderedJson.OObject(
                        replaceEntryValue("child", updated, entries), objStyle)
                case None => JsonOrdered.OrderedJson.OObject(entries, objStyle)
            }
        } else {
            // "@@N" (children[N]) または "@@<key>" (named entry) へ降りる
            let rest = String.dropLeft(2, seg);
            match Int32.fromString(rest) {
                case Some(n) =>
                    // 整数なら children[N]
                    match findEntryValue("children", entries) {
                        case Some(JsonOrdered.OrderedJson.OArray(items, style)) =>
                            let newItems = applyToArrayIndex(items, n, deeper, updates);
                            JsonOrdered.OrderedJson.OObject(
                                replaceEntryValue("children",
                                    JsonOrdered.OrderedJson.OArray(newItems, style), entries),
                                objStyle)
                        case _ => JsonOrdered.OrderedJson.OObject(entries, objStyle)
                    }
                case None =>
                    // 整数でなければ named entry として扱う (例: "@@properties")
                    match findEntryValue(rest, entries) {
                        case Some(fieldJson) =>
                            let updated = applyToObjectField(fieldJson, deeper, updates);
                            JsonOrdered.OrderedJson.OObject(
                                replaceEntryValue(rest, updated, entries), objStyle)
                        case None => JsonOrdered.OrderedJson.OObject(entries, objStyle)
                    }
            }
        }

    /// object フィールド (layout / child) に対して deeper path を進めて updates を適用する
    def applyToObjectField(fieldJson: JsonOrdered.OrderedJson, deeper: NodePath,
                            updates: List[FieldUpdate]): JsonOrdered.OrderedJson =
        match fieldJson {
            case JsonOrdered.OrderedJson.OObject(fieldEntries, fieldStyle) =>
                match deeper {
                    case Nil =>
                        JsonOrdered.OrderedJson.OObject(
                            applyUpdates(updates, fieldEntries), fieldStyle)
                    case _ =>
                        applyPathFromHere(deeper, updates, fieldEntries, fieldStyle)
                }
            case _ => fieldJson
        }

    /// 配列の n 番目要素に対して deeper path を進めて updates を適用する
    def applyToArrayIndex(items: List[JsonOrdered.OrderedJson], n: Int32, deeper: NodePath,
                           updates: List[FieldUpdate]): List[JsonOrdered.OrderedJson] =
        List.mapWithIndex((idx, item) ->
            if (idx == n)
                applyToObjectField(item, deeper, updates)
            else
                item, items)

    /// updates を entries にマージする。
    /// 既存キーは順序を保ったまま値を置換、新規キーは末尾に追加する
    def applyUpdates(updates: List[FieldUpdate],
                     entries: List[(String, JsonOrdered.OrderedJson)]):
                    List[(String, JsonOrdered.OrderedJson)] =
        List.foldLeft((acc, update) ->
            upsertEntry(update#key, valueToOrderedJson(update#value), acc),
            entries, updates)

    /// (key, value) リストを順序を保ったまま走査し、key 一致なら value を置き換える。
    /// 一致しなければ末尾に追加する
    def upsertEntry(key: String, value: JsonOrdered.OrderedJson,
                     entries: List[(String, JsonOrdered.OrderedJson)]):
                    List[(String, JsonOrdered.OrderedJson)] =
        let (found, replaced) = List.foldLeft((acc, entry) -> {
            let (k, v) = entry;
            let (foundFlag, accList) = acc;
            if (k == key) (true, List.append(accList, (k, value) :: Nil))
            else (foundFlag, List.append(accList, (k, v) :: Nil))
        }, (false, Nil), entries);
        if (found) replaced
        else List.append(entries, (key, value) :: Nil)

    /// 順序付き entries から key の値を取り出す
    def findEntryValue(key: String,
                        entries: List[(String, JsonOrdered.OrderedJson)]):
                       Option[JsonOrdered.OrderedJson] =
        match entries {
            case Nil => None
            case (k, v) :: rest =>
                if (k == key) Some(v) else findEntryValue(key, rest)
        }

    /// 順序付き entries の key の値だけを差し替える（順序は変えない）
    def replaceEntryValue(key: String, value: JsonOrdered.OrderedJson,
                           entries: List[(String, JsonOrdered.OrderedJson)]):
                          List[(String, JsonOrdered.OrderedJson)] =
        List.map(entry -> {
            let (k, v) = entry;
            if (k == key) (k, value) else (k, v)
        }, entries)

    /// FieldValue を OrderedJson に変換する。
    /// Vec2 は inline 配列 (`[0, 0]`) として出す。
    /// shape はキー順を kind → width → height（または radius / vertical）に固定する
    def valueToOrderedJson(v: FieldValue): JsonOrdered.OrderedJson =
        match v {
            case FieldValue.VecValue(v2) =>
                JsonOrdered.OrderedJson.OArray(
                    JsonOrdered.OrderedJson.ONumber(formatFloat(v2#x)) ::
                    JsonOrdered.OrderedJson.ONumber(formatFloat(v2#y)) :: Nil,
                    JsonOrdered.ArrayStyle.Inline)
            case FieldValue.ScalarValue(f) =>
                JsonOrdered.OrderedJson.ONumber(formatFloat(f))
            case FieldValue.IntValue(i) =>
                JsonOrdered.OrderedJson.ONumber(Int32.toString(i))
            case FieldValue.StringValue(s) =>
                JsonOrdered.OrderedJson.OString(s)
            case FieldValue.BoolValue(b) =>
                JsonOrdered.OrderedJson.OBool(b)
            case FieldValue.ColorValue(c) =>
                JsonOrdered.OrderedJson.OObject(
                    ("r", JsonOrdered.OrderedJson.ONumber(formatFloat(Float32.toFloat64(c#r)))) ::
                    ("g", JsonOrdered.OrderedJson.ONumber(formatFloat(Float32.toFloat64(c#g)))) ::
                    ("b", JsonOrdered.OrderedJson.ONumber(formatFloat(Float32.toFloat64(c#b)))) :: Nil,
                    JsonOrdered.ObjectStyle.ObjInline)
            case FieldValue.ShapeValue(shape) =>
                shapeToOrderedJson(shape)
        }

    /// CollisionShape2D を `{"kind": ..., "width": ..., ...}` の OObject に変換する。
    /// shape は通常 inline `{"kind": ..., ...}` で書かれているため Inline スタイルで出力する
    def shapeToOrderedJson(shape: CollisionShape2D): JsonOrdered.OrderedJson =
        match shape {
            case CollisionShape2D.RectShape2D(r) =>
                JsonOrdered.OrderedJson.OObject(
                    ("kind",   JsonOrdered.OrderedJson.OString("RectShape2D")) ::
                    ("width",  JsonOrdered.OrderedJson.ONumber(formatFloat(r#width))) ::
                    ("height", JsonOrdered.OrderedJson.ONumber(formatFloat(r#height))) :: Nil,
                    JsonOrdered.ObjectStyle.ObjInline)
            case CollisionShape2D.CircleShape2D(c) =>
                JsonOrdered.OrderedJson.OObject(
                    ("kind",   JsonOrdered.OrderedJson.OString("CircleShape2D")) ::
                    ("radius", JsonOrdered.OrderedJson.ONumber(formatFloat(c#radius))) :: Nil,
                    JsonOrdered.ObjectStyle.ObjInline)
            case CollisionShape2D.CapsuleShape2D(c) =>
                JsonOrdered.OrderedJson.OObject(
                    ("kind",     JsonOrdered.OrderedJson.OString("CapsuleShape2D")) ::
                    ("radius",   JsonOrdered.OrderedJson.ONumber(formatFloat(c#radius))) ::
                    ("height",   JsonOrdered.OrderedJson.ONumber(formatFloat(c#height))) ::
                    ("vertical", JsonOrdered.OrderedJson.OBool(c#vertical)) :: Nil,
                    JsonOrdered.ObjectStyle.ObjInline)
        }

    /// Float64 を JSON 数値文字列に。整数値なら "144"、小数なら "144.5" のようにする
    def formatFloat(value: Float64): String =
        unsafe IO {
            BigDecimal.valueOf(value).stripTrailingZeros().toPlainString()
        }
}
