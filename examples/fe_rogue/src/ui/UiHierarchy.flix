// UiHierarchy — UI entity の親子ツリー走査（完全純粋）
//
// UI ツリーは parents（子→親）と order（兄弟内の並び順）だけで表現される。
// このモジュールは「ある親の子一覧」「部分木の全 entity」「継承済み可視性」を導出する。

mod UiHierarchy {

    /// parent を親に持つ entity を order 昇順で返す。
    /// order 未登録の entity は 0 扱い。
    pub def childrenOf(parent: EntityId, parents: Map[EntityId, EntityId], order: Map[EntityId, Int32]): List[EntityId] =
        parents
            |> Map.foldLeftWithKey((acc, id, p) -> if (p == parent) id :: acc else acc, Nil)
            |> List.sortBy(id -> Option.getWithDefault(0, Map.get(id, order)))

    /// root とその全子孫を集めた集合（root 自身を含む）。
    pub def descendants(root: EntityId, parents: Map[EntityId, EntityId]): Set[EntityId] =
        descendantsRec(root :: Nil, parents, Set#{})

    /// フロンティアを 1 件ずつ処理し、未訪問なら子を積んで集合へ加える。
    def descendantsRec(frontier: List[EntityId], parents: Map[EntityId, EntityId], acc: Set[EntityId]): Set[EntityId] =
        match frontier {
            case Nil => acc
            case id :: rest =>
                if (Set.memberOf(id, acc)) descendantsRec(rest, parents, acc)
                else {
                    let kids = parents |> Map.foldLeftWithKey((a, kid, p) -> if (p == id) kid :: a else a, Nil);
                    descendantsRec(List.append(kids, rest), parents, Set.insert(id, acc))
                }
        }

    /// 継承済み可視性（Bevy InheritedVisibility）。祖先が不可視なら子も不可視。
    /// visible 未登録の entity は true 扱い。root から下へ AND を伝播する。
    pub def resolveInherited(visible: Map[EntityId, Bool], parents: Map[EntityId, EntityId],
                             root: EntityId, order: Map[EntityId, Int32]): Map[EntityId, Bool] =
        resolveInheritedRec(root, true, visible, parents, order, Map.empty())

    /// id の実効可視性 = 親の実効可視性 AND 自分の設定可視性。子孫へ再帰する。
    def resolveInheritedRec(id: EntityId, parentVisible: Bool, visible: Map[EntityId, Bool],
                            parents: Map[EntityId, EntityId], order: Map[EntityId, Int32],
                            acc: Map[EntityId, Bool]): Map[EntityId, Bool] =
        let selfVisible = Option.getWithDefault(true, Map.get(id, visible));
        let effective = parentVisible and selfVisible;
        let acc1 = Map.insert(id, effective, acc);
        childrenOf(id, parents, order)
            |> List.foldLeft((a, child) -> resolveInheritedRec(child, effective, visible, parents, order, a), acc1)
}
