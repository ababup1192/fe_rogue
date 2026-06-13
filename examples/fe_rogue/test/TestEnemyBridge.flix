/// EffectBridge.ringmanRule（敵特殊 RingMan）を固定する。
/// 敵特殊で唯一 replaceAttack（攻撃差し替え）が要る効果。隣接条件・30%差し替え・
/// 差し替え先が ringify（持ち物指輪化）であることを確認する。
/// （詠唱=staffRule(Bind/Stopgap)・瓶投げ=consumableRule を onEnemyTurn で再利用するだけなので
///  個別ブリッジは不要。RingMan のみが新規。）
mod TestEnemyBridge {

    use EffectRule.RayUnit
    use EffectPlan.PlanItem

    /// RingMan は隣接時のみ。adjacent=true で cond 成立、false で不成立。
    @Test
    def testRingmanCondAdjacent(): Unit \ Assert =
        let cond = EffectBridge.ringmanRule()#cond;
        let ctxAdj = {selfHpPct = 100, targetHpPct = 100, targetAlive = true,
                      equippedIsRogue = false, adjacent = true};
        let ctxFar = {selfHpPct = 100, targetHpPct = 100, targetAlive = true,
                      equippedIsRogue = false, adjacent = false};
        Assert.assertEq(expected = (true, false),
            (EffectDsl.evalPredicate(cond, ctxAdj), EffectDsl.evalPredicate(cond, ctxFar)))

    /// flow:replaceAttack は roll 29(<30) で差し替え成立、roll 30 で不成立。followUp ではない。
    @Test
    def testRingmanReplaceChance(): Unit \ Assert =
        let flow = EffectBridge.ringmanRule()#flow;
        let decide = roll -> flow
                        |> Option.map(f -> EffectFlow.replaceDecision(f, roll))
                        |> Option.getWithDefault(false);
        Assert.assertEq(expected = (true, false), (decide(29), decide(30)))

    /// 差し替え先 do[] は ringify 1 件。applyReplace（roll29 成立）が RequestReplace に 1 アクションを載せる。
    @Test
    def testRingmanReplaceAction(): Unit \ Assert =
        let flow = EffectBridge.ringmanRule()#flow;
        let tags = flow
                    |> Option.map(f -> List.map(flowTag, EffectFlow.applyReplace(f, 29)))
                    |> Option.getWithDefault("none" :: Nil);
        Assert.assertEq(expected = "replace:1" :: Nil, tags)

    def flowTag(fe: EffectFlow.FlowEffect): String = match fe {
        case EffectFlow.FlowEffect.MarkFollowUpUsed       => "mark"
        case EffectFlow.FlowEffect.RequestAttack(_, ts)   => "attack:times=${ts}"
        case EffectFlow.FlowEffect.RequestReplace(acts)   => "replace:${List.length(acts)}"
        case EffectFlow.FlowEffect.NoFlow                 => "noflow"
    }
}
