/// EffectBridge — 既存のアイテムデータ（ConsumableResource 等）→ 効果 DSL ルール（EffectRule）
///
/// 既存の `Consumable.ConsumableResource` を、その `effect` / `magnitude` / `duration` から
/// `EffectRule.EffectRule` へ写す移植テーブル。これにより「いま JSON にある全消費アイテム」を
/// コードを書き換えずに DSL 経路（planActions → runPlan）へ流せる。
/// 将来は効果そのものを effect JSON で宣言し、この橋は不要になる（移行期の互換層）。
/// Scene 非依存の純粋関数。
mod EffectBridge {

    use EffectDsl.Amount
    use EffectRule.{Trigger, Deliver, Role, Faction, TargetState, Op, Duration, Flow}
    use Consumable.ConsumableEffect
    use Consumable.ConsumableResource

    /// 自分対象（self）の 1 アクションを作る。
    def selfAct(op: Op, amount: Option[Amount], dur: Option[Duration]): EffectRule.Action =
        {to = {role = Role.RoleSelf, faction = Faction.FactionAny, state = TargetState.StateAny},
         op = op, amount = amount, dir = None, duration = dur, vfx = None, sfx = None}

    /// 投擲（ray 最初の faction 体）の 1 アクションを作る。
    def throwAct(op: Op, faction: Faction, amount: Option[Amount],
                 dur: Option[Duration]): EffectRule.Action =
        {to = {role = Role.RoleTarget, faction = faction, state = TargetState.StateAny},
         op = op, amount = amount, dir = None, duration = dur, vfx = None, sfx = None}

    /// 範囲（周囲 r マス）の 1 アクションを作る。
    def areaAct(op: Op, r: Int32, amount: Option[Amount]): EffectRule.Action =
        {to = {role = Role.RoleArea(r), faction = Faction.FactionAny, state = TargetState.StateAny},
         op = op, amount = amount, dir = None, duration = None, vfx = None, sfx = None}

    def mkRule(trigger: Trigger, deliver: List[Deliver],
               actions: List[EffectRule.Action]): EffectRule.EffectRule =
        {trigger = trigger, deliver = deliver, cond = EffectDsl.Pred.AllOf(Nil),
         chance = 100, actions = actions, flow = None}

    /// 消費アイテム 1 件を効果 DSL ルールへ写す。magnitude / duration は item の実値を使う。
    /// 全 11 種を網羅（移植テーブル）。delivery は effect から既定で決まるものに合わせる。
    pub def consumableRule(item: ConsumableResource): EffectRule.EffectRule =
        let mag = item#magnitude;
        let dur = item#duration;
        match item#effect {
            case ConsumableEffect.Heal       =>
                mkRule(Trigger.OnUse, Deliver.DeliverSelf :: Nil,
                       selfAct(Op.OpHealFlat, Some(Amount.Flat(mag)), None) :: Nil)
            case ConsumableEffect.FullHeal   =>
                mkRule(Trigger.OnUse, Deliver.DeliverSelf :: Nil,
                       selfAct(Op.OpHealFull, None, None) :: Nil)
            case ConsumableEffect.MaxHpUp    =>
                mkRule(Trigger.OnUse, Deliver.DeliverSelf :: Nil,
                       selfAct(Op.OpMaxHpUp, Some(Amount.Flat(mag)), Some(Duration.DurPermanent)) :: Nil)
            case ConsumableEffect.AtkUp      =>
                mkRule(Trigger.OnUse, Deliver.DeliverSelf :: Nil,
                       selfAct(Op.OpAtkUp, Some(Amount.Flat(mag)), Some(Duration.DurTurns(dur))) :: Nil)
            case ConsumableEffect.SpdUp      =>
                mkRule(Trigger.OnUse, Deliver.DeliverSelf :: Nil,
                       selfAct(Op.OpSpdUp, Some(Amount.Flat(mag)), Some(Duration.DurTurns(dur))) :: Nil)
            case ConsumableEffect.BlindHit   =>
                mkRule(Trigger.OnUse, Deliver.DeliverThrow :: Nil,
                       throwAct(Op.OpHitDown, Faction.FactionEnemy, Some(Amount.Flat(mag)), Some(Duration.DurTurns(dur))) :: Nil)
            case ConsumableEffect.SpdDownHit =>
                mkRule(Trigger.OnUse, Deliver.DeliverThrow :: Nil,
                       throwAct(Op.OpSpdDown, Faction.FactionEnemy, Some(Amount.Flat(mag)), Some(Duration.DurTurns(dur))) :: Nil)
            case ConsumableEffect.DefDownHit =>
                mkRule(Trigger.OnUse, Deliver.DeliverThrow :: Nil,
                       throwAct(Op.OpDefDown, Faction.FactionEnemy, Some(Amount.Flat(mag)), Some(Duration.DurTurns(dur))) :: Nil)
            case ConsumableEffect.FireBottle  =>
                mkRule(Trigger.OnUse, Deliver.DeliverThrow :: Nil,
                       throwAct(Op.OpDamageFlat, Faction.FactionEnemy, Some(Amount.Flat(mag)), None) :: Nil)
            case ConsumableEffect.BlastBottle =>
                mkRule(Trigger.OnUse, Deliver.DeliverThrow :: Nil,
                       areaAct(Op.OpDamageFlat, 1, Some(Amount.Flat(mag))) :: Nil)
            case ConsumableEffect.AutoRevive  =>
                mkRule(Trigger.OnDeath, Deliver.DeliverAuto :: Nil,
                       selfAct(Op.OpReviveCharge, None, None) :: Nil)
        }
}
