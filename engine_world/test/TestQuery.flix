// Query コンビネータのテスト。join / read-model 構築 / tag 更新の境界を固定する。

mod TestQuery {

    // ── with2 / updateWith2（既存コンビネータの基本契約）──

    /// with2 は「両方持つ」entity だけ残す。
    @Test
    def testWith2KeepsOnlyBoth(): Unit \ Assert =
        let a = Map#{1 => "a", 2 => "b"};
        let b = Map#{2 => 20, 3 => 30};
        Assert.assertEq(expected = Map#{2 => ("b", 20)}, Query.with2(a, b))

    /// updateWith2 は両方持つ entity だけ更新、other を持たない entity は据え置き。
    @Test
    def testUpdateWith2KeepsMissing(): Unit \ Assert =
        let target = Map#{1 => 10, 2 => 20};
        let other  = Map#{1 => 5};
        Assert.assertEq(expected = Map#{1 => 15, 2 => 20}, Query.updateWith2(target, other, (t, o) -> t + o))

    // ── indexBy / tagOf（read-model mirror の核）──

    @Test
    def testIndexByBuildsStore(): Unit \ Assert =
        let xs = {id = 1, hp = 10} :: {id = 2, hp = 20} :: Nil;
        Assert.assertEq(expected = Map#{1 => 10, 2 => 20}, Query.indexBy(r -> r#id, r -> r#hp, xs))

    @Test
    def testTagOfCollectsIds(): Unit \ Assert =
        let xs = {id = 4, hidden = true} :: {id = 8, hidden = false} :: Nil;
        Assert.assertEq(expected = Set#{4, 8}, Query.tagOf(r -> r#id, xs))

    // ── updateTagged（With<T> フィルタ更新）──

    @Test
    def testUpdateTaggedOnlyTagged(): Unit \ Assert =
        let store = Map#{1 => 10, 2 => 20, 3 => 30};
        Assert.assertEq(expected = Map#{1 => 11, 2 => 20, 3 => 31}, Query.updateTagged(Set#{1, 3}, v -> v + 1, store))

    @Test
    def testUpdateTaggedEmptyTagIsIdentity(): Unit \ Assert =
        let store = Map#{1 => 10, 2 => 20};
        Assert.assertEq(expected = store, Query.updateTagged((Set.empty(): Set[EntityId]), v -> v + 1, store))

    // ── with2List（join → 射影 list）──

    @Test
    def testWith2ListProjectsBoth(): Unit \ Assert =
        let a = Map#{1 => "a", 2 => "b"};   // id 1 は b を持たない → 除外
        let b = Map#{2 => 20};
        Assert.assertEq(expected = ("b", 20) :: Nil, Query.with2List(a, b, (_, x, y) -> (x, y)))
}
