/// EffectRule の日本語プレビュー（previewRule）と保存前検証（validateRule / isSavable）を固定する。
/// 既存35件の代表をルールとして組み、IDE 表示文と論理死/配線死/whileEquipped 縛りを検証する。
mod TestEffectRule {

    use EffectDsl.{Amount, Pred, Stat, AmountBase}
    use EffectRule.{Trigger, Deliver, Role, Faction, TargetState, Op, Duration, Flow, FollowKind}

    // ── フィクスチャ組み立てヘルパ ──────────────────────────────

    def tgt(role: Role, faction: Faction, state: TargetState): EffectRule.Target =
        {role = role, faction = faction, state = state}

    def act(t: EffectRule.Target, op: Op, amount: Option[Amount],
            dur: Option[Duration]): EffectRule.Action =
        {to = t, op = op, amount = amount, dir = None, duration = dur, vfx = None, sfx = None}

    // 述語なし（常に true）。
    def always(): Pred = Pred.AllOf(Nil)

    def rule(trigger: Trigger, deliver: List[Deliver], chance: Int32,
             actions: List[EffectRule.Action], flow: Option[Flow]): EffectRule.EffectRule =
        {trigger = trigger, deliver = deliver, cond = always(),
         chance = chance, actions = actions, flow = flow}

    def has(needle: String, hay: String): Bool = String.contains({substr = needle}, hay)

    // ════════════════════════════════════════════════════════
    // previewRule（日本語1文）
    // ════════════════════════════════════════════════════════

    // ちから薬: つかって自分の攻撃力を3ターン上げる。
    def powerPotion(): EffectRule.EffectRule =
        rule(Trigger.OnUse, Deliver.DeliverSelf :: Nil, 100,
             act(tgt(Role.RoleSelf, Faction.FactionAny, TargetState.StateAny),
                 Op.OpAtkUp, Some(Amount.Flat(4)), Some(Duration.DurTurns(3))) :: Nil,
             None)

    /// ちから薬の文に「攻撃力を 4」「3 ターン」「つかって」が含まれる。
    @Test
    def testPreviewPowerPotion(): Unit \ Assert =
        let p = EffectRule.previewRule(powerPotion());
        Assert.assertEq(expected = (true, true, true),
            (has("攻撃力を 4", p), has("3 ターン", p), has("使用すると", p)))

    // 火炎瓶: 投げて、当たった敵に15の固定ダメージ。
    def fireBottle(): EffectRule.EffectRule =
        rule(Trigger.OnUse, Deliver.DeliverThrow :: Nil, 100,
             act(tgt(Role.RoleTarget, Faction.FactionEnemy, TargetState.StateAny),
                 Op.OpDamageFlat, Some(Amount.Flat(15)), None) :: Nil,
             None)

    /// 火炎瓶の文に「投げて」「敵」「15 の固定ダメージ」が含まれる。
    @Test
    def testPreviewFireBottle(): Unit \ Assert =
        let p = EffectRule.previewRule(fireBottle());
        Assert.assertEq(expected = (true, true, true),
            (has("投げて", p), has("敵", p), has("15 の固定ダメージ", p)))

    // 回復の杖: faction 省略(rayFirst) → 「最初に当たった相手」。
    def healStaff(): EffectRule.EffectRule =
        rule(Trigger.OnCast, Deliver.DeliverThrow :: Nil, 100,
             act(tgt(Role.RoleTarget, Faction.FactionAny, TargetState.StateAny),
                 Op.OpHealFlat, Some(Amount.StatPlus(Stat.Magic, 10)), None) :: Nil,
             None)

    /// 杖回復は陣営無視なので「最初に当たった相手」「魔力+10 回復」になる。
    @Test
    def testPreviewHealStaffRayFirst(): Unit \ Assert =
        let p = EffectRule.previewRule(healStaff());
        Assert.assertEq(expected = (true, true),
            (has("最初に当たった相手", p), has("魔力+10 回復", p)))

    // はやぶさ: flow:followUp(brave)。
    def hayabusa(): EffectRule.EffectRule =
        rule(Trigger.OnAttack, Nil, 100, Nil, Some(Flow.FollowUp(FollowKind.Brave)))

