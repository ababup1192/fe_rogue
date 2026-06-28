// 武器特殊効果（WeaponEffect）の純粋ロジック検証。
//
// アクセサ（braveThreshold 等）・背水の威力倍率（Combat.estimate 内）・
// はやぶさの 2 回攻撃条件（CombatRules.braveFollowUp）を数値だけで固定する。

mod TestWeaponEffect {

    use WeaponCatalog.WeaponEffect

    // ════════════════════════════════════════════════════════
    // アクセサ — effect / effectValue から各効果のパラメータを取り出す
    // ════════════════════════════════════════════════════════

    @Test
    def testBraveThreshold(): Unit \ Assert =
        Assert.assertEq(expected = (Some(3), None),
            (WeaponCatalog.braveThreshold(WeaponEffect.BraveOnSpeed, 3),
             WeaponCatalog.braveThreshold(WeaponEffect.NoEffect, 3)))

    @Test
    def testKnockbackTiles(): Unit \ Assert =
        Assert.assertEq(expected = (Some(2), None),
            (WeaponCatalog.knockbackTiles(WeaponEffect.Knockback, 2),
             WeaponCatalog.knockbackTiles(WeaponEffect.Lifesteal, 2)))

    @Test
    def testDesperationThreshold(): Unit \ Assert =
        Assert.assertEq(expected = (Some(30), None),
            (WeaponCatalog.desperationThreshold(WeaponEffect.Desperation, 30),
             WeaponCatalog.desperationThreshold(WeaponEffect.NoEffect, 30)))

    @Test
    def testLifestealPercent(): Unit \ Assert =
        Assert.assertEq(expected = (30, 0),
            (WeaponCatalog.lifestealPercent(WeaponEffect.Lifesteal, 30),
             WeaponCatalog.lifestealPercent(WeaponEffect.NoEffect, 30)))

    @Test
    def testThiefDropChance(): Unit \ Assert =
        Assert.assertEq(expected = (20, 0),
            (WeaponCatalog.thiefDropChance(WeaponEffect.ThiefDrop, 20),
             WeaponCatalog.thiefDropChance(WeaponEffect.Knockback, 20)))

    // ════════════════════════════════════════════════════════
    // parseEffect / effectToString — round-trip
    // ════════════════════════════════════════════════════════

    @Test
    def testEffectRoundTrip(): Unit \ Assert =
        use WeaponCatalog.WeaponEffect.{NoEffect, BraveOnSpeed, Knockback, Desperation, Lifesteal, ThiefDrop};
        let all = NoEffect :: BraveOnSpeed :: Knockback :: Desperation :: Lifesteal :: ThiefDrop :: Nil;
        Assert.assertEq(expected = all |> List.map(Ok),
            all |> List.map(e -> WeaponCatalog.parseEffect(WeaponCatalog.effectToString(e))))

    @Test
    def testParseEffectUnknown(): Unit \ Assert =
        Assert.assertEq(expected = Err("Nope"), WeaponCatalog.parseEffect("Nope"))

    // ════════════════════════════════════════════════════════
    // はやぶさ — braveFollowUp（速さ差 +d 以上で確定・二重追撃なし）
    // ════════════════════════════════════════════════════════

    /// 速さが相手 +3 以上ちょうど → 追撃する。
    @Test
    def testBraveTriggersAtThreshold(): Unit \ Assert =
        Assert.assertEq(expected = true,
            CombatRules.braveFollowUp(10, 7, false, Some(3)))

    /// 速さ差が +2 → 追撃しない。
    @Test
    def testBraveNotBelowThreshold(): Unit \ Assert =
        Assert.assertEq(expected = false,
            CombatRules.braveFollowUp(9, 7, false, Some(3)))

    /// すでにこの攻撃で追撃済み → 追撃しない（指輪追撃と併用しても二重追撃しない不変条件）。
    @Test
    def testBraveBlockedWhenAlreadyFollowedUp(): Unit \ Assert =
        Assert.assertEq(expected = false,
            CombatRules.braveFollowUp(10, 7, true, Some(3)))

    /// ブレイブ武器でない（None）→ 追撃しない。
    @Test
    def testBraveNoneNeverTriggers(): Unit \ Assert =
        Assert.assertEq(expected = false,
            CombatRules.braveFollowUp(99, 0, false, None))

    // ════════════════════════════════════════════════════════
    // 背水 — Combat.estimate 内の HP%しきい値で威力 1.5 倍（境界）
    // ════════════════════════════════════════════════════════

    /// Desperation(30) の槍を持つ攻撃側。素ダメージ 10 が、HP%しきい値で 15 になる。
    /// `maxHp = 100` 固定で hp を 29/30/31 と動かして境界（hp*100 <= maxHp*30）を確認する。
    def desperationDamage(hp: Int32): Int32 =
        let attacker: Combat.CombatView =
            {attack = 10, magicAttack = 0, defense = 0, magicDefense = 0,
             skill = 0, speed = 0, luck = 0, hp = hp, maxHp = 100, hitMod = 0,
             weapon = Some({weaponType = WeaponCatalog.WeaponType.Lance, attack = 0, hit = 100,
                            crit = 0, isPhysical = true, proficient = true,
                            effect = WeaponCatalog.WeaponEffect.Desperation, effectValue = 30})};
        let defender: Combat.CombatView =
            {attack = 0, magicAttack = 0, defense = 0, magicDefense = 0,
             skill = 0, speed = 0, luck = 0, hp = 99, maxHp = 99, hitMod = 0, weapon = None};
        Combat.estimate(attacker, defender)#damage

    /// hp=29（< 30%）→ 1.5 倍（10→15）。hp=30（= 30%ちょうど）→ 発動（15）。hp=31（> 30%）→ 不発（10）。
    @Test
    def testDesperationBoundary(): Unit \ Assert =
        Assert.assertEq(expected = (15, 15, 10),
            (desperationDamage(29), desperationDamage(30), desperationDamage(31)))

    /// 効果なし武器は HP が低くても倍率なし（素ダメージ 10 のまま）。
    @Test
    def testNoEffectWeaponNoBoost(): Unit \ Assert =
        let attacker: Combat.CombatView =
            {attack = 10, magicAttack = 0, defense = 0, magicDefense = 0,
             skill = 0, speed = 0, luck = 0, hp = 1, maxHp = 100, hitMod = 0,
             weapon = Some({weaponType = WeaponCatalog.WeaponType.Lance, attack = 0, hit = 100,
                            crit = 0, isPhysical = true, proficient = true,
                            effect = WeaponCatalog.WeaponEffect.NoEffect, effectValue = 0})};
        let defender: Combat.CombatView =
            {attack = 0, magicAttack = 0, defense = 0, magicDefense = 0,
             skill = 0, speed = 0, luck = 0, hp = 99, maxHp = 99, hitMod = 0, weapon = None};
        Assert.assertEq(expected = 10, Combat.estimate(attacker, defender)#damage)
}
