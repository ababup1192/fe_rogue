/// EffectRunner — Plan（PlanItem 列）を実副作用へ流す interpreter
///
/// `EffectPlan.planActions` が確定した「何が・誰に・いくつ」を、実際の副作用
/// （HP 書き換え・状態付与・演出）へ落とす唯一の出口。副作用そのものは `PlanHandlers`
/// に逃がしてあり、実 Scene は Combat.heal / StatusSystem.add / AudioStreamPlayer.play を
/// 包んだ handler を渡し、テストは呼び出しを記録する recorder handler を渡す。
/// これにより「runPlan が PlanItem をどの handler へ振り分けるか」を Scene 抜きで検証できる
/// （実ゲームのライブ状態を立ち上げずにディスパッチの正しさを固定する）。
mod EffectRunner {

    use EffectPlan.PlanItem
    use StatusSystem.StatusEffect

    /// 各 PlanItem 種別に対応する副作用 handler の束。effect 変数 `ef` で
    /// 実 Scene（Scene[NodeTag] / Audio 等）でもテスト（region/Ref）でも同じ runPlan を使える。
    pub type alias PlanHandlers[ef: Eff] = {
        heal       = (Int32, Int32) -> Unit \ ef,
        fullHeal   = Int32 -> Unit \ ef,
        damage     = (Int32, Int32) -> Unit \ ef,
        maxHpUp    = (Int32, Int32) -> Unit \ ef,
        status     = (Int32, StatusEffect, Int32, Int32) -> Unit \ ef,
        immobilize = Int32 -> Unit \ ef,
        revive     = Int32 -> Unit \ ef,
        custom     = (String, Int32) -> Unit \ ef,
        sfx        = String -> Unit \ ef,
        noOp       = String -> Unit \ ef
    }

    /// 1 つの PlanItem を対応する handler へ振り分ける。
    pub def runItem(h: PlanHandlers[ef], item: PlanItem): Unit \ ef = match item {
        case PlanItem.HealAt(id, n)          => h#heal(id, n)
        case PlanItem.FullHealAt(id)         => h#fullHeal(id)
        case PlanItem.DamageAt(id, n)        => h#damage(id, n)
        case PlanItem.MaxHpUpAt(id, n)       => h#maxHpUp(id, n)
        case PlanItem.StatusAt(id, se, m, t) => h#status(id, se, m, t)
        case PlanItem.ImmobilizeAt(id)       => h#immobilize(id)
        case PlanItem.ReviveAt(id)           => h#revive(id)
        case PlanItem.CustomAt(op, id)       => h#custom(op, id)
        case PlanItem.PlaySfx(name)          => h#sfx(name)
        case PlanItem.NoOp(reason)           => h#noOp(reason)
    }

    /// Plan 全体を順に実行する。do[] の適用順（上から）をそのまま保つ。
    pub def runPlan(h: PlanHandlers[ef], items: List[PlanItem]): Unit \ ef =
        List.forEach(item -> runItem(h, item), items)
}
