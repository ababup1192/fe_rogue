// Query コンビネータのテスト。exclude（Map - Set＝"without" 系）の境界を固定する。

mod TestQuery {

    /// ids に含まれる entity だけ抜け、残りは値ごと保持される。
    @Test
    def testExcludeDropsIds(): Unit \ Assert =
        let a = Map#{1 => 10, 2 => 20, 3 => 30};
        Assert.assertEq(expected = Map#{1 => 10}, Query.exclude(a, Set#{2, 3}))

    /// 空集合の除外は恒等（全 entity そのまま）。
    @Test
    def testExcludeEmptySetKeepsAll(): Unit \ Assert =
        let a = Map#{1 => 10, 2 => 20};
        Assert.assertEq(expected = a, Query.exclude(a, (Set.empty(): Set[EntityId])))

    /// 全 id を除外すると空になる。
    @Test
    def testExcludeAll(): Unit \ Assert =
        let a = Map#{1 => 10};
        Assert.assertEq(expected = (Map.empty(): Map[EntityId, Int32]), Query.exclude(a, Set#{1}))
}
