/// EffectBridge.ringRule の移植テーブルを固定する。指輪効果 8 種を effect+power から
/// DSL ルールへ写し、whileEquipped 常時補正(Power/Swift/Guard)・イベント発火(Mend/vengeance)・
/// flow(Pursuit)・estimate介入(Finisher) が正しく落ちることを確認する。
mod TestRingBridge {

    use Ring.RingEffect
    use EffectPlan.PlanItem
    use EffectRule.RayUnit

    def enemy(id: Int32): RayUnit =
        {id = id, ally = false, immobilized = false, alive = true}

    def ctxWith(rayUnits: List[RayUnit]): EffectPlan.PlanCtx =
        {selfId = 0, attackerId = 9, rayUnits = rayUnits,
         amount = {max = 30, dealt = 20, incoming = 12, magic = 0}}

    def planOf(effect: RingEffect, power: Int32, ctx: EffectPlan.PlanCtx): List[PlanItem] =
        EffectPlan.planActions(EffectBridge.ringRule(effect, power), ctx)

    def has(needle: String, hay: String): Bool = String.contains({substr = needle}, hay)

    // ════════════════════════════════════════════════════════
    // 常時補正（whileEquipped → runPlan は NoOp、Ring.bonuses が実行）
    // ════════════════════════════════════════════════════════

    /// ちから/まもりのリングは whileEquipped なので Plan では常時補正 NoOp に短絡する。
    @Test
    def testWhileEquippedNoOp(): Unit \ Assert =
        let noop = PlanItem.NoOp("常時補正（装備中・Ring.bonuses が処理）") :: Nil;
        Assert.assertEq(expected = (noop, noop),
            (planOf(RingEffect.Power, 3, ctxWith(Nil)),
             planOf(RingEffect.Guard, 3, ctxWith(Nil))))

    /// まもりのリング(Guard,3) のプレビューは「守備を 3 上げる」「装備しているあいだ」を含む（OpDefUp）。
    @Test
    def testGuardPreview(): Unit \ Assert =
        let p = EffectRule.previewRule(EffectBridge.ringRule(RingEffect.Guard, 3));
        Assert.assertEq(expected = (true, true),
            (has("守備を 3 上げる", p), has("装備しているあいだ", p)))

    // ════════════════════════════════════════════════════════
    // イベント発火（Mend / vengeance / Finisher / Pursuit）
    // ════════════════════════════════════════════════════════

    /// いやしのリング(Mend,2) はターン開始時、自分に HealAt 2。
    @Test
    def testMend(): Unit \ Assert =
        Assert.assertEq(expected = PlanItem.HealAt(0, true, 2) :: Nil,
            planOf(RingEffect.Mend, 2, ctxWith(Nil)))

    /// みかえりのリング(Lifesteal,5) は撃破時、attacker#9 に HealAt 5。
    @Test
    def testVengeance(): Unit \ Assert =
        Assert.assertEq(expected = PlanItem.HealAt(9, true, 5) :: Nil,
            planOf(RingEffect.Lifesteal, 5, ctxWith(Nil)))

    /// 死神のネックレス(Finisher,30) の cond は 敵HP30%以下。do は estimate介入で NoOp。
    @Test
    def testFinisher(): Unit \ Assert =
        let cond = EffectBridge.ringRule(RingEffect.Finisher, 30)#cond;
        let predLow = {selfHpPct = 100, targetHpPct = 25, targetAlive = true,
                       equippedIsRogue = false, adjacent = false};
        Assert.assertEq(
            expected = (true, PlanItem.NoOp("finisher は estimate 内介入（Phase4）") :: Nil),
            (EffectDsl.evalPredicate(cond, predLow),
             planOf(RingEffect.Finisher, 30, ctxWith(enemy(3) :: Nil))))

    /// 追撃のリング(Pursuit) は flow:followUp pursuit。速さ差+3・roll<15・所持で成立。
    @Test
    def testPursuitFlow(): Unit \ Assert =
        let flow = EffectBridge.ringRule(RingEffect.Pursuit, 0)#flow;
        let fctx = {atkSpd = 10, defSpd = 7, roll = 14, followUpUsed = false,
                    brave = (None: Option[Int32]), pursuit = true};
        let decided = flow
                        |> Option.map(f -> EffectFlow.followUpDecision(f, fctx))
                        |> Option.getWithDefault(false);
        Assert.assertEq(expected = true, decided)

    /// ただのリング(Trivial) は do[] 空・flow なし。
    @Test
    def testTrivial(): Unit \ Assert =
        let r = EffectBridge.ringRule(RingEffect.Trivial, 0);
        Assert.assertEq(expected = (true, true),
            (List.isEmpty(r#actions), Option.isEmpty(r#flow)))
}
