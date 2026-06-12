/// DungeonGenerator の重み付きマップ抽選 (pickWeightedPath) と
/// 重複なし抽選 (excludeUsed) の境界を固定する。
///
/// 観点:
///   - 空プール → None（Math.Random 値に依存しない）
///   - 単一エントリ → 必ずその path
///   - weight 合計 0（全要素 0）→ 一様抽選フォールバックで非 None（「選べない」破綻を避ける）
///   - excludeUsed: 使った部屋を除く / 全部使ったら全プールに戻す
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

    // ════════════════════════════════════════════════════════
    // excludeUsed: 同じ部屋が続けて出ないようにするための重複なし抽選
    // ════════════════════════════════════════════════════════

    /// 3 種プールから 1 種を使用済みにすると、残り 2 種だけが候補に残る
    /// （weight は保ったまま）。「6 種から 2 つ選ぶ」の 2 つ目を引く状況に相当。
    @Test
    def testExcludeUsedRemovesUsedRoom(): Unit \ Assert =
        let pool = ("room_a", 10i32) :: ("room_b", 10i32) :: ("room_c", 10i32) :: Nil;
        Assert.assertEq(
            expected = ("room_b", 10i32) :: ("room_c", 10i32) :: Nil,
            DungeonGenerator.excludeUsed(pool, "room_a" :: Nil))

    /// プールの種類をすべて使い切ったら、空にせず元のプール全体に戻す
    /// （部屋数がプール種類数を超えたときに「引けなくなる」破綻を防ぐフォールバック）。
    @Test
    def testExcludeUsedFallsBackToFullWhenAllUsed(): Unit \ Assert =
        let pool = ("room_a", 10i32) :: ("room_b", 10i32) :: Nil;
        Assert.assertEq(
            expected = pool,
            DungeonGenerator.excludeUsed(pool, "room_a" :: "room_b" :: Nil))
}
