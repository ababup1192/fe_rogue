/// EffectPlan — 「発動したルール → 具体的な効果リスト（Plan）」の純粋計算
///
/// `runPlan`（Scene 副作用＝HP 書き換え・状態付与・演出）が実行する「何が・誰に・いくつ
/// 起きるか」を純粋データ `PlanItem` の列として確定する層。対象解決（resolveTarget）と
/// 効果量解決（resolveAmount）を済ませた中間表現なので、runPlan は match して既存関数
/// （Combat.heal / StatusSystem.add / ExplosionScene / AudioStreamPlayer）へ委譲するだけ。
/// この層は Scene 非依存ゆえテストが値だけで完結する。
mod EffectPlan {

    use EffectDsl.Amount
    use EffectRule.{Action, Op, Duration, RayUnit}
    use StatusSystem.StatusEffect

    /// 確定した効果 1 つ。対象系は `id` と `ally`（使用者と同陣営か）を持ち、runPlan が
    /// player/enemy ノードを出し分けられるようにする。
    ///   - 投射系の HP / status / 範囲 / 演出
    ///   - B custom op は `CustomAt(op名, id, ally)` で runPlan が既存 Scene handler へ委譲
    ///   - estimate 内介入（powerMul / finisher）と空振りは `NoOp(理由)`
    pub enum PlanItem with Eq, ToString {
        case HealAt(Int32, Bool, Int32)
        case FullHealAt(Int32, Bool)
        case DamageAt(Int32, Bool, Int32)
        case MaxHpUpAt(Int32, Bool, Int32)
        case StatusAt(Int32, Bool, StatusEffect, Int32, Int32)
        case ImmobilizeAt(Int32, Bool)
        case ReviveAt(Int32, Bool)
        case CustomAt(String, Int32, Bool)
        case PlaySfx(String)
        case NoOp(String)
    }

    /// planActions に必要な文脈。対象解決（selfId/attackerId/rayUnits）と
    /// 効果量解決（amount）の両方を束ねる。実 Scene が PlayerData/EnemyData から組む。
    pub type alias PlanCtx = {
        selfId     = Int32,
        attackerId = Int32,
        rayUnits   = List[RayUnit],
        amount     = EffectDsl.AmountCtx
    }

    /// 時限効果の継続ターン数を取り出す（DurTurns 以外は 1 とみなす）。
    def turnsOf(d: Option[Duration]): Int32 = match d {
        case Some(Duration.DurTurns(n)) => n
        case _                          => 1
    }

    /// status 系 op を StatusSystem.StatusEffect へ写像（時限ステータス）。
    def statusKind(op: Op): Option[StatusEffect] = match op {
        case Op.OpAtkUp   => Some(StatusEffect.AtkUp)
        case Op.OpSpdUp   => Some(StatusEffect.SpdUp)
        case Op.OpSpdDown => Some(StatusEffect.SpdDown)
        case Op.OpDefDown => Some(StatusEffect.DefDown)
        case Op.OpHitDown => Some(StatusEffect.HitDown)
        case _            => None
    }

    /// 継続が whileEquipped か（常時補正＝Ring.bonuses 経路。runPlan は発火しない）。
    def isWhileEquipped(dur: Option[Duration]): Bool = match dur {
        case Some(Duration.DurWhileEquipped) => true
        case _                               => false
    }

