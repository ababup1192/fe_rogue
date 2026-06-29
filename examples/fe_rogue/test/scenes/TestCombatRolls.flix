// Roll-sequence 等価テスト（slice `rng-world`）。
//
// CHOKEPOINT 不変条件: combat の全ロールが単一の `World.RngDraw.nextPercent` を **固定の順序・回数** で
// 通ることを固定する。seeded PRNG（withRecordedRolls）で applyAttackHit / applyEnemyAttackHit /
// onLungeDone を public seam から駆動し、記録された draw 列が純粋 Prng 列と COUNT+ORDER で一致することを
// 証明する。stat-position（どの draw がどの成長か）は仮定しない＝順序と本数だけを固定する。
//
// 期待値 `prngSeq(seed, n)` は値→値の `Prng.nextPercent` を n 回回した列。combat の record/argument が
// left-to-right で決定論的に評価される（rollGrowth の record・thief roll の arg）ため、seeded == 列。

mod TestCombatRolls {

    /// 純粋 Prng から n 個を draw 順に集める（期待値の出所）。
    def prngSeq(seed: Int64, n: Int32): List[Int32] =
        drawFrom(n, Prng.seed(seed))

    def drawFrom(n: Int32, st: Prng.State): List[Int32] =
        if (n <= 0) Nil
        else
            let (p, st1) = Prng.nextPercent(st);
            p :: drawFrom(n - 1, st1)

    // ════════════════════════════════════════════════════════
    // フィクスチャ（TestCombatScene と同型の最小戦闘シーン）
    // ════════════════════════════════════════════════════════

    /// 攻撃対象 enemy=1 を抱えた選択中味方。weaponHit/exp/speed を作り分ける。hp は大きめ（反撃で死なない）。
    def playerData(weaponHit: Int32, exp: Int32, speed: Int32): PlayerScene.Data = {
        id                = 0,
        classId           = "test_player",
        gridPos           = {x = 2, y = 2},
        moveTiles         = 4,
        hp                = 50,
        waited            = false,
        attackTargetId    = Some(1),
        resource          = TestUnitFixtures.testResourceFull(4, 50, 3, 1, speed),
        weapons           = ({hit = weaponHit | TestUnitFixtures.testWeapon()}: UnitCatalog.WeaponResource) :: Nil,
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

    /// 隣接 (3,2) の敵。curHp/weaponHit/speed/attackTarget/effectRule を作り分ける。
    def enemyData(curHp: Int32, weaponHit: Int32, speed: Int32,
                   attackTarget: Option[Int32], effectRule: Option[Util.Json.Json]): EnemyScene.Data = {
        id             = 1,
        resourceId     = "test_enemy",
        gridPos        = {x = 3, y = 2},
        alerted        = false,
        homeModuleIdx  = 0,
        moveTiles      = 3,
        hp             = curHp,
        isDying        = false,
        attackTargetId = attackTarget,
        resource       = {speed = speed, effectRule = effectRule
                            | TestUnitFixtures.testEnemyResource(3, 50)},
        weapon         = Some({hit = weaponHit | TestUnitFixtures.testWeapon()}),
        acted          = false,
        prevPos        = None,
        statuses       = Nil,
        ring           = None,
        followUpUsed   = false,
        bottleUsed     = false
    }

    /// World 配下に Player(0)・Enemy(1) を直接挿した最小シーン（TestCombatScene.battleScene と同型）。
    def battleScene(p: PlayerScene.Data, e: EnemyScene.Data): Scene[NodeTag] =
        let world = Marker2D.make(Vec2.zero()) |> CanvasItem.setYSortEnabled(true);
        let pMarker = Marker2D.make(Vec2.zero());
        let eMarker = Marker2D.make(Vec2.zero());
        Scene.empty()
            |> Scene.addNode(MapScene.worldName(),
                EngineNode.Marker2DWithState(world, NodeTag.NoTag))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(0),
                EngineNode.Marker2DWithState(pMarker, NodeTag.Player(p)))
            |> Scene.addChildAt(MapScene.worldPath(), EnemyScene.enemyName(1),
                EngineNode.Marker2DWithState(eMarker, NodeTag.Enemy(e)))

    /// onHit で spdDown を撒く敵 effectRule（chance 省略＝既定 100＝必ず発火＝effect roll を必ず draw）。
    def onHitEffectRule(): Option[Util.Json.Json] =
        Util.Json.parse("{\"when\":\"onHit\",\"to\":\"enemy\",\"op\":\"spdDown\",\"amount\":3,\"for\":\"turns\",\"forTurns\":3}")
            |> Result.toOption

    // ════════════════════════════════════════════════════════
    // (1) 味方攻撃 — hit→crit→thief→kill→level-up = 12 draw
    // ════════════════════════════════════════════════════════

