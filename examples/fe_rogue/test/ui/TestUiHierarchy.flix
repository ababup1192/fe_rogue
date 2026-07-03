/// UiHierarchy のツリー走査（子並び順・部分木集合・継承可視性）を固定する。
mod TestUiHierarchy {

    // ════════════════════════════════════════════════════════
    // childrenOf: order 昇順
    // ════════════════════════════════════════════════════════

    /// 親1 の子は order 昇順 4(0),2(1),3(2) の順（挿入順と無関係）。
    @Test
    def testChildrenOfSortedByOrder(): Unit \ Assert =
        let parents = Map#{2 => 1, 3 => 1, 4 => 1};
        let order = Map#{2 => 1, 3 => 2, 4 => 0};
        Assert.assertEq(expected = 4 :: 2 :: 3 :: Nil, UiHierarchy.childrenOf(1, parents, order))

    // ════════════════════════════════════════════════════════
    // descendants: root 含む
    // ════════════════════════════════════════════════════════

    /// 1 の子孫。1─{2,3}, 2─{4} なので {1,2,3,4}。
    @Test
    def testDescendantsIncludesRootAndAll(): Unit \ Assert =
        let parents = Map#{2 => 1, 3 => 1, 4 => 2};
        Assert.assertEq(expected = Set#{1, 2, 3, 4}, UiHierarchy.descendants(1, parents))

    // ════════════════════════════════════════════════════════
    // resolveInherited: 親不可視→子不可視・未登録=true
    // ════════════════════════════════════════════════════════

    /// 1(可視) ─ 2(不可視) ─ 3(未登録)
    ///          └ 4(未登録)
    /// 2 が不可視ゆえ 3 も実効不可視。4 は親可視かつ未登録なので true。
    @Test
    def testResolveInheritedParentHidesChild(): Unit \ Assert =
        let parents = Map#{2 => 1, 3 => 2, 4 => 1};
        let order = Map#{2 => 0, 3 => 0, 4 => 1};
        let visible = Map#{1 => true, 2 => false};
        let result = UiHierarchy.resolveInherited(visible, parents, 1, order);
        Assert.assertEq(
            expected = (Some(true), Some(false), Some(false), Some(true)),
            (Map.get(1, result), Map.get(2, result), Map.get(3, result), Map.get(4, result)))
}
