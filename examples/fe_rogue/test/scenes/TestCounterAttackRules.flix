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
    // 旧 playerAt fixture は decide テスト撤去で未使用となり削除（decideView は UnitView fixture を使う）。

    /// 任意 id / 位置 / 武器 / 瀕死状態の Enemy.Data。`killedTargetEnemyId` テストで使用。
    def enemyAt(id: Int32, x: Int32, y: Int32,
                 weapon: Option[UnitCatalog.WeaponResource],
                 isDying: Bool): EnemyScene.Data = {
        id             = id,
        resourceId     = "test_enemy",
        gridPos        = {x = x, y = y},
        alerted        = false,
        homeModuleIdx  = 0,
        moveTiles      = 3,
        hp             = if (isDying) 0 else 10,
        isDying        = isDying,
        attackTargetId = None,
        resource       = TestUnitFixtures.testEnemyResource(3, 10),
        weapon         = weapon,
        acted          = false,
        prevPos        = None,
        statuses       = Nil,
        ring           = None,
        followUpUsed   = false,
        bottleUsed     = false
    }


    // 旧 decide(味方→敵) の 4 ケース分類テストは、Track A の faction-blind 統合で
    // `testDecideViewUnifiesFactionBranches`（下部）に集約・置換した（旧関数は削除済）。

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

    // ════════════════════════════════════════════════════════
    // Track A: decideView（faction-blind 統合版）= 旧 decide / decidePlayerCounter の全分類を 1 関数で
    // ════════════════════════════════════════════════════════

    /// `decideView` が所属を見ずに 5 分類を返す。隣接(距離1)・剣 range{1,1} を基準に、
    /// target None→Commit / 瀕死→Kill / hp<=0(味方視点の死亡統一)→Kill / 武器なし→Commit /
    /// 射程内→Counter / 射程外(距離3)→Commit。旧 decide(味方→敵) と decidePlayerCounter(敵→味方) の
    /// 両分類表を 1 つの faction-blind 述語で被覆することを固定する。
    @Test
    def testDecideViewUnifiesFactionBranches(): Unit \ Assert =
        let sword     = Some({min = 1, max = 1});
        let attacker  = TestUnitFixtures.mkUnit(0, Faction.Player, {x = 2, y = 2}, 10, false, sword);
        let mk        = (id, x, y, hp, dying, range) ->
                            TestUnitFixtures.mkUnit(id, Faction.Enemy, {x = x, y = y}, hp, dying, range);
        let d         = CounterAttackRules.decideView;
        Assert.assertEq(
            expected = ( CounterAttackRules.Outcome.Commit,        // target なし
                         CounterAttackRules.Outcome.Kill,          // 瀕死(isDying)
                         CounterAttackRules.Outcome.Kill,          // hp<=0（味方死亡の統一）
                         CounterAttackRules.Outcome.Commit,        // 武器なし
                         CounterAttackRules.Outcome.Counter(5),    // 隣接・射程内
                         CounterAttackRules.Outcome.Commit ),      // 射程外(距離3)
            ( d(attacker, None),
              d(attacker, Some(mk(5, 2, 3, 4, true,  sword))),
              d(attacker, Some(mk(5, 2, 3, 0, false, sword))),
              d(attacker, Some(mk(5, 2, 3, 6, false, None))),
              d(attacker, Some(mk(5, 2, 3, 6, false, sword))),
              d(attacker, Some(mk(5, 2, 5, 6, false, sword))) ))
}
