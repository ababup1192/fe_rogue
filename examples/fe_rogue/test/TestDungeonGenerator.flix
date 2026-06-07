/// DungeonGenerator の重み付きマップ抽選 (pickWeightedPath) の境界を固定する。
///
/// 観点:
///   - 空プール → None（Math.Random 値に依存しない）
///   - 単一エントリ → 必ずその path
///   - weight 合計 0（全要素 0）→ 一様抽選フォールバックで非 None（「選べない」破綻を避ける）
mod TestDungeonGenerator {

    /// 空プールは None
    @Test
    def testPickWeightedPathEmptyIsNone(): Unit \ {Assert, Math.Random} =
        Assert.assertEq(expected = None,
            DungeonGenerator.pickWeightedPath((Nil: List[(String, Int32)])))

    /// 1 件だけのエントリは必ずその path を返す（randomFloat64 の値に依存しない）
    @Test
    def testPickWeightedPathSingleAlwaysReturnsIt(): Unit \ {Assert, Math.Random} =
        let entries = ("assets/maps/room_1.map.json", 100i32) :: Nil;
        Assert.assertEq(expected = Some("assets/maps/room_1.map.json"),
            DungeonGenerator.pickWeightedPath(entries))

    /// weight が全部 0 でも、非空なら一様抽選フォールバックで Some を返す（None で破綻させない）。
    /// 単一 0-weight エントリならそのエントリが返る。
    @Test
    def testPickWeightedPathZeroWeightFallsBackToUniform(): Unit \ {Assert, Math.Random} =
        let entries = ("assets/maps/room_only.map.json", 0i32) :: Nil;
        Assert.assertEq(expected = Some("assets/maps/room_only.map.json"),
            DungeonGenerator.pickWeightedPath(entries))
}
