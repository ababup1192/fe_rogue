// JsonOps — IDE の Inspector が JSON ツリーを書き換えるときに使う純粋関数群
//
// ここに置く関数はすべて副作用なし。シーン JSON を読み書きする際の経路上で、
// 「子インデックス列で目的ノードまで降りる」「キー列で値を差し替える」「BigDecimal にパースする」
// など、IO や Swing から切り離してテストできるロジックだけを集める。
//
// 注意: JSON ファイル書き込み (Fs.WriteFile) や Util.Json.toPrettyString は IO 寄りなので
// ここには置かない。それらは IdeState / InspectorView 側で扱う。

mod JsonOps {

    import java.math.BigDecimal

    use Util.Json.Json.{JObject, JArray, JString, JNull}

    /// 不変リストの idx 番目を newElem に差し替えた新リストを返す。
    /// idx が範囲外なら元のリストをそのまま返す（クラッシュさせない）。
    pub def replaceListAt(idx: Int32, newElem: a, list: List[a]): List[a] =
        match list {
            case Nil     => Nil
            case x :: xs =>
                if (idx == 0i32) newElem :: xs
                else x :: replaceListAt(idx - 1i32, newElem, xs)
        }

    /// JObject / JArray の中をキー列で降りて末端を newValue に置き換える。
    /// keys が空なら obj を newValue で置き換える。
    /// 現在位置が JObject なら headKey をフィールド名として降りる。
    /// 現在位置が JArray なら headKey を整数インデックス（"0", "1" ...）として降りる。
    /// 途中で型が合わなければ（= 想定外のスキーマ）そこで諦めて obj を返す。
    pub def setAtKeyPath(obj: Util.Json.Json, keys: List[String], newValue: Util.Json.Json): Util.Json.Json =
        match keys {
            case Nil => newValue
            case headKey :: restKeys =>
                match obj {
                    case JObject(map) =>
                        let raw = Map.get(headKey, map) |> Option.getWithDefault(JNull);
                        // 中間レベルで JNull / 非オブジェクトの場合は空 object を作って降りる
                        // （schema にあるが JSON にまだ無い nested フィールドを編集できるようにする）
                        let child = match raw {
                            case JObject(_) => raw
                            case _             =>
                                if (List.isEmpty(restKeys)) raw
                                else JObject(Map.empty())
                        };
                        let updatedChild = setAtKeyPath(child, restKeys, newValue);
                        JObject(Map.insert(headKey, updatedChild, map))
                    case JArray(items) =>
                        match Int32.fromString(headKey) {
                            case Some(idx) =>
                                let itemList = Vector.toList(items);
                                match List.nth(idx, itemList) {
                                    case None => obj
                                    case Some(child) =>
                                        let updatedChild = setAtKeyPath(child, restKeys, newValue);
                                        JArray(List.toVector(replaceListAt(idx, updatedChild, itemList)))
                                }
                            case None => obj
                        }
                    case _ => obj
                }
        }

