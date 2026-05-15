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

    // ════════════════════════════════════════════════════════
    // attackDamage: max(0, attack - defense)
    // ════════════════════════════════════════════════════════

    /// 攻撃 6 vs 防御 1 → 5 ダメージ
    @Test
    def testAttackDamageNormal(): Unit \ Assert =
        Assert.assertEq(expected = 5, Combat.attackDamage(6, 1))

    /// 攻撃 = 防御 → 0 ダメージ（弱攻撃が硬い相手に通らない）
    @Test
    def testAttackDamageEqualIsZero(): Unit \ Assert =
        Assert.assertEq(expected = 0, Combat.attackDamage(3, 3))

    /// 攻撃 < 防御 でも下限 0（負ダメは出ない）
    @Test
    def testAttackDamageDefenseHigherIsZero(): Unit \ Assert =
        Assert.assertEq(expected = 0, Combat.attackDamage(2, 5))

    // ════════════════════════════════════════════════════════
    // hitRate: clamp(80 + (atkSpd - defSpd) * 5, 5, 100)
    // ════════════════════════════════════════════════════════

    /// 速さ同等 → 基準値 80%
    @Test
    def testHitRateEqualSpeed(): Unit \ Assert =
        Assert.assertEq(expected = 80, Combat.hitRate(3, 3))

    /// 攻撃側速さ +5 → 上限 100% に張りつく（80 + 25 → clamp）
    @Test
    def testHitRateClampUpper(): Unit \ Assert =
        Assert.assertEq(expected = 100, Combat.hitRate(8, 3))

    /// 防御側速さ +20 → 下限 5% に張りつく（80 - 100 → clamp）
    @Test
    def testHitRateClampLower(): Unit \ Assert =
        Assert.assertEq(expected = 5, Combat.hitRate(0, 20))

    // ════════════════════════════════════════════════════════
    // forecast: スペックの「与:N 命中:P% 撃破」が一発で出る
    // ════════════════════════════════════════════════════════

    /// knight (atk6, spd2) → goblin (hp3, def1, spd4):
    /// 与 = 6-1 = 5, 命中 = 80 + (2-4)*5 = 70, 残 HP 3-5 ≦ 0 → 撃破
    @Test
    def testForecastKnightVsGoblin(): Unit \ Assert =
        let f = Combat.forecast(
            {attack = 6, speed = 2},
            {hp = 3, defense = 1, speed = 4});
        Assert.assertEq(expected = (5, 70, true), (f#damage, f#hit, f#kill))
}
