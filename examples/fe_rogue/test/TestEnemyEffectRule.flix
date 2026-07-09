/// 敵固有の特殊能力（enemies.json の effectRule = IDE 合成エディタ簡易形式 JSON）が、
/// 敵 actor 視点（actorIsPlayer=false）で正しい PlanItem に落ちることを固定する。
/// 設計の核心「ally = is-player」: 敵が actor でも player 駒には ally=true、敵自身には ally=false。
/// これにより「毒は player に付く / 吸血は敵自身が回復する」が値として保証される。
mod TestEnemyEffectRule {

    use EffectPlan.PlanItem
    use EffectRule.RayUnit
    use EffectRule.{Op, Trigger, Faction, Flow}
    use EffectDsl.{Amount, AmountBase}
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
    /// player 駒は is-player ⇒ ally=true で返り、PlayerDriver 側へ作用する。
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

    // ════════════════════════════════════════════════════════
    // IDE 合成エディタで足した語彙（lifesteal / dropItem / ringify / 新 trigger）
    // ════════════════════════════════════════════════════════

    // 1 action 目の op を取り出す（簡易 form は単一 action）。
    def firstOp(s: String): Option[Op] =
        ruleOf(s) |> Option.flatMap(r -> List.head(r#actions)) |> Option.map(a -> a#op)

    def firstAmount(s: String): Option[Option[Amount]] =
        ruleOf(s) |> Option.flatMap(r -> List.head(r#actions)) |> Option.map(a -> a#amount)

    /// lifesteal は amount を flat ではなく Pct(dealt, N) で符号化する（{flat:N} に化けない）。
    /// ★ flat に化けると「与ダメージの N%」でなく「固定 N 回復」になる致命的な意味崩れ。
    @Test
    def testLifestealAmountIsPctDealt(): Unit \ Assert =
        let json = "{\"when\":\"onHit\",\"to\":\"self\",\"op\":\"lifesteal\",\"amount\":50}";
        Assert.assertEq(expected = Some(Some(Amount.Pct(AmountBase.Dealt, 50))), firstAmount(json))

    /// lifesteal は敵自身（ally=false）を、与えたダメージ分回復する PlanItem に落ちる。
    @Test
    def testEnemyLifestealHealsEnemySide(): Unit \ Assert =
        let json = "{\"when\":\"onHit\",\"to\":\"self\",\"op\":\"lifesteal\",\"amount\":50}";
        Assert.assertEq(expected = PlanItem.HealAt(100, false, 5) :: Nil,
            planOf(json, enemyCtx(7, 10)))

    /// dropItem は amount を取らず（None）、OpDropItem として decode される。
    @Test
    def testDropItemDecodesWithoutAmount(): Unit \ Assert =
        let json = "{\"when\":\"onHit\",\"to\":\"enemy\",\"op\":\"dropItem\"}";
        Assert.assertEq(expected = Some(Op.OpDropItem), firstOp(json));
        Assert.assertEq(expected = Some(None), firstAmount(json))

    /// ringify も amount を取らず、OpRingify として decode される。
    @Test
    def testRingifyDecodesWithoutAmount(): Unit \ Assert =
        let json = "{\"when\":\"onEnemyTurn\",\"to\":\"enemy\",\"op\":\"ringify\"}";
        Assert.assertEq(expected = Some(Op.OpRingify), firstOp(json));
        Assert.assertEq(expected = Some(None), firstAmount(json))

    /// 新 trigger（onCast / onDamaged / onEnemyTurn）が正しい enum に decode される。
    @Test
    def testNewTriggersDecode(): Unit \ Assert =
        let triggerOf = s -> ruleOf(s) |> Option.map(r -> r#trigger);
        let mk = w -> "{\"when\":\"${w}\",\"to\":\"self\",\"op\":\"healFlat\",\"amount\":1}";
        Assert.assertEq(expected = Some(Trigger.OnCast), triggerOf(mk("onCast")));
        Assert.assertEq(expected = Some(Trigger.OnDamaged), triggerOf(mk("onDamaged")));
        Assert.assertEq(expected = Some(Trigger.OnEnemyTurn), triggerOf(mk("onEnemyTurn")))

    // ════════════════════════════════════════════════════════
    // リング職人の簡易form（IDE 合成エディタ kind:"replaceAttack"）= ringmanRule 等価
    //   ランタイムは enemies.json の簡易form を fromComposer 経由で読む。それが参照実装
    //   EffectBridge.ringmanRule() と各軸で一致することを証明する（Flow/Action は Eq 未導出のため
    //   assertEq で丸ごと比較できず、trigger/chance/cond/flow確率/action を分解して突き合わせる）。
    // ════════════════════════════════════════════════════════

    // enemies.json の "ringman" effectRule と同じ簡易form（手動同期。変えたら enemies.json も）。
    def ringmanSimple(): String =
        "{\"when\":\"onEnemyTurn\",\"to\":\"enemy\",\"op\":\"ringify\",\"chance\":30,\"kind\":\"replaceAttack\"}"

    // 簡易form 経由のルール（本番経路）／参照実装。
    def ringmanSimpleRule(): Option[EffectRule.EffectRule] = ruleOf(ringmanSimple())
    def ringmanRefRule(): EffectRule.EffectRule = EffectBridge.ringmanRule()

    def adjCtx(adj: Bool): EffectDsl.PredCtx =
        {selfHpPct = 100, targetHpPct = 100, targetAlive = true, equippedIsRogue = false, adjacent = adj}

    // flow:replaceAttack の先頭 action を取り出す。
    def replaceActionOf(rule: EffectRule.EffectRule): Option[EffectRule.Action] =
        rule#flow |> Option.flatMap(f -> match f {
            case Flow.ReplaceAttack(_, acts) => List.head(acts)
            case _                           => None
        })

    def replaceDecideOf(rule: EffectRule.EffectRule, roll: Int32): Bool =
        rule#flow |> Option.map(f -> EffectFlow.replaceDecision(f, roll)) |> Option.getWithDefault(false)

    /// 本番経路（簡易form）が参照実装 ringmanRule() と各軸で一致する＝「生きた等価証明」。
    /// 片方を変えてもう片方とズレれば赤くなる（コメント上の「等価」をコードで担保）。
    @Test
    def testRingmanSimpleMatchesRingmanRule(): Unit \ Assert =
        let ref = ringmanRefRule();
        let s   = ringmanSimpleRule();
        // trigger / top-level chance
        Assert.assertEq(expected = Some(ref#trigger), s |> Option.map(x -> x#trigger));
        Assert.assertEq(expected = Some(ref#chance), s |> Option.map(x -> x#chance));
        // cond（adjacent 真偽での評価が一致）
        let evalC = (rule, adj) -> EffectDsl.evalPredicate(rule#cond, adjCtx(adj));
        Assert.assertEq(expected = Some((evalC(ref, true), evalC(ref, false))),
            s |> Option.map(x -> (evalC(x, true), evalC(x, false))));
        // 差し替え確率（roll 境界での判定が一致）
        Assert.assertEq(expected = Some((replaceDecideOf(ref, 29), replaceDecideOf(ref, 30))),
            s |> Option.map(x -> (replaceDecideOf(x, 29), replaceDecideOf(x, 30))));
        // 差し替え action の op / faction が一致
        let refAct = replaceActionOf(ref);
        Assert.assertEq(expected = (refAct |> Option.map(a -> a#op), refAct |> Option.map(a -> a#to#faction)),
            (s |> Option.flatMap(replaceActionOf) |> Option.map(a -> a#op),
             s |> Option.flatMap(replaceActionOf) |> Option.map(a -> a#to#faction)))

    /// 絶対値の固定: trigger=onEnemyTurn、top-level chance=100（replaceForm が出さない＝常時発火）。
    @Test
    def testRingmanSimpleTriggerAndChance(): Unit \ Assert =
        let r = ringmanSimpleRule();
        Assert.assertEq(expected = Some(Trigger.OnEnemyTurn), r |> Option.map(x -> x#trigger));
        Assert.assertEq(expected = Some(100), r |> Option.map(x -> x#chance))

    /// cond は Adjacent: 隣接で成立、非隣接で不成立（replaceForm が "if":"adjacent" を暗黙付与）。
    @Test
    def testRingmanSimpleCondAdjacent(): Unit \ Assert =
        let cond = ringmanSimpleRule() |> Option.map(r -> r#cond);
        let evalWith = adj -> cond |> Option.map(c -> EffectDsl.evalPredicate(c, adjCtx(adj)));
        Assert.assertEq(expected = (Some(true), Some(false)), (evalWith(true), evalWith(false)))

    /// flow は replaceAttack で差し替え確率 30%: roll 29 成立 / 30 不成立。
    @Test
    def testRingmanSimpleReplaceChance(): Unit \ Assert =
        let decide = roll -> ringmanSimpleRule() |> Option.map(r -> replaceDecideOf(r, roll))
                                                 |> Option.getWithDefault(false);
        Assert.assertEq(expected = (true, false), (decide(29), decide(30)))

    /// 差し替え先 action は ringify を敵(=player駒)へ。amount 無し。parse 失敗なら None で赤くなる。
    @Test
    def testRingmanSimpleReplaceAction(): Unit \ Assert =
        let act = ringmanSimpleRule() |> Option.flatMap(replaceActionOf);
        Assert.assertEq(expected = Some(Op.OpRingify), act |> Option.map(a -> a#op));
        Assert.assertEq(expected = Some(Faction.FactionEnemy), act |> Option.map(a -> a#to#faction));
        Assert.assertEq(expected = Some(None), act |> Option.map(a -> a#amount))

    /// 差し替え action を planAction すると ringify の CustomAt(targetId, ally=true) に落ちる。
    @Test
    def testRingmanSimpleRoutesToCustom(): Unit \ Assert =
        let items = ringmanSimpleRule() |> Option.flatMap(replaceActionOf)
                    |> Option.map(a -> EffectPlan.planAction(a, replaceCtx(7)))
                    |> Option.getWithDefault(Nil);
        Assert.assertEq(expected = PlanItem.CustomAt("ringify", 7, true) :: Nil, items)

    // ringify 差し替えの PlanCtx（敵 actor 視点、対象=player駒 id）。
    def replaceCtx(targetId: Int32): EffectPlan.PlanCtx =
        {selfId = 100, attackerId = 100, actorIsPlayer = false,
         rayUnits = ({id = targetId, ally = true, immobilized = false, alive = true}: RayUnit) :: Nil,
         amount = {max = 30, dealt = 0, incoming = 0, magic = 0}}
}
