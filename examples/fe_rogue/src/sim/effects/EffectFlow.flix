/// EffectFlow — 制御フロー系（flow）の純粋判定。Phase 2。
///
/// 投射系（do[]＝対象に作用を撒く）とは別の「攻撃の流れを変える」系統:
///   - followUp     : 攻撃をもう一度繰り返す（はやぶさ＝速さ差ブレイブ / 追撃＝速さ差+確率）
///   - replaceAttack : 通常攻撃を確率で別アクションに差し替える（RingMan の指輪化など）
///
/// ここは「撃つか／差し替えるか」の純粋判定と、2 撃目の効果量文脈の純粋導出だけを持つ。
/// 実際の攻撃再入・状態書き換えは Scene 側（runFlow）が担い、ここは Scene 非依存でテストできる。
/// 既存の `CombatRules.braveFollowUp` / `CombatRules.shouldFollowUp` と同一ロジックだが、循環依存を避けるため
/// DSL 文脈（FollowUpCtx）で独立に持つ（移行完了後に単一化する）。
mod EffectFlow {

    use EffectRule.{Flow, FollowKind}
    use EffectDsl.AmountCtx

    /// followUp 判定に必要な文脈。投射系の量文脈とは分離（roll を量計算が誤参照しない）。
    ///   - `brave`   : ブレイブ閾値（はやぶさの effectValue）。None なら brave 不発
    ///   - `pursuit` : 追撃リング所持か
    ///   - `followUpUsed` : このターン既に追撃済みか（無限追撃防止）
    pub type alias FollowUpCtx = {
        atkSpd       = Int32,
        defSpd       = Int32,
        roll         = Int32,
        followUpUsed = Bool,
        brave        = Option[Int32],
        pursuit      = Bool
    }

    /// 追撃するか。`braveFollowUp` / `CombatRules.shouldFollowUp` と同一:
    ///   brave   = 未追撃 かつ 速さ差 >= 閾値
    ///   pursuit = 追撃リング所持 かつ 未追撃 かつ 速さ差 >= 3 かつ roll < 15
    pub def followUpDecision(flow: Flow, ctx: FollowUpCtx): Bool = match flow {
        case Flow.FollowUp(FollowKind.Brave) =>
            not ctx#followUpUsed and (match ctx#brave {
                case Some(d) => ctx#atkSpd >= ctx#defSpd + d
                case None    => false
            })
        case Flow.FollowUp(FollowKind.Pursuit) =>
            ctx#pursuit and not ctx#followUpUsed
                and ctx#atkSpd >= ctx#defSpd + 3 and ctx#roll < 15
        case Flow.ReplaceAttack(_, _) => false
    }

    /// 通常攻撃を差し替えるか（確率ロール）。`if`（隣接など）は呼び出し側で AND する。
    pub def replaceDecision(flow: Flow, roll: Int32): Bool = match flow {
        case Flow.ReplaceAttack(chance, _) => roll < chance
        case Flow.FollowUp(_)              => false
    }

    /// 1 撃目の確定結果。2 撃目の効果量文脈を純粋に導くために runFlow が渡す。
    pub type alias HitResult = {
        attackerMax       = Int32,
        secondHitDealt    = Int32,
        secondHitIncoming = Int32,
        magic             = Int32
    }

    /// 2 撃目の AmountCtx を 1 撃目結果から純粋に導く。runFlow は再入時にこれを渡すだけで、
    /// 量計算（吸収など）を一切行わない。これにより「血吸い×はやぶさ 2 撃目の吸収量」を
    /// Scene 抜きで assertEq できる（flow と amount の実行時結合を切る）。
    pub def secondHitAmountCtx(hr: HitResult): AmountCtx =
        {max = hr#attackerMax, dealt = hr#secondHitDealt,
         incoming = hr#secondHitIncoming, magic = hr#magic}

    /// flow が runFlow（Scene 側）に要求する作用。純粋データで、副作用は持たない。
    /// runFlow（Scene）がこれを解釈して startAttack 再入・フラグ書き込み・差し替えを実行する。
    /// AmountCtx / List[Action]（record alias）を含むため Eq/ToString は自動導出しない。
    ///   - `MarkFollowUpUsed`  : 追撃済みフラグを立てる（無限追撃防止）
    ///   - `RequestAttack(ctx2, times)` : 2 撃目の攻撃を ctx2 で要求（times は連続回数、現状 1）
    ///   - `RequestReplace(actions)`    : 通常攻撃の代わりに actions を撒く
    ///   - `NoFlow`            : 何もしない
    pub enum FlowEffect {
        case MarkFollowUpUsed
        case RequestAttack(AmountCtx, Int32)
        case RequestReplace(List[EffectRule.Action])
        case NoFlow
    }

    /// followUp の純粋な適用結果。決定が真なら「フラグを立てて 2 撃目を要求」、偽なら NoFlow。
    /// runFlow はこの列を解釈するだけで、撃つか否かの判定も量計算もここで済んでいる。
    pub def applyFollow(flow: Flow, ctx: FollowUpCtx, hr: HitResult): List[FlowEffect] =
        if (followUpDecision(flow, ctx))
            FlowEffect.MarkFollowUpUsed :: FlowEffect.RequestAttack(secondHitAmountCtx(hr), 1) :: Nil
        else
            FlowEffect.NoFlow :: Nil

    /// replaceAttack の純粋な適用結果。決定が真なら差し替え do[] を要求、偽なら NoFlow
    /// （runFlow 側は NoFlow を見て通常攻撃へ進む）。
    pub def applyReplace(flow: Flow, roll: Int32): List[FlowEffect] =
        if (replaceDecision(flow, roll))
            FlowEffect.RequestReplace(replaceActions(flow)) :: Nil
        else
            FlowEffect.NoFlow :: Nil

    /// replaceAttack の差し替え先 action 列を取り出す（followUp なら空）。
    def replaceActions(flow: Flow): List[EffectRule.Action] = match flow {
        case Flow.ReplaceAttack(_, actions) => actions
        case Flow.FollowUp(_)               => Nil
    }
}
