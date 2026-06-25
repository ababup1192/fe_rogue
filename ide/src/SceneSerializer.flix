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
        // 既存のオブジェクト値（例: "shape"）の中の 1 キーだけを差し替える（他キーは保持）。
        // 形状の width/height/radius/vertical を個別に編集しても互いを上書きしないために使う。
        case ShapeMergeValue(String, FieldValue)
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
    // 子ノードの追加（構造変更）— Add Child Node 用
    // ========================================================================

    /// jsonPath のシーンの parentPath にあるノードの "children" 配列に、childType の
    /// 子ノードを「型名で一意に自動命名」して追加し、書き戻す。成功時は付与した名前を Ok。
    /// 初期スコープは素の `children` 配列を持つ通常ノードのみ（Container/layout は対象外）。
    pub def addChild(jsonPath: String, parentPath: NodePath, childType: String):
            Result[String, String] \ {Fs.FileRead, Fs.FileWrite} =
        let readResult = run { Fs.ReadFile.read(jsonPath) } with Fs.ReadFile.runWithFileRead;
        let parsed = readResult
            |> Result.mapErr(e -> "read failed: ${e}")
            |> Result.flatMap(text -> JsonOrdered.parse(String.trim(text)));
        match parsed {
            case Err(msg) => Err(msg)
            case Ok(json) =>
                match insertChildAtRoot(parentPath, childType, json) {
                    case None                  => Err("parent node not found: ${parentPath}")
                    case Some((newJson, name)) => writeAddChild(jsonPath, newJson, name)
                }
        }

    def writeAddChild(jsonPath: String, newJson: JsonOrdered.OrderedJson, childName: String):
            Result[String, String] \ Fs.FileWrite =
        writeOrderedJson(jsonPath, newJson) |> Result.map(_ -> childName)

    /// OrderedJson をファイルに pretty 書き戻す（成功時 Unit）
    def writeOrderedJson(jsonPath: String, newJson: JsonOrdered.OrderedJson):
            Result[String, Unit] \ Fs.FileWrite =
        let pretty = JsonOrdered.writePretty(2, newJson);
        let writeResult = run { Fs.WriteFile.write({str = pretty}, jsonPath) }
            with Fs.WriteFile.runWithFileWrite;
        writeResult |> Result.mapErr(e -> "write failed: ${e}")

    // ========================================================================
    // 構造変更 — ノード除去 / サブツリー挿入（素の `children` 配列のみ対象）
    // addChild / insertChildInArray / descendForInsert の mirror。
    // 除去は Undo 用に「除去断片 + 親 path + index」を返す。挿入はその逆操作。
    // ========================================================================

    /// nodePath のノードを親の "children" から除去して書き戻す。
    /// 成功時 {parentPath, index, fragment}（Undo で insertSubtree に渡せる）。
    pub def removeChild(jsonPath: String, nodePath: NodePath):
            Result[String, {parentPath = NodePath, index = Int32, fragment = JsonOrdered.OrderedJson}]
            \ {Fs.FileRead, Fs.FileWrite} =
        let readResult = run { Fs.ReadFile.read(jsonPath) } with Fs.ReadFile.runWithFileRead;
        let parsed = readResult
            |> Result.mapErr(e -> "read failed: ${e}")
            |> Result.flatMap(text -> JsonOrdered.parse(String.trim(text)));
        match parsed {
            case Err(msg) => Err(msg)
            case Ok(json) =>
                match removeAtRoot(nodePath, json) {
                    case None => Err("node not found: ${nodePath}")
                    case Some((newJson, frag, index)) =>
                        let parentPath = List.take(List.length(nodePath) - 1, nodePath);
                        writeOrderedJson(jsonPath, newJson)
                            |> Result.map(_ ->
                                {parentPath = parentPath, index = index, fragment = frag})
                }
        }

    /// parentPath の "children" の index 位置に fragment を挿入して書き戻す（範囲はクランプ）。
    pub def insertSubtree(jsonPath: String, parentPath: NodePath, index: Int32,
                          fragment: JsonOrdered.OrderedJson):
            Result[String, Unit] \ {Fs.FileRead, Fs.FileWrite} =
        let readResult = run { Fs.ReadFile.read(jsonPath) } with Fs.ReadFile.runWithFileRead;
        let parsed = readResult
            |> Result.mapErr(e -> "read failed: ${e}")
            |> Result.flatMap(text -> JsonOrdered.parse(String.trim(text)));
        match parsed {
            case Err(msg) => Err(msg)
            case Ok(json) =>
                match insertSubtreeAtRoot(parentPath, index, fragment, json) {
                    case None          => Err("parent node not found: ${parentPath}")
                    case Some(newJson) => writeOrderedJson(jsonPath, newJson)
                }
        }

    // ---- removeChild ナビゲーション ----

    def removeAtRoot(nodePath: NodePath, json: JsonOrdered.OrderedJson):
            Option[(JsonOrdered.OrderedJson, JsonOrdered.OrderedJson, Int32)] =
        match nodePath {
            case Nil          => None
            case rootName :: rest =>
                match json {
                    case JsonOrdered.OrderedJson.OObject(_, _) =>
                        removeInNode(rootName, rest, json)
                    case JsonOrdered.OrderedJson.OArray(items, style) =>
                        removeInArray(rootName, rest, items)
                            |> Option.map(t -> {
                                let (newItems, frag, idx) = t;
                                (JsonOrdered.OrderedJson.OArray(newItems, style), frag, idx)
                            })
                    case _ => None
                }
        }

    def removeInNode(targetName: String, restPath: NodePath, element: JsonOrdered.OrderedJson):
            Option[(JsonOrdered.OrderedJson, JsonOrdered.OrderedJson, Int32)] =
        match element {
            case JsonOrdered.OrderedJson.OObject(entries, style) =>
                match nodeNameOf(entries) {
                    case Some(name) if name == targetName =>
                        match restPath {
                            case last :: Nil    => removeFromChildren(entries, style, last)
                            case next :: deeper  => descendForRemove(entries, style, next, deeper)
                            case Nil             => None
                        }
                    case _ => None
                }
            case _ => None
        }

    def removeFromChildren(entries: List[(String, JsonOrdered.OrderedJson)],
                           style: JsonOrdered.ObjectStyle, childName: String):
            Option[(JsonOrdered.OrderedJson, JsonOrdered.OrderedJson, Int32)] =
        match findEntryValue("children", entries) {
            case Some(JsonOrdered.OrderedJson.OArray(items, arrStyle)) =>
                removeNamedFromItems(childName, items, 0)
                    |> Option.map(t -> {
                        let (newItems, frag, idx) = t;
                        let newChildren = JsonOrdered.OrderedJson.OArray(newItems, arrStyle);
                        (JsonOrdered.OrderedJson.OObject(
                            replaceEntryValue("children", newChildren, entries), style), frag, idx)
                    })
            case _ => None
        }

    def removeNamedFromItems(childName: String, items: List[JsonOrdered.OrderedJson], idx: Int32):
            Option[(List[JsonOrdered.OrderedJson], JsonOrdered.OrderedJson, Int32)] =
        match items {
            case Nil          => None
            case head :: tail =>
                let headName = match head {
                    case JsonOrdered.OrderedJson.OObject(es, _) => nodeNameOf(es)
                    case _                                      => None
                };
                if (headName == Some(childName)) Some((tail, head, idx))
                else removeNamedFromItems(childName, tail, idx + 1)
                    |> Option.map(t -> {
                        let (rest, frag, i) = t;
                        (head :: rest, frag, i)
                    })
        }

    def descendForRemove(entries: List[(String, JsonOrdered.OrderedJson)],
                         style: JsonOrdered.ObjectStyle, next: String, deeper: NodePath):
            Option[(JsonOrdered.OrderedJson, JsonOrdered.OrderedJson, Int32)] =
        match findEntryValue("children", entries) {
            case Some(JsonOrdered.OrderedJson.OArray(items, arrStyle)) =>
                removeInArray(next, deeper, items)
                    |> Option.map(t -> {
                        let (newItems, frag, idx) = t;
                        let newChildren = JsonOrdered.OrderedJson.OArray(newItems, arrStyle);
                        (JsonOrdered.OrderedJson.OObject(
                            replaceEntryValue("children", newChildren, entries), style), frag, idx)
                    })
            case _ => None
        }

    def removeInArray(targetName: String, restPath: NodePath, items: List[JsonOrdered.OrderedJson]):
            Option[(List[JsonOrdered.OrderedJson], JsonOrdered.OrderedJson, Int32)] =
        match items {
            case Nil          => None
            case head :: tail =>
                match removeInNode(targetName, restPath, head) {
                    case Some((newHead, frag, idx)) => Some((newHead :: tail, frag, idx))
                    case None =>
                        removeInArray(targetName, restPath, tail)
                            |> Option.map(t -> {
                                let (newTail, frag, idx) = t;
                                (head :: newTail, frag, idx)
                            })
                }
        }

    // ---- insertSubtree ナビゲーション ----

    def insertSubtreeAtRoot(parentPath: NodePath, index: Int32, fragment: JsonOrdered.OrderedJson,
                            json: JsonOrdered.OrderedJson): Option[JsonOrdered.OrderedJson] =
        match parentPath {
            case Nil              => None
            case rootName :: rest =>
                match json {
                    case JsonOrdered.OrderedJson.OObject(_, _) =>
                        insertSubtreeInNode(rootName, rest, index, fragment, json)
                    case JsonOrdered.OrderedJson.OArray(items, style) =>
                        insertSubtreeInArray(rootName, rest, index, fragment, items)
                            |> Option.map(newItems ->
                                JsonOrdered.OrderedJson.OArray(newItems, style))
                    case _ => None
                }
        }

    def insertSubtreeInNode(targetName: String, restPath: NodePath, index: Int32,
                            fragment: JsonOrdered.OrderedJson, element: JsonOrdered.OrderedJson):
            Option[JsonOrdered.OrderedJson] =
        match element {
            case JsonOrdered.OrderedJson.OObject(entries, style) =>
                match nodeNameOf(entries) {
                    case Some(name) if name == targetName =>
                        match restPath {
                            case Nil            => Some(insertFragmentAt(entries, style, index, fragment))
                            case next :: deeper => descendForInsertSubtree(entries, style, next, deeper, index, fragment)
                        }
                    case _ => None
                }
            case _ => None
        }

    def descendForInsertSubtree(entries: List[(String, JsonOrdered.OrderedJson)],
                                style: JsonOrdered.ObjectStyle, next: String, deeper: NodePath,
                                index: Int32, fragment: JsonOrdered.OrderedJson):
            Option[JsonOrdered.OrderedJson] =
        match findEntryValue("children", entries) {
            case Some(JsonOrdered.OrderedJson.OArray(items, arrStyle)) =>
                insertSubtreeInArray(next, deeper, index, fragment, items)
                    |> Option.map(newItems -> {
                        let newChildren = JsonOrdered.OrderedJson.OArray(newItems, arrStyle);
                        JsonOrdered.OrderedJson.OObject(
                            replaceEntryValue("children", newChildren, entries), style)
                    })
            case _ => None
        }

    def insertSubtreeInArray(targetName: String, restPath: NodePath, index: Int32,
                             fragment: JsonOrdered.OrderedJson, items: List[JsonOrdered.OrderedJson]):
            Option[List[JsonOrdered.OrderedJson]] =
        match items {
            case Nil          => None
            case head :: tail =>
                match insertSubtreeInNode(targetName, restPath, index, fragment, head) {
                    case Some(newHead) => Some(newHead :: tail)
                    case None =>
                        insertSubtreeInArray(targetName, restPath, index, fragment, tail)
                            |> Option.map(newTail -> head :: newTail)
                }
        }

    /// 対象ノードの "children" の index 位置に fragment を挿入する（無ければ新設）。
    def insertFragmentAt(entries: List[(String, JsonOrdered.OrderedJson)],
                         style: JsonOrdered.ObjectStyle, index: Int32,
                         fragment: JsonOrdered.OrderedJson): JsonOrdered.OrderedJson =
        let (childItems, arrStyle) = match findEntryValue("children", entries) {
            case Some(JsonOrdered.OrderedJson.OArray(items, st)) => (items, st)
            case _ => (Nil, JsonOrdered.ArrayStyle.Block)
        };
        let newItems = insertItemAt(index, fragment, childItems);
        let newChildren = JsonOrdered.OrderedJson.OArray(newItems, arrStyle);
        let newEntries =
            if (hasEntry("children", entries))
                replaceEntryValue("children", newChildren, entries)
            else
                List.append(entries, ("children", newChildren) :: Nil);
        JsonOrdered.OrderedJson.OObject(newEntries, style)

    /// index 位置に item を挿入（範囲外はクランプ）
    def insertItemAt(index: Int32, item: JsonOrdered.OrderedJson,
                     items: List[JsonOrdered.OrderedJson]): List[JsonOrdered.OrderedJson] =
        let n = List.length(items);
        let i = if (index < 0) 0 else if (index > n) n else index;
        List.append(List.take(i, items), item :: List.drop(i, items))

    // ========================================================================
    // ノード複製 — 対象サブツリーを clone（root 名を兄弟内一意にリネーム＋pos を少しオフセット）し、
    // 同じ親の元ノード直後に挿入する。insertSubtree を再利用。
    // ========================================================================

    /// 複製時の位置オフセット（重なって見えないように少しずらす）
    def dupOffset(): Float64 = 16.0

    /// nodePath のノードを複製して同じ親に挿入する。成功時 {newName, newNodePath}。
    pub def duplicateNode(jsonPath: String, nodePath: NodePath):
            Result[String, {newName = String, newNodePath = NodePath}]
            \ {Fs.FileRead, Fs.FileWrite} =
        let readResult = run { Fs.ReadFile.read(jsonPath) } with Fs.ReadFile.runWithFileRead;
        let parsed = readResult
            |> Result.mapErr(e -> "read failed: ${e}")
            |> Result.flatMap(text -> JsonOrdered.parse(String.trim(text)));
        match parsed {
            case Err(msg) => Err(msg)
            case Ok(json) =>
                let parentPath = List.take(List.length(nodePath) - 1, nodePath);
                match List.last(nodePath) {
                    case None             => Err("invalid nodePath: ${nodePath}")
                    case Some(targetName) =>
                        match findNodeEntries(parentPath, json) {
                            case None => Err("parent not found: ${parentPath}")
                            case Some(parentEntries) =>
                                match findEntryValue("children", parentEntries) {
                                    case Some(JsonOrdered.OrderedJson.OArray(items, _)) =>
                                        duplicateInItems(jsonPath, parentPath, targetName, items)
                                    case _ => Err("parent has no children array")
                                }
                        }
                }
        }

    def duplicateInItems(jsonPath: String, parentPath: NodePath, targetName: String,
                         items: List[JsonOrdered.OrderedJson]):
            Result[String, {newName = String, newNodePath = NodePath}] \ {Fs.FileRead, Fs.FileWrite} =
        match locateNamed(targetName, items, 0) {
            case None => Err("node not found: ${targetName}")
            case Some((frag, idx)) =>
                let siblings = List.filterMap(itemName, items);
                let newName = uniqueChildName(targetName, siblings, 2);
                let clone = cloneFragment(frag, newName, dupOffset(), dupOffset());
                insertSubtree(jsonPath, parentPath, idx + 1, clone)
                    |> Result.map(_ ->
                        {newName = newName,
                         newNodePath = List.append(parentPath, newName :: Nil)})
        }

    /// items から name 一致のノードと index を返す
    def locateNamed(name: String, items: List[JsonOrdered.OrderedJson], idx: Int32):
            Option[(JsonOrdered.OrderedJson, Int32)] =
        match items {
            case Nil          => None
            case head :: tail =>
                if (itemName(head) == Some(name)) Some((head, idx))
                else locateNamed(name, tail, idx + 1)
        }

    def itemName(item: JsonOrdered.OrderedJson): Option[String] =
        match item {
            case JsonOrdered.OrderedJson.OObject(es, _) => nodeNameOf(es)
            case _                                      => None
        }

    /// フラグメントの root を newName にリネームし、"pos" を (dx, dy) ずらす（子は相対なので不変）
    def cloneFragment(frag: JsonOrdered.OrderedJson, newName: String,
                      dx: Float64, dy: Float64): JsonOrdered.OrderedJson =
        match frag {
            case JsonOrdered.OrderedJson.OObject(entries, style) =>
                let renamed = replaceEntryValue("name",
                    JsonOrdered.OrderedJson.OString(newName), entries);
                JsonOrdered.OrderedJson.OObject(offsetPosEntries(renamed, dx, dy), style)
            case other => other
        }

    def offsetPosEntries(entries: List[(String, JsonOrdered.OrderedJson)],
                         dx: Float64, dy: Float64): List[(String, JsonOrdered.OrderedJson)] =
        match findEntryValue("pos", entries) {
            case Some(JsonOrdered.OrderedJson.OArray(
                        JsonOrdered.OrderedJson.ONumber(xs) ::
                        JsonOrdered.OrderedJson.ONumber(ys) :: rest, arrStyle)) =>
                let nx = JsonOrdered.OrderedJson.ONumber(offsetNumberText(xs, dx));
                let ny = JsonOrdered.OrderedJson.ONumber(offsetNumberText(ys, dy));
                replaceEntryValue("pos",
                    JsonOrdered.OrderedJson.OArray(nx :: ny :: rest, arrStyle), entries)
            case _ => entries
        }

    def offsetNumberText(text: String, delta: Float64): String =
        match Float64.fromString(String.trim(text)) {
            case Some(v) => formatFloat(v + delta)
            case None    => text
        }

    /// path のノードの entries を返す（複製の対象探索に使う読み取り専用ナビゲーション）
    def findNodeEntries(path: NodePath, json: JsonOrdered.OrderedJson):
            Option[List[(String, JsonOrdered.OrderedJson)]] =
        match path {
            case Nil          => None
            case name :: rest =>
                match json {
                    case JsonOrdered.OrderedJson.OObject(entries, _) =>
                        match nodeNameOf(entries) {
                            case Some(n) if n == name =>
                                match rest {
                                    case Nil => Some(entries)
                                    case _   =>
                                        match findEntryValue("children", entries) {
                                            case Some(JsonOrdered.OrderedJson.OArray(items, _)) =>
                                                findNodeEntriesInArray(rest, items)
                                            case _ => None
                                        }
                                }
                            case _ => None
                        }
                    case JsonOrdered.OrderedJson.OArray(items, _) =>
                        findNodeEntriesInArray(path, items)
                    case _ => None
                }
        }

    def findNodeEntriesInArray(path: NodePath, items: List[JsonOrdered.OrderedJson]):
            Option[List[(String, JsonOrdered.OrderedJson)]] =
        match items {
            case Nil          => None
            case head :: tail =>
                match findNodeEntries(path, head) {
                    case Some(e) => Some(e)
                    case None    => findNodeEntriesInArray(path, tail)
                }
        }

    def insertChildAtRoot(parentPath: NodePath, childType: String,
                          json: JsonOrdered.OrderedJson):
                         Option[(JsonOrdered.OrderedJson, String)] =
        match parentPath {
            case Nil => None
            case rootName :: rest =>
                match json {
                    case JsonOrdered.OrderedJson.OObject(_, _) =>
                        insertChildInNode(rootName, rest, childType, json)
                    case JsonOrdered.OrderedJson.OArray(items, style) =>
                        insertChildInArray(rootName, rest, childType, items)
                            |> Option.map(pair -> {
                                let (newItems, nm) = pair;
                                (JsonOrdered.OrderedJson.OArray(newItems, style), nm)
                            })
                    case _ => None
                }
        }

    def insertChildInNode(targetName: String, restPath: NodePath, childType: String,
                          element: JsonOrdered.OrderedJson):
                         Option[(JsonOrdered.OrderedJson, String)] =
        match element {
            case JsonOrdered.OrderedJson.OObject(entries, style) =>
                match nodeNameOf(entries) {
                    case Some(name) if name == targetName =>
                        match restPath {
                            case Nil =>
                                let (newEntries, childName) = appendChildEntry(entries, childType);
                                Some((JsonOrdered.OrderedJson.OObject(newEntries, style), childName))
                            case next :: deeper =>
                                descendForInsert(entries, style, next, deeper, childType)
                        }
                    case _ => None
                }
            case _ => None
        }

    def descendForInsert(entries: List[(String, JsonOrdered.OrderedJson)],
                         style: JsonOrdered.ObjectStyle, next: String, deeper: NodePath,
                         childType: String): Option[(JsonOrdered.OrderedJson, String)] =
        match findEntryValue("children", entries) {
            case Some(JsonOrdered.OrderedJson.OArray(items, arrStyle)) =>
                insertChildInArray(next, deeper, childType, items)
                    |> Option.map(pair -> {
                        let (newItems, nm) = pair;
                        let newChildren = JsonOrdered.OrderedJson.OArray(newItems, arrStyle);
                        (JsonOrdered.OrderedJson.OObject(
                            replaceEntryValue("children", newChildren, entries), style), nm)
                    })
            case _ => None
        }

    def insertChildInArray(targetName: String, restPath: NodePath, childType: String,
                           items: List[JsonOrdered.OrderedJson]):
                          Option[(List[JsonOrdered.OrderedJson], String)] =
        match items {
            case Nil => None
            case head :: tail =>
                match insertChildInNode(targetName, restPath, childType, head) {
                    case Some((newHead, nm)) => Some((newHead :: tail, nm))
                    case None =>
                        insertChildInArray(targetName, restPath, childType, tail)
                            |> Option.map(pair -> {
                                let (newTail, nm) = pair;
                                (head :: newTail, nm)
                            })
                }
        }

    /// 対象ノードの entries に子を 1 つ追加する。"children" が無ければ新設する。
    def appendChildEntry(entries: List[(String, JsonOrdered.OrderedJson)], childType: String):
            (List[(String, JsonOrdered.OrderedJson)], String) =
        let (childItems, arrStyle) = match findEntryValue("children", entries) {
            case Some(JsonOrdered.OrderedJson.OArray(items, st)) => (items, st)
            case _ => (Nil, JsonOrdered.ArrayStyle.Block)
        };
        let existing = List.filterMap(it -> match it {
            case JsonOrdered.OrderedJson.OObject(es, _) => nodeNameOf(es)
            case _                                      => None
        }, childItems);
        let childName = uniqueChildName(childType, existing, 2);
        let childJson = match JsonOrdered.parse(defaultChildJson(childType, childName)) {
            case Ok(j)  => j
            case Err(_) => JsonOrdered.OrderedJson.OObject(Nil, JsonOrdered.ObjectStyle.ObjBlock)
        };
        let newItems = List.append(childItems, childJson :: Nil);
        let newChildren = JsonOrdered.OrderedJson.OArray(newItems, arrStyle);
        let newEntries =
            if (hasEntry("children", entries))
                replaceEntryValue("children", newChildren, entries)
            else
                List.append(entries, ("children", newChildren) :: Nil);
        (newEntries, childName)

    def nodeNameOf(entries: List[(String, JsonOrdered.OrderedJson)]): Option[String] =
        findEntryValue("name", entries) |> Option.flatMap(v -> match v {
            case JsonOrdered.OrderedJson.OString(s) => Some(s)
            case _                                  => None
        })

    def hasEntry(key: String, entries: List[(String, JsonOrdered.OrderedJson)]): Bool =
        match findEntryValue(key, entries) {
            case Some(_) => true
            case None    => false
        }

    /// 型名ベースで兄弟内一意の名前を作る。base が空いていれば base、無ければ base2, base3...
    def uniqueChildName(base: String, existing: List[String], n: Int32): String =
        if (not List.memberOf(base, existing)) base
        else {
            let candidate = "${base}${n}";
            if (not List.memberOf(candidate, existing)) candidate
            else uniqueChildName(base, existing, n + 1)
        }

    /// 型ごとの最小デフォルト JSON（基盤c の defaults テーブル）。テクスチャ不要な型に限定。
    /// 子ノードは IDE で配置後に Inspector で寸法・色を調整していく。
    // 既定 JSON 断片は NodeRegistry に集約（カタログの単一ソース）。
    def defaultChildJson(childType: String, name: String): String =
        NodeRegistry.defaultJsonFor(childType, name)

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
            match update#value {
                // 既存オブジェクト（"shape" 等）の 1 キーだけマージ（他キーは保持）。
                case FieldValue.ShapeMergeValue(innerKey, innerVal) =>
                    match findEntryValue(update#key, acc) {
                        case Some(JsonOrdered.OrderedJson.OObject(objEntries, objStyle)) =>
                            let merged = upsertEntry(innerKey,
                                valueToOrderedJson(innerVal), objEntries);
                            upsertEntry(update#key,
                                JsonOrdered.OrderedJson.OObject(merged, objStyle), acc)
                        // 対象オブジェクトが無ければ何もしない（形状が無い等の異常時）
                        case _ => acc
                    }
                case _ => upsertEntry(update#key, valueToOrderedJson(update#value), acc)
            },
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
            // マージ用ラッパ: 内側の値を JSON 化（applyUpdates が key マージで使う。単独では内側値のみ）。
            case FieldValue.ShapeMergeValue(_, innerVal) =>
                valueToOrderedJson(innerVal)
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
