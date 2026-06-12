/// EffectRunner.runPlan のディスパッチを recorder handler で固定する。
/// 実 Scene を立ち上げずに「PlanItem 列がどの副作用へ・どの順で・どの引数で振り分けられるか」を
/// 検証する。JSON → Plan → runPlan の全経路を1本で通す統合的な純粋テスト。
mod TestEffectRunner {

    use EffectPlan.PlanItem
    use EffectRule.RayUnit
    use StatusSystem.StatusEffect

    def decodeStr(s: String): Option[EffectRule.EffectRule] =
        Util.Json.parse(s) |> Result.toOption |> Option.flatMap(EffectRuleCodec.decodeRule)

    def unit(id: Int32, ally: Bool): RayUnit =
        {id = id, ally = ally, immobilized = false, alive = true}

    def ctxWith(rayUnits: List[RayUnit]): EffectPlan.PlanCtx =
        {selfId = 1, attackerId = 9, rayUnits = rayUnits,
         amount = {max = 30, dealt = 20, incoming = 12, magic = 7}}

    /// 与えた PlanItem 列を runPlan に流し、handler 呼び出しを文字列で記録して返す。
    /// region で副作用が完結するため戻りは Pure。
    def record(items: List[PlanItem]): List[String] =
        region rc {
            let log = Ref.fresh(rc, (Nil: List[String]));
            let push = s -> Ref.put(s :: Ref.get(log), log);
            let h = {
                heal       = (id, n)       -> push("heal:${id}:${n}"),
                fullHeal   = id            -> push("fullHeal:${id}"),
                damage     = (id, n)       -> push("damage:${id}:${n}"),
                maxHpUp    = (id, n)       -> push("maxHpUp:${id}:${n}"),
                status     = (id, se, m, t) -> push("status:${id}:${se}:${m}:${t}"),
                immobilize = id            -> push("immobilize:${id}"),
                revive     = id            -> push("revive:${id}"),
                custom     = (op, id)      -> push("custom:${op}:${id}"),
                sfx        = name          -> push("sfx:${name}"),
                noOp       = reason        -> push("noOp:${reason}")
            };
            EffectRunner.runPlan(h, items);
            Ref.get(log) |> List.reverse
        }

    // JSON → Plan → runPlan の記録。
    def fire(json: String, ctx: EffectPlan.PlanCtx): List[String] =
        decodeStr(json)
            |> Option.map(r -> EffectPlan.planActions(r, ctx))
            |> Option.getWithDefault(Nil)
            |> record

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
