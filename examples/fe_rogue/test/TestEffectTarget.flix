/// EffectRule.resolveTarget の対象解決を固定する。設計の核心「rayFirst（陣営無視が既定）/
/// faction を明示したときだけ陣営で絞る / notImmobilized 等の state フィルタ」を実証する。
/// レビューで論点になった「杖 Heal は ray が最初に当てた相手なら敵でも回復する」を型で担保。
mod TestEffectTarget {

    use EffectRule.{Role, Faction, TargetState}
    use EffectRule.RayUnit

    def tgt(role: Role, faction: Faction, state: TargetState): EffectRule.Target =
        {role = role, faction = faction, state = state}

    def unit(id: Int32, ally: Bool, immobilized: Bool, alive: Bool): RayUnit =
        {id = id, ally = ally, immobilized = immobilized, alive = alive}

    def resolve(t: EffectRule.Target, units: List[RayUnit]): Option[Int32] =
        EffectRule.resolveTarget(t, 1, 9, units, true) |> Option.map(u -> u#id)

    /// actorIsPlayer を明示して (id, ally) を返す。敵 actor 視点の検証用。
    def resolveAs(t: EffectRule.Target, units: List[RayUnit], actorIsPlayer: Bool): Option[(Int32, Bool)] =
        EffectRule.resolveTarget(t, 1, 9, units, actorIsPlayer) |> Option.map(u -> (u#id, u#ally))

    // ════════════════════════════════════════════════════════
    // rayFirst（faction 省略 = Any = 陣営無視）
    // ════════════════════════════════════════════════════════

    // ray: [敵#3, 味方#4] の順。
    def rayEnemyThenAlly(): List[RayUnit] =
        unit(3, false, false, true) :: unit(4, true, false, true) :: Nil

    /// 杖 Heal（faction 省略=Any）は ray 最初の1体＝敵#3 を対象にする（敵でも回復＝既存挙動）。
    @Test
    def testRayFirstHitsEnemy(): Unit \ Assert =
        let t = tgt(Role.RoleTarget, Faction.FactionAny, TargetState.StateAny);
        Assert.assertEq(expected = Some(3), resolve(t, rayEnemyThenAlly()))

    /// faction=enemy を明示すると敵#3（火炎瓶: 味方を焼かない）。先頭が味方でも敵まで進む。
    @Test
    def testFactionEnemySkipsAlly(): Unit \ Assert =
        let ray = unit(4, true, false, true) :: unit(3, false, false, true) :: Nil;
        let t = tgt(Role.RoleTarget, Faction.FactionEnemy, TargetState.StateAny);
        Assert.assertEq(expected = Some(3), resolve(t, ray))

    /// faction=ally を明示すると味方#4（先頭の敵#3 を飛ばす）。
    @Test
    def testFactionAllyPicksAlly(): Unit \ Assert =
        let t = tgt(Role.RoleTarget, Faction.FactionAlly, TargetState.StateAny);
        Assert.assertEq(expected = Some(4), resolve(t, rayEnemyThenAlly()))

    // ════════════════════════════════════════════════════════
    // state フィルタ（かなしばり詠唱: 止まっていない味方だけ）
    // ════════════════════════════════════════════════════════

    /// faction=ally + notImmobilized は、停止中の味方#5 を飛ばして 動ける味方#6 を選ぶ。
    @Test
    def testNotImmobilizedSkipsStopped(): Unit \ Assert =
        let ray = unit(5, true, true, true) :: unit(6, true, false, true) :: Nil;
        let t = tgt(Role.RoleTarget, Faction.FactionAlly, TargetState.StateNotImmobilized);
        Assert.assertEq(expected = Some(6), resolve(t, ray))

    /// 条件を満たす候補が ray 上にいなければ None（空振り → runPlan は NoOp）。
    @Test
    def testNoMatchIsNone(): Unit \ Assert =
        let ray = unit(5, true, true, true) :: Nil;   // 停止中の味方しかいない
        let t = tgt(Role.RoleTarget, Faction.FactionAlly, TargetState.StateNotImmobilized);
        Assert.assertEq(expected = None, resolve(t, ray))

    // ════════════════════════════════════════════════════════
    // role 別（self / attacker / area）
    // ════════════════════════════════════════════════════════

    /// RoleSelf は selfId(1)、RoleAttacker は attackerId(9) を返す（ray 非依存）。
    @Test
    def testSelfAndAttacker(): Unit \ Assert =
        let self0 = tgt(Role.RoleSelf, Faction.FactionAny, TargetState.StateAny);
        let atk = tgt(Role.RoleAttacker, Faction.FactionAny, TargetState.StateAny);
        Assert.assertEq(expected = (Some(1), Some(9)),
            (resolve(self0, Nil), resolve(atk, Nil)))

    /// RoleArea は単一 id ではないので None（範囲は runPlan が Board.cellsWithin で展開）。
    @Test
    def testAreaIsNone(): Unit \ Assert =
        let t = tgt(Role.RoleArea(1), Faction.FactionAny, TargetState.StateAny);
        Assert.assertEq(expected = None, resolve(t, rayEnemyThenAlly()))

    // ════════════════════════════════════════════════════════
    // actorIsPlayer（敵 actor 視点）— 自己回復が player に漏れない / 敵が player を狙える
    // ════════════════════════════════════════════════════════

    /// 敵 actor（actorIsPlayer=false）の RoleSelf は EnemyScene 側（ally=false）を指す。
    /// これが true に漏れると敵の吸血が player を回復してしまう（致命バグの回帰検知）。
    @Test
    def testEnemyActorSelfIsEnemySide(): Unit \ Assert =
        let t = tgt(Role.RoleSelf, Faction.FactionAny, TargetState.StateAny);
        Assert.assertEq(expected = Some((1, false)), resolveAs(t, Nil, false))

    /// 敵 actor（actorIsPlayer=false）の RoleAttacker も EnemyScene 側（ally=false）。
    @Test
    def testEnemyActorAttackerIsEnemySide(): Unit \ Assert =
        let t = tgt(Role.RoleAttacker, Faction.FactionAny, TargetState.StateAny);
        Assert.assertEq(expected = Some((9, false)), resolveAs(t, Nil, false))

    /// 敵 actor が faction=enemy で狙うと ray 上の player 駒（is-player=true）に当たり、ally=true で返る
    /// （→ runPlan が PlayerScene 側へ作用＝毒/鈍足が player に付く）。
    @Test
    def testEnemyActorHitsPlayer(): Unit \ Assert =
        let ray = unit(7, true, false, true) :: Nil;   // player#7（is-player）
        let t = tgt(Role.RoleTarget, Faction.FactionEnemy, TargetState.StateAny);
        Assert.assertEq(expected = Some((7, true)), resolveAs(t, ray, false))

    /// 同じ敵 actor の faction=ally は「敵にとっての味方＝別の敵駒」を指す（player#7 は弾く）。
    @Test
    def testEnemyActorAllyIsOtherEnemy(): Unit \ Assert =
        let ray = unit(7, true, false, true) :: unit(8, false, false, true) :: Nil;  // player#7, enemy#8
        let t = tgt(Role.RoleTarget, Faction.FactionAlly, TargetState.StateAny);
        Assert.assertEq(expected = Some((8, false)), resolveAs(t, ray, false))
}
