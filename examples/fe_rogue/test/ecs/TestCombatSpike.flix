// TestCombatSpike — SPIKE 検証（throwaway）。
//
// Phase C の resolveCombat モデル「sim を解いて (World, [SimEvent]) を返す」が、既存土台
// （combatViewOf / CombatRules / RngDraw / SimEvent / applyEventToWorld）だけで player 攻撃 1 本を
// 解けることを示す。命中ロールは withMockRandom（RngDraw=50）で決定的。
//
// 検証する観点:
//   (1) 撃破→exp: events=[Damaged, Dying, ExpGained]、enemy hp=0、player exp 増（World だけから解ける）。
//   (2) 撃破→level-up: events=[Damaged, Dying, LeveledUp]、player level+1・hp 成長。
//       ★この経路は atkResource(growthRates) を要する＝**World に growthRates が無い gap** を spike が露出。
mod TestCombatSpike {

    /// 攻撃対象 enemy=1 を抱えた player。`hit`/`exp` を作り分ける。攻撃力 素3+武器2=5。
    def playerData(hit: Int32, exp: Int32, res: UnitCatalog.UnitResource): PlayerScene.Data = {
        id                = 0,
        classId           = "test_player",
        gridPos           = {x = 2, y = 2},
        moveTiles         = 4,
        hp                = 10,
        waited            = false,
        attackTargetId    = Some(1),
        resource          = res,
        weapons           = ({hit = hit | TestUnitFixtures.testWeapon()}: UnitCatalog.WeaponResource) :: Nil,
        staves            = Nil,
        consumables       = Nil,
        selectedItem      = None,
        moveStepsTaken    = 0,
        facing            = Staff.Direction.Down,
        hidden            = false,
        usedStairs        = false,
        level             = 1,
        exp               = exp,
        pendingLevelUp    = None,
        statuses          = Nil,
        rings             = Nil,
        ringEquipped      = false,
        followUpUsed      = false
    }

    /// hp=4 の敵（player の 5−1=4 ダメージでちょうど newHp=0 → 撃破。overkill 負値を避け clean kill にする）。
    def enemyData(): EnemyScene.Data = {
        id             = 1,
        resourceId     = "test_enemy",
        gridPos        = {x = 3, y = 2},
        alerted        = false,
        homeModuleIdx  = 0,
        moveTiles      = 3,
        hp             = 4,
        isDying        = false,
        attackTargetId = None,
        resource       = TestUnitFixtures.testEnemyResource(3, 10),
        weapon         = Some(TestUnitFixtures.testWeapon()),
        acted          = false,
        prevPos        = None,
        statuses       = Nil,
        ring           = None,
        followUpUsed   = false,
        bottleUsed     = false
    }

    def scene(p: PlayerScene.Data): Scene[NodeTag] =
        let world = Marker2D.make(Vec2.zero()) |> CanvasItem.setYSortEnabled(true);
        Scene.empty()
            |> Scene.addNode(MapScene.worldName(),
                EngineNode.Marker2DWithState(world, NodeTag.NoTag))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(0),
                EngineNode.Marker2DWithState(Marker2D.make(Vec2.zero()), NodeTag.Player(p)))
            |> Scene.addChildAt(MapScene.worldPath(), EnemyScene.enemyName(1),
                EngineNode.Marker2DWithState(Marker2D.make(Vec2.zero()), NodeTag.Enemy(enemyData())))

    /// (1) 撃破→exp（レベルアップ無し）: resolveAttack が World だけから解き、enemy hp=0・player exp 増・
    /// events 3 件（Damaged/Dying/ExpGained）を返す。命中ロール=50 < 命中率77 で命中。
    @Test
    def testSpikeResolveKill(): Unit \ Assert =
        let res = TestUnitFixtures.testResource(4, 10);
        let w0  = World.syncFromScene(scene(playerData(80, 0, res)), World.empty());
        let (w1, events) = TestUnitFixtures.withMockRandom(() ->
            CombatSpike.resolveAttack(w0, World.EntityRef.Player(0), World.EntityRef.Enemy(1), 1, 1));
        let expectedExp = LevelSystem.gainExp(0, Combat.battleExp(1, 1, true))#exp;
        Assert.assertEq(
            expected = (Some(0), Some((1, expectedExp)), 3),
            (World.hpOf(World.EntityRef.Enemy(1), w1),
             World.progressOf(World.EntityRef.Player(0), w1),
             List.length(events)))

    /// (2) 撃破→level-up: player exp=99 で撃破すると 100 到達でレベルアップ。
    /// ★GAP 露出: LeveledUp の newHp は atkResource(growthRates) を統計成長して求める＝World に growth が無い。
    /// growthRates#hp=100・成長ロール=50 で hp は決定的に成長する。期待 level=2・hp=成長後。
    @Test
    def testSpikeResolveKillLevelsUp(): Unit \ Assert =
        let growRes = {growthRates = {hp = 100 | UnitCatalog.zeroGrowthRates()}
                        | TestUnitFixtures.testResource(4, 10)};
        let w0 = World.syncFromScene(scene(playerData(80, 99, growRes)), World.empty());
        let (w1, _events) = TestUnitFixtures.withMockRandom(() ->
            CombatSpike.resolveAttack(w0, World.EntityRef.Player(0), World.EntityRef.Enemy(1), 1, 1));
        // 期待 hp = 10 + (成長後hp − 成長前hp)。spike と同じ純関数で再導出して一致を要求する。
        let before = LevelSystem.statsOf(growRes);
        let rolls  = {hp = 50, attack = 50, defense = 50, magicAttack = 50, magicDefense = 50,
                      speed = 50, skill = 50, luck = 50, constitution = 50};
        let after  = LevelSystem.applyGrowth(before, growRes#growthRates, rolls);
        let expectedHp = 10 + (after#hp - before#hp);
        let lvl = match World.progressOf(World.EntityRef.Player(0), w1) {
                    case Some((l, _)) => l
                    case None         => -1
                  };
        Assert.assertEq(
            expected = (2, Some(expectedHp)),
            (lvl, World.hpOf(World.EntityRef.Player(0), w1)))
}
