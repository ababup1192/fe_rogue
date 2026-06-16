/// EffectBridge.weaponRule の移植テーブルを固定する。武器効果 6 種を effect+effectValue から
/// DSL ルールへ写し、planActions / 述語 / flow で正しい挙動に落ちることを確認する。
/// 「既存武器がコード改変なしで DSL 経路に乗る」ことの実証。
mod TestWeaponBridge {

    use WeaponCatalog.WeaponEffect
    use EffectPlan.PlanItem
    use EffectRule.RayUnit

    def enemy(id: Int32): RayUnit =
        {id = id, ally = false, immobilized = false, alive = true}

    def ctxWith(rayUnits: List[RayUnit]): EffectPlan.PlanCtx =
        {selfId = 0, attackerId = 9, actorIsPlayer = true, rayUnits = rayUnits,
         amount = {max = 30, dealt = 20, incoming = 12, magic = 0}}

    def planOf(effect: WeaponEffect, v: Int32, ctx: EffectPlan.PlanCtx): List[PlanItem] =
        EffectPlan.planActions(EffectBridge.weaponRule(effect, v), ctx)

    def predCtx(selfHpPct: Int32): EffectDsl.PredCtx =
        {selfHpPct = selfHpPct, targetHpPct = 100, targetAlive = true,
         equippedIsRogue = true, adjacent = false}

    // ════════════════════════════════════════════════════════

    /// NoEffect は do[] 空・flow なし。
    @Test
    def testNoEffect(): Unit \ Assert =
        let r = EffectBridge.weaponRule(WeaponEffect.NoEffect, 0);
        Assert.assertEq(expected = (true, true),
            (List.isEmpty(r#actions), Option.isEmpty(r#flow)))

    /// はやぶさ(BraveOnSpeed,3) は flow:followUp brave。速さ差+3 で追撃成立。
    @Test
    def testBraveOnSpeedFlow(): Unit \ Assert =
        let flow = EffectBridge.weaponRule(WeaponEffect.BraveOnSpeed, 3)#flow;
        let fctx = {atkSpd = 10, defSpd = 7, roll = 0, followUpUsed = false,
                    brave = Some(3), pursuit = false};
        let decided = flow
                        |> Option.map(f -> EffectFlow.followUpDecision(f, fctx))
                        |> Option.getWithDefault(false);
        Assert.assertEq(expected = true, decided)

    /// 如意棒(Knockback,2) は命中時、敵#3 を knockback（B custom → CustomAt）。
    @Test
    def testKnockback(): Unit \ Assert =
        Assert.assertEq(expected = PlanItem.CustomAt("knockback", 3, false) :: Nil,
            planOf(WeaponEffect.Knockback, 2, ctxWith(enemy(3) :: Nil)))

    /// 背水(Desperation,30) の cond は 自HP30%以下。25%で発動、31%で非発動。
    @Test
    def testDesperationCond(): Unit \ Assert =
        let cond = EffectBridge.weaponRule(WeaponEffect.Desperation, 30)#cond;
        Assert.assertEq(expected = (true, false),
            (EffectDsl.evalPredicate(cond, predCtx(25)),
             EffectDsl.evalPredicate(cond, predCtx(31))))

    /// 背水の do は powerMul ＝ estimate 内介入なので Plan では NoOp（Phase4）。
    @Test
    def testDesperationPlanIsNoOp(): Unit \ Assert =
        Assert.assertEq(
            expected = PlanItem.NoOp("powerMul は estimate 内介入（Phase4）") :: Nil,
            planOf(WeaponEffect.Desperation, 30, ctxWith(Nil)))

    /// 血吸い(Lifesteal,30) は命中時、与ダメ(20)の30%=6 を attacker#9 に回復。
    @Test
    def testLifesteal(): Unit \ Assert =
        Assert.assertEq(expected = PlanItem.HealAt(9, true, 6) :: Nil,
            planOf(WeaponEffect.Lifesteal, 30, ctxWith(Nil)))

    /// 盗人(ThiefDrop,20) は命中時、敵#3 に dropItem（B custom）。chance=20 は shouldFire 側。
    @Test
    def testThiefDrop(): Unit \ Assert =
        Assert.assertEq(expected = PlanItem.CustomAt("dropItem", 3, false) :: Nil,
            planOf(WeaponEffect.ThiefDrop, 20, ctxWith(enemy(3) :: Nil)))
}
