/// EffectBridge — 既存のアイテムデータ（ConsumableResource 等）→ 効果 DSL ルール（EffectRule）
///
/// 既存の `Consumable.ConsumableResource` を、その `effect` / `magnitude` / `duration` から
/// `EffectRule.EffectRule` へ写す移植テーブル。これにより「いま JSON にある全消費アイテム」を
/// コードを書き換えずに DSL 経路（planActions → runPlan）へ流せる。
/// 将来は効果そのものを effect JSON で宣言し、この橋は不要になる（移行期の互換層）。
/// Scene 非依存の純粋関数。
mod EffectBridge {

    use EffectDsl.{Amount, AmountBase, Atom, Pred, Stat}
    use EffectRule.{Trigger, Deliver, Role, Faction, TargetState, Op, Dir, Duration, Flow, FollowKind}
    use Consumable.ConsumableEffect
    use Consumable.ConsumableResource
    use WeaponCatalog.WeaponEffect
    use Ring.RingEffect
    use Staff.StaffEffect
    use Util.Json.Json
    use Util.Json.Json.{JObject, JString, JArray, JNumber}
    use JsonCodec.{expectString, expectInt, intToBd}

    /// 投げ対象（throw・ray 最初の1体・陣営無視）の 1 アクションを作る。
    def anyTargetAct(op: Op, amount: Option[Amount], dur: Option[Duration]): EffectRule.Action =
        {to = {role = Role.RoleTarget, faction = Faction.FactionAny, state = TargetState.StateAny},
         op = op, amount = amount, dir = None, duration = dur, vfx = None, sfx = None}

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

    /// 消費アイテムを「投げた」ときのルール（deliver:throw・対象＝ray 最初の1体・陣営無視）。
    /// 同じ薬でも「つかう」(consumableRule＝自分) と「投げる」(これ＝当たった相手) で対象が変わる
    /// （1 アイテム＝複数 delivery）。投げは敵味方どちらにも当たる（既存挙動。throwConsumableAtEnemy/
    /// AtPlayer がどちらも適用する）。AutoRevive は投げると対象を全回復（敵 full heal の既存挙動）。
    pub def consumableThrowRule(item: ConsumableResource): EffectRule.EffectRule =
        let mag = item#magnitude;
        let dur = item#duration;
        let throwRule = (op, amount, d) ->
            mkRule(Trigger.OnUse, Deliver.DeliverThrow :: Nil, anyTargetAct(op, amount, d) :: Nil);
        match item#effect {
            case ConsumableEffect.Heal       => throwRule(Op.OpHealFlat, Some(Amount.Flat(mag)), None)
            case ConsumableEffect.FullHeal   => throwRule(Op.OpHealFull, None, None)
            case ConsumableEffect.AutoRevive => throwRule(Op.OpHealFull, None, None)
            case ConsumableEffect.MaxHpUp    => throwRule(Op.OpMaxHpUp, Some(Amount.Flat(mag)), Some(Duration.DurPermanent))
            case ConsumableEffect.AtkUp      => throwRule(Op.OpAtkUp, Some(Amount.Flat(mag)), Some(Duration.DurTurns(dur)))
            case ConsumableEffect.SpdUp      => throwRule(Op.OpSpdUp, Some(Amount.Flat(mag)), Some(Duration.DurTurns(dur)))
            case ConsumableEffect.BlindHit   => throwRule(Op.OpHitDown, Some(Amount.Flat(mag)), Some(Duration.DurTurns(dur)))
            case ConsumableEffect.SpdDownHit => throwRule(Op.OpSpdDown, Some(Amount.Flat(mag)), Some(Duration.DurTurns(dur)))
            case ConsumableEffect.DefDownHit => throwRule(Op.OpDefDown, Some(Amount.Flat(mag)), Some(Duration.DurTurns(dur)))
            case ConsumableEffect.FireBottle  => throwRule(Op.OpDamageFlat, Some(Amount.Flat(mag)), None)
            case ConsumableEffect.BlastBottle =>
                mkRule(Trigger.OnUse, Deliver.DeliverThrow :: Nil,
                       areaAct(Op.OpDamageFlat, 1, Some(Amount.Flat(mag))) :: Nil)
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

    /// 自分対象・常時補正（whileEquipped）の 1 アクション。Power/Swift/Guard 用。
    def equipAct(op: Op, power: Int32): EffectRule.Action =
        selfAct(op, Some(Amount.Flat(power)), Some(Duration.DurWhileEquipped))

