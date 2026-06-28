/// EffectRunner — Plan（PlanItem 列）を実副作用へ流す interpreter
///
/// `EffectPlan.planActions` が確定した「何が・誰に・いくつ」を、実際の作用へ落とす唯一の出口。
/// 本エンジンの Scene は不変値を `|>` で畳んで更新するため、runPlan は**アキュムレータ `s`
/// （実 Scene では `Scene[NodeTag]`、テストでは記録リスト）を handler に通して畳む**。
/// 副作用そのものは `PlanHandlers` に逃がしてあり、実 Scene は Combat.heal / PlayerScene.mapPlayer /
/// AudioStreamPlayer.play を包んだ handler を、テストは呼び出しを記録する handler を渡す。
/// これにより「runPlan が PlanItem をどの handler へ・どの順で振り分けるか」を Scene 抜きで固定できる。
mod EffectRunner {

    use EffectPlan.PlanItem
    use StatusSystem.StatusEffect

    /// 各 PlanItem 種別に対応する handler の束。`s` は畳む状態（Scene / 記録）、`ef` はその効果。
    /// 全 handler が `(s, args) -> s` でアキュムレータを受け取り更新後を返す。
    pub type alias PlanHandlers[s: Type, ef: Eff] = {
        heal       = (s, Int32, Bool, Int32) -> s \ ef,
        fullHeal   = (s, Int32, Bool) -> s \ ef,
        damage     = (s, Int32, Bool, Int32) -> s \ ef,
        maxHpUp    = (s, Int32, Bool, Int32) -> s \ ef,
        status     = (s, Int32, Bool, StatusEffect, Int32, Int32) -> s \ ef,
        immobilize = (s, Int32, Bool, Int32) -> s \ ef,
        revive     = (s, Int32, Bool) -> s \ ef,
        custom     = (s, String, Int32, Bool) -> s \ ef,
        sfx        = (s, String) -> s \ ef,
        noOp       = (s, String) -> s \ ef
    }

    /// 1 つの PlanItem を対応する handler へ振り分け、更新後のアキュムレータを返す。
    /// 対象系は id と ally（使用者と同陣営か）を handler へ渡し、player/enemy を出し分けさせる。
    pub def runItem(h: PlanHandlers[s, ef], item: PlanItem, acc: s): s \ ef = match item {
        case PlanItem.HealAt(id, ally, n)        => h#heal(acc, id, ally, n)
        case PlanItem.FullHealAt(id, ally)       => h#fullHeal(acc, id, ally)
        case PlanItem.DamageAt(id, ally, n)      => h#damage(acc, id, ally, n)
        case PlanItem.MaxHpUpAt(id, ally, n)     => h#maxHpUp(acc, id, ally, n)
        case PlanItem.StatusAt(id, ally, se, m, t) => h#status(acc, id, ally, se, m, t)
        case PlanItem.ImmobilizeAt(id, ally, turns) => h#immobilize(acc, id, ally, turns)
        case PlanItem.ReviveAt(id, ally)         => h#revive(acc, id, ally)
        case PlanItem.CustomAt(op, id, ally)     => h#custom(acc, op, id, ally)
        case PlanItem.PlaySfx(name)              => h#sfx(acc, name)
        case PlanItem.NoOp(reason)               => h#noOp(acc, reason)
    }

    /// Plan 全体を順に畳む。do[] の適用順（上から）をそのまま保つ。
    pub def runPlan(h: PlanHandlers[s, ef], items: List[PlanItem], acc0: s): s \ ef =
        List.foldLeft((acc, item) -> runItem(h, item, acc), acc0, items)
}
