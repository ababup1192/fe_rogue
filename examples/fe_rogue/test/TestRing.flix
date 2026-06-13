/// Ring の純粋ロジック（ステータス補正・各効果量・しきい値・追撃判定・effect 文字列・decode）を固定する。
///
/// 乱数を引く 15% 追撃はシーン経由でモック発火できないため、判定は純関数
/// `CombatScene.shouldFollowUp` と `Ring.*` を直接テストする（境界値中心）。
mod TestRing {

    use Ring.RingEffect

    // ════════════════════════════════════════════════════════
    // フィクスチャ
    // ════════════════════════════════════════════════════════

    /// effect と power だけ変えたテスト用指輪。sprite/name/description は固定ダミー。
    def ring(effect: RingEffect, power: Int32): Ring.RingResource =
        {name = "テスト指輪", effect = effect, power = power,
         description = "",
         sprite = {texture = "t", hframes = 1, vframes = 1, frame = 0,
                   offset = {x = 0.0, y = 0.0}, scale = {x = 1.0, y = 1.0}, flipForFacing = false}, effectRule = None}

    // ════════════════════════════════════════════════════════
    // bonuses: 装備中指輪のステータス補正（命中・必殺は触らない）
    // ════════════════════════════════════════════════════════

    /// ちから(Power,3) は攻撃 +3、他のステータスは 0。
    @Test
    def testBonusesPower(): Unit \ Assert =
        let b = Ring.bonuses(Some(ring(RingEffect.Power, 3)));
        Assert.assertEq(expected = (3, 0, 0, 0, 0),
            (b#attack, b#speed, b#defense, b#skill, b#luck))

    /// すばやさ(Swift,3) は速さ +3。
    @Test
    def testBonusesSwift(): Unit \ Assert =
        Assert.assertEq(expected = 3, Ring.bonuses(Some(ring(RingEffect.Swift, 3)))#speed)

    /// まもり(Guard,3) は防御 +3。
    @Test
    def testBonusesGuard(): Unit \ Assert =
        Assert.assertEq(expected = 3, Ring.bonuses(Some(ring(RingEffect.Guard, 3)))#defense)

    /// さび(Power,-1) は攻撃 -1（むしろ弱い）。負の power も素直に効く。
    @Test
    def testBonusesNegativePower(): Unit \ Assert =
        Assert.assertEq(expected = -1, Ring.bonuses(Some(ring(RingEffect.Power, -1)))#attack)

    /// 特殊効果(Pursuit) / 未装備(None) はステータス補正 0。
    @Test
    def testBonusesNoStatEffects(): Unit \ Assert =
        let pursuit = Ring.bonuses(Some(ring(RingEffect.Pursuit, 0)))#attack;
        let none    = Ring.bonuses(None)#attack;
        Assert.assertEq(expected = (0, 0), (pursuit, none))

    // ════════════════════════════════════════════════════════
    // 各効果量: Mend / Lifesteal / Finisher しきい値
    // ════════════════════════════════════════════════════════

    /// Mend(2) のターン回復量は 2。Mend 以外 / 未装備は 0。
    @Test
    def testMendAmount(): Unit \ Assert =
        Assert.assertEq(expected = (2, 0, 0),
            (Ring.mendAmount(Some(ring(RingEffect.Mend, 2))),
             Ring.mendAmount(Some(ring(RingEffect.Power, 9))),
             Ring.mendAmount(None)))

    /// Lifesteal(5) の撃破回復量は 5。Lifesteal 以外は 0。
    @Test
    def testLifestealAmount(): Unit \ Assert =
        Assert.assertEq(expected = (5, 0),
            (Ring.lifestealAmount(Some(ring(RingEffect.Lifesteal, 5))),
             Ring.lifestealAmount(Some(ring(RingEffect.Mend, 5)))))

    /// Finisher(30) のしきい値は Some(30)。Finisher 以外は None。
    @Test
    def testFinisherThreshold(): Unit \ Assert =
        Assert.assertEq(expected = (Some(30), None),
            (Ring.finisherThreshold(Some(ring(RingEffect.Finisher, 30))),
             Ring.finisherThreshold(Some(ring(RingEffect.Power, 30)))))

    /// とどめ判定: 残 HP がちょうど最大の 30%（3/10）なら発動（境界は「以下」で含む）。
    /// 31%（4/10 で 40% > 30%）は発動しない。しきい値 None は常に false。
    @Test
    def testFinisherTriggers(): Unit \ Assert =
        Assert.assertEq(expected = (true, false, false),
            (Ring.finisherTriggers(3, 10, Some(30)),
             Ring.finisherTriggers(4, 10, Some(30)),
             Ring.finisherTriggers(1, 10, None)))

    // ════════════════════════════════════════════════════════
    // shouldFollowUp: 追撃判定（速さ差+3・15%・未追撃・追撃リング）
    // ════════════════════════════════════════════════════════

    /// 速さ 10 vs 7（差ちょうど +3）・roll 0（<15）・追撃リング所持・未追撃 → 追撃する。
    @Test
    def testShouldFollowUpAtThreshold(): Unit \ Assert =
        Assert.assertEq(expected = true,
            CombatScene.shouldFollowUp(10, 7, 0, true, false))

    /// 速さ差が +2（10 vs 8）だと、ほかの条件が揃っても追撃しない（速さ差の境界）。
    @Test
    def testShouldFollowUpSpeedTooClose(): Unit \ Assert =
        Assert.assertEq(expected = false,
            CombatScene.shouldFollowUp(10, 8, 0, true, false))

    /// roll 14 は <15 で当たり、roll 15 は外れ（15% の境界）。
    @Test
    def testShouldFollowUpRollBoundary(): Unit \ Assert =
        Assert.assertEq(expected = (true, false),
            (CombatScene.shouldFollowUp(10, 0, 14, true, false),
             CombatScene.shouldFollowUp(10, 0, 15, true, false)))

    /// すでに追撃済み（alreadyFollowedUp=true）なら、条件が揃っても追撃しない（二重発動防止の核）。
    @Test
    def testShouldFollowUpNoDoubleFollow(): Unit \ Assert =
        Assert.assertEq(expected = false,
            CombatScene.shouldFollowUp(10, 0, 0, true, true))

    /// 追撃リングを持っていない（hasPursuit=false）なら追撃しない。
    @Test
    def testShouldFollowUpNoRing(): Unit \ Assert =
        Assert.assertEq(expected = false,
            CombatScene.shouldFollowUp(10, 0, 0, false, false))

    // ════════════════════════════════════════════════════════
    // effect 文字列の round-trip と decode の既定値
    // ════════════════════════════════════════════════════════

    /// `effectToString` → `parseEffect` で同じ enum に戻る（4 種を代表で確認）。
    @Test
    def testEffectRoundTrip(): Unit \ Assert =
        let rt = e -> Ring.parseEffect(Ring.effectToString(e));
        Assert.assertEq(
            expected = (Ok(RingEffect.Pursuit), Ok(RingEffect.Lifesteal),
                        Ok(RingEffect.Finisher), Ok(RingEffect.Trivial)),
            (rt(RingEffect.Pursuit), rt(RingEffect.Lifesteal),
             rt(RingEffect.Finisher), rt(RingEffect.Trivial)))

    /// 未知の effect 文字列は `Err`（JSON 直編集の typo を起動時に発覚させる）。
    @Test
    def testParseEffectUnknown(): Unit \ Assert =
        Assert.assertEq(expected = Err("Bogus"), Ring.parseEffect("Bogus"))
}
