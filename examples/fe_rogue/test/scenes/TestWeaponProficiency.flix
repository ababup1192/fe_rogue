/// 武器タイプ習熟（得意/苦手）の固定テスト。
///
/// 観点:
///   - 苦手武器は威力・命中が 80%（整数 ×4/5、切り捨て）に下がり、得意は据え置き
///   - units.json の習熟設定（ロード職種=全タイプ得意、他職種=初期装備タイプ）が読めている
///   - 戦闘予報（estimate）にも 80% 補正が効く
mod TestWeaponProficiency {

    use WeaponCatalog.WeaponType

    // ════════════════════════════════════════════════════════
    // proficiencyAdjust: 苦手 80% / 得意 据え置き
    // ════════════════════════════════════════════════════════

    /// 得意（proficient=true）なら威力・命中はそのまま。
    @Test
    def testProficiencyAdjustKeepsWhenProficient(): Unit \ Assert =
        Assert.assertEq(expected = (10, 90), Combat.proficiencyAdjust(10, 90, true))

    /// 苦手（proficient=false）なら威力・命中が 80%（10→8, 90→72）。
    @Test
    def testProficiencyAdjustReducesWhenNotProficient(): Unit \ Assert =
        Assert.assertEq(expected = (8, 72), Combat.proficiencyAdjust(10, 90, false))

    // ════════════════════════════════════════════════════════
    // units.json の習熟設定
    // ════════════════════════════════════════════════════════

    /// 本番 units.json をロードして職種ごとの得意武器を確認する。
    def loadCatalog(): UnitCatalog.UnitCatalog \ Fs.FileRead =
        let weaponCatalog = WeaponCatalog.load();
        UnitCatalog.load("resources/units.json", weaponCatalog)

    def unitNamed(id: String, catalog: UnitCatalog.UnitCatalog): UnitCatalog.PlayerResource =
        match List.find(u -> u#description == id, UnitCatalog.pool("players", catalog)) {
            case Some(u) => u
            case None    => bug!("unit with description '${id}' not found")
        }

    /// ロード職種（description="ロード"）は全タイプ得意。剣も魔法も true。
    @Test
    def testLordIsProficientWithAllTypes(): Unit \ {Assert, Fs.FileRead} =
        let lord = unitNamed("ロード", loadCatalog());
        Assert.assertEq(
            expected = (true, true),
            (UnitCatalog.proficientWith(lord, WeaponType.Sword),
             UnitCatalog.proficientWith(lord, WeaponType.Magic)))

    /// メイジは初期装備が魔法なので Magic 得意・Sword 苦手。
    @Test
    def testMageProficientWithMagicOnly(): Unit \ {Assert, Fs.FileRead} =
        let mage = unitNamed("メイジ", loadCatalog());
        Assert.assertEq(
            expected = (true, false),
            (UnitCatalog.proficientWith(mage, WeaponType.Magic),
             UnitCatalog.proficientWith(mage, WeaponType.Sword)))

    /// ファイターは初期装備が剣・斧なので両方得意、槍は苦手。
    @Test
    def testFighterProficientWithSwordAndAxe(): Unit \ {Assert, Fs.FileRead} =
        let fighter = unitNamed("ファイター", loadCatalog());
        Assert.assertEq(
            expected = (true, true, false),
            (UnitCatalog.proficientWith(fighter, WeaponType.Sword),
             UnitCatalog.proficientWith(fighter, WeaponType.Axe),
             UnitCatalog.proficientWith(fighter, WeaponType.Lance)))

    // ════════════════════════════════════════════════════════
    // estimate（戦闘予報）への反映
    // ════════════════════════════════════════════════════════

    /// 攻撃側の武器が苦手だと、予報の威力・命中が 80% に下がる。
    /// 力10・武器威力0・命中90・相手防御0/回避0 → 得意 (10,90) / 苦手 (8,72)。
    @Test
    def testEstimateAppliesProficiencyPenalty(): Unit \ Assert =
        let defender: Combat.CombatView =
            {attack = 0, magicAttack = 0, defense = 0, magicDefense = 0,
             skill = 0, speed = 0, luck = 0, hp = 99, weapon = None, hitMod = 0};
        let attackerWith = proficient ->
            ({attack = 10, magicAttack = 0, defense = 0, magicDefense = 0,
              skill = 0, speed = 0, luck = 0, hp = 10,
              weapon = Some({weaponType = WeaponType.Sword, attack = 0, hit = 90,
                             crit = 0, isPhysical = true, proficient = proficient}), hitMod = 0}: Combat.CombatView);
        let good = Combat.estimate(attackerWith(true), defender);
        let weak = Combat.estimate(attackerWith(false), defender);
        Assert.assertEq(
            expected = ((10, 90), (8, 72)),
            ((good#damage, good#hit), (weak#damage, weak#hit)))
}
