/// Weapon の純粋ロジックと、武器込みの総合攻撃力計算の検証。
///
/// 検証する観点:
///   - 耐久度 2 → 1 で武器は残る（Some）
///   - 耐久度 1 → 0 で武器が壊れる（None）
///   - 武器込みの総合攻撃力 = `unit#attack + weapon#attack` が Combat.attackDamage の入力になる

mod TestWeapon {

    // ════════════════════════════════════════════════════════
    // Weapon.consume — 耐久度減少と「壊れたか」の境界
    // ════════════════════════════════════════════════════════

    /// 耐久度 5 の武器を 1 回使うと耐久度 4 で残る
    @Test
    def testConsumeDecrementsDurability(): Unit \ Assert =
        let weapon = TestUnitFixtures.testWeaponFull(2, 5);
        let result = Weapon.consume(weapon);
        let dur = match result {
            case Some(w) => w#durability
            case None    => -1
        };
        Assert.assertEq(expected = (true, 4), (Option.nonEmpty(result), dur))

    /// 耐久度 1 の武器を 1 回使うと壊れる（None）
    /// 「最後の 1 撃で壊れる」境界条件
    @Test
    def testConsumeBreaksAtZero(): Unit \ Assert =
        let weapon = TestUnitFixtures.testWeaponFull(2, 1);
        let result = Weapon.consume(weapon);
        Assert.assertEq(expected = true, Option.isEmpty(result))

    // ════════════════════════════════════════════════════════
    // 武器込みの総合攻撃力（Combat.attackDamage の引数として正しく機能するか）
    // ════════════════════════════════════════════════════════

    /// 力 6 + 武器 2 - 防御 1 = 7 ダメージ
    /// 攻撃側 caller が `unit#attack + weapon#attack` を足してから
    /// Combat.attackDamage に渡す設計を検証する
    @Test
    def testTotalAttackWithWeapon(): Unit \ Assert =
        // testResourceFull(moveTiles, hp, attack, defense, speed)
        let unit   = TestUnitFixtures.testResourceFull(4, 14, 6, 5, 2);
        let weapon = TestUnitFixtures.testWeaponFull(2, 41);
        let totalAttack = unit#attack + weapon#attack;
        let dmg = Combat.attackDamage(totalAttack, 1);
        Assert.assertEq(expected = 7, dmg)

    /// 力 1 + 武器 1 - 防御 5 = 0 ダメージ（max(0, ...) で下限 0 にクランプ）
    @Test
    def testTotalAttackClampedAtZero(): Unit \ Assert =
        let unit   = TestUnitFixtures.testResourceFull(4, 14, 1, 5, 2);
        let weapon = TestUnitFixtures.testWeaponFull(1, 41);
        let totalAttack = unit#attack + weapon#attack;
        let dmg = Combat.attackDamage(totalAttack, 5);
        Assert.assertEq(expected = 0, dmg)
}
