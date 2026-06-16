/// EffectBridge.staffRule の移植テーブルを固定する。杖効果 5 種を DSL ルールへ写し、
/// rayFirst（陣営無視で最初の1体）で正しい PlanItem に落ちることを確認する。
mod TestStaffBridge {

    use Staff.StaffEffect
    use EffectPlan.PlanItem
    use EffectRule.RayUnit

    def unit(id: Int32, ally: Bool): RayUnit =
        {id = id, ally = ally, immobilized = false, alive = true}

    // 杖回復は statPlus magic を使うので magic を 5 に。
    def ctxWith(rayUnits: List[RayUnit]): EffectPlan.PlanCtx =
        {selfId = 0, attackerId = 0, actorIsPlayer = true, rayUnits = rayUnits,
         amount = {max = 30, dealt = 0, incoming = 0, magic = 5}}

    def planOf(effect: StaffEffect, ctx: EffectPlan.PlanCtx): List[PlanItem] =
        EffectPlan.planActions(EffectBridge.staffRule(effect), ctx)

    /// 回復の杖: rayFirst で当たった味方#4 を 魔力5+10=15 回復（敵に当たれば敵も回復＝rayFirst）。
    @Test
    def testHeal(): Unit \ Assert =
        Assert.assertEq(expected = PlanItem.HealAt(4, true, 15) :: Nil,
            planOf(StaffEffect.Heal, ctxWith(unit(4, true) :: Nil)))

    /// 回復の杖を敵#3 に当てると 敵が15回復する（rayFirst・陣営無視の証拠）。
    @Test
    def testHealHitsEnemy(): Unit \ Assert =
        Assert.assertEq(expected = PlanItem.HealAt(3, false, 15) :: Nil,
            planOf(StaffEffect.Heal, ctxWith(unit(3, false) :: Nil)))

    /// ふきとばしの杖: 当たった相手に 1 ダメージ＋ノックバック（2 アクション）。
    @Test
    def testBlowback(): Unit \ Assert =
        Assert.assertEq(
            expected = PlanItem.DamageAt(3, false, 1) :: PlanItem.CustomAt("knockback", 3, false) :: Nil,
            planOf(StaffEffect.Blowback, ctxWith(unit(3, false) :: Nil)))

    /// いれかえの杖: 当たった相手と位置交換（B custom swapPos）。
    @Test
    def testSwap(): Unit \ Assert =
        Assert.assertEq(expected = PlanItem.CustomAt("swapPos", 3, false) :: Nil,
            planOf(StaffEffect.Swap, ctxWith(unit(3, false) :: Nil)))

    /// かなしばりの杖: 当たった相手を完全停止（ImmobilizeAt）。
    @Test
    def testBind(): Unit \ Assert =
        Assert.assertEq(expected = PlanItem.ImmobilizeAt(3, false, 5) :: Nil,
            planOf(StaffEffect.Bind, ctxWith(unit(3, false) :: Nil)))

    /// 一時しのぎの杖: 停止 → 階段へワープ（2 アクション、上から順）。
    @Test
    def testStopgap(): Unit \ Assert =
        Assert.assertEq(
            expected = PlanItem.ImmobilizeAt(4, true, 5) :: PlanItem.CustomAt("warpToStairs", 4, true) :: Nil,
            planOf(StaffEffect.Stopgap, ctxWith(unit(4, true) :: Nil)))
}