    /// flow ルールは flow 文（「もう一度攻撃する」）を出す。
    @Test
    def testPreviewFollowUp(): Unit \ Assert =
        Assert.assertEq(expected = true,
            has("もう一度攻撃する", EffectRule.previewRule(hayabusa())))

    // 一時しのぎ: 2 アクション（止めて→飛ばす）を「、さらに」で連結。
    def stopgap(): EffectRule.EffectRule =
        rule(Trigger.OnCast, Deliver.DeliverThrow :: Nil, 100,
             act(tgt(Role.RoleTarget, Faction.FactionAlly, TargetState.StateNotImmobilized),
                 Op.OpImmobilize, None, Some(Duration.DurUntilHit)) ::
             act(tgt(Role.RoleTarget, Faction.FactionAlly, TargetState.StateAny),
                 Op.OpWarpToStairs, None, None) :: Nil,
             None)

    /// 複文連結「、さらに」と「攻撃を受けるまで」「止まっていない味方」が出る。
    @Test
    def testPreviewStopgapMultiAction(): Unit \ Assert =
        let p = EffectRule.previewRule(stopgap());
        Assert.assertEq(expected = (true, true, true),
            (has("、さらに", p), has("攻撃を受けるまで", p), has("止まっていない味方", p)))

    // ════════════════════════════════════════════════════════
    // validateRule / isSavable（論理死・配線死・whileEquipped 縛り）
    // ════════════════════════════════════════════════════════

    /// 健全なルール（ちから薬）は問題なし・保存可。
    @Test
    def testValidateHealthy(): Unit \ Assert =
        Assert.assertEq(expected = (true, 0),
            (EffectRule.isSavable(powerPotion()),
             List.length(EffectRule.validateRule(powerPotion()))))

    /// chance:0 は論理死で保存不可。
    @Test
    def testValidateChanceZeroBlocksSave(): Unit \ Assert =
        let r = rule(Trigger.OnHit, Nil, 0,
                     act(tgt(Role.RoleTarget, Faction.FactionEnemy, TargetState.StateAny),
                         Op.OpDamageFlat, Some(Amount.Flat(10)), None) :: Nil, None);
        Assert.assertEq(expected = false, EffectRule.isSavable(r))

    /// mul:100 は等倍=無効果で warn が出るが、Reject ではないので保存は可。
    @Test
    def testValidateMulHundredWarnsButSavable(): Unit \ Assert =
        let r = rule(Trigger.OnAttack, Nil, 100,
                     act(tgt(Role.RoleSelf, Faction.FactionAny, TargetState.StateAny),
                         Op.OpPowerMul, Some(Amount.Mul(100)), None) :: Nil, None);
        Assert.assertEq(expected = (true, 1),
            (EffectRule.isSavable(r), List.length(EffectRule.validateRule(r))))

    /// whileEquipped を self 以外（target）に付けると保存不可（隠れルーティング封じ）。
    @Test
    def testValidateWhileEquippedSelfOnly(): Unit \ Assert =
        let onTarget = rule(Trigger.OnEquip, Nil, 100,
                            act(tgt(Role.RoleTarget, Faction.FactionAlly, TargetState.StateAny),
                                Op.OpAtkUp, Some(Amount.Flat(3)), Some(Duration.DurWhileEquipped)) :: Nil, None);
        let onSelf = rule(Trigger.OnEquip, Nil, 100,
                            act(tgt(Role.RoleSelf, Faction.FactionAny, TargetState.StateAny),
                                Op.OpAtkUp, Some(Amount.Flat(3)), Some(Duration.DurWhileEquipped)) :: Nil, None);
        Assert.assertEq(expected = (false, true),
            (EffectRule.isSavable(onTarget), EffectRule.isSavable(onSelf)))

    /// 未結線の B custom op（knockback）を含むと保存不可（配線死）。
    @Test
    def testValidateUnwiredOpBlocksSave(): Unit \ Assert =
        let r = rule(Trigger.OnHit, Nil, 100,
                     act(tgt(Role.RoleTarget, Faction.FactionEnemy, TargetState.StateAny),
                         Op.OpKnockback, Some(Amount.Tiles(2)), None) :: Nil, None);
        Assert.assertEq(expected = false, EffectRule.isSavable(r))
}
