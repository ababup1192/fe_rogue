/// EffectFlow の followUp/replace 判定と secondHitAmountCtx を固定する。
/// 既存 CombatScene.braveFollowUp/shouldFollowUp と同じ境界を DSL 文脈で確認し、
/// 2 撃目の効果量が純粋に導けることを示す（flow と amount の実行時結合を切った証拠）。
mod TestEffectFlow {

    use EffectRule.{Flow, FollowKind}
    use EffectDsl.{Amount, AmountBase}

    // followUp 判定用の文脈。各テストで上書きするフィールドだけ変える。
    def fctx(atkSpd: Int32, defSpd: Int32, roll: Int32, used: Bool,
             brave: Option[Int32], pursuit: Bool): EffectFlow.FollowUpCtx =
        {atkSpd = atkSpd, defSpd = defSpd, roll = roll,
         followUpUsed = used, brave = brave, pursuit = pursuit}

    // ════════════════════════════════════════════════════════
    // followUp: brave（はやぶさ＝速さ差ブレイブ、乱数なし）
    // ════════════════════════════════════════════════════════

    /// brave 閾値3: 速さ差ちょうど+3 で追撃、+2 では追撃しない（境界「以上」）。
    @Test
    def testBraveThreshold(): Unit \ Assert =
        let f = Flow.FollowUp(FollowKind.Brave);
        Assert.assertEq(expected = (true, false),
            (EffectFlow.followUpDecision(f, fctx(10, 7, 0, false, Some(3), false)),
             EffectFlow.followUpDecision(f, fctx(10, 8, 0, false, Some(3), false))))

    /// 既に追撃済み(used=true)なら brave 条件が揃っても追撃しない（二重発動防止）。
    /// brave 閾値 None（はやぶさ以外）は常に false。
    @Test
    def testBraveBlocked(): Unit \ Assert =
        let f = Flow.FollowUp(FollowKind.Brave);
        Assert.assertEq(expected = (false, false),
            (EffectFlow.followUpDecision(f, fctx(10, 0, 0, true, Some(3), false)),
             EffectFlow.followUpDecision(f, fctx(10, 0, 0, false, None, false))))

    // ════════════════════════════════════════════════════════
    // followUp: pursuit（追撃リング＝速さ差+3 かつ 15%）
    // ════════════════════════════════════════════════════════

    /// pursuit: 速さ差+3・roll 14(<15)・リング所持・未追撃 → 追撃。roll 15 は外れ。
    @Test
    def testPursuitRollBoundary(): Unit \ Assert =
        let f = Flow.FollowUp(FollowKind.Pursuit);
        Assert.assertEq(expected = (true, false),
            (EffectFlow.followUpDecision(f, fctx(10, 7, 14, false, None, true)),
             EffectFlow.followUpDecision(f, fctx(10, 7, 15, false, None, true))))

    /// pursuit: リング非所持 / 速さ差+2 はいずれも追撃しない。
    @Test
    def testPursuitNegatives(): Unit \ Assert =
        let f = Flow.FollowUp(FollowKind.Pursuit);
        Assert.assertEq(expected = (false, false),
            (EffectFlow.followUpDecision(f, fctx(10, 0, 0, false, None, false)),
             EffectFlow.followUpDecision(f, fctx(10, 8, 0, false, None, true))))

    // ════════════════════════════════════════════════════════
    // replaceAttack: 確率差し替え
    // ════════════════════════════════════════════════════════

    /// chance30: roll 29(<30) で差し替え、roll 30 で差し替えない。followUp には replaceDecision は効かない。
    @Test
    def testReplaceDecision(): Unit \ Assert =
        let f = Flow.ReplaceAttack(30, Nil);
        Assert.assertEq(expected = (true, false, false),
            (EffectFlow.replaceDecision(f, 29),
             EffectFlow.replaceDecision(f, 30),
             EffectFlow.replaceDecision(Flow.FollowUp(FollowKind.Brave), 0)))

    // ════════════════════════════════════════════════════════
    // secondHitAmountCtx: 2 撃目の効果量が純粋に導ける
    // ════════════════════════════════════════════════════════

    /// 1 撃目結果(2撃目見込み与ダメ=8)から導いた AmountCtx で、血吸い(与ダメ30%)の
    /// 2 撃目吸収量 = 8*30/100 = 2 を Scene 抜きで算出できる。
    @Test
    def testSecondHitLifesteal(): Unit \ Assert =
        let hr = {attackerMax = 30, secondHitDealt = 8, secondHitIncoming = 0, magic = 0};
        let ctx2 = EffectFlow.secondHitAmountCtx(hr);
        Assert.assertEq(expected = 2,
            EffectDsl.resolveAmount(Amount.Pct(AmountBase.Dealt, 30), ctx2))

    // ════════════════════════════════════════════════════════
    // applyFollow / applyReplace（runFlow が解釈する純粋 FlowEffect 列）
    //   FlowEffect は Eq 非導出（AmountCtx/Action を含む）ためタグ文字列へ projection して比較。
    // ════════════════════════════════════════════════════════

    def flowTag(fe: EffectFlow.FlowEffect): String = match fe {
        case EffectFlow.FlowEffect.MarkFollowUpUsed       => "mark"
        case EffectFlow.FlowEffect.RequestAttack(ctx, ts) => "attack:dealt=${ctx#dealt}:times=${ts}"
        case EffectFlow.FlowEffect.RequestReplace(acts)   => "replace:${List.length(acts)}"
        case EffectFlow.FlowEffect.NoFlow                 => "noflow"
    }

    def tags(fes: List[EffectFlow.FlowEffect]): List[String] = List.map(flowTag, fes)

    def hr8(): EffectFlow.HitResult =
        {attackerMax = 30, secondHitDealt = 8, secondHitIncoming = 0, magic = 0}

    /// brave 成立: applyFollow は [追撃済みフラグ, 2撃目(dealt=8)を要求] を返す。
    @Test
    def testApplyFollowHits(): Unit \ Assert =
        let f = Flow.FollowUp(FollowKind.Brave);
        Assert.assertEq(expected = "mark" :: "attack:dealt=8:times=1" :: Nil,
            tags(EffectFlow.applyFollow(f, fctx(10, 7, 0, false, Some(3), false), hr8())))

    /// brave 不成立(追撃済み): applyFollow は [NoFlow] のみ（2撃目を要求しない）。
    @Test
    def testApplyFollowNoFlow(): Unit \ Assert =
        let f = Flow.FollowUp(FollowKind.Brave);
        Assert.assertEq(expected = "noflow" :: Nil,
            tags(EffectFlow.applyFollow(f, fctx(10, 7, 0, true, Some(3), false), hr8())))

    /// replace 成立/不成立: roll 29 で差し替え要求(do[]空=0件)、roll 30 で NoFlow。
    @Test
    def testApplyReplace(): Unit \ Assert =
        let f = Flow.ReplaceAttack(30, Nil);
        Assert.assertEq(expected = ("replace:0" :: Nil, "noflow" :: Nil),
            (tags(EffectFlow.applyReplace(f, 29)), tags(EffectFlow.applyReplace(f, 30))))
}
