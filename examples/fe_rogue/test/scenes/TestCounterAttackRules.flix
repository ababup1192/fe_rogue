/// CounterAttackRules.decide のテスト
///
/// 攻撃モーション完了後の挙動分類 (`Kill` / `Counter(eid)` / `Commit`) を、
/// Player / Enemy の Data record を直接合成して検証する。
/// Scene[NodeTag] / effect は一切使わない (純粋関数なので必要ない)。
///
/// 確認する性質:
///   - 対象が居ない (target=None) → Commit
///   - 対象が瀕死 (isDying=true) → Kill
///   - 対象に武器が無い → Commit
///   - 対象に武器 + 射程内 → Counter(eid)
///   - 対象に武器 + 射程外 (弓 range 2-2 で隣接) → Commit (回帰ガード)
mod TestCounterAttackRules {

    // ════════════════════════════════════════════════════════
    // 共通フィクスチャ
    // ════════════════════════════════════════════════════════

    /// 任意座標の Player.Data。テストに不要なフィールドは固定値で埋める。
    def playerAt(x: Int32, y: Int32): PlayerScene.Data = {
        id                 = 0,
        gridPos            = {x = x, y = y},
        moveTiles          = 4,
        hp                 = 10,
        waited             = false,
        attackTargetId     = None,
        resource           = TestUnitFixtures.testResource(4, 10),
        weapons            = Nil,
        staves             = Nil,
        consumables        = Nil,
        selectedItem       = None,
        moveStepsTaken     = 0,
        facing             = Staff.Direction.Down,
        hidden             = false,
        usedStairs             = false,
        level                      = 1,
        exp                        = 0,
        pendingLevelUp             = None
    }

    /// 任意 id / 位置 / 武器 / 瀕死状態の Enemy.Data。
    def enemyAt(id: Int32, x: Int32, y: Int32,
                 weapon: Option[UnitCatalog.WeaponResource],
                 isDying: Bool): EnemyScene.Data = {
        id             = id,
        gridPos        = {x = x, y = y},
        alerted        = false,
        homeModuleIdx  = 0,
        moveTiles      = 3,
        hp             = if (isDying) 0 else 10,
        isDying        = isDying,
        attackTargetId = None,
        resource       = TestUnitFixtures.testEnemyResource(3, 10),
        weapon         = weapon
    }

    /// 射程 2-2 の弓 (隣接攻撃には届かない)
    def bow(): UnitCatalog.WeaponResource = {
        range = { min = 2, max = 2 }
        | TestUnitFixtures.testWeapon()
    }

    // ════════════════════════════════════════════════════════
    // decide: 4 ケースの分類表
    // ════════════════════════════════════════════════════════

    /// 攻撃対象が消滅していれば Commit (反撃も kill 演出も無し)
    @Test
    def testDecideReturnsCommitWhenTargetMissing(): Unit \ Assert =
        let result = CounterAttackRules.decide(playerAt(2, 2), None);
        Assert.assertEq(
            expected = CounterAttackRules.Outcome.Commit,
            result)

    /// 攻撃対象が瀕死 (isDying=true) なら Kill (倒した演出に進む)
    @Test
    def testDecideReturnsKillWhenTargetIsDying(): Unit \ Assert =
        let target = Some(enemyAt(5, 3, 2, Some(TestUnitFixtures.testWeapon()), true));
        let result = CounterAttackRules.decide(playerAt(2, 2), target);
        Assert.assertEq(
            expected = CounterAttackRules.Outcome.Kill,
            result)

    /// 攻撃対象が武器を持たない (壊れている等) なら Commit (反撃不可)
    @Test
    def testDecideReturnsCommitWhenEnemyDisarmed(): Unit \ Assert =
        let target = Some(enemyAt(5, 3, 2, None, false));
        let result = CounterAttackRules.decide(playerAt(2, 2), target);
        Assert.assertEq(
            expected = CounterAttackRules.Outcome.Commit,
            result)

    /// 隣接 + 剣 (range 1-1) → Counter(eid)
    /// 味方 (2,2) と敵 (3,2) でマンハッタン距離 1
    @Test
    def testDecideReturnsCounterWhenInRange(): Unit \ Assert =
        let target = Some(enemyAt(5, 3, 2, Some(TestUnitFixtures.testWeapon()), false));
        let result = CounterAttackRules.decide(playerAt(2, 2), target);
        Assert.assertEq(
            expected = CounterAttackRules.Outcome.Counter(5),
            result)

    /// 隣接 + 弓 (range 2-2) → Commit (射程外: 弓は距離 1 に届かない)
    /// FE 風の「弓は近接で反撃できない」境界条件
    @Test
    def testDecideReturnsCommitWhenBowAtMeleeRange(): Unit \ Assert =
        let target = Some(enemyAt(5, 3, 2, Some(bow()), false));
        let result = CounterAttackRules.decide(playerAt(2, 2), target);
        Assert.assertEq(
            expected = CounterAttackRules.Outcome.Commit,
            result)

    // ════════════════════════════════════════════════════════
    // killedTargetEnemyId: 瀕死なら id、それ以外なら None
    // ════════════════════════════════════════════════════════

    /// 攻撃対象が瀕死なら id を返す
    @Test
    def testKilledTargetReturnsIdWhenDying(): Unit \ Assert =
        let target = Some(enemyAt(7, 3, 2, Some(TestUnitFixtures.testWeapon()), true));
        let result = CounterAttackRules.killedTargetEnemyId(target);
        Assert.assertEq(expected = Some(7), result)

    /// 攻撃対象が生存中なら None (倒せていない)
    @Test
    def testKilledTargetReturnsNoneWhenAlive(): Unit \ Assert =
        let target = Some(enemyAt(7, 3, 2, Some(TestUnitFixtures.testWeapon()), false));
        let result = CounterAttackRules.killedTargetEnemyId(target);
        Assert.assertEq(expected = None, result)
}