    /// op を、解決済み対象（id, ally）・効果量・継続から PlanItem 列へ。
    /// whileEquipped（指輪の常時補正 Power/Swift/Guard）は runPlan で発火せず Ring.bonuses が
    /// 戦闘ビュー構築時に読むため、ここでは NoOp に短絡する（時限ステータスと混同しない）。
    def opPlan(op: Op, id: Int32, ally: Bool, amt: Int32, dur: Option[Duration]): List[PlanItem] =
        if (isWhileEquipped(dur))
            PlanItem.NoOp("常時補正（装備中・Ring.bonuses が処理）") :: Nil
        else match op {
        case Op.OpHealFlat     => PlanItem.HealAt(id, ally, amt) :: Nil
        case Op.OpLifesteal    => PlanItem.HealAt(id, ally, amt) :: Nil
        case Op.OpHealFull     => PlanItem.FullHealAt(id, ally) :: Nil
        case Op.OpDamageFlat   => PlanItem.DamageAt(id, ally, amt) :: Nil
        case Op.OpMaxHpUp      => PlanItem.MaxHpUpAt(id, ally, amt) :: Nil
        case Op.OpImmobilize   => PlanItem.ImmobilizeAt(id, ally) :: Nil
        case Op.OpReviveCharge => PlanItem.ReviveAt(id, ally) :: Nil
        case Op.OpAtkUp        => statusItem(op, id, ally, amt, dur)
        case Op.OpSpdUp        => statusItem(op, id, ally, amt, dur)
        case Op.OpSpdDown      => statusItem(op, id, ally, amt, dur)
        case Op.OpDefDown      => statusItem(op, id, ally, amt, dur)
        case Op.OpHitDown      => statusItem(op, id, ally, amt, dur)
        // 守備+N は whileEquipped 常時補正専用。上の短絡に乗らない（=時限）ものはルール不正なので NoOp。
        case Op.OpDefUp        => PlanItem.NoOp("defUp は whileEquipped 専用（常時補正）") :: Nil
        case Op.OpPowerMul     => PlanItem.NoOp("powerMul は estimate 内介入（Phase4）") :: Nil
        case Op.OpFinisher     => PlanItem.NoOp("finisher は estimate 内介入（Phase4）") :: Nil
        case Op.OpKnockback    => PlanItem.CustomAt("knockback", id, ally) :: Nil
        case Op.OpDropItem     => PlanItem.CustomAt("dropItem", id, ally) :: Nil
        case Op.OpSwapPos      => PlanItem.CustomAt("swapPos", id, ally) :: Nil
        case Op.OpWarpToStairs => PlanItem.CustomAt("warpToStairs", id, ally) :: Nil
        case Op.OpRingify      => PlanItem.CustomAt("ringify", id, ally) :: Nil
    }

    def statusItem(op: Op, id: Int32, ally: Bool, amt: Int32, dur: Option[Duration]): List[PlanItem] =
        match statusKind(op) {
            case Some(se) => PlanItem.StatusAt(id, ally, se, amt, turnsOf(dur)) :: Nil
            case None     => PlanItem.NoOp("status 写像なし") :: Nil
        }

    /// sfx があれば末尾に PlaySfx を足す。
    def appendSfx(items: List[PlanItem], sfx: Option[String]): List[PlanItem] = match sfx {
        case Some(s) => List.append(items, PlanItem.PlaySfx(s) :: Nil)
        case None    => items
    }

    /// 1 アクションを Plan へ。対象が解決できなければ NoOp（空振り）。
    pub def planAction(a: Action, ctx: PlanCtx): List[PlanItem] =
        match EffectRule.resolveTarget(a#to, ctx#selfId, ctx#attackerId, ctx#rayUnits) {
            case None      => PlanItem.NoOp("対象なし（空振り）") :: Nil
            case Some(ref) =>
                let amt = a#amount
                            |> Option.map(am -> EffectDsl.resolveAmount(am, ctx#amount))
                            |> Option.getWithDefault(0);
                appendSfx(opPlan(a#op, ref#id, ref#ally, amt, a#duration), a#sfx)
        }

    /// ルールの全 do[] アクションを Plan へ（do[] → flow 順は runFlow 側で扱う。ここは do[] のみ）。
    pub def planActions(rule: EffectRule.EffectRule, ctx: PlanCtx): List[PlanItem] =
        List.flatMap(a -> planAction(a, ctx), rule#actions)

    /// ルールが今このフレームで発動するか（確率ロール AND ガード述語）。
    /// roll は呼び出し側が引いた 0..99 の乱数、predCtx は述語評価の文脈。
    pub def shouldFire(rule: EffectRule.EffectRule, predCtx: EffectDsl.PredCtx, roll: Int32): Bool =
        roll < rule#chance and EffectDsl.evalPredicate(rule#cond, predCtx)
}
