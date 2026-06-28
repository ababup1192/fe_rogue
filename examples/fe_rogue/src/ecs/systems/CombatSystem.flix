// CombatSystem — Phase C「resolveCombat」本体（★最初の真の `World→World`(系) System・branch 温存・cutover 前）
//
// combat の sim を `(World, [SimEvent])` として解く。view/anim/scene は触らず、演出は SimEvent log から
// 後段（ViewReplay）が replay する設計。live combat（signal 駆動の CombatScene）は**消さず並行**で、
// golden-trace 等価が全 path で取れたら cutover する。土台:
//   - combatViewOf(ref, world)        … combat stats を World から（reader flip 済み）
//   - CombatRules.resolveStrike       … 命中/ダメージ/撃破（純 rule）
//   - World.RngDraw.nextPercent()     … 命中ロール（live=Math.Random / trace=seeded・draw 順は位置で決まる）
//   - World.growthOf / progressOf     … level-up 成長・進行度（World 完結）
//   - World.applyEventToWorld         … SimEvent を World へ畳む reducer
//   - SimEvent（Damaged/Dying/ExpGained/LeveledUp/ViewFx）… 戻り値の event 代数
//
// 実装状況（正直なスコープ）:
//   ✓ player 攻撃の **撃破 path**（damage→hp 0 clamp / exp / level-up）を World 完結で解ける。final-World は
//     legacy と等価 — ただし **crit=0・growthRates=0・命中固定の golden fixture 範囲**での等価。
//     検証: TestGoldenTrace の A2(no-levelup)/A(levelup) 凍結 World に resolveAttack が一致（下記 ☐ がその制約を外す）。
//   ☐ 残（legacy 厳密一致への反復・golden gate）:
//      - **crit/finisher の damage・撃破・exp 再計算**（現状は base ダメージのみ＝crit 武器で乖離・CombatScene.flix:521-537）
//      - **非撃破 path の SetAlerted + releaseBind**（`SimEvent.Alerted` 変種の追加が要・現状 Damaged のみ＝enemyAlerted/immob が乖離）
//      - hit→crit→thief→growth の **draw 順厳密一致**（現状 hit 1 draw のみ＝counter/follow-up 連鎖で seeded stream desync）
//      - weapon 効果（knockback/thief/status）・counter チェーン（反撃）・enemy 攻撃 path・ViewReplay 配線・cutover。
mod CombatSystem {

    /// 9 stat 成長ロール（legacy CombatScene.rollGrowth と同義）。draw 順の厳密一致は spike では要求しない
    /// （それは golden-trace=本丸の仕事）。ここでは「level-up が成長ロールを要する」構造だけを示す。
    def rollGrowth(): LevelSystem.Rolls \ World.RngDraw =
        {hp = World.RngDraw.nextPercent(), attack = World.RngDraw.nextPercent(),
         defense = World.RngDraw.nextPercent(), magicAttack = World.RngDraw.nextPercent(),
         magicDefense = World.RngDraw.nextPercent(), speed = World.RngDraw.nextPercent(),
         skill = World.RngDraw.nextPercent(), luck = World.RngDraw.nextPercent(),
         constitution = World.RngDraw.nextPercent()}

    /// 戦闘の一方（攻撃側 / 防御側）。同型の `EntityRef` と `level: Int32` を 2 つ並べて取ると誤順しやすいので、
    /// 各陣営を 1 レコードに束ねて名前渡しする（`attacker#ref`/`attacker#level`）。
    pub type alias Combatant = {ref = World.EntityRef, level = Int32}

    /// 撃破時の attacker 側 exp/level イベントを解く。exp 据置なら ExpGained、レベルアップなら LeveledUp。
    /// ★gap CLOSED: level-up 成長は `World.growthOf`（S-A0d）から読む＝resource threading 不要・World 完結。
    def expEvents(world: World, attacker: Combatant, defender: Combatant): List[World.SimEvent] \ World.RngDraw =
        let expGain = Combat.battleExp(defender#level, attacker#level, true);
        let curExp  = match World.progressOf(attacker#ref, world) {
                        case Some((_, xp)) => xp
                        case None          => 0
                      };
        let curHp   = World.hpOf(attacker#ref, world) |> Option.getWithDefault(0);
        let outcome = LevelSystem.gainExp(curExp, expGain);
        if (not outcome#levelUp)
            World.SimEvent.ExpGained({entity = attacker#ref, newLevel = attacker#level, newExp = outcome#exp}) :: Nil
        else
            match World.growthOf(attacker#ref, world) {
                case Some(g) =>
                    let rolls  = rollGrowth();
                    let after  = LevelSystem.applyGrowth(g#base, g#rates, rolls);
                    let newHp  = curHp + (after#hp - g#base#hp);
                    let result = LevelSystem.buildResult(g#name, attacker#level, g#base, after);
                    World.SimEvent.LeveledUp({entity = attacker#ref, newLevel = attacker#level + 1,
                                              newExp = outcome#exp, newHp = newHp, result = result}) :: Nil
                case None =>
                    // growth 未登録（enemy 等は level-up しない）＝防御的に exp 据置イベントに落とす。
                    World.SimEvent.ExpGained({entity = attacker#ref, newLevel = attacker#level, newExp = outcome#exp}) :: Nil
            }

    /// `attacker`（{ref, level}）→ `defender` の 1 撃を **sim 解決**し (World', [SimEvent]) を返す。
    /// World から combatView を読み、RngDraw で命中ロールを引き、SimEvent を産んで applyEventToWorld で畳む。
    /// scene も view も触らない＝これが Phase C の resolveCombat の最小形。
    pub def resolveAttack(world: World, attacker: Combatant, defender: Combatant):
            (World, List[World.SimEvent]) \ World.RngDraw =
        match (World.combatViewOf(attacker#ref, world), World.combatViewOf(defender#ref, world)) {
            case (Some(atk), Some(defView)) =>
                let hitRoll = World.RngDraw.nextPercent();
                let strike  = CombatRules.resolveStrike(atk, defView);
                let events  =
                    if (hitRoll >= strike#hit)
                        World.SimEvent.ViewFx(World.ViewFxKind.Sound("miss")) :: Nil
                    else if (strike#killed)
                        // B1: 撃破時の最終 hp は legacy（startDeathAnimation が hard 0 を emit）に合わせ 0 に clamp。
                        // strike#newHp は overkill で負値になり得るが、legacy/golden oracle は常に 0。
                        World.SimEvent.Damaged(defender#ref, {newHp = 0, dmg = strike#dmg})
                            :: World.SimEvent.Dying(defender#ref)
                            :: expEvents(world, attacker, defender)
                    else
                        World.SimEvent.Damaged(defender#ref, {newHp = strike#newHp, dmg = strike#dmg}) :: Nil;
                let world1 = List.foldLeft((w, e) -> World.applyEventToWorld(e, w), world, events);
                (world1, events)
            case (_, _) => (world, Nil)
        }

}
