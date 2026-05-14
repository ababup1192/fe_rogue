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
    /// - JsonObject: "[type] name" 形式。type/name が無ければデフォルト文字列を使う
    /// - JsonArray:  "<root array>" として子だけが意味を持つ箱表示
    /// - その他:     "<invalid>" でクラッシュさせない
    pub def labelFor(elem: Json.JsonElement): String =
        match elem {
            case JsonObject(map) =>
                let nodeType = match Map.get("type", map) {
                    case Some(JsonString(s)) => s
                    case _                   => "Node"
                };
                let nodeName = match Map.get("name", map) {
                    case Some(JsonString(s)) => s
                    case _                   => "<unnamed>"
                };
                "[${nodeType}] ${nodeName}"
            case JsonArray(_) => "<root array>"
            case _            => "<invalid>"
        }

    /// 与えられた JSON 要素の子要素列を返す。
    /// - JsonObject の "children" が JsonArray ならその要素群
    /// - 直接 JsonArray ならその要素群（シーンツリーのルートが配列のケース）
    /// - それ以外は空
    def jsonChildrenOf(elem: Json.JsonElement): List[Json.JsonElement] =
        match elem {
            case JsonObject(map) =>
                match Map.get("children", map) {
                    case Some(JsonArray(children)) => Vector.toList(children)
                    case _                         => Nil
                }
            case JsonArray(items) => Vector.toList(items)
            case _ => Nil
        }
}