    /// 指輪効果を効果 DSL ルールへ写す。`power` はステータス補正量/回復量/しきい値。
    /// Power/Swift/Guard は onEquip + whileEquipped（常時補正＝Ring.bonuses が実行、runPlan は NoOp）。
    /// Pursuit は flow:followUp。Finisher は estimate 内介入（Phase4）。全 8 種を網羅。
    pub def ringRule(effect: RingEffect, power: Int32): EffectRule.EffectRule =
        match effect {
            case RingEffect.Power     =>
                fullRule(Trigger.OnEquip, Pred.AllOf(Nil), 100, equipAct(Op.OpAtkUp, power) :: Nil, None)
            case RingEffect.Swift     =>
                fullRule(Trigger.OnEquip, Pred.AllOf(Nil), 100, equipAct(Op.OpSpdUp, power) :: Nil, None)
            case RingEffect.Guard     =>
                fullRule(Trigger.OnEquip, Pred.AllOf(Nil), 100, equipAct(Op.OpDefUp, power) :: Nil, None)
            case RingEffect.Mend      =>
                fullRule(Trigger.OnTurnStart, Pred.AllOf(Nil), 100,
                         selfAct(Op.OpHealFlat, Some(Amount.Flat(power)), None) :: Nil, None)
            case RingEffect.Lifesteal =>
                fullRule(Trigger.OnKill, Pred.AllOf(Nil), 100,
                         attackerAct(Op.OpHealFlat, Some(Amount.Flat(power))) :: Nil, None)
            case RingEffect.Finisher  =>
                fullRule(Trigger.OnAttack, Pred.PAtom(Atom.TargetHpPctAtMost(power)), 100,
                         throwAct(Op.OpFinisher, Faction.FactionAny, None, None) :: Nil, None)
            case RingEffect.Pursuit   =>
                fullRule(Trigger.OnAttack, Pred.AllOf(Nil), 100, Nil,
                         Some(Flow.FollowUp(FollowKind.Pursuit)))
            case RingEffect.Trivial   =>
                fullRule(Trigger.OnEquip, Pred.AllOf(Nil), 100, Nil, None)
            // 浮雲。装備されない「持つだけ」系なので効果ルールは無し（Trivial と同じ no-op）。
            case RingEffect.Levitate  =>
                fullRule(Trigger.OnEquip, Pred.AllOf(Nil), 100, Nil, None)
        }

    /// 投擲対象（throw・ray 最初の1体・陣営無視）の 1 アクション。
    def castAct(op: Op, amount: Option[Amount], dur: Option[Duration]): EffectRule.Action =
        {to = {role = Role.RoleTarget, faction = Faction.FactionAny, state = TargetState.StateAny},
         op = op, amount = amount, dir = None, duration = dur, vfx = None, sfx = None}

    /// 杖効果を効果 DSL ルールへ写す。杖は方向を選んで撃ち、ray 最初の1体（敵味方問わず）に効く
    /// （rayFirst = faction 省略相当）。効果量は固定（魔力+10 / 1ダメージ等）。全 5 種を網羅。
    pub def staffRule(effect: StaffEffect): EffectRule.EffectRule =
        match effect {
            case StaffEffect.Heal     =>
                fullRule(Trigger.OnCast, Pred.AllOf(Nil), 100,
                         castAct(Op.OpHealFlat, Some(Amount.StatPlus(Stat.Magic, 10)), None) :: Nil, None)
            case StaffEffect.Blowback =>
                fullRule(Trigger.OnCast, Pred.AllOf(Nil), 100,
                         castAct(Op.OpDamageFlat, Some(Amount.Flat(1)), None) ::
                         dirAct(Op.OpKnockback, Faction.FactionAny, Dir.DirCastRay,
                                Some(Amount.Tiles(0))) :: Nil, None)
            case StaffEffect.Swap     =>
                fullRule(Trigger.OnCast, Pred.AllOf(Nil), 100,
                         castAct(Op.OpSwapPos, None, None) :: Nil, None)
            case StaffEffect.Bind     =>
                fullRule(Trigger.OnCast, Pred.AllOf(Nil), 100,
                         castAct(Op.OpImmobilize, None, Some(Duration.DurUntilHit)) :: Nil, None)
            case StaffEffect.Stopgap  =>
                fullRule(Trigger.OnCast, Pred.AllOf(Nil), 100,
                         castAct(Op.OpImmobilize, None, Some(Duration.DurUntilHit)) ::
                         castAct(Op.OpWarpToStairs, None, None) :: Nil, None)
        }

    // ════════════════════════════════════════════════════════
    // IDE 合成エディタの簡易形式 JSON → EffectRule
    //   簡易形式 {when,to,op,amount,for,forTurns,sfx,vfx} を完全な EffectRule JSON へ展開し
    //   EffectRuleCodec.decodeRule で解釈する。これでゲームが effectRule を発火に使える。
    // ════════════════════════════════════════════════════════

    /// 簡易形式 JSON を EffectRule へ変換（不正なら None）。
    pub def fromComposer(simple: Json): Option[EffectRule.EffectRule] =
        EffectRuleCodec.decodeRule(simpleToFull(simple))

    def simpleToFull(simple: Json): Json =
        let obj = match simple {
            case JObject(m) => m
            case _          => Map.empty()
        };
        let gs = (k, d) -> Map.get(k, obj) |> Option.flatMap(expectString) |> Option.getWithDefault(d);
        let gi = (k, d) -> Map.get(k, obj) |> Option.flatMap(expectInt) |> Option.getWithDefault(d);
        let toV = gs("to", "self");
        // chance は任意（欠落 → 100＝必ず発動。decodeRule の既定と同値）。確率発動の敵特殊
        // （毒30%付与など）を簡易form のままコードレスで書けるようにここで通す。
        let action = actionFull(toV, gs("op", "healFlat"), gi("amount", 0),
                                gs("for", "instant"), gi("forTurns", 0), gs("sfx", ""), gs("vfx", ""));
        // kind で出し分け: do=通常（top-level do[]）/ replaceAttack=攻撃差し替え（flow + 隣接条件）。
        fullComposer(gs("kind", "do"), gs("when", "onUse"), toV, gi("chance", 100), action)

