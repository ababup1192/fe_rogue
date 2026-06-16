/// 敵固有の特殊能力（enemies.json の effectRule = IDE 合成エディタ簡易形式 JSON）が、
/// 敵 actor 視点（actorIsPlayer=false）で正しい PlanItem に落ちることを固定する。
/// 設計の核心「ally = is-player」: 敵が actor でも player 駒には ally=true、敵自身には ally=false。
/// これにより「毒は player に付く / 吸血は敵自身が回復する」が値として保証される。
mod TestEnemyEffectRule {

    use EffectPlan.PlanItem
    use EffectRule.RayUnit
    use StatusSystem.StatusEffect

    // 簡易形式 JSON → EffectRule（EffectBridge.fromComposer 経由）。
    def ruleOf(s: String): Option[EffectRule.EffectRule] =
        Util.Json.parse(s) |> Result.toOption |> Option.flatMap(EffectBridge.fromComposer)

    // 敵 actor 文脈: actorIsPlayer=false、ray は被弾した player 駒（is-player ⇒ ally=true）1 体。
    // 敵自身の id は 100（player の id 空間と区別するため大きめ）。
    def enemyCtx(targetId: Int32, dmg: Int32): EffectPlan.PlanCtx =
        {selfId = 100, attackerId = 100, actorIsPlayer = false,
         rayUnits = ({id = targetId, ally = true, immobilized = false, alive = true}: RayUnit) :: Nil,
         amount = {max = 30, dealt = dmg, incoming = 0, magic = 0}}

    def planOf(s: String, ctx: EffectPlan.PlanCtx): List[PlanItem] =
        ruleOf(s) |> Option.map(r -> EffectPlan.planActions(r, ctx)) |> Option.getWithDefault(Nil)

    // ════════════════════════════════════════════════════════
    // 戦闘トリガー効果（onHit）
    // ════════════════════════════════════════════════════════

    /// 鈍足付与の敵: onHit で to:enemy（敵から見た相手＝player）に SpdDown 3 を 3T。
    /// player 駒は is-player ⇒ ally=true で返り、PlayerScene 側へ作用する。
    @Test
    def testEnemySpdDownHitsPlayer(): Unit \ Assert =
        let json = "{\"when\":\"onHit\",\"to\":\"enemy\",\"op\":\"spdDown\",\"amount\":3,\"for\":\"turns\",\"forTurns\":3}";
        Assert.assertEq(expected = PlanItem.StatusAt(7, true, StatusEffect.SpdDown, 3, 3) :: Nil,
            planOf(json, enemyCtx(7, 5)))

    /// 命中低下付与の敵: onHit で player に HitDown 5 を 4T。
    @Test
    def testEnemyHitDownHitsPlayer(): Unit \ Assert =
        let json = "{\"when\":\"onHit\",\"to\":\"enemy\",\"op\":\"hitDown\",\"amount\":5,\"for\":\"turns\",\"forTurns\":4}";
        Assert.assertEq(expected = PlanItem.StatusAt(7, true, StatusEffect.HitDown, 5, 4) :: Nil,
            planOf(json, enemyCtx(7, 5)))

    /// 自己回復 on hit（簡易吸血）: to:self healFlat 3 → 敵自身（ally=false）を回復する。
    /// ★ ここが true に漏れると敵の回復が player に乗る致命バグ。actorIsPlayer=false の証拠。
    @Test
    def testEnemySelfHealIsEnemySide(): Unit \ Assert =
        let json = "{\"when\":\"onHit\",\"to\":\"self\",\"op\":\"healFlat\",\"amount\":3}";
        Assert.assertEq(expected = PlanItem.HealAt(100, false, 3) :: Nil,
            planOf(json, enemyCtx(7, 5)))

    // ════════════════════════════════════════════════════════
    // chance パススルー（simpleToFull の小改修）
    // ════════════════════════════════════════════════════════

    /// 簡易form の chance:30 が EffectRule.chance に乗る（確率発動をコードレスで書ける）。
    @Test
    def testChancePassthrough(): Unit \ Assert =
        let json = "{\"when\":\"onHit\",\"to\":\"enemy\",\"op\":\"spdDown\",\"amount\":3,\"for\":\"turns\",\"forTurns\":3,\"chance\":30}";
        Assert.assertEq(expected = Some(30), ruleOf(json) |> Option.map(r -> r#chance))

    /// chance 省略時は既定 100（必ず発動）。
    @Test
    def testChanceDefaultsTo100(): Unit \ Assert =
        let json = "{\"when\":\"onHit\",\"to\":\"enemy\",\"op\":\"spdDown\",\"amount\":3,\"for\":\"turns\",\"forTurns\":3}";
        Assert.assertEq(expected = Some(100), ruleOf(json) |> Option.map(r -> r#chance))
}
