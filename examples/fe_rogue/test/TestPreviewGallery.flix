/// 全カテゴリの効果 → 日本語1文プレビュー（previewRule）を横断的に固定する。
/// 既存データ → ブリッジ → EffectRule → 日本語、という「IDE がアイテムに見せる文」を
/// 消費/武器/指輪/杖/敵特殊すべてで確認する。DSL の核心「日本語でプログラミング」の体験ギャラリー。
mod TestPreviewGallery {

    use Consumable.ConsumableEffect
    use WeaponCatalog.WeaponEffect
    use Ring.RingEffect
    use Staff.StaffEffect

    def has(needle: String, hay: String): Bool = String.contains({substr = needle}, hay)

    // 各ブリッジ → previewRule。
    def pc(effect: ConsumableEffect, mag: Int32, dur: Int32): String =
        EffectRule.previewRule(EffectBridge.consumableRule(Consumable.bottle(effect, mag, dur, "薬")))
    def pw(effect: WeaponEffect, v: Int32): String =
        EffectRule.previewRule(EffectBridge.weaponRule(effect, v))
    def pr(effect: RingEffect, power: Int32): String =
        EffectRule.previewRule(EffectBridge.ringRule(effect, power))
    def ps(effect: StaffEffect): String =
        EffectRule.previewRule(EffectBridge.staffRule(effect))

    // ════════════════════════════════════════════════════════
    // 消費アイテム
    // ════════════════════════════════════════════════════════

    /// きずぐすり / 火炎瓶 / ちから薬 の日本語。
    @Test
    def testConsumablePreviews(): Unit \ Assert =
        Assert.assertEq(expected = (true, true, true),
            (has("HP を 10 回復する", pc(ConsumableEffect.Heal, 10, 0)),
             has("15 の固定ダメージ", pc(ConsumableEffect.FireBottle, 15, 0)),
             has("攻撃力を 4 上げる", pc(ConsumableEffect.AtkUp, 4, 3))))

    // ════════════════════════════════════════════════════════
    // 武器
    // ════════════════════════════════════════════════════════

    /// はやぶさ（追撃文）/ 血吸い（吸収文）/ 背水（威力文）。
    @Test
    def testWeaponPreviews(): Unit \ Assert =
        Assert.assertEq(expected = (true, true, true),
            (has("もう一度攻撃する", pw(WeaponEffect.BraveOnSpeed, 3)),
             has("与えたダメージの 30% を回復する", pw(WeaponEffect.Lifesteal, 30)),
             has("威力を", pw(WeaponEffect.Desperation, 30))))

    // ════════════════════════════════════════════════════════
    // 指輪
    // ════════════════════════════════════════════════════════

    /// まもり（守備＋常時補正）/ いやし（ターン回復）/ 追撃（flow）。
    @Test
    def testRingPreviews(): Unit \ Assert =
        let guard = pr(RingEffect.Guard, 3);
        Assert.assertEq(expected = (true, true, true, true),
            (has("守備を 3 上げる", guard),
             has("装備しているあいだ", guard),
             has("HP を 2 回復する", pr(RingEffect.Mend, 2)),
             has("もう一度攻撃", pr(RingEffect.Pursuit, 0))))

    // ════════════════════════════════════════════════════════
    // 杖（rayFirst）
    // ════════════════════════════════════════════════════════

    /// 回復（魔力+10・最初に当たった相手）/ かなしばり（停止・攻撃を受けるまで）。
    @Test
    def testStaffPreviews(): Unit \ Assert =
        let heal = ps(StaffEffect.Heal);
        let bind = ps(StaffEffect.Bind);
        Assert.assertEq(expected = (true, true, true, true),
            (has("最初に当たった相手", heal),
             has("魔力+10 回復する", heal),
             has("完全に動けなくする", bind),
             has("攻撃を受けるまで", bind)))

    // ════════════════════════════════════════════════════════
    // 敵特殊
    // ════════════════════════════════════════════════════════

    /// RingMan: replaceAttack の日本語（通常攻撃をやめて差し替える）。
    @Test
    def testEnemyPreview(): Unit \ Assert =
        Assert.assertEq(expected = true,
            has("通常攻撃をやめて差し替える", EffectRule.previewRule(EffectBridge.ringmanRule())))
}
