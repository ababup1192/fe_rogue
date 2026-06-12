/// EffectRuleCodec の JSON decode を固定する。効果 JSON 文字列 → EffectRule を
/// パースし、日本語プレビュー・既定値・述語評価・未知値の None を検証する。
/// 「特殊効果が JSON データとして宣言でき、コードに触れず増やせる」ことの実証。
mod TestEffectRuleCodec {

    // JSON 文字列 → EffectRule（パース失敗・decode 失敗はいずれも None）。
    def decodeStr(s: String): Option[EffectRule.EffectRule] =
        Util.Json.parse(s) |> Result.toOption |> Option.flatMap(EffectRuleCodec.decodeRule)

    // decode 成功なら日本語プレビュー、失敗なら番兵文字列。
    def prev(s: String): String =
        decodeStr(s) |> Option.map(EffectRule.previewRule) |> Option.getWithDefault("DECODE-FAILED")

    def has(needle: String, hay: String): Bool = String.contains({substr = needle}, hay)

    // 述語評価用の固定文脈（自HP25% 敵HP40% 生存 ローグ 隣接）。
    def predCtx(): EffectDsl.PredCtx =
        {selfHpPct = 25, targetHpPct = 40, targetAlive = true,
         equippedIsRogue = true, adjacent = true}

    def evalCond(s: String): Bool =
        decodeStr(s)
            |> Option.map(r -> EffectDsl.evalPredicate(r#cond, predCtx()))
            |> Option.getWithDefault(false)

    // ════════════════════════════════════════════════════════
    // 基本 decode → 日本語プレビュー
    // ════════════════════════════════════════════════════════

    /// ちから薬 JSON を decode → 「つかって…攻撃力を 4…3 ターン」。
    @Test
    def testDecodePowerPotion(): Unit \ Assert =
        let json = "{\"when\":\"onUse\",\"deliver\":[\"self\"],\"do\":[{\"to\":{\"role\":\"self\"},\"op\":\"atkUp\",\"amount\":{\"flat\":4},\"for\":{\"turns\":3},\"sfx\":\"cure\"}]}";
        let p = prev(json);
        Assert.assertEq(expected = (true, true, true),
            (has("つかって", p), has("攻撃力を 4", p), has("3 ターン", p)))

    /// 死神 JSON（if + finisher）を decode → 「必ず必殺にする」。
    @Test
    def testDecodeFinisher(): Unit \ Assert =
        let json = "{\"when\":\"onAttack\",\"if\":{\"targetHpPctAtMost\":30},\"do\":[{\"to\":{\"role\":\"target\"},\"op\":\"finisher\"}]}";
        Assert.assertEq(expected = true, has("必ず必殺にする", prev(json)))

    /// 血吸い JSON（amount: pct of dealt）を decode → 「与えたダメージの 30%」。
    @Test
    def testDecodeLifestealPct(): Unit \ Assert =
        let json = "{\"when\":\"onHit\",\"do\":[{\"to\":{\"role\":\"attacker\"},\"op\":\"lifesteal\",\"amount\":{\"pct\":{\"base\":\"dealt\",\"value\":30}}}]}";
        Assert.assertEq(expected = true, has("30%", prev(json)))

    /// 回復の杖 JSON（faction 省略 = rayFirst, amount: statPlus magic）を decode。
    @Test
    def testDecodeHealStaffRayFirst(): Unit \ Assert =
        let json = "{\"when\":\"onCast\",\"deliver\":[\"throw\"],\"do\":[{\"to\":{\"role\":\"target\"},\"op\":\"healFlat\",\"amount\":{\"statPlus\":{\"stat\":\"magic\",\"value\":10}}}]}";
        let p = prev(json);
        Assert.assertEq(expected = (true, true),
            (has("最初に当たった相手", p), has("魔力+10", p)))

    /// はやぶさ JSON（flow: followUp brave）を decode → flow 文。
    @Test
    def testDecodeFollowUp(): Unit \ Assert =
        let json = "{\"when\":\"onAttack\",\"flow\":{\"followUp\":{\"trigger\":\"brave\"}}}";
        Assert.assertEq(expected = true, has("もう一度攻撃する", prev(json)))

    // ════════════════════════════════════════════════════════
    // 述語 if（allOf/anyOf）decode → evalPredicate
    // ════════════════════════════════════════════════════════

    /// 盗人の if {allOf:[equippedIsRogue, targetAlive]} は ローグ&生存 で true。
    @Test
    def testDecodeAllOfCond(): Unit \ Assert =
        let json = "{\"when\":\"onHit\",\"if\":{\"allOf\":[\"equippedIsRogue\",\"targetAlive\"]},\"do\":[{\"to\":{\"role\":\"target\",\"faction\":\"enemy\"},\"op\":\"dropItem\"}]}";
        Assert.assertEq(expected = true, evalCond(json))

    /// 深さ1の積和 allOf[targetAlive, anyOf[selfHp<=30(真), targetHp<=30(偽)]] は true。
    @Test
    def testDecodeNestedCond(): Unit \ Assert =
        let json = "{\"when\":\"onAttack\",\"if\":{\"allOf\":[\"targetAlive\",{\"anyOf\":[{\"selfHpPctAtMost\":30},{\"targetHpPctAtMost\":30}]}]},\"do\":[{\"to\":{\"role\":\"target\"},\"op\":\"finisher\"}]}";
        Assert.assertEq(expected = true, evalCond(json))

    /// 配列 if（暗黙 allOf）も decode できる: [adjacent] は隣接 true で true。
    @Test
    def testDecodeArrayImplicitAllOf(): Unit \ Assert =
        let json = "{\"when\":\"onEnemyTurn\",\"if\":[\"adjacent\"],\"do\":[{\"to\":{\"role\":\"target\"},\"op\":\"immobilize\"}]}";
        Assert.assertEq(expected = true, evalCond(json))

    // ════════════════════════════════════════════════════════
    // 既定値 / 異常系
    // ════════════════════════════════════════════════════════

    /// chance 省略時は既定 100。
    @Test
    def testDefaultChance(): Unit \ Assert =
        let json = "{\"when\":\"onHit\",\"do\":[{\"to\":{\"role\":\"target\",\"faction\":\"enemy\"},\"op\":\"damageFlat\",\"amount\":{\"flat\":10}}]}";
        let c = decodeStr(json) |> Option.map(r -> r#chance) |> Option.getWithDefault(-1);
        Assert.assertEq(expected = 100, c)

    /// 未知の when 文字列は decode 失敗（None）。typo を起動時に発覚させる。
    @Test
    def testUnknownTriggerIsNone(): Unit \ Assert =
        Assert.assertEq(expected = true,
            Option.isEmpty(decodeStr("{\"when\":\"bogus\"}")))

    /// 未知の op も decode 失敗（None）。
    @Test
    def testUnknownOpIsNone(): Unit \ Assert =
        let json = "{\"when\":\"onUse\",\"do\":[{\"to\":{\"role\":\"self\"},\"op\":\"teleportToMoon\"}]}";
        Assert.assertEq(expected = true, Option.isEmpty(decodeStr(json)))
}