    /// scene root JSON を walk して、子インデックス列 `nodePath` で辿った先のノードの中で、
    /// さらに `subKeys` を順に降りて末端を `newValue` で差し替えた新 root を返す。
    /// path 途中で children/index/key が無いときは root を変えずに返す（クラッシュ回避）。
    pub def setAtNodePath(root: {root = Util.Json.Json, nodePath = List[Int32],
                                  subKeys = List[String], newValue = Util.Json.Json}): Util.Json.Json =
        setAtNodePathRec(root#root, root#nodePath, root#subKeys, root#newValue)

    def setAtNodePathRec(root: Util.Json.Json, nodePath: List[Int32],
                         subKeys: List[String], newValue: Util.Json.Json): Util.Json.Json =
        match nodePath {
            case Nil => setAtKeyPath(root, subKeys, newValue)
            case idx :: restPath =>
                match root {
                    case JObject(map) =>
                        match Map.get("type", map) {
                            case Some(JString("Container")) =>
                                setContainerChildAt(map, idx, restPath, subKeys, newValue, root)
                            case _ =>
                                match Map.get("children", map) {
                                    case Some(JArray(children)) =>
                                        let childList = Vector.toList(children);
                                        match List.nth(idx, childList) {
                                            case Some(child) =>
                                                let updatedChild = setAtNodePathRec(child, restPath, subKeys, newValue);
                                                let updated = replaceListAt(idx, updatedChild, childList);
                                                let newChildren = JArray(List.toVector(updated));
                                                JObject(Map.insert("children", newChildren, map))
                                            case None => root
                                        }
                                    case _ => root
                                }
                        }
                    case _ => root
                }
        }

    /// Container 内の idx 番目の子（layout 配下の実ノード）を更新して、Container を
    /// 再構築した JObject を返す。Panel/HBox/VBox は layout.children[idx]、
    /// Margin/Center は layout.child を idx=0 のときだけ書き換える
    def setContainerChildAt(map: Map[String, Util.Json.Json], idx: Int32,
                            restPath: List[Int32], subKeys: List[String],
                            newValue: Util.Json.Json, originalRoot: Util.Json.Json): Util.Json.Json =
        match Map.get("layout", map) {
            case Some(JObject(layoutMap)) =>
                match Map.get("kind", layoutMap) {
                    case Some(JString(kind)) =>
                        if (kind == "MarginContainer" or kind == "CenterContainer") {
                            if (idx != 0i32) originalRoot
                            else match Map.get("child", layoutMap) {
                                case Some(childElem) =>
                                    let updatedChild = setAtNodePathRec(childElem, restPath, subKeys, newValue);
                                    let newLayout = JObject(Map.insert("child", updatedChild, layoutMap));
                                    JObject(Map.insert("layout", newLayout, map))
                                case None => originalRoot
                            }
                        } else
                            match Map.get("children", layoutMap) {
                                case Some(JArray(children)) =>
                                    let childList = Vector.toList(children);
                                    match List.nth(idx, childList) {
                                        case Some(child) =>
                                            let updatedChild = setAtNodePathRec(child, restPath, subKeys, newValue);
                                            let updated = replaceListAt(idx, updatedChild, childList);
                                            let newChildren = JArray(List.toVector(updated));
                                            let newLayout = JObject(Map.insert("children", newChildren, layoutMap));
                                            JObject(Map.insert("layout", newLayout, map))
                                        case None => originalRoot
                                    }
                                case _ => originalRoot
                            }
                    case _ => originalRoot
                }
            case _ => originalRoot
        }

    /// JObject / JArray の中をキー列で降りて末端の値を返す。
    /// `setAtKeyPath` の逆方向で、widget が現在値を読み出すために使う。
    /// 途中で型が合わなかったり、キーが存在しない場合は None。
    pub def getAtKeyPath(obj: Util.Json.Json, keys: List[String]): Option[Util.Json.Json] =
        match keys {
            case Nil => Some(obj)
            case headKey :: restKeys =>
                match obj {
                    case JObject(map) =>
                        Map.get(headKey, map)
                            |> Option.flatMap(child -> getAtKeyPath(child, restKeys))
                    case JArray(items) =>
                        match Int32.fromString(headKey) {
                            case Some(idx) =>
                                Vector.toList(items)
                                    |> List.nth(idx)
                                    |> Option.flatMap(child -> getAtKeyPath(child, restKeys))
                            case None => None
                        }
                    case _ => None
                }
        }

    /// 子インデックス列 `nodePath` を辿って該当ノードの Json を返す。
    /// 途中で children/index が無いときは None。
    /// Tree 選択時の Inspector 初期化に使う。
    pub def getAtNodePath(root: Util.Json.Json, nodePath: List[Int32]): Option[Util.Json.Json] =
        match nodePath {
            case Nil => Some(root)
            case idx :: restPath =>
                match getChildAt(root, idx) {
                    case Some(child) => getAtNodePath(child, restPath)
                    case None        => None
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
    ///   - JObject root (例 BirdScene): tree の root は JSON root オブジェクト
    ///     そのものを表示する。よって engine NodePath はルート name から始める。
    ///     tree [] = engine ["root"]; tree [0] = engine ["root", "child0"]。
    ///   - JArray root: tree root は合成された "<root array>" なので、
    ///     indices[0] が配列要素 = engine ルートを指す。tree [0] = engine ["root0"]。
    ///
    /// 途中で children が無かったり index 範囲外だったり、"name" が文字列でなければ None
    pub def extractNodeNames(root: Util.Json.Json, indices: List[Int32]): Option[List[String]] =
        let initialAcc = match root {
            case JObject(_) => nameOf(root) |> Option.toList
            case _             => Nil
        };
        extractNodeNamesRec(root, indices, initialAcc)

    def extractNodeNamesRec(root: Util.Json.Json, indices: List[Int32],
                            acc: List[String]): Option[List[String]] =
        match indices {
            case Nil =>
                // 最終ノードが透過 (Container / Layout primitive) なら engine 側に対応
                // ノードがないので None
                if (isTransparentJson(root)) None
                else Some(List.reverse(acc))
            case idx :: restIndices =>
                match getChildAt(root, idx) {
                    case None => None
                    case Some(child) =>
                        // 透過ノード (Container / Layout primitive) は engine の scene tree
                        // には現れないので、name を acc に積まず素通り
                        if (isTransparentJson(child))
                            extractNodeNamesRec(child, restIndices, acc)
                        else match nameOf(child) {
                            case None       => None
                            case Some(name) => extractNodeNamesRec(child, restIndices, name :: acc)
                        }
                }
        }

    /// JSON 要素の idx 番目の子を返す。
    /// - type が "Container" の JObject は layout 配下の実ノード列の idx 番目を返す
    ///   (SceneTreeModel.jsonChildrenOf と同じ規約)
    /// - その他の JObject は "children" 配列の idx 番目
    /// - JArray は idx 番目の要素
    /// - それ以外や範囲外は None
    def getChildAt(elem: Util.Json.Json, idx: Int32): Option[Util.Json.Json] =
        match elem {
            case JObject(map) =>
                match Map.get("type", map) {
                    case Some(JString("Container")) =>
                        List.nth(idx, containerInnerChildren(map))
                    case _ =>
                        match Map.get("children", map) {
                            case Some(JArray(children)) =>
                                List.nth(idx, Vector.toList(children))
                            case _ => None
                        }
                }
            case JArray(items) => List.nth(idx, Vector.toList(items))
            case _ => None
        }

    /// JSON 要素が type=="Container" の JObject か判定する
    pub def isContainerJson(elem: Util.Json.Json): Bool =
        match elem {
            case JObject(map) =>
                match Map.get("type", map) {
                    case Some(JString("Container")) => true
                    case _ => false
                }
            case _ => false
        }

    /// JSON 要素が engine の scene tree には現れない「透過ノード」か判定する。
    /// - type=="Container" → load-time directive
    /// - "kind" のみ持ち "type" を持たない JObject → Layout primitive
    ///   (Panel / HBoxContainer / VBoxContainer / MarginContainer / CenterContainer)
    /// これらは IDE tree には見えるが、engine NodePath には積まれないので、
    /// extractNodeNames / namesToIndices で name を skip し、子を素通しで辿る
    pub def isTransparentJson(elem: Util.Json.Json): Bool =
        match elem {
            case JObject(map) =>
                match Map.get("type", map) {
                    case Some(JString("Container")) => true
                    case Some(_)                       => false
                    case None                          => Map.memberOf("kind", map)
                }
            case _ => false
        }

    /// Container ("type": "Container") の "layout" を覗き、Panel/HBox/VBox の
    /// "children" または Margin/Center の "child" を返す
    pub def containerInnerChildren(map: Map[String, Util.Json.Json]): List[Util.Json.Json] =
        match Map.get("layout", map) {
            case Some(JObject(layoutMap)) => layoutChildren(layoutMap)
            case _ => Nil
        }

    /// 透過 JObject の「直接の子」列を返す。
    /// - Container: layout 配下 (containerInnerChildren と同じ)
    /// - Panel / HBoxContainer / VBoxContainer: 自身の "children"
    /// - MarginContainer / CenterContainer: 自身の "child" を 1 要素リストにラップ
    pub def transparentInnerChildren(map: Map[String, Util.Json.Json]): List[Util.Json.Json] =
        match Map.get("type", map) {
            case Some(JString("Container")) => containerInnerChildren(map)
            case _                             => layoutChildren(map)
        }

    /// Layout JSON の kind に応じた子ノード列。
    /// Panel/HBoxContainer/VBoxContainer は "children" 配列、
    /// MarginContainer/CenterContainer は 1 件の "child"
    def layoutChildren(layoutMap: Map[String, Util.Json.Json]): List[Util.Json.Json] =
        match Map.get("kind", layoutMap) {
            case Some(JString(kind)) =>
                if (kind == "MarginContainer" or kind == "CenterContainer")
                    match Map.get("child", layoutMap) {
                        case Some(c) => c :: Nil
                        case None    => Nil
                    }
                else
                    match Map.get("children", layoutMap) {
                        case Some(JArray(children)) => Vector.toList(children)
                        case _                         => Nil
                    }
            case _ => Nil
        }

    /// JSON 要素の "name" フィールド (文字列) を取り出す。
    /// "name" が無い・文字列でない場合は None
    def nameOf(elem: Util.Json.Json): Option[String] =
        match elem {
            case JObject(map) =>
                match Map.get("name", map) {
                    case Some(Util.Json.Json.JString(s)) => Some(s)
                    case _ => None
                }
            case _ => None
        }
}
