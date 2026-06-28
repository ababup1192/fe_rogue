// CombatSpike — THROWAWAY SPIKE（Phase C resolveCombat モデルの妥当性検証用・production 未配線）
//
// 目的: 「combat の sim を解いて (World, [SimEvent]) を返す」resolveCombat モデルを **player 攻撃 1 本**で
// 検証する。既存の土台だけで組めるか（threading 無しで World から読めるか）を確かめる:
//   - combatViewOf(ref, world)        … combat stats を World から（flip 済み）
//   - CombatRules.resolveStrike       … 命中/ダメージ/撃破（純 rule）
//   - World.RngDraw.nextPercent()     … 命中ロール（live=Math.Random / trace=seeded・draw 順は位置で決まる）
//   - World.applyEventToWorld         … SimEvent を World へ畳む reducer
//   - SimEvent（Damaged/Dying/ExpGained/LeveledUp/ViewFx）… 戻り値の event 代数
// view/anim/scene は一切触らない（ViewFx で表現するに留める）。
//
// ★所見（テスト testSpike* に記録）:
//   1. damage/kill/exp は **World だけから解ける**（combatViewOf + progressOf + hpOf + RngDraw）。
//   2. level-up の成長も **World 完結**になった（`World.growthOf`=S-A0d で base Stats + 成長率 + 表示名を読む）。
//      spike が当初露出した「level-up は resource を要する」gap は growth component（S-A0d）の追加で CLOSED。
//      resolveAttack は resource を一切 threading せず、引数は (world, attackerRef, defenderRef, levels) のみ。
mod CombatSpike {

    /// 9 stat 成長ロール（legacy CombatScene.rollGrowth と同義）。draw 順の厳密一致は spike では要求しない
    /// （それは golden-trace=本丸の仕事）。ここでは「level-up が成長ロールを要する」構造だけを示す。
    def rollGrowth(): LevelSystem.Rolls \ World.RngDraw =
        {hp = World.RngDraw.nextPercent(), attack = World.RngDraw.nextPercent(),
         defense = World.RngDraw.nextPercent(), magicAttack = World.RngDraw.nextPercent(),
         magicDefense = World.RngDraw.nextPercent(), speed = World.RngDraw.nextPercent(),
         skill = World.RngDraw.nextPercent(), luck = World.RngDraw.nextPercent(),
         constitution = World.RngDraw.nextPercent()}

    /// 撃破時の attacker 側 exp/level イベントを解く。exp 据置なら ExpGained、レベルアップなら LeveledUp。
    /// ★gap CLOSED: level-up 成長は `World.growthOf`（S-A0d）から読む＝resource threading 不要・World 完結。
    def expEvents(world: World, attackerRef: World.EntityRef, atkLevel: Int32, defLevel: Int32):
            List[World.SimEvent] \ World.RngDraw =
        let expGain = Combat.battleExp(defLevel, atkLevel, true);
        let curExp  = match World.progressOf(attackerRef, world) {
                        case Some((_, xp)) => xp
                        case None          => 0
                      };
        let curHp   = World.hpOf(attackerRef, world) |> Option.getWithDefault(0);
        let outcome = LevelSystem.gainExp(curExp, expGain);
        if (not outcome#levelUp)
            World.SimEvent.ExpGained({entity = attackerRef, newLevel = atkLevel, newExp = outcome#exp}) :: Nil
        else
            match World.growthOf(attackerRef, world) {
                case Some(g) =>
                    let rolls  = rollGrowth();
                    let after  = LevelSystem.applyGrowth(g#base, g#rates, rolls);
                    let newHp  = curHp + (after#hp - g#base#hp);
                    let result = LevelSystem.buildResult(g#name, atkLevel, g#base, after);
                    World.SimEvent.LeveledUp({entity = attackerRef, newLevel = atkLevel + 1,
                                              newExp = outcome#exp, newHp = newHp, result = result}) :: Nil
                case None =>
                    // growth 未登録（enemy 等は level-up しない）＝防御的に exp 据置イベントに落とす。
                    World.SimEvent.ExpGained({entity = attackerRef, newLevel = atkLevel, newExp = outcome#exp}) :: Nil
            }

    /// player(attackerRef) → enemy(defenderRef) の 1 撃を **sim 解決**し (World', [SimEvent]) を返す。
    /// World から combatView を読み、RngDraw で命中ロールを引き、SimEvent を産んで applyEventToWorld で畳む。
    /// scene も view も触らない＝これが Phase C の resolveCombat の最小形。
    pub def resolveAttack(world: World, attackerRef: World.EntityRef, defenderRef: World.EntityRef,
                          atkLevel: Int32, defLevel: Int32): (World, List[World.SimEvent]) \ World.RngDraw =
        match (World.combatViewOf(attackerRef, world), World.combatViewOf(defenderRef, world)) {
            case (Some(atk), Some(defView)) =>
                let hitRoll = World.RngDraw.nextPercent();
                let strike  = CombatRules.resolveStrike(atk, defView);
                let events  =
                    if (hitRoll >= strike#hit)
                        World.SimEvent.ViewFx(World.ViewFxKind.Sound("miss")) :: Nil
                    else if (strike#killed)
                        World.SimEvent.Damaged(defenderRef, {newHp = strike#newHp, dmg = strike#dmg})
                            :: World.SimEvent.Dying(defenderRef)
                            :: expEvents(world, attackerRef, atkLevel, defLevel)
                    else
                        World.SimEvent.Damaged(defenderRef, {newHp = strike#newHp, dmg = strike#dmg}) :: Nil;
                let world1 = List.foldLeft((w, e) -> World.applyEventToWorld(e, w), world, events);
                (world1, events)
            case (_, _) => (world, Nil)
        }

}
