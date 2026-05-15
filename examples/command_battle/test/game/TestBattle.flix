/// Battle.flix の DQ1 ダメージ計算式の検証。
/// rng を引数で与えるので決定的にテストできる。
mod TestBattle {

    // ── computeAttack: 基本値 + factor 範囲 ──

    /// atk=10, def=4 → base = (20 - 4) / 4 = 4
    /// rng=0.0 → factor=0.75 → 4 * 0.75 = 3 → max(1, 3) = 3
    @Test
    def testComputeAttackMin(): Unit \ Assert =
        Assert.assertEq(expected = 3, Battle.computeAttack(10, 4, 0.0))

    /// atk=10, def=4 → base = 4、 rng=1.0 → factor=1.0 → 4 * 1.0 = 4
    @Test
    def testComputeAttackMax(): Unit \ Assert =
        Assert.assertEq(expected = 4, Battle.computeAttack(10, 4, 1.0))

    /// 守備が高くて base <= 0 でも、 最低 1 ダメージは入る
    @Test
    def testComputeAttackMinimum1(): Unit \ Assert =
        Assert.assertEq(expected = 1, Battle.computeAttack(2, 10, 0.5))

    /// rng が範囲外 (負値) でも 0.0 にクランプされて factor=0.75
    @Test
    def testComputeAttackRngClampLow(): Unit \ Assert =
        Assert.assertEq(expected = 3, Battle.computeAttack(10, 4, -0.5))

    /// rng が範囲外 (>1.0) でも 1.0 にクランプ
    @Test
    def testComputeAttackRngClampHigh(): Unit \ Assert =
        Assert.assertEq(expected = 4, Battle.computeAttack(10, 4, 1.5))

    // ── computeSpell: 一様乱数で min..max ──

    /// minPower=10, maxPower=14, rng=0.0 → minPower 直値
    @Test
    def testComputeSpellMin(): Unit \ Assert =
        Assert.assertEq(expected = 10, Battle.computeSpell(10, 14, 0.0))

    /// rng=1.0 → maxPower 直値
    @Test
    def testComputeSpellMax(): Unit \ Assert =
        Assert.assertEq(expected = 14, Battle.computeSpell(10, 14, 1.0))

    /// rng=0.5 → minPower + span/2 = 10 + 2 = 12
    @Test
    def testComputeSpellMid(): Unit \ Assert =
        Assert.assertEq(expected = 12, Battle.computeSpell(10, 14, 0.5))
}
