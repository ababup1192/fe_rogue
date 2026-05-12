/// Combat.damage のテスト
///
/// HP に対して 1 回のダメージを与えたときの「ダメージ後の HP」と
/// 「このダメージで倒れたか」の判定を検証する。
///
/// 自明な減算（hp - amount で newHp が出る）は型シグネチャから明らかなので
/// テストしない。**死亡判定の境界** に絞って書く:
///   - HP がダメージとぴったり一致して死亡する瞬間
///   - HP よりダメージが大きいときも死亡扱いになる（newHp が負でも isDead = true）
///   - HP がダメージより大きいときは生存
mod TestCombat {

    // ════════════════════════════════════════════════════════
    // 死亡境界: HP <= 0 のときに isDead = true になる
    // ════════════════════════════════════════════════════════

    /// HP 1 にダメージ 1 を与えると、HP = 0 になりちょうど倒れる
    /// （「残り 1 から最後の一撃」の境界条件）
    @Test
    def testDamageReducesHpToZeroAndMarksDead(): Unit \ Assert =
        let result = Combat.damage(hp = 1, amount = 1);
        Assert.assertEq(expected = (0, true), (result#newHp, result#isDead))

    /// HP 5 にダメージ 10 を与えると、HP = -5 になっても倒れた扱い
    /// （オーバーキルでも isDead = true。負の HP を上位で気にしないで済むようにする）
    @Test
    def testDamageOverkillStillMarksDead(): Unit \ Assert =
        let result = Combat.damage(hp = 5, amount = 10);
        Assert.assertEq(expected = (-5, true), (result#newHp, result#isDead))

    /// HP 10 にダメージ 1 を与えると、HP = 9 で生存
    /// （「ダメージは食らったがまだ立っている」状態の確認）
    @Test
    def testDamageLeavesHpPositiveWhenNotLethal(): Unit \ Assert =
        let result = Combat.damage(hp = 10, amount = 1);
        Assert.assertEq(expected = (9, false), (result#newHp, result#isDead))
}