    def fullComposer(kind: String, when: String, toV: String, chance: Int32, action: Json): Json =
        match kind {
            case "replaceAttack" => replaceForm(when, chance, action)
            case _               => doForm(when, toV, chance, action)
        }

    /// 通常効果: chance は top-level（発火確率）、action は do[] に撒く。
    def doForm(when: String, toV: String, chance: Int32, action: Json): Json =
        JObject(Map#{
            "when" => JString(when),
            "deliver" => JArray(Vector#{JString(deliverOfComposer(toV))}),
            "chance" => JNumber(intToBd(chance)),
            "do" => JArray(Vector#{action})
        })

    /// 攻撃差し替え（RingMan 等）: 隣接条件を暗黙付与し、chance は replaceAttack 内（差し替え確率）に
    /// 載せる。top-level chance は出さない（decodeRule 既定 100＝ルール自体は常時発火）。
    /// 隣接限定は**仕様**: 敵ターンの差し替え特殊は近接前提（RingMan の指輪化は隣接時のみ）。
    /// cond 欄を簡易form に設けない代わりにここで if:"adjacent" を固定付与する。
    def replaceForm(when: String, chance: Int32, action: Json): Json =
        JObject(Map#{
            "when" => JString(when),
            "if" => JString("adjacent"),
            "flow" => JObject(Map#{
                "replaceAttack" => JObject(Map#{
                    "chance" => JNumber(intToBd(chance)),
                    "do" => JArray(Vector#{action})
                })
            })
        })

    def deliverOfComposer(to: String): String = match to {
        case "self"     => "self"
        case "attacker" => "self"
        case _          => "throw"
    }

    def actionFull(to: String, op: String, amt: Int32, forV: String, ft: Int32,
                   sfx: String, vfx: String): Json =
        let base0 = Map#{"to" => toFull(to), "op" => JString(op)};
        let base1 = if (opTakesAmount(op))
                        Map.insert("amount", amountJsonOf(op, amt), base0)
                    else base0;
        let base2 = Map.insert("for", forFull(forV, ft), base1);
        let base3 = if (sfx == "") base2 else Map.insert("sfx", JString(sfx), base2);
        let base4 = if (vfx == "") base3 else Map.insert("vfx", JString(vfx), base3);
        JObject(base4)

    def toFull(to: String): Json = match to {
        case "attacker" => JObject(Map#{"role" => JString("attacker")})
        case "target"   => JObject(Map#{"role" => JString("target")})
        case "enemy"    => JObject(Map#{"role" => JString("target"), "faction" => JString("enemy")})
        case "ally"     => JObject(Map#{"role" => JString("target"), "faction" => JString("ally")})
        case _          => JObject(Map#{"role" => JString("self")})
    }

    def forFull(forV: String, ft: Int32): Json = match forV {
        case "turns" => JObject(Map#{"turns" => JNumber(intToBd(ft))})
        case _       => JString(forV)
    }

    /// op ごとに amount の符号化を出し分ける。多くは flat だが、lifesteal は
    /// 「与えたダメージの N%」＝ Pct(dealt, N) なので {pct:{base:"dealt",value:N}} を出す
    /// （flat のままだと「固定 N 回復」に化けて意味が壊れる）。
    def amountJsonOf(op: String, amt: Int32): Json = match op {
        case "lifesteal" => JObject(Map#{"pct" => JObject(Map#{"base" => JString("dealt"),
                                                               "value" => JNumber(intToBd(amt))})})
        case _           => JObject(Map#{"flat" => JNumber(intToBd(amt))})
    }

    def opTakesAmount(op: String): Bool = match op {
        case "healFull"     => false
        case "immobilize"   => false
        case "reviveCharge" => false
        // 盤面副作用系は量を取らない（杖の knockback は無制限・swapPos/warpToStairs は対象のみ）
        case "knockback"    => false
        case "swapPos"      => false
        case "warpToStairs" => false
        case "dropItem"     => false
        case "ringify"      => false
        case _              => true
    }

    /// RingMan（敵特殊）: 敵ターンに隣接していると 30% で通常攻撃をやめ、相手（味方）の
    /// 持ち物を指輪化する。flow:replaceAttack（攻撃を差し替える）＋ ringify（B custom）。
    /// 敵視点なので対象 faction は enemy（＝プレイヤー駒）。設計で replaceAttack が要る唯一の敵特殊。
    pub def ringmanRule(): EffectRule.EffectRule =
        let ringify = throwAct(Op.OpRingify, Faction.FactionEnemy, None, None);
        fullRule(Trigger.OnEnemyTurn, Pred.PAtom(Atom.Adjacent), 100, Nil,
                 Some(Flow.ReplaceAttack(30, ringify :: Nil)))
}
