/// UnitView のテスト — faction 非依存の攻撃可否 / 推定ダメージ述語
///
/// `canAttack`（射程内 + 防御側生存）と `estDamage`（`Combat.estimate` 委譲）、
/// `isEnemyOf`（faction 異同）を純粋値で検証する。散在していた join 述語の集約先。
mod TestUnitView {

    use WeaponCatalog.WeaponType

    /// 武器なしの戦闘ビュー（canAttack のように combat を見ない経路用）。
    def noCombat(): Combat.CombatView =
        {attack = 0, magicAttack = 0, defense = 0, magicDefense = 0,
         skill = 0, speed = 0, luck = 0, hp = 0, weapon = None}

    /// 射程・位置・生存だけ指定して UnitView を組む（combat は空＝canAttack 用）。
    def mkUnit(id: Int32, faction: Faction, pos: {x = Int32, y = Int32}, hp: Int32,
               isDying: Bool, range: Option[{min = Int32, max = Int32}]): UnitView =
        {id = id, faction = faction, pos = pos, hp = hp, moveTiles = 4,
         weaponRange = range, combat = noCombat(), isDying = isDying, hidden = false}

    def at(x: Int32, y: Int32): {x = Int32, y = Int32} = {x = x, y = y}

    // ════════════════════════════════════════════════════════
    // canAttack: 攻撃側射程内 + 防御側生存
    // ════════════════════════════════════════════════════════

    /// 射程 {1,1} の近接が距離 1 の生存相手に届く → true
    @Test
    def testCanAttackInRange(): Unit \ Assert =
        let attacker = mkUnit(0, Faction.Enemy, at(0, 0), 10, false, Some({min = 1, max = 1}));
        let defender = mkUnit(1, Faction.Player, at(1, 0), 5, false, None);
        Assert.assertEq(expected = true, UnitView.canAttack(attacker, defender))

    /// 射程 {1,1} で距離 2 は届かない → false
    @Test
    def testCanAttackOutOfRange(): Unit \ Assert =
        let attacker = mkUnit(0, Faction.Enemy, at(0, 0), 10, false, Some({min = 1, max = 1}));
        let defender = mkUnit(1, Faction.Player, at(2, 0), 5, false, None);
        Assert.assertEq(expected = false, UnitView.canAttack(attacker, defender))

    /// 武器なし（weaponRange None）は届かない → false
    @Test
    def testCanAttackNoWeapon(): Unit \ Assert =
        let attacker = mkUnit(0, Faction.Enemy, at(0, 0), 10, false, None);
        let defender = mkUnit(1, Faction.Player, at(1, 0), 5, false, None);
        Assert.assertEq(expected = false, UnitView.canAttack(attacker, defender))

    /// 防御側が HP 0 → 攻撃対象にならない → false
    @Test
    def testCanAttackDeadDefender(): Unit \ Assert =
        let attacker = mkUnit(0, Faction.Enemy, at(0, 0), 10, false, Some({min = 1, max = 1}));
        let defender = mkUnit(1, Faction.Player, at(1, 0), 0, false, None);
        Assert.assertEq(expected = false, UnitView.canAttack(attacker, defender))

    /// 防御側が死亡演出中（isDying）→ false
    @Test
    def testCanAttackDyingDefender(): Unit \ Assert =
        let attacker = mkUnit(0, Faction.Player, at(0, 0), 10, false, Some({min = 1, max = 2}));
        let defender = mkUnit(1, Faction.Enemy, at(2, 0), 5, true, None);
        Assert.assertEq(expected = false, UnitView.canAttack(attacker, defender))

    // ════════════════════════════════════════════════════════
    // estDamage: Combat.estimate#damage の委譲
    // ════════════════════════════════════════════════════════

    /// 剣(atk4 + 武器2 = 6) → 防御 def1 → 与 5（Combat.estimate と同値）
    @Test
    def testEstDamageDelegatesToCombat(): Unit \ Assert =
        let atkCombat: Combat.CombatView =
            {attack = 4, magicAttack = 0, defense = 0, magicDefense = 0,
             skill = 0, speed = 0, luck = 0, hp = 10,
             weapon = Some({weaponType = WeaponType.Sword, attack = 2, hit = 70, isPhysical = true})};
        let defCombat: Combat.CombatView =
            {attack = 0, magicAttack = 0, defense = 1, magicDefense = 9,
             skill = 0, speed = 0, luck = 0, hp = 3, weapon = None};
        let attacker = {combat = atkCombat | mkUnit(0, Faction.Enemy, at(0, 0), 10, false, Some({min = 1, max = 1}))};
        let defender = {combat = defCombat | mkUnit(1, Faction.Player, at(1, 0), 3, false, None)};
        Assert.assertEq(expected = 5, UnitView.estDamage(attacker, defender))

    // ════════════════════════════════════════════════════════
    // isEnemyOf: faction 異同
    // ════════════════════════════════════════════════════════

    /// Player と Enemy は交戦相手 → true、同 faction 同士 → false
    @Test
    def testIsEnemyOf(): Unit \ Assert =
        let p = mkUnit(0, Faction.Player, at(0, 0), 10, false, None);
        let e = mkUnit(1, Faction.Enemy, at(1, 0), 10, false, None);
        let p2 = mkUnit(2, Faction.Player, at(2, 0), 10, false, None);
        Assert.assertEq(expected = (true, false),
                          (UnitView.isEnemyOf(p, e), UnitView.isEnemyOf(p, p2)))
}
