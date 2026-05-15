// SceneTreeModel — シーンの JSON ツリーを Swing から切り離した純粋なツリーモデルに変換する
//
// 役割:
//   - JSON ツリー (Json.JsonElement) → ラベル + 子インデックス列 + 子モデル のツリー (TreeModelNode)
//   - 「[Type] Name」というラベル整形ロジック
//   - ルート JsonArray・想定外の要素のフォールバック表示
//
// この層は副作用を持たないため、テストで木構造を直接突き合わせできる。
// Swing の DefaultMutableTreeNode への変換 と identityHashCode → nodePath の登録は
// IO 層 (SceneTreeView 側) で行う

mod SceneTreeModel {

    use Json.JsonElement.{JsonObject, JsonArray, JsonString}

    /// シーンツリーの 1 ノード。Swing から独立した中間表現。
    ///   label:    ノードを 1 行で表す表示文字列（例 "[Sprite2D] hero"）
    ///   nodePath: ルートからの子インデックス列（root は Nil）
    ///   children: 同じ型の子ノード列
    pub enum TreeModelNode({
        label    = String,
        nodePath = List[Int32],
        children = List[TreeModelNode]
    })

    /// ノードのラベル文字列を返す
    pub def labelOf(node: TreeModelNode): String =
        let TreeModelNode.TreeModelNode(record) = node;
        record#label

    /// ノードのルートからの子インデックス列を返す
    pub def nodePathOf(node: TreeModelNode): List[Int32] =
        let TreeModelNode.TreeModelNode(record) = node;
        record#nodePath

    /// ノードの子ノード列を返す
    pub def childrenOf(node: TreeModelNode): List[TreeModelNode] =
        let TreeModelNode.TreeModelNode(record) = node;
        record#children

    /// JSON ツリーから TreeModelNode を構築する。ルートのノードパスは Nil。
    pub def fromJson(elem: Json.JsonElement): TreeModelNode =
        fromJsonAt(elem, Nil)

    def fromJsonAt(elem: Json.JsonElement, nodePath: List[Int32]): TreeModelNode =
        let label = labelFor(elem);
        let children = jsonChildrenOf(elem)
            |> List.mapWithIndex((idx, child) -> fromJsonAt(child, nodePath ::: idx :: Nil));
        TreeModelNode.TreeModelNode({label = label, nodePath = nodePath, children = children})

    /// JSON 要素を 1 行で表すラベル文字列を返す。
    /// - type=="Container" : "[Container <layoutKind>] name" 形式
    ///   (どのレイアウトを持つ容器か tree からひと目で分かるように layout.kind を併記)
    /// - JsonObject with "type" : "[type] name" 形式
    /// - JsonObject with "kind" only (Layout primitive) : "[kind] name" 形式
    ///   (Panel / HBoxContainer / VBoxContainer / MarginContainer / CenterContainer)
    /// - JsonArray :  "<root array>"
    /// - その他   :  "<invalid>"
    pub def labelFor(elem: Json.JsonElement): String =
        match elem {
            case JsonObject(map) =>
                match Map.get("type", map) {
                    case Some(JsonString("Container")) => containerLabel(map)
                    case Some(JsonString(t))           =>
                        "[${t}] ${nameOrUnnamed(map)}"
                    case _ =>
                        // type 無し: Layout primitive なら kind を type 代わりに表示
                        match Map.get("kind", map) {
                            case Some(JsonString(k)) => "[${k}] ${nameOrUnnamed(map)}"
                            case _                   => "[Node] ${nameOrUnnamed(map)}"
                        }
                }
            case JsonArray(_) => "<root array>"
            case _            => "<invalid>"
        }

    /// Container 自身のラベル。layout.kind があれば "[Container Panel]" のように併記する
    def containerLabel(map: Map[String, Json.JsonElement]): String =
        let kindSuffix = match layoutKindOf(map) {
            case Some(k) => " ${k}"
            case None    => ""
        };
        "[Container${kindSuffix}] ${nameOrUnnamed(map)}"

    /// Container map から layout.kind の文字列を取り出す。layout 不在 or kind 非文字列なら None
    def layoutKindOf(map: Map[String, Json.JsonElement]): Option[String] =
        match Map.get("layout", map) {
            case Some(JsonObject(layoutMap)) =>
                match Map.get("kind", layoutMap) {
                    case Some(JsonString(k)) => Some(k)
                    case _                   => None
                }
            case _ => None
        }

    /// "name" を取り出す。無い / 非文字列なら "<unnamed>"
    def nameOrUnnamed(map: Map[String, Json.JsonElement]): String =
        match Map.get("name", map) {
            case Some(JsonString(s)) => s
            case _                   => "<unnamed>"
        }

    /// 与えられた JSON 要素の子要素列を返す。
    /// - type が "Container" の JsonObject は load-time directive。layout に格納された
    ///   実ノード列 (Panel/HBox/VBox の "children"、Margin/Center の "child") を
    ///   そのまま自分の子として展開する
    /// - その他の JsonObject の "children" が JsonArray ならその要素群
    /// - 直接 JsonArray ならその要素群（シーンツリーのルートが配列のケース）
    /// - それ以外は空
    def jsonChildrenOf(elem: Json.JsonElement): List[Json.JsonElement] =
        match elem {
            case JsonObject(map) =>
                match Map.get("type", map) {
                    case Some(JsonString("Container")) => containerInnerChildren(map)
                    case _ =>
                        match Map.get("children", map) {
                            case Some(JsonArray(children)) => Vector.toList(children)
                            case _                         => Nil
                        }
                }
            case JsonArray(items) => Vector.toList(items)
            case _ => Nil
        }

    /// Container の "layout" を覗き、その中の実ノード列を取り出す。
    /// JsonOps 側 (getChildAt / setAtNodePath / extractNodeNames) も同じ規約で
    /// Container を扱う
    def containerInnerChildren(map: Map[String, Json.JsonElement]): List[Json.JsonElement] =
        match Map.get("layout", map) {
            case Some(JsonObject(layoutMap)) => layoutChildren(layoutMap)
            case _ => Nil
        }

    /// Layout の kind に応じた子ノード列。
    /// Panel/HBoxContainer/VBoxContainer は "children" 配列、
    /// MarginContainer/CenterContainer は 1 件の "child"
    def layoutChildren(layoutMap: Map[String, Json.JsonElement]): List[Json.JsonElement] =
        match Map.get("kind", layoutMap) {
            case Some(JsonString(kind)) =>
                if (kind == "MarginContainer" or kind == "CenterContainer")
                    match Map.get("child", layoutMap) {
                        case Some(c) => c :: Nil
                        case None    => Nil
                    }
                else
                    match Map.get("children", layoutMap) {
                        case Some(JsonArray(children)) => Vector.toList(children)
                        case _                         => Nil
                    }
            case _ => Nil
        }
}
