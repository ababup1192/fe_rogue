/// EffectBridge — 既存のアイテムデータ（ConsumableResource 等）→ 効果 DSL ルール（EffectRule）
///
/// 既存の `Consumable.ConsumableResource` を、その `effect` / `magnitude` / `duration` から
/// `EffectRule.EffectRule` へ写す移植テーブル。これにより「いま JSON にある全消費アイテム」を
/// コードを書き換えずに DSL 経路（planActions → runPlan）へ流せる。
/// 将来は効果そのものを effect JSON で宣言し、この橋は不要になる（移行期の互換層）。
/// Scene 非依存の純粋関数。
mod EffectBridge {

    use EffectDsl.{Amount, AmountBase, Atom, Pred}
    use EffectRule.{Trigger, Deliver, Role, Faction, TargetState, Op, Dir, Duration, Flow, FollowKind}
    use Consumable.ConsumableEffect
    use Consumable.ConsumableResource
    use WeaponCatalog.WeaponEffect

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

    /// 攻撃側（自分）対象の 1 アクション。
    def attackerAct(op: Op, amount: Option[Amount]): EffectRule.Action =
        {to = {role = Role.RoleAttacker, faction = Faction.FactionAny, state = TargetState.StateAny},
         op = op, amount = amount, dir = None, duration = None, vfx = None, sfx = None}

    /// 向き付き（ノックバック）の 1 アクション。
    def dirAct(op: Op, faction: Faction, dir: Dir, amount: Option[Amount]): EffectRule.Action =
        {to = {role = Role.RoleTarget, faction = faction, state = TargetState.StateAny},
         op = op, amount = amount, dir = Some(dir), duration = None, vfx = None, sfx = None}

    /// 全フィールド指定のルール構築（cond/chance/flow も明示）。
    def fullRule(trigger: Trigger, cond: Pred, chance: Int32,
                 actions: List[EffectRule.Action], flow: Option[Flow]): EffectRule.EffectRule =
        {trigger = trigger, deliver = Nil, cond = cond,
         chance = chance, actions = actions, flow = flow}

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

    /// 武器効果を効果 DSL ルールへ写す。`effectValue` は閾値/マス数/割合/確率として使う。
    /// BraveOnSpeed は flow:followUp（閾値は実行時 FollowUpCtx#brave で供給）。
    /// 全 6 種を網羅。
    pub def weaponRule(effect: WeaponEffect, effectValue: Int32): EffectRule.EffectRule =
        match effect {
            case WeaponEffect.NoEffect     =>
                fullRule(Trigger.OnAttack, Pred.AllOf(Nil), 100, Nil, None)
            case WeaponEffect.BraveOnSpeed =>
                fullRule(Trigger.OnAttack, Pred.AllOf(Nil), 100, Nil,
                         Some(Flow.FollowUp(FollowKind.Brave)))
            case WeaponEffect.Knockback    =>
                fullRule(Trigger.OnHit, Pred.PAtom(Atom.TargetAlive), 100,
                         dirAct(Op.OpKnockback, Faction.FactionEnemy, Dir.DirFromAttacker,
                                Some(Amount.Tiles(effectValue))) :: Nil, None)
            case WeaponEffect.Desperation  =>
                fullRule(Trigger.OnAttack, Pred.PAtom(Atom.SelfHpPctAtMost(effectValue)), 100,
                         selfAct(Op.OpPowerMul, Some(Amount.Mul(150)), None) :: Nil, None)
            case WeaponEffect.Lifesteal    =>
                fullRule(Trigger.OnHit, Pred.AllOf(Nil), 100,
                         attackerAct(Op.OpLifesteal,
                                     Some(Amount.Pct(AmountBase.Dealt, effectValue))) :: Nil, None)
            case WeaponEffect.ThiefDrop    =>
                let rogueAndAlive = Pred.AllOf(
                    Pred.PAtom(Atom.EquippedIsRogue) :: Pred.PAtom(Atom.TargetAlive) :: Nil);
                fullRule(Trigger.OnHit, rogueAndAlive, effectValue,
                         throwAct(Op.OpDropItem, Faction.FactionEnemy, None, None) :: Nil, None)
        }
}
