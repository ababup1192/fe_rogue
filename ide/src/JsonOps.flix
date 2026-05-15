// JsonOps — IDE の Inspector が JSON ツリーを書き換えるときに使う純粋関数群
//
// ここに置く関数はすべて副作用なし。シーン JSON を読み書きする際の経路上で、
// 「子インデックス列で目的ノードまで降りる」「キー列で値を差し替える」「BigDecimal にパースする」
// など、IO や Swing から切り離してテストできるロジックだけを集める。
//
// 注意: JSON ファイル書き込み (Fs.WriteFile) や Json.Write.toPrettyString は IO 寄りなので
// ここには置かない。それらは IdeState / InspectorView 側で扱う。

mod JsonOps {

    import java.math.BigDecimal

    use Json.JsonElement.{JsonObject, JsonArray, JsonNull}

    /// 不変リストの idx 番目を newElem に差し替えた新リストを返す。
    /// idx が範囲外なら元のリストをそのまま返す（クラッシュさせない）。
    pub def replaceListAt(idx: Int32, newElem: a, list: List[a]): List[a] =
        match list {
            case Nil     => Nil
            case x :: xs =>
                if (idx == 0i32) newElem :: xs
                else x :: replaceListAt(idx - 1i32, newElem, xs)
        }

    /// JsonObject の中をキー列で降りて末端を newValue に置き換える。
    /// keys が空なら obj を newValue で置き換える。
    /// 途中で JsonObject でなくなったら（= 想定外のスキーマ）そこで諦めて obj を返す。
    pub def setAtKeyPath(obj: Json.JsonElement, keys: List[String], newValue: Json.JsonElement): Json.JsonElement =
        match keys {
            case Nil => newValue
            case headKey :: restKeys =>
                match obj {
                    case JsonObject(map) =>
                        let child = Map.get(headKey, map) |> Option.getWithDefault(JsonNull);
                        let updatedChild = setAtKeyPath(child, restKeys, newValue);
                        JsonObject(Map.insert(headKey, updatedChild, map))
                    case _ => obj
                }
        }

    /// scene root JSON を walk して、子インデックス列 `nodePath` で辿った先のノードの中で、
    /// さらに `subKeys` を順に降りて末端を `newValue` で差し替えた新 root を返す。
    /// path 途中で children/index/key が無いときは root を変えずに返す（クラッシュ回避）。
    pub def setAtNodePath(root: {root = Json.JsonElement, nodePath = List[Int32],
                                  subKeys = List[String], newValue = Json.JsonElement}): Json.JsonElement =
        setAtNodePathRec(root#root, root#nodePath, root#subKeys, root#newValue)

    def setAtNodePathRec(root: Json.JsonElement, nodePath: List[Int32],
                         subKeys: List[String], newValue: Json.JsonElement): Json.JsonElement =
        match nodePath {
            case Nil => setAtKeyPath(root, subKeys, newValue)
            case idx :: restPath =>
                match root {
                    case JsonObject(map) =>
                        match Map.get("children", map) {
                            case Some(JsonArray(children)) =>
                                let childList = Vector.toList(children);
                                match List.nth(idx, childList) {
                                    case Some(child) =>
                                        let updatedChild = setAtNodePathRec(child, restPath, subKeys, newValue);
                                        let updated = replaceListAt(idx, updatedChild, childList);
                                        let newChildren = JsonArray(List.toVector(updated));
                                        JsonObject(Map.insert("children", newChildren, map))
                                    case None => root
                                }
                            case _ => root
                        }
                    case _ => root
                }
        }

    /// 子インデックス列 `nodePath` を辿って該当ノードの JsonElement を返す。
    /// 途中で children/index が無いときは None。
    /// Tree 選択時の Inspector 初期化に使う。
    pub def getAtNodePath(root: Json.JsonElement, nodePath: List[Int32]): Option[Json.JsonElement] =
        match nodePath {
            case Nil => Some(root)
            case idx :: restPath =>
                match root {
                    case JsonObject(map) =>
                        match Map.get("children", map) {
                            case Some(JsonArray(children)) =>
                                match List.nth(idx, Vector.toList(children)) {
                                    case Some(child) => getAtNodePath(child, restPath)
                                    case None        => None
                                }
                            case _ => None
                        }
                    case _ => None
                }
        }

    /// テキストを BigDecimal にパースする。Float64 を経由するので精度は割り切る（v1）。
    /// パースに失敗した文字列・空文字列・前後空白以外の余分な文字を含む場合は None。
    pub def parseBigDecimal(text: String): Option[BigDecimal] =
        Float64.fromString(String.trim(text))
            |> Option.map(value -> unsafe IO { BigDecimal.valueOf(value).stripTrailingZeros() })

    /// IDE の selectedNodePathRef は「JSON ツリー上の子インデックス列」だが、
    /// engine の NodePath は「ノード名の列」(List[String]) でできている。
    /// JSON ツリーを indices に沿って降りつつ、各ステップで child の "name" フィールドを
    /// 集めて NodePath 相当を作る。
    ///
    /// ルートの扱い:
    ///   - JsonObject root (例 BirdScene): tree の root は JSON root オブジェクト
    ///     そのものを表示する。よって engine NodePath はルート name から始める。
    ///     tree [] = engine ["root"]; tree [0] = engine ["root", "child0"]。
    ///   - JsonArray root: tree root は合成された "<root array>" なので、
    ///     indices[0] が配列要素 = engine ルートを指す。tree [0] = engine ["root0"]。
    ///
    /// 途中で children が無かったり index 範囲外だったり、"name" が文字列でなければ None
    pub def extractNodeNames(root: Json.JsonElement, indices: List[Int32]): Option[List[String]] =
        let initialAcc = match root {
            case JsonObject(_) => nameOf(root) |> Option.toList
            case _             => Nil
        };
        extractNodeNamesRec(root, indices, initialAcc)

    def extractNodeNamesRec(root: Json.JsonElement, indices: List[Int32],
                            acc: List[String]): Option[List[String]] =
        match indices {
            case Nil => Some(List.reverse(acc))
            case idx :: restIndices =>
                match getChildAt(root, idx) {
                    case None => None
                    case Some(child) =>
                        match nameOf(child) {
                            case None       => None
                            case Some(name) => extractNodeNamesRec(child, restIndices, name :: acc)
                        }
                }
        }

    /// JSON 要素の idx 番目の子を返す。JsonObject なら "children" 配列の idx 番目を、
    /// JsonArray なら idx 番目の要素を返す。範囲外や子を持たない要素なら None
    def getChildAt(elem: Json.JsonElement, idx: Int32): Option[Json.JsonElement] =
        match elem {
            case JsonObject(map) =>
                match Map.get("children", map) {
                    case Some(JsonArray(children)) => List.nth(idx, Vector.toList(children))
                    case _                         => None
                }
            case JsonArray(items) => List.nth(idx, Vector.toList(items))
            case _ => None
        }

    /// JSON 要素の "name" フィールド (文字列) を取り出す。
    /// "name" が無い・文字列でない場合は None
    def nameOf(elem: Json.JsonElement): Option[String] =
        match elem {
            case JsonObject(map) =>
                match Map.get("name", map) {
                    case Some(Json.JsonElement.JsonString(s)) => Some(s)
                    case _ => None
                }
            case _ => None
        }
}
