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
    // hitRate: clamp(0, 100, 命中 - 回避)
    //   命中 = 武器命中 + 技×2 + 幸運÷2
    //   回避 = 速さ×2 + 幸運
    //   引数: (attackerSkill, attackerLuck, weaponHit, defenderSpeed, defenderLuck)
    // ════════════════════════════════════════════════════════

    /// 技5 幸運4 武器命中70 / 防御 速さ4 幸運3:
    /// 命中 = 70 + 5*2 + 4/2 = 82, 回避 = 4*2 + 3 = 11 → 82 - 11 = 71
    @Test
    def testHitRateBasic(): Unit \ Assert =
        Assert.assertEq(expected = 71, Combat.hitRate(5, 4, 70, 4, 3))

    /// 命中が回避を大きく上回る → 上限 100% に張りつく
    /// 命中 = 100 + 10*2 + 0/2 = 120, 回避 = 0*2 + 0 = 0 → clamp(120) = 100
    @Test
    def testHitRateClampUpper(): Unit \ Assert =
        Assert.assertEq(expected = 100, Combat.hitRate(10, 0, 100, 0, 0))

    /// 回避が命中を上回る → 下限 0% に張りつく（負にならない）
    /// 命中 = 30 + 0*2 + 0/2 = 30, 回避 = 20*2 + 10 = 50 → clamp(-20) = 0
    @Test
    def testHitRateClampLower(): Unit \ Assert =
        Assert.assertEq(expected = 0, Combat.hitRate(0, 0, 30, 20, 10))

    // ════════════════════════════════════════════════════════
    // forecast: スペックの「与:N 命中:P% 撃破」が一発で出る
    // ════════════════════════════════════════════════════════

    /// knight (atk6, skill5, luck3, 武器命中70) → goblin (hp3, def1, spd4, luck1):
    /// 与 = 6-1 = 5
    /// 命中 = 70 + 5*2 + 3/2 = 81, 回避 = 4*2 + 1 = 9 → 81 - 9 = 72
    /// 残 HP 3-5 ≦ 0 → 撃破
    @Test
    def testForecastKnightVsGoblin(): Unit \ Assert =
        let f = Combat.forecast(
            {attack = 6, skill = 5, luck = 3, weaponHit = 70},
            {hp = 3, defense = 1, speed = 4, luck = 1});
        Assert.assertEq(expected = (5, 72, true), (f#damage, f#hit, f#kill))

    // ════════════════════════════════════════════════════════
    // attackStatFor / defenseStatFor: 物理/魔法のステ参照切替
    // ════════════════════════════════════════════════════════

    /// 物理武器 (isPhysical=true) → 攻撃側は `attack` を参照、`magicAttack` は無視
    /// (atk=7, mAtk=3, weapon=2) → 7+2 = 9
    @Test
    def testAttackStatForPhysical(): Unit \ Assert =
        Assert.assertEq(expected = 9, Combat.attackStatFor(7, 3, 2, true))

    /// 魔法武器 (isPhysical=false) → 攻撃側は `magicAttack` を参照、`attack` は無視
    /// (atk=7, mAtk=3, weapon=2) → 3+2 = 5
    @Test
    def testAttackStatForMagic(): Unit \ Assert =
        Assert.assertEq(expected = 5, Combat.attackStatFor(7, 3, 2, false))

    /// 物理武器 → 防御側は `defense` を参照
    /// (def=4, mDef=5) + 物理武器 → 4
    @Test
    def testDefenseStatForPhysical(): Unit \ Assert =
        Assert.assertEq(expected = 4, Combat.defenseStatFor(4, 5, true))

    /// 魔法武器 → 防御側は `magicDefense` を参照
    /// (def=4, mDef=5) + 魔法武器 → 5
    @Test
    def testDefenseStatForMagic(): Unit \ Assert =
        Assert.assertEq(expected = 5, Combat.defenseStatFor(4, 5, false))

    // ════════════════════════════════════════════════════════
    // heal: 過剰回復は max でクランプ、負の amount は無視（0 として扱う）
    // ════════════════════════════════════════════════════════

    /// 現 HP 5、max 10、回復 10 → 過剰分は捨てて HP = 10（上限クランプ）
    @Test
    def testHealClampsToMaxHp(): Unit \ Assert =
        let result = Combat.heal(5, 10, 10);
        Assert.assertEq(expected = 10, result#newHp)

    /// 現 HP 5、max 10、回復 0 → HP は変わらない（5）
    @Test
    def testHealZeroAmountKeepsHp(): Unit \ Assert =
        let result = Combat.heal(5, 10, 0);
        Assert.assertEq(expected = 5, result#newHp)

    /// 現 HP 5、max 10、回復 -3（負）→ ダメージ用途と分けるため負は無視。HP は変わらない（5）
    @Test
    def testHealNegativeAmountIgnored(): Unit \ Assert =
        let result = Combat.heal(5, 10, -3);
        Assert.assertEq(expected = 5, result#newHp)
}
