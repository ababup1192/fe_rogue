/// EffectPlan の planActions / shouldFire を固定する。
/// JSON → EffectRule → Plan の全経路を通し、確定した PlanItem 列を assertEq する。
/// 「データ宣言された効果が、誰に・何を・いくつ するか」が値として決まることの実証。
mod TestEffectPlan {

    use EffectPlan.PlanItem
    use EffectRule.RayUnit
    use StatusSystem.StatusEffect

    // JSON → EffectRule。
    def decodeStr(s: String): Option[EffectRule.EffectRule] =
        Util.Json.parse(s) |> Result.toOption |> Option.flatMap(EffectRuleCodec.decodeRule)

    def unit(id: Int32, ally: Bool, immobilized: Bool, alive: Bool): RayUnit =
        {id = id, ally = ally, immobilized = immobilized, alive = alive}

    // selfId=1, attackerId=9, amount文脈 max30/dealt20/incoming12/magic7。
    def ctxWith(rayUnits: List[RayUnit]): EffectPlan.PlanCtx =
        {selfId = 1, attackerId = 9, rayUnits = rayUnits,
         amount = {max = 30, dealt = 20, incoming = 12, magic = 7}}

    // JSON → Plan（decode 失敗時は空リスト）。
    def plan(json: String, ctx: EffectPlan.PlanCtx): List[PlanItem] =
        decodeStr(json) |> Option.map(r -> EffectPlan.planActions(r, ctx)) |> Option.getWithDefault(Nil)

    // ════════════════════════════════════════════════════════
    // 投射系 A 純粋 op → PlanItem
    // ════════════════════════════════════════════════════════

    /// ちから薬: self に AtkUp+4 を 3 ターン、効果音 cure。
    @Test
    def testPlanPowerPotion(): Unit \ Assert =
        let json = "{\"when\":\"onUse\",\"deliver\":[\"self\"],\"do\":[{\"to\":{\"role\":\"self\"},\"op\":\"atkUp\",\"amount\":{\"flat\":4},\"for\":{\"turns\":3},\"sfx\":\"cure\"}]}";
        Assert.assertEq(
            expected = PlanItem.StatusAt(1, StatusEffect.AtkUp, 4, 3) :: PlanItem.PlaySfx("cure") :: Nil,
            plan(json, ctxWith(Nil)))

    /// 火炎瓶: 投げて当たった敵#3 に 15 ダメージ、効果音 magic。
    @Test
    def testPlanFireBottle(): Unit \ Assert =
        let json = "{\"when\":\"onUse\",\"deliver\":[\"throw\"],\"do\":[{\"to\":{\"role\":\"target\",\"faction\":\"enemy\"},\"op\":\"damageFlat\",\"amount\":{\"flat\":15},\"sfx\":\"magic\"}]}";
        let ray = unit(3, false, false, true) :: Nil;
        Assert.assertEq(
            expected = PlanItem.DamageAt(3, 15) :: PlanItem.PlaySfx("magic") :: Nil,
            plan(json, ctxWith(ray)))

    /// 回復の杖: statPlus magic(7)+10 = 17 を、ray 最初の味方#4 に回復。
    @Test
    def testPlanHealStaffStatPlus(): Unit \ Assert =
        let json = "{\"when\":\"onCast\",\"deliver\":[\"throw\"],\"do\":[{\"to\":{\"role\":\"target\"},\"op\":\"healFlat\",\"amount\":{\"statPlus\":{\"stat\":\"magic\",\"value\":10}}}]}";
        let ray = unit(4, true, false, true) :: Nil;
        Assert.assertEq(expected = PlanItem.HealAt(4, 17) :: Nil, plan(json, ctxWith(ray)))

    /// 血吸い: 与ダメージ(dealt20)の30% = 6 を attacker#9 に回復。
    @Test
    def testPlanLifesteal(): Unit \ Assert =
        let json = "{\"when\":\"onHit\",\"do\":[{\"to\":{\"role\":\"attacker\"},\"op\":\"lifesteal\",\"amount\":{\"pct\":{\"base\":\"dealt\",\"value\":30}}}]}";
        Assert.assertEq(expected = PlanItem.HealAt(9, 6) :: Nil, plan(json, ctxWith(Nil)))

    // ════════════════════════════════════════════════════════
    // B custom op / estimate 介入 / 空振り
    // ════════════════════════════════════════════════════════

    /// knockback(B custom) は CustomAt で runPlan の Scene handler へ委譲する形になる。
    @Test
    def testPlanCustomOp(): Unit \ Assert =
        let json = "{\"when\":\"onHit\",\"do\":[{\"to\":{\"role\":\"target\",\"faction\":\"enemy\"},\"op\":\"knockback\",\"amount\":{\"tiles\":2}}]}";
        let ray = unit(3, false, false, true) :: Nil;
        Assert.assertEq(expected = PlanItem.CustomAt("knockback", 3) :: Nil, plan(json, ctxWith(ray)))

    /// powerMul は estimate 内介入なので Plan では NoOp（Phase4 で estimate へ）。
    @Test
    def testPlanPowerMulIsNoOp(): Unit \ Assert =
        let json = "{\"when\":\"onAttack\",\"if\":{\"selfHpPctAtMost\":30},\"do\":[{\"to\":{\"role\":\"self\"},\"op\":\"powerMul\",\"amount\":{\"mul\":150}}]}";
        Assert.assertEq(
            expected = PlanItem.NoOp("powerMul は estimate 内介入（Phase4）") :: Nil,
            plan(json, ctxWith(Nil)))

    /// 止まっていない味方を求めたが停止中の味方しかいない → 空振り NoOp。
    @Test
    def testPlanNoTargetIsNoOp(): Unit \ Assert =
        let json = "{\"when\":\"onCast\",\"deliver\":[\"throw\"],\"do\":[{\"to\":{\"role\":\"target\",\"faction\":\"ally\",\"state\":\"notImmobilized\"},\"op\":\"immobilize\"}]}";
        let ray = unit(5, true, true, true) :: Nil;
        Assert.assertEq(expected = PlanItem.NoOp("対象なし（空振り）") :: Nil, plan(json, ctxWith(ray)))

    // ════════════════════════════════════════════════════════
    // shouldFire（確率 AND ガード述語）
    // ════════════════════════════════════════════════════════

    def predCtx(rogue: Bool): EffectDsl.PredCtx =
        {selfHpPct = 25, targetHpPct = 40, targetAlive = true,
         equippedIsRogue = rogue, adjacent = true}

    /// 盗人(chance20, if rogue&alive): roll19&ローグ → 発動 / roll20 → 不発 / 非ローグ → 不発。
    @Test
    def testShouldFire(): Unit \ Assert =
        let json = "{\"when\":\"onHit\",\"if\":{\"allOf\":[\"equippedIsRogue\",\"targetAlive\"]},\"chance\":20,\"do\":[{\"to\":{\"role\":\"target\",\"faction\":\"enemy\"},\"op\":\"dropItem\"}]}";
        let r = decodeStr(json) |> Option.getWithDefault(emptyRule());
        Assert.assertEq(expected = (true, false, false),
            (EffectPlan.shouldFire(r, predCtx(true), 19),
             EffectPlan.shouldFire(r, predCtx(true), 20),
             EffectPlan.shouldFire(r, predCtx(false), 0)))

    // decode 失敗時のフォールバック（テストでは到達しない）。
    def emptyRule(): EffectRule.EffectRule =
        {trigger = EffectRule.Trigger.OnUse, deliver = Nil,
         cond = EffectDsl.Pred.AllOf(Nil), chance = 0, actions = Nil, flow = None}
}
