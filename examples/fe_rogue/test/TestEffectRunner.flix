/// EffectRunner.runPlan のディスパッチを記録 handler で固定する。
/// アキュムレータに「どの副作用へ・どの順で・どの引数で」を文字列で積み、実 Scene 抜きで検証する。
/// JSON → Plan → runPlan の全経路を1本で通す統合的な純粋テスト（s = List[String]、ef = Pure）。
mod TestEffectRunner {

    use EffectPlan.PlanItem
    use EffectRule.RayUnit

    def decodeStr(s: String): Option[EffectRule.EffectRule] =
        Util.Json.parse(s) |> Result.toOption |> Option.flatMap(EffectRuleCodec.decodeRule)

    def unit(id: Int32, ally: Bool): RayUnit =
        {id = id, ally = ally, immobilized = false, alive = true}

    def ctxWith(rayUnits: List[RayUnit]): EffectPlan.PlanCtx =
        {selfId = 1, attackerId = 9, rayUnits = rayUnits,
         amount = {max = 30, dealt = 20, incoming = 12, magic = 7}}

    /// 各 handler が「呼び出しを表す文字列」を先頭に積むだけの記録 handler（純粋・効果なし）。
    def recordHandlers(): EffectRunner.PlanHandlers[List[String], {}] = {
        heal       = (acc, id, n)        -> "heal:${id}:${n}" :: acc,
        fullHeal   = (acc, id)           -> "fullHeal:${id}" :: acc,
        damage     = (acc, id, n)        -> "damage:${id}:${n}" :: acc,
        maxHpUp    = (acc, id, n)        -> "maxHpUp:${id}:${n}" :: acc,
        status     = (acc, id, se, m, t) -> "status:${id}:${se}:${m}:${t}" :: acc,
        immobilize = (acc, id)           -> "immobilize:${id}" :: acc,
        revive     = (acc, id)           -> "revive:${id}" :: acc,
        custom     = (acc, op, id)       -> "custom:${op}:${id}" :: acc,
        sfx        = (acc, name)         -> "sfx:${name}" :: acc,
        noOp       = (acc, reason)       -> "noOp:${reason}" :: acc
    }

    // JSON → Plan → runPlan の記録（積んだ順を反転して時系列に戻す）。
    def fire(json: String, ctx: EffectPlan.PlanCtx): List[String] =
        let items = decodeStr(json)
                        |> Option.map(r -> EffectPlan.planActions(r, ctx))
                        |> Option.getWithDefault(Nil);
        EffectRunner.runPlan(recordHandlers(), items, Nil) |> List.reverse

    // ════════════════════════════════════════════════════════

    /// ちから薬: status handler に (self=1, AtkUp, 4, 3) → 続けて sfx cure。順序も保つ。
    @Test
    def testRunPowerPotion(): Unit \ Assert =
        let json = "{\"when\":\"onUse\",\"deliver\":[\"self\"],\"do\":[{\"to\":{\"role\":\"self\"},\"op\":\"atkUp\",\"amount\":{\"flat\":4},\"for\":{\"turns\":3},\"sfx\":\"cure\"}]}";
        Assert.assertEq(
            expected = "status:1:AtkUp:4:3" :: "sfx:cure" :: Nil,
            fire(json, ctxWith(Nil)))

    /// 火炎瓶: damage handler に (敵#3, 15) → sfx magic。
    @Test
    def testRunFireBottle(): Unit \ Assert =
        let json = "{\"when\":\"onUse\",\"deliver\":[\"throw\"],\"do\":[{\"to\":{\"role\":\"target\",\"faction\":\"enemy\"},\"op\":\"damageFlat\",\"amount\":{\"flat\":15},\"sfx\":\"magic\"}]}";
        Assert.assertEq(
            expected = "damage:3:15" :: "sfx:magic" :: Nil,
            fire(json, ctxWith(unit(3, false) :: Nil)))

    /// 回復の杖: heal handler に (味方#4, 魔力7+10=17)。
    @Test
    def testRunHealStaff(): Unit \ Assert =
        let json = "{\"when\":\"onCast\",\"deliver\":[\"throw\"],\"do\":[{\"to\":{\"role\":\"target\"},\"op\":\"healFlat\",\"amount\":{\"statPlus\":{\"stat\":\"magic\",\"value\":10}}}]}";
        Assert.assertEq(
            expected = "heal:4:17" :: Nil,
            fire(json, ctxWith(unit(4, true) :: Nil)))

    /// 一時しのぎ: 2 アクション（immobilize → custom warpToStairs）を順に振り分ける（複文の適用順）。
    @Test
    def testRunStopgapOrder(): Unit \ Assert =
        let json = "{\"when\":\"onCast\",\"deliver\":[\"throw\"],\"do\":[{\"to\":{\"role\":\"target\",\"faction\":\"ally\"},\"op\":\"immobilize\",\"for\":\"untilHit\"},{\"to\":{\"role\":\"target\",\"faction\":\"ally\"},\"op\":\"warpToStairs\"}]}";
        Assert.assertEq(
            expected = "immobilize:4" :: "custom:warpToStairs:4" :: Nil,
            fire(json, ctxWith(unit(4, true) :: Nil)))

    /// 空振り（対象なし）は noOp handler に流れ、HP 等は一切触らない。
    @Test
    def testRunNoOp(): Unit \ Assert =
        let json = "{\"when\":\"onCast\",\"deliver\":[\"throw\"],\"do\":[{\"to\":{\"role\":\"target\",\"faction\":\"enemy\"},\"op\":\"damageFlat\",\"amount\":{\"flat\":10}}]}";
        Assert.assertEq(
            expected = "noOp:対象なし（空振り）" :: Nil,
            fire(json, ctxWith(Nil)))
}
