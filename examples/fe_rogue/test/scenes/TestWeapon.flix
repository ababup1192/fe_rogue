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
        // 耐久 5 を 1 回使うと Some(耐久 4) が残る（壊れず Some のまま）
        Assert.assertEq(expected = Some(4), Weapon.consume(weapon) |> Option.map(w -> w#durability))

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
        // 武器相性は本テストの対象外なので中立（補正なし）で計算する
        let dmg = Combat.attackDamage(totalAttack, 1, WeaponTriangle.Relation.Neutral);
        Assert.assertEq(expected = 7, dmg)

    /// 力 1 + 武器 1 - 防御 5 = 0 ダメージ（max(0, ...) で下限 0 にクランプ）
    @Test
    def testTotalAttackClampedAtZero(): Unit \ Assert =
        let unit   = TestUnitFixtures.testResourceFull(4, 14, 1, 5, 2);
        let weapon = TestUnitFixtures.testWeaponFull(1, 41);
        let totalAttack = unit#attack + weapon#attack;
        // 武器相性は本テストの対象外なので中立（補正なし）で計算する
        let dmg = Combat.attackDamage(totalAttack, 5, WeaponTriangle.Relation.Neutral);
        Assert.assertEq(expected = 0, dmg)

    // ════════════════════════════════════════════════════════
    // Weapon.manhattan / Weapon.canReach — 反撃の射程判定
    // ════════════════════════════════════════════════════════

    /// 隣接 (距離 1) の剣 {min:1, max:1} は届く
    @Test
    def testCanReachAdjacentSword(): Unit \ Assert =
        let sword: UnitCatalog.WeaponResource =
            {name = "sword", attack = 1, hit = 80, crit = 0, durability = 10,
             range = {min = 1, max = 1}, weaponType = WeaponCatalog.WeaponType.Sword,
             sprite = {texture = "t", hframes = 1, vframes = 1, frame = 0, offset = {x = 0.0, y = 0.0}, scale = {x = 1.0, y = 1.0}, flipForFacing = false}, description = ""};
        Assert.assertEq(expected = true, Weapon.canReach(1, sword))

    /// 隣接 (距離 1) を弓 {min:2, max:2} は届かない → 反撃不可ケース
    @Test
    def testCanReachBowCannotCounterAdjacent(): Unit \ Assert =
        let bow: UnitCatalog.WeaponResource =
            {name = "bow", attack = 1, hit = 80, crit = 0, durability = 10,
             range = {min = 2, max = 2}, weaponType = WeaponCatalog.WeaponType.Bow,
             sprite = {texture = "t", hframes = 1, vframes = 1, frame = 0, offset = {x = 0.0, y = 0.0}, scale = {x = 1.0, y = 1.0}, flipForFacing = false}, description = ""};
        Assert.assertEq(expected = false, Weapon.canReach(1, bow))

    /// 距離 1 の剣 {min:1, max:1} は 2 マス先には届かない (= 弓に反撃できない)
    @Test
    def testCanReachSwordCannotCounterBow(): Unit \ Assert =
        let sword: UnitCatalog.WeaponResource =
            {name = "sword", attack = 1, hit = 80, crit = 0, durability = 10,
             range = {min = 1, max = 1}, weaponType = WeaponCatalog.WeaponType.Sword,
             sprite = {texture = "t", hframes = 1, vframes = 1, frame = 0, offset = {x = 0.0, y = 0.0}, scale = {x = 1.0, y = 1.0}, flipForFacing = false}, description = ""};
        Assert.assertEq(expected = false, Weapon.canReach(2, sword))

    /// 手槍 {min:1, max:2} は隣接にも 2 マス先にも届く
    @Test
    def testCanReachJavelinBoth(): Unit \ Assert =
        let javelin: UnitCatalog.WeaponResource =
            {name = "javelin", attack = 1, hit = 80, crit = 0, durability = 10,
             range = {min = 1, max = 2}, weaponType = WeaponCatalog.WeaponType.Lance,
             sprite = {texture = "t", hframes = 1, vframes = 1, frame = 0, offset = {x = 0.0, y = 0.0}, scale = {x = 1.0, y = 1.0}, flipForFacing = false}, description = ""};
        Assert.assertEq(expected = (true, true, false),
                        (Weapon.canReach(1, javelin),
                         Weapon.canReach(2, javelin),
                         Weapon.canReach(3, javelin)))

    /// 斜め (1,1) のマンハッタン距離は 2
    @Test
    def testManhattanDiagonal(): Unit \ Assert =
        let a = {x = 0, y = 0};
        let b = {x = 1, y = 1};
        Assert.assertEq(expected = 2, Weapon.manhattan(a, b))

    /// 同セルは距離 0
    @Test
    def testManhattanSameCell(): Unit \ Assert =
        let a = {x = 3, y = 5};
        Assert.assertEq(expected = 0, Weapon.manhattan(a, a))

    // ════════════════════════════════════════════════════════
    // 魔法武器の総合攻撃力（attackStatFor / defenseStatFor 経由）
    // ════════════════════════════════════════════════════════

    /// 魔力 8 + 武器 2 - 魔防 3 = 7 ダメージ（魔法武器ルート）
    /// PlayerScene / EnemyScene の attackStatFor + defenseStatFor + attackDamage の流れを再現
    @Test
    def testMagicWeaponDamageUsesMagicStats(): Unit \ Assert =
        let unit   = TestUnitFixtures.testResourceMagic(4, 14, 2, 1, 8, 4, 3);
        let target = TestUnitFixtures.testResourceMagic(4, 14, 6, 5, 1, 3, 2);
        let weapon = TestUnitFixtures.testWeaponWithType(2, WeaponCatalog.WeaponType.Magic);
        let phys   = UnitCatalog.isPhysical(weapon#weaponType);
        let totalAttack = Combat.attackStatFor(unit#attack, unit#magicAttack,
                                                weapon#attack, phys);
        let targetDef   = Combat.defenseStatFor(target#defense, target#magicDefense, phys);
        // 武器相性は本テストの対象外なので中立（補正なし）で計算する
        let dmg = Combat.attackDamage(totalAttack, targetDef, WeaponTriangle.Relation.Neutral);
        Assert.assertEq(expected = 7, dmg)

    /// 物理武器なら魔力・魔防は完全に無視される
    /// (atk=2, mAtk=8) × 物理武器 weapon=3 → 2+3=5 vs (def=4, mDef=0) → 5-4=1
    @Test
    def testPhysicalWeaponIgnoresMagicStats(): Unit \ Assert =
        let unit   = TestUnitFixtures.testResourceMagic(4, 14, 2, 1, 8, 4, 3);
        let target = TestUnitFixtures.testResourceMagic(4, 14, 6, 4, 1, 0, 2);
        let weapon = TestUnitFixtures.testWeaponWithType(3, WeaponCatalog.WeaponType.Sword);
        let phys   = UnitCatalog.isPhysical(weapon#weaponType);
        let totalAttack = Combat.attackStatFor(unit#attack, unit#magicAttack,
                                                weapon#attack, phys);
        let targetDef   = Combat.defenseStatFor(target#defense, target#magicDefense, phys);
        // 武器相性は本テストの対象外なので中立（補正なし）で計算する
        let dmg = Combat.attackDamage(totalAttack, targetDef, WeaponTriangle.Relation.Neutral);
        Assert.assertEq(expected = 1, dmg)
}
