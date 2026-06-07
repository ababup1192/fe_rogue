/// UnitView のテスト — faction 非依存の攻撃可否 / 推定ダメージ述語
///
/// `canAttack`（射程内 + 防御側生存）と `estDamage`（`Combat.estimate` 委譲）を純粋値で検証する。
/// 散在していた join 述語の集約先。
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
    // projection: PlayerScene.unitView / EnemyScene.unitView の結線
    //   scene を介す `Encounter.fromScene` は TileMapLayer 構築が要る統合テストになるため
    //   （TestEnemyRangeScene の注記と同様、実機側に委ねる）、ここでは join の核である
    //   Data → UnitView の projection を直接検証する: faction / weaponRange / combat 結線 /
    //   hidden / isDying フラグ。
    // ════════════════════════════════════════════════════════

    /// 武器を持つ味方 Data。装備武器は `weapons` の先頭（剣・射程1-1・攻2）、防御 1（testResource）。
    def playerData(id: Int32, pos: {x = Int32, y = Int32}, hp: Int32, hidden: Bool,
                   weapons: List[UnitCatalog.WeaponResource]): PlayerScene.Data =
        {id = id, gridPos = pos, moveTiles = 4, hp = hp, waited = false,
         attackTargetId = None, resource = TestUnitFixtures.testResource(4, hp),
         weapons = weapons, staves = Nil, consumables = Nil, selectedItem = None,
         moveStepsTaken = 0, facing = Staff.Direction.Down, hidden = hidden,
         usedStairs = false, level = 1, exp = 0, pendingLevelUp = None}

    /// 敵 Data。装備武器は `weapon`（攻2・剣）、攻撃 3（testEnemyResource）。
    def enemyData(id: Int32, pos: {x = Int32, y = Int32}, hp: Int32, isDying: Bool,
                  weapon: Option[UnitCatalog.WeaponResource]): EnemyScene.Data =
        {id = id, gridPos = pos, alerted = false, homeModuleIdx = 0, moveTiles = 4,
         hp = hp, isDying = isDying, attackTargetId = None,
         resource = TestUnitFixtures.testEnemyResource(4, hp), weapon = weapon}

    /// 味方 projection: faction = Player、weaponRange = 装備武器(先頭)の射程、hidden を引き継ぐ。
    @Test
    def testPlayerUnitViewWiring(): Unit \ Assert =
        let v = PlayerScene.unitView(playerData(2, at(3, 4), 7, true,
                                                TestUnitFixtures.testWeapon() :: Nil));
        let rangeTuple = match v#weaponRange {
            case Some(r) => (true, r#min, r#max)
            case None    => (false, -1, -1)
        };
        Assert.assertEq(
            expected = (2, true, 3, 4, 7, true, (true, 1, 1)),
            (v#id, v#faction == Faction.Player, v#pos#x, v#pos#y, v#hp, v#hidden, rangeTuple))

    /// 武器なしの味方 projection: weaponRange = None（攻撃不能）。
    @Test
    def testPlayerUnitViewNoWeaponHasNoRange(): Unit \ Assert =
        let v = PlayerScene.unitView(playerData(0, at(0, 0), 10, false, Nil));
        let hasRange = match v#weaponRange {
            case Some(_) => true
            case None    => false
        };
        Assert.assertEq(expected = (true, false),
                          (v#faction == Faction.Player, hasRange))

    /// 敵 projection: faction = Enemy、weaponRange = 装備武器の射程、isDying を引き継ぐ。
    @Test
    def testEnemyUnitViewWiring(): Unit \ Assert =
        let v = EnemyScene.unitView(enemyData(9, at(5, 6), 3, true,
                                              Some(TestUnitFixtures.testWeapon())));
        let rangeTuple = match v#weaponRange {
            case Some(r) => (true, r#min, r#max)
            case None    => (false, -1, -1)
        };
        Assert.assertEq(
            expected = (9, true, 5, 6, 3, true, (true, 1, 1)),
            (v#id, v#faction == Faction.Enemy, v#pos#x, v#pos#y, v#hp, v#isDying, rangeTuple))

    /// combat 結線: 敵 (攻 3 + 武器 2 = 5) → 味方 (防 1) の推定ダメージは 4。
    /// projection が `combatView` を正しく埋めていることを estDamage 経由で確認する。
    @Test
    def testUnitViewCombatWiredThroughProjection(): Unit \ Assert =
        let enemyV  = EnemyScene.unitView(enemyData(9, at(0, 0), 5, false,
                                                    Some(TestUnitFixtures.testWeapon())));
        let playerV = PlayerScene.unitView(playerData(0, at(1, 0), 10, false,
                                                      TestUnitFixtures.testWeapon() :: Nil));
        Assert.assertEq(expected = 4, UnitView.estDamage(enemyV, playerV))
}
