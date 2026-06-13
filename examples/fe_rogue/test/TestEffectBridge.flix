/// EffectBridge.consumableRule の移植テーブルを固定する。
/// 既存の ConsumableResource を DSL ルールへ写し、その実データ（magnitude/duration）で
/// 正しい PlanItem に落ちることを全消費アイテムについて確認する。
/// 「いま JSON にある全消費アイテムがコード改変なしで DSL 経路に乗る」ことの実証。
mod TestEffectBridge {

    use EffectPlan.PlanItem
    use EffectRule.RayUnit
    use StatusSystem.StatusEffect
    use Consumable.ConsumableEffect

    // 実 ConsumableResource を簡便に作る（Consumable.bottle は sprite ダミー付き）。
    def item(effect: ConsumableEffect, magnitude: Int32, duration: Int32): Consumable.ConsumableResource =
        Consumable.bottle(effect, magnitude, duration, "テスト薬")

    def enemy(id: Int32): RayUnit =
        {id = id, ally = false, immobilized = false, alive = true}

    def ctxWith(rayUnits: List[RayUnit]): EffectPlan.PlanCtx =
        {selfId = 0, attackerId = 0, rayUnits = rayUnits,
         amount = {max = 10, dealt = 0, incoming = 0, magic = 0}}

    // 消費アイテム → ルール → Plan。
    def planOf(effect: ConsumableEffect, mag: Int32, dur: Int32,
               ctx: EffectPlan.PlanCtx): List[PlanItem] =
        EffectPlan.planActions(EffectBridge.consumableRule(item(effect, mag, dur)), ctx)

    // ════════════════════════════════════════════════════════
    // 自己使用（self）
    // ════════════════════════════════════════════════════════

    /// きずぐすり(Heal,10) → self に HealAt 10。
    @Test
    def testHeal(): Unit \ Assert =
        Assert.assertEq(expected = PlanItem.HealAt(0, true, 10) :: Nil,
            planOf(ConsumableEffect.Heal, 10, 0, ctxWith(Nil)))

    /// 特効薬(FullHeal) → self に FullHealAt。
    @Test
    def testFullHeal(): Unit \ Assert =
        Assert.assertEq(expected = PlanItem.FullHealAt(0, true) :: Nil,
            planOf(ConsumableEffect.FullHeal, 0, 0, ctxWith(Nil)))

    /// 命の草(MaxHpUp,3) → self に MaxHpUpAt 3。
    @Test
    def testMaxHpUp(): Unit \ Assert =
        Assert.assertEq(expected = PlanItem.MaxHpUpAt(0, true, 3) :: Nil,
            planOf(ConsumableEffect.MaxHpUp, 3, 0, ctxWith(Nil)))

    /// ちから薬(AtkUp,4,3T) → self に StatusAt AtkUp 4 3。
    @Test
    def testAtkUp(): Unit \ Assert =
        Assert.assertEq(expected = PlanItem.StatusAt(0, true, StatusEffect.AtkUp, 4, 3) :: Nil,
            planOf(ConsumableEffect.AtkUp, 4, 3, ctxWith(Nil)))

    /// すばやさ薬(SpdUp,5,3T) → self に StatusAt SpdUp 5 3。
    @Test
    def testSpdUp(): Unit \ Assert =
        Assert.assertEq(expected = PlanItem.StatusAt(0, true, StatusEffect.SpdUp, 5, 3) :: Nil,
            planOf(ConsumableEffect.SpdUp, 5, 3, ctxWith(Nil)))

    /// 蘇生薬(AutoRevive) → onDeath で self に ReviveAt。
    @Test
    def testAutoRevive(): Unit \ Assert =
        Assert.assertEq(expected = PlanItem.ReviveAt(0, true) :: Nil,
            planOf(ConsumableEffect.AutoRevive, 0, 0, ctxWith(Nil)))

    // ════════════════════════════════════════════════════════
    // 投擲（throw・enemy 絞り）
    // ════════════════════════════════════════════════════════

    /// 目潰し薬(BlindHit,25,5T) → 当たった敵#3 に StatusAt HitDown 25 5。
    @Test
    def testBlindHit(): Unit \ Assert =
        Assert.assertEq(expected = PlanItem.StatusAt(3, false, StatusEffect.HitDown, 25, 5) :: Nil,
            planOf(ConsumableEffect.BlindHit, 25, 5, ctxWith(enemy(3) :: Nil)))

    /// 鈍足薬(SpdDownHit,5,5T) → 敵#3 に StatusAt SpdDown 5 5。
    @Test
    def testSpdDownHit(): Unit \ Assert =
        Assert.assertEq(expected = PlanItem.StatusAt(3, false, StatusEffect.SpdDown, 5, 5) :: Nil,
            planOf(ConsumableEffect.SpdDownHit, 5, 5, ctxWith(enemy(3) :: Nil)))

    /// ほころび薬(DefDownHit,5,3T) → 敵#3 に StatusAt DefDown 5 3。
    @Test
    def testDefDownHit(): Unit \ Assert =
        Assert.assertEq(expected = PlanItem.StatusAt(3, false, StatusEffect.DefDown, 5, 3) :: Nil,
            planOf(ConsumableEffect.DefDownHit, 5, 3, ctxWith(enemy(3) :: Nil)))

    /// 火炎瓶(FireBottle,15) → 敵#3 に DamageAt 15。
    @Test
    def testFireBottle(): Unit \ Assert =
        Assert.assertEq(expected = PlanItem.DamageAt(3, false, 15) :: Nil,
            planOf(ConsumableEffect.FireBottle, 15, 0, ctxWith(enemy(3) :: Nil)))

    /// 爆発瓶(BlastBottle,10) は範囲(RoleArea)。現状 planActions は単一 id 解決なので NoOp になる
    /// （範囲展開は runPlan が Board.cellsWithin で行う将来対応。ここではその境界を明示的に固定）。
    @Test
    def testBlastBottleAreaPendingExpansion(): Unit \ Assert =
        Assert.assertEq(expected = PlanItem.NoOp("対象なし（空振り）") :: Nil,
            planOf(ConsumableEffect.BlastBottle, 10, 0, ctxWith(enemy(3) :: Nil)))
}