    /// applyAttackHit が hit(515)→crit(516)→thief(548)→growth×9(951-959) の順に
    /// ちょうど 12 回 draw する。weaponHit を大きくして必中、enemy curHp=1 で確殺、exp=99 で確実にレベルアップ。
    /// 記録列 == 純粋 Prng 列（seed 0）で COUNT+ORDER を固定する。
    @Test
    def testPlayerAttackTwelveDrawSequence(): Unit \ Assert =
        region rc {
            let scene = battleScene(playerData(200, 99, 3),
                                    enemyData(1, 80, 3, None, None));
            let (_, rolls) =
                TestUnitFixtures.withWorldQuery(World.syncFromScene(scene, World.empty()), () ->
                TestUnitFixtures.dischargeWorldCommand(() ->
                TestUnitFixtures.withMockBoard(BoardSnapshot.fromScene(scene), () ->
                TestUnitFixtures.withNoopThiefDrop(() ->
                TestUnitFixtures.withMockGame(() ->
                TestUnitFixtures.withMockAudio(() ->
                TestUnitFixtures.withMockGameLogger(() ->
                TestUnitFixtures.withNoopAnim(() ->
                TestUnitFixtures.withNoopTween(() ->
                TestUnitFixtures.withRecordedRolls(rc, 0i64, () ->
                    CombatScene.applyAttackHitLegacy(0, scene)))))))))));
            Assert.assertEq(
                expected = (12, prngSeq(0i64, 12)),
                (List.length(rolls), rolls))
        }

    // ════════════════════════════════════════════════════════
    // (2) 敵攻撃（effectRule + 必中） — hit→crit→effect = 3 draw
    // ════════════════════════════════════════════════════════

    /// applyEnemyAttackHit が hit(717)→crit(728)→effect(801) の順にちょうど 3 回 draw する。
    /// 敵 weaponHit を大きくして必中、player hp=50 で生存（killed=false でも onHit effectRule は発火＝effect roll を draw）。
    @Test
    def testEnemyAttackHitCritEffectSequence(): Unit \ Assert =
        region rc {
            let scene = battleScene(playerData(80, 0, 3),
                                    enemyData(50, 200, 3, Some(0), onHitEffectRule()));
            let (_, rolls) =
                TestUnitFixtures.withWorldQuery(World.syncFromScene(scene, World.empty()), () ->
                TestUnitFixtures.dischargeWorldCommand(() ->
                TestUnitFixtures.withMockBoard(BoardSnapshot.fromScene(scene), () ->
                TestUnitFixtures.withMockGame(() ->
                TestUnitFixtures.withMockAudio(() ->
                TestUnitFixtures.withMockGameLogger(() ->
                TestUnitFixtures.withNoopTween(() ->
                TestUnitFixtures.withNoopAnim(() ->
                TestUnitFixtures.withRecordedRolls(rc, 0i64, () ->
                    CombatScene.applyEnemyAttackHitLegacy(1, scene))))))))));
            Assert.assertEq(
                expected = (3, prngSeq(0i64, 3)),
                (List.length(rolls), rolls))
        }

    // ════════════════════════════════════════════════════════
    // (3) onLungeDone — 追撃ロールが IN POSITION で 1 回引かれる
    // ════════════════════════════════════════════════════════

    /// 味方主攻撃完了の onLungeDone(PlayerTurn 分岐) は追撃判定で rollPercent()@203 を 1 回 draw する。
    /// player speed を enemy より遅くして追撃ブランチを fire させない（None）が、roll は arg として消費される。
    /// resolvePlayerMainAttack は roll を引かない（CounterAttackRules は純粋）ので記録は [先頭 draw] ちょうど 1 件。
    @Test
    def testOnLungeDoneFollowUpRollInPosition(): Unit \ Assert =
        region rc {
            let scene = battleScene(playerData(80, 0, 1),
                                    enemyData(10, 80, 30, None, None));
            let (_, rolls) =
                TestUnitFixtures.withWorldQuery(World.syncFromScene(scene, World.empty()), () ->
                TestUnitFixtures.withWorldPhase(SimPhase.PlayerTurn, () ->
                TestUnitFixtures.withWorldCommand(rc, () ->
                TestUnitFixtures.withMockGameLogger(() ->
                TestUnitFixtures.withMockEnemyTurnQueue(() ->
                TestUnitFixtures.withNoopAnim(() ->
                TestUnitFixtures.withRecordedRolls(rc, 0i64, () ->
                    run {
                        let _ = CombatScene.onLungeDone(Faction.Player, 0, scene);
                        ()
                    } with Tween.withScheduler(rc)
                      with TurnPhase.withState(rc)
                      with SelectedPlayer.withState(rc)
                      with Pacing.withState(rc))))))));
            Assert.assertEq(
                expected = (1, prngSeq(0i64, 1)),
                (List.length(rolls), rolls))
        }

}
