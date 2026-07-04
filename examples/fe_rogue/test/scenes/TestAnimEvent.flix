/// AnimEvent モジュールのテスト
///
/// 検証する観点:
///   - 全ての `Tag` バリアントについて `parseTag(tagToString(t)) == Some(t)`
///     のラウンドトリップが成立する（書き手側と dispatch 側の表現が完全に対応）
///   - 未知文字列に対して `parseTag` が `None` を返す（防御的に no-op になる）
///
/// このテストの存在意義:
///   - 新しい Tag バリアントを追加したときに `tagToString` / `parseTag` の
///     両方を更新し忘れる事故を **テスト失敗で気付ける**
///   - engine 側の `name: String` と game 側の `Tag` enum を分離している
///     設計の代償（ラウンドトリップ責任）を pin しておくため
mod TestAnimEvent {

    use AnimEvent.Tag

    // ════════════════════════════════════════════════════════
    // ラウンドトリップ: 各 Tag が tagToString → parseTag で復元できる
    // ════════════════════════════════════════════════════════

    @Test
    def testRoundTripAttackHit(): Unit \ Assert =
        let s = AnimEvent.tagToString(Tag.AttackHit);
        Assert.assertEq(expected = Some(Tag.AttackHit), AnimEvent.parseTag(s))

    @Test
    def testRoundTripDeathBlink(): Unit \ Assert =
        let s = AnimEvent.tagToString(Tag.DeathBlink);
        Assert.assertEq(expected = Some(Tag.DeathBlink), AnimEvent.parseTag(s))

    @Test
    def testRoundTripAttackLunge(): Unit \ Assert =
        let s = AnimEvent.tagToString(Tag.AttackLunge);
        Assert.assertEq(expected = Some(Tag.AttackLunge), AnimEvent.parseTag(s))

    // ════════════════════════════════════════════════════════
    // 防御的: 未知文字列は None
    // ════════════════════════════════════════════════════════

    /// 知らない文字列が来ても dispatch を巻き込まずに no-op に倒れることを保証
    @Test
    def testParseTagUnknownReturnsNone(): Unit \ Assert =
        Assert.assertEq(expected = None, AnimEvent.parseTag("unknown"))

    /// 空文字も None。境界条件
    @Test
    def testParseTagEmptyReturnsNone(): Unit \ Assert =
        Assert.assertEq(expected = None, AnimEvent.parseTag(""))
}
