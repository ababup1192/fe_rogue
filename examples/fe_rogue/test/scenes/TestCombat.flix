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

    use WeaponCatalog.WeaponType
    use WeaponTriangle.Relation

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
    // attackDamage: max(0, attack + 相性補正 - defense)
    //   ここでは武器相性の影響を切り離すため中立（補正 0）で確認する。
    //   相性補正ありのケースは後段「武器相性の補正」セクション参照。
    // ════════════════════════════════════════════════════════

    /// 攻撃 6 vs 防御 1（中立）→ 5 ダメージ
    @Test
    def testAttackDamageNormal(): Unit \ Assert =
        Assert.assertEq(expected = 5,
                          Combat.attackDamage(6, 1, WeaponTriangle.Relation.Neutral))

    /// 攻撃 = 防御（中立）→ 0 ダメージ（弱攻撃が硬い相手に通らない）
    @Test
    def testAttackDamageEqualIsZero(): Unit \ Assert =
        Assert.assertEq(expected = 0,
                          Combat.attackDamage(3, 3, WeaponTriangle.Relation.Neutral))

    /// 攻撃 < 防御（中立）でも下限 0（負ダメは出ない）
    @Test
    def testAttackDamageDefenseHigherIsZero(): Unit \ Assert =
        Assert.assertEq(expected = 0,
                          Combat.attackDamage(2, 5, WeaponTriangle.Relation.Neutral))

    // ════════════════════════════════════════════════════════
    // hitRate: clamp(0, 100, 命中 - 回避)
    //   命中 = 武器命中 + 技×2 + 幸運÷2 + 相性補正
    //   回避 = 速さ×2 + 幸運
    //   引数: (attackerSkill, attackerLuck, weaponHit, defenderSpeed, defenderLuck, 相性)
    //   ここでは相性補正の影響を切り離すため中立（補正 0）で確認する。
    // ════════════════════════════════════════════════════════

    /// 技5 幸運4 武器命中70 / 防御 速さ4 幸運3（中立）:
    /// 命中 = 70 + 5*2 + 4/2 = 82, 回避 = 4*2 + 3 = 11 → 82 - 11 = 71
    @Test
    def testHitRateBasic(): Unit \ Assert =
        Assert.assertEq(expected = 71,
                          Combat.hitRate(5, 4, 70, 4, 3, WeaponTriangle.Relation.Neutral))

    /// 命中が回避を大きく上回る → 上限 100% に張りつく
    /// 命中 = 100 + 10*2 + 0/2 = 120, 回避 = 0*2 + 0 = 0 → clamp(120) = 100
    @Test
    def testHitRateClampUpper(): Unit \ Assert =
        Assert.assertEq(expected = 100,
                          Combat.hitRate(10, 0, 100, 0, 0, WeaponTriangle.Relation.Neutral))

    /// 回避が命中を上回る → 下限 0% に張りつく（負にならない）
    /// 命中 = 30 + 0*2 + 0/2 = 30, 回避 = 20*2 + 10 = 50 → clamp(-20) = 0
    @Test
    def testHitRateClampLower(): Unit \ Assert =
        Assert.assertEq(expected = 0,
                          Combat.hitRate(0, 0, 30, 20, 10, WeaponTriangle.Relation.Neutral))

    // ════════════════════════════════════════════════════════
    // isHit: roll < hitRate で命中
    // ════════════════════════════════════════════════════════

    /// roll(40) < hitRate(70) → 命中
    @Test
    def testIsHitRollBelowRateHits(): Unit \ Assert =
        Assert.assertEq(expected = true, Combat.isHit(70, 40))

    /// roll(70) == hitRate(70) → 外れ（境界。roll は 0..99 なので 100% で必中になる）
    @Test
    def testIsHitRollEqualRateMisses(): Unit \ Assert =
        Assert.assertEq(expected = false, Combat.isHit(70, 70))

    /// hitRate(100) は roll が最大(99)でも命中（必中）
    @Test
    def testIsHitFullRateAlwaysHits(): Unit \ Assert =
        Assert.assertEq(expected = true, Combat.isHit(100, 99))

    /// hitRate(0) は roll が最小(0)でも外れる（必中失敗）
    @Test
    def testIsHitZeroRateAlwaysMisses(): Unit \ Assert =
        Assert.assertEq(expected = false, Combat.isHit(0, 0))

    // ════════════════════════════════════════════════════════
    // forecast: スペックの「与:N 命中:P% 撃破」が一発で出る
    // ════════════════════════════════════════════════════════

    /// knight (atk6, skill5, luck3, 武器命中70) → goblin (hp3, def1, spd4, luck1)、相性中立:
    /// 与 = 6-1 = 5
    /// 命中 = 70 + 5*2 + 3/2 = 81, 回避 = 4*2 + 1 = 9 → 81 - 9 = 72
    /// 残 HP 3-5 ≦ 0 → 撃破
    @Test
    def testForecastKnightVsGoblin(): Unit \ Assert =
        let f = Combat.forecast(
            {attack = 6, skill = 5, luck = 3, weaponHit = 70},
            {hp = 3, defense = 1, speed = 4, luck = 1},
            WeaponTriangle.Relation.Neutral);
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

    // ════════════════════════════════════════════════════════
    // WeaponTriangle.relation: 三竦み（剣 → 斧 → 槍 → 剣）
    //   各矢印が「有利」方向。剣は斧に、斧は槍に、槍は剣に有利。
    //   同種同士は中立。弓・魔法は三竦みの外で常に中立。
    //   剣・斧・槍の 3×3 = 9 組合せを起点ごと（剣 / 斧 / 槍）に 1 行ずつ確認する。
    // ════════════════════════════════════════════════════════

    /// 剣を起点にした 1 行: 剣同士は中立、剣→斧は有利、剣→槍は不利
    @Test
    def testRelationFromSword(): Unit \ Assert =
        Assert.assertEq(
            expected = (Relation.Neutral, Relation.Advantage, Relation.Disadvantage),
            (WeaponTriangle.relation(WeaponType.Sword, WeaponType.Sword),
             WeaponTriangle.relation(WeaponType.Sword, WeaponType.Axe),
             WeaponTriangle.relation(WeaponType.Sword, WeaponType.Lance)))

    /// 斧を起点にした 1 行: 斧→剣は不利、斧同士は中立、斧→槍は有利
    @Test
    def testRelationFromAxe(): Unit \ Assert =
        Assert.assertEq(
            expected = (Relation.Disadvantage, Relation.Neutral, Relation.Advantage),
            (WeaponTriangle.relation(WeaponType.Axe, WeaponType.Sword),
             WeaponTriangle.relation(WeaponType.Axe, WeaponType.Axe),
             WeaponTriangle.relation(WeaponType.Axe, WeaponType.Lance)))

    /// 槍を起点にした 1 行: 槍→剣は有利、槍→斧は不利、槍同士は中立
    @Test
    def testRelationFromLance(): Unit \ Assert =
        Assert.assertEq(
            expected = (Relation.Advantage, Relation.Disadvantage, Relation.Neutral),
            (WeaponTriangle.relation(WeaponType.Lance, WeaponType.Sword),
             WeaponTriangle.relation(WeaponType.Lance, WeaponType.Axe),
             WeaponTriangle.relation(WeaponType.Lance, WeaponType.Lance)))

    /// 弓・魔法は三竦みの外で常に中立（攻撃側でも防御側でも補正は付かない）
    /// 弓→剣 / 剣→弓 / 魔法→斧 / 槍→魔法 / 弓→魔法 のいずれも中立
    @Test
    def testRelationBowAndMagicAlwaysNeutral(): Unit \ Assert =
        Assert.assertEq(
            expected = (Relation.Neutral, Relation.Neutral, Relation.Neutral,
                        Relation.Neutral, Relation.Neutral),
            (WeaponTriangle.relation(WeaponType.Bow, WeaponType.Sword),
             WeaponTriangle.relation(WeaponType.Sword, WeaponType.Bow),
             WeaponTriangle.relation(WeaponType.Magic, WeaponType.Axe),
             WeaponTriangle.relation(WeaponType.Lance, WeaponType.Magic),
             WeaponTriangle.relation(WeaponType.Bow, WeaponType.Magic)))

    /// relationOpt: 防御側が未装備（None）なら中立、武器があれば relation と同じ
    /// （剣 vs 斧 → 有利）
    @Test
    def testRelationOptHandlesMissingWeapon(): Unit \ Assert =
        Assert.assertEq(
            expected = (Relation.Neutral, Relation.Advantage),
            (WeaponTriangle.relationOpt(WeaponType.Sword, None),
             WeaponTriangle.relationOpt(WeaponType.Sword, Some(WeaponType.Axe))))

    // ════════════════════════════════════════════════════════
    // 武器相性の補正: 有利 +攻1 / +命15、不利 -攻1 / -命15、中立 0
    //   中立のときの素の値は前段の attackDamage / hitRate / forecast で確認済み。
    //   ここでは相性で値がどれだけ動くかだけを確認する。
    // ════════════════════════════════════════════════════════

    /// 攻撃 6 vs 防御 1: 有利なら +1 で 6、不利なら -1 で 4（中立の 5 を基準に ±1）
    @Test
    def testAttackDamageWeaponTriangleBonus(): Unit \ Assert =
        Assert.assertEq(
            expected = (6, 4),
            (Combat.attackDamage(6, 1, Relation.Advantage),
             Combat.attackDamage(6, 1, Relation.Disadvantage)))

    /// 命中: 技5 幸運4 武器命中70 / 速さ4 幸運3（中立で 71）に対し、
    /// 有利は +15 で 86、不利は -15 で 56
    @Test
    def testHitRateWeaponTriangleBonus(): Unit \ Assert =
        Assert.assertEq(
            expected = (86, 56),
            (Combat.hitRate(5, 4, 70, 4, 3, Relation.Advantage),
             Combat.hitRate(5, 4, 70, 4, 3, Relation.Disadvantage)))

    /// 受け入れ条件: 剣 vs 斧 で剣側が有利。knight(剣) → goblin(斧) の予報で
    /// 与 = 6+1-1 = 6（攻 +1）、命中 = 70+10+1+15-9 = 87（命中 +15）、撃破。
    /// 相性は relation(Sword, Axe) = Advantage を forecast に渡して再現する。
    @Test
    def testForecastSwordVsAxeGetsAdvantage(): Unit \ Assert =
        let rel = WeaponTriangle.relation(WeaponType.Sword, WeaponType.Axe);
        let f = Combat.forecast(
            {attack = 6, skill = 5, luck = 3, weaponHit = 70},
            {hp = 3, defense = 1, speed = 4, luck = 1},
            rel);
        Assert.assertEq(expected = (6, 87, true), (f#damage, f#hit, f#kill))

    // ════════════════════════════════════════════════════════
    // EXP 獲得（FE7 流のレベル差ベース）
    //   定数: クラスの強さ=3 / 基準値=31 / 撃破固定=20。Int32 除算は 0 方向に切り捨て。
    //   戦闘EXP hitExp = max(1, (31 + 敵Lv − 自Lv) / 3)
    //   撃破EXP killExp = max(0, 3×(敵Lv − 自Lv) + 20)
    //   1攻撃   battleExp = hitExp + (撃破なら killExp)
    // ════════════════════════════════════════════════════════

    /// 同レベルなら戦闘EXPは基準値どおり: (31 + 0) / 3 = 10
    @Test
    def testHitExpEqualLevels(): Unit \ Assert =
        Assert.assertEq(expected = 10, Combat.hitExp(5, 5))

    /// 自分が遥かに高レベルでも下限 1 にクランプ。
    /// (31 + 2 − 39) / 3 = (−6) / 3 = −2 → max(1, −2) = 1（負の切り捨ても確認）
    @Test
    def testHitExpFarBelowFloorsAtOne(): Unit \ Assert =
        Assert.assertEq(expected = 1, Combat.hitExp(2, 39))

    /// 敵が自分より高レベルだと戦闘EXPが増える: (31 + 8 − 2) / 3 = 37 / 3 = 12（切り捨て）
    @Test
    def testHitExpHigherEnemyGivesMore(): Unit \ Assert =
        Assert.assertEq(expected = 12, Combat.hitExp(8, 2))

    /// 同レベル撃破の上乗せは固定値どおり: max(0, 3×0 + 20) = 20
    @Test
    def testKillExpEqualLevels(): Unit \ Assert =
        Assert.assertEq(expected = 20, Combat.killExp(5, 5))

    /// 敵が高レベルなら撃破EXPも増える: max(0, 3×(10 − 5) + 20) = max(0, 35) = 35
    @Test
    def testKillExpHigherEnemyAddsBonus(): Unit \ Assert =
        Assert.assertEq(expected = 35, Combat.killExp(10, 5))

    /// 自分より十分弱い敵の撃破は 0 にクランプ: max(0, 3×(0 − 10) + 20) = max(0, −10) = 0
    @Test
    def testKillExpFarBelowEnemyFloorsAtZero(): Unit \ Assert =
        Assert.assertEq(expected = 0, Combat.killExp(0, 10))

    /// 未撃破（killed=false）は戦闘EXPのみ: battleExp(5,5,false) = hitExp(5,5) = 10
    @Test
    def testBattleExpHitOnlyEqualsHitExp(): Unit \ Assert =
        Assert.assertEq(expected = 10, Combat.battleExp(5, 5, false))

    /// 撃破（killed=true）は戦闘EXP + 撃破EXP: battleExp(5,5,true) = 10 + 20 = 30
    @Test
    def testBattleExpKillAddsKillExp(): Unit \ Assert =
        Assert.assertEq(expected = 30, Combat.battleExp(5, 5, true))
}
