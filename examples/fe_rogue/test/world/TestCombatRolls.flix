// Roll-sequence 等価テスト。
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
    // フィクスチャ（TestCombatDriver と同型の最小戦闘シーン）
    // ════════════════════════════════════════════════════════

    /// playerData 相当の spawn Cmd 列（id=0, pos=(2,2), hp=50 固定・attackTarget=enemy(1) 固定）。
    /// weaponHit/exp/speed を作り分ける（playerData と同じ値を Cmd で上書きする）。
    def playerUnitCmds(weaponHit: Int32, exp: Int32, speed: Int32): List[World.Cmd] =
        let ref    = World.EntityRef.Player(0);
        let weapon = ({hit = weaponHit | TestUnitFixtures.testWeapon()}: UnitCatalog.WeaponResource);
        let res    = TestUnitFixtures.testResourceFull(4, 50, 3, 1, speed);
        List.flatten(
            TestWorldFixtures.playerCmds({hp = 50 | TestWorldFixtures.unitSpec(0, {x = 2, y = 2})})
                :: (World.Cmd.SetWeapons(ref, weapon :: Nil)
                    :: World.Cmd.SetWeaponView(ref, Combat.weaponView(Some(weapon), true))
                    :: World.Cmd.SetPlayerResource(0, res)
                    :: World.Cmd.SetBaseStats(ref, Combat.baseStatsFrom(res))
                    :: World.Cmd.SetProgress(ref, res#level, exp)
                    :: World.Cmd.SetAttackTarget(ref, 1)
                    :: Nil)
                :: Nil)

    /// enemyData 相当の spawn Cmd 列（id=1, pos=(3,2), maxHp=50 固定）。
    /// curHp/weaponHit/speed/attackTarget/effectRule を作り分ける（enemyData と同じ値を Cmd で上書きする）。
    def enemyUnitCmds(curHp: Int32, weaponHit: Int32, speed: Int32,
                       attackTarget: Option[Int32], effectRule: Option[Util.Json.Json]): List[World.Cmd] =
        let ref     = World.EntityRef.Enemy(1);
        let weapon  = ({hit = weaponHit | TestUnitFixtures.testWeapon()}: UnitCatalog.WeaponResource);
        let res     = {speed = speed, effectRule = effectRule | TestUnitFixtures.testEnemyResource(3, 50)};
        let atkCmds = attackTarget |> Option.map(t -> World.Cmd.SetAttackTarget(ref, t) :: Nil)
                                    |> Option.getWithDefault(Nil);
        List.flatten(
            TestWorldFixtures.enemyCmds({hp = 50, moveTiles = 3 | TestWorldFixtures.unitSpec(1, {x = 3, y = 2})})
                :: (World.Cmd.SetWeapons(ref, weapon :: Nil)
                    :: World.Cmd.SetWeaponView(ref, Combat.weaponView(Some(weapon), true))
                    :: World.Cmd.SetEnemyResource(1, res)
                    :: World.Cmd.SetBaseStats(ref, Combat.baseStatsFrom(res))
                    :: World.Cmd.SetEffectRule(1, effectRule)
                    :: World.Cmd.SetHp(ref, curHp)
                    :: Nil)
                :: atkCmds
                :: Nil)

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
            let cmds = List.append(playerUnitCmds(200, 99, 3),
                                    enemyUnitCmds(1, 80, 3, None, None));
            // ONE-Ref traced world（Command+Query 同一 World）。RngDraw は内側の
            // withRecordedRolls が先に intercept する（traced の seeded RngDraw は到達しない）。
            let (out3, _keys, _w) =
                TestUnitFixtures.withTracedWorld(rc, 0i64, cmds, () ->
                TestUnitFixtures.withMockBoard(BoardSnapshot.fromWorld(TestWorldFixtures.floorSnapshot({w = 13, h = 13})), () ->
                TestUnitFixtures.withNoopThiefDrop(() ->
                TestUnitFixtures.withMockGame(() ->
                TestUnitFixtures.withMockAudio(() ->
                TestUnitFixtures.withMockGameLogger(() ->
                TestUnitFixtures.withNoopAnim(() ->
                TestUnitFixtures.withNoopTween(() ->
                TestUnitFixtures.withRecordedRolls(rc, 0i64, () ->
                    CombatDriver.applyAttackHit(0))))))))));
            let (_, rolls) = out3;
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
            let cmds = List.append(playerUnitCmds(80, 0, 3),
                                    enemyUnitCmds(50, 200, 3, Some(0), onHitEffectRule()));
            // ONE-Ref traced world（上と同型）。
            let (out3, _keys, _w) =
                TestUnitFixtures.withTracedWorld(rc, 0i64, cmds, () ->
                TestUnitFixtures.withMockBoard(BoardSnapshot.fromWorld(TestWorldFixtures.floorSnapshot({w = 13, h = 13})), () ->
                TestUnitFixtures.withMockGame(() ->
                TestUnitFixtures.withMockAudio(() ->
                TestUnitFixtures.withMockGameLogger(() ->
                TestUnitFixtures.withNoopTween(() ->
                TestUnitFixtures.withNoopAnim(() ->
                TestUnitFixtures.withRecordedRolls(rc, 0i64, () ->
                    CombatDriver.applyEnemyAttackHit(1)))))))));
            let (_, rolls) = out3;
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
            let cmds = List.append(playerUnitCmds(80, 0, 1),
                                    enemyUnitCmds(10, 80, 30, None, None));
            let (_, rolls) =
                TestUnitFixtures.withWorldQuery(TestWorldFixtures.worldOf(cmds), () ->
                TestUnitFixtures.withWorldPhase(SimPhase.PlayerTurn, () ->
                TestUnitFixtures.withWorldCommand(rc, () ->
                TestUnitFixtures.withMockGameLogger(() ->
                TestUnitFixtures.withMockEnemyTurnQueue(() ->
                TestUnitFixtures.withNoopAnim(() ->
                TestUnitFixtures.withRecordedRolls(rc, 0i64, () ->
                    run {
                        let _ = CombatDriver.onLungeDone(Faction.Player, 0);
                        ()
                    } with TurnPhase.withState(rc)
                      with SelectedPlayer.withState(rc)
                      with CursorState.withState(rc)
                      with Pacing.withState(rc)
                      with RangeOverlayState.withState(rc))))))));
            Assert.assertEq(
                expected = (1, prngSeq(0i64, 1)),
                (List.length(rolls), rolls))
        }

}
