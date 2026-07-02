// CombatSystem — Phase C「resolveCombat」本体（★最初の真の `World→World`(系) System・branch 温存・cutover 前）
//
// combat の sim を `(World, [SimEvent])` として解く。view/anim/scene は触らず、演出は SimEvent log から
// 後段（ViewReplay）が replay する設計。live combat（signal 駆動の CombatDriver）は**消さず並行**で、
// golden-trace 等価が全 path で取れたら cutover する。土台:
//   - combatViewOf(ref, world)        … combat stats を World から（reader flip 済み）
//   - CombatRules.resolveStrike       … 命中/ダメージ/撃破（純 rule）
//   - World.RngDraw.nextPercent()     … 命中ロール（live=Math.Random / trace=seeded・draw 順は位置で決まる）
//   - World.growthOf / progressOf     … level-up 成長・進行度（World 完結）
//   - World.applyEventToWorld         … SimEvent を World へ畳む reducer
//   - SimEvent（Damaged/Dying/Alerted/Released/Lifesteal/Moved/Afflicted/ExpGained/LeveledUp/ViewFx）
//                                     … 戻り値の event 代数。**既存の CLOSED 集合を再利用**し、sim パスは新変種を足さない。
//
// 実装状況（正直なスコープ）:
//   ✓ player 攻撃の **撃破 path**（damage→hp 0 clamp / **crit damage(applyCrit)＋crit-kill exp 再計算** / exp / level-up）を
//     World 完結で解き、final-World は legacy と等価。**hit→crit→thief→growth の draw 順を legacy に一致**させたので、
//     crit 武器・growthRates>0 でも等価（crit=0/growthRates=0 の制約は外れた）。
//   ✓ **非撃破 path**（hp 更新 + SetAlerted(true) + releaseBind + **hit-exp 付与**）も legacy 等価。
//     ※ `SimEvent.Alerted` 変種は**この非撃破 path のために先行コミットで World.flix へ追加済み**であり、
//        以降の resolveCombat sim スライスは新 SimEvent 変種を一切足さない（後述の World.flix 追加は read-model のみ）。
//     ※ legacy は**命中したら撃破でなくても EXP を付与**する（battleExp(.., killed)）＝expEvents を両分岐で呼ぶ。
//     検証: TestGoldenTrace A2/A/overkill/roll-sensitive-levelup/**non-kill(alerted+progress)**/**crit(applyCrit)** が legacy に一致。
//   ✓ **ring/weapon 効果＆敵攻撃 path**（finisher / ring・weapon lifesteal / knockback / 敵攻撃 / 敵 effectRule status afflict /
//     counter チェーン合成）も legacy final-World 等価。**これらが World.flix へ足すのは read-model アクセサのみ**
//     （`equippedRingOf` / `posOf` / `boardOf`(mapSnapshot) / `effectRuleOf` ＝ weaponView と同じ Option-store mirror）で、
//     **新しい SimEvent / ViewFxKind 変種は作らず既存 CLOSED 集合を再利用**する（finisher=Damaged+Dying、lifesteal=Lifesteal、
//     knockback=Moved、status=Afflicted、敵死=ViewFx(Died)）。thief（盗人の剣）は World 不変＝draw 整合の roll だけ消費。
//     検証: TestGoldenTrace の Finisher / Ring・WeaponLifesteal(+emit順/level-up) / Knockback(+crit) /
//           Enemy(EffectRule/Immobilize/Overkill/NoHpOps) / **CounterChain（resolveAttack→resolveEnemyAttack 合成）** が legacy に一致。
//   ✓ **view-script 化**（ViewReplay の前段）: 命中 SE（`hitSoundName`）・魔法武器の着弾爆発（player 攻撃のみ）・
//     miss テキストポップアップを `ViewFx(Sound/Explosion/Popup)` としてログに載せた＝ログが「完全な view-script」。
//     これらは World identity（reducer no-op・eventToCmds=Nil）ゆえ golden/final-World 等価は不変。ダメージ数字
//     ポップアップ・HPバー・death 演出は既存 `Damaged`/`Dying`/`ViewFx(Died)` から ViewReplay が引ける。
//   ✓ **ViewReplay dispatcher ＋ cutover 配線済み**（戦闘は常時 ECS 経路・トグルも legacy branch も無し）。scene 権威の
//     副作用は cutover wrapper（`applyEcsSceneEffects`）が反映: statuses（Afflicted/Released）・level-up（pendingLevelUp
//     panel ＋ resource stat 成長 via `grownStats`）・武器耐久（`consumeEquippedWeapon`）。World 権威 field（hp/dying/
//     progress/alerted/pos）は eventToCmds→World の Cmd 経由。
//   ✓ P1-b: thief view-fx（`ViewFx(Thief)`＝`isRogueOf` read-model で点火）・drop 実体は wrapper `applyThiefDrop`。
//   ✓ P1-c: 敵ノックバック（faction-blind `knockbackEvents` を `resolveEnemyAttack` で再利用）。
//   cutover は ECS 既定化まで完了済み（legacy 分岐・トグルは撤去）。敵 heal effectRule / lifesteal+heal stacking も ECS 経路で解決する。
mod CombatSystem {

    /// 9 stat 成長ロール（legacy CombatDriver.rollGrowth と同義）。draw 順の厳密一致は spike では要求しない
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

    /// 1 撃の解決結果（被弾ダメージ / 被弾後 hp / 撃破フラグ / 必殺フラグ）。finisher>crit>base のどれを選んでも
    /// この型に落ちる。`isCrit` は **finisher も含む**（legacy resolveAttack:524 `isCrit or finisherFired`）で、
    /// view の命中 SE / 必殺タグ判定に使う。lifesteal/effectRule など後段は dmg/newHp/killed を読む。
    type alias Outcome = {dmg = Int32, newHp = Int32, killed = Bool, isCrit = Bool}

    /// SimEvent 列を World へ畳む（`applyEventToWorld` の foldLeft）。resolve 各所（二相 fold の中間 / 最終）で再利用。
    def applyAll(events: List[World.SimEvent], world: World): World =
        List.foldLeft((w, e) -> World.applyEventToWorld(e, w), world, events)

    /// miss 時の view-fx（SE "miss" ＋ "miss" テキストポップアップ）。legacy applyMiss を踏襲。
    /// いずれも World 不変＝ViewFx。防御側 pos が World 未登録（empty()-world 等）なら popup を省く（SE のみ）。
    /// player/enemy 両パス共通。
    def missFxEvents(world: World, defenderRef: World.EntityRef): List[World.SimEvent] =
        let popup =
            World.posOf(defenderRef, world)
                |> Option.map(c -> World.SimEvent.ViewFx(World.ViewFxKind.Popup({x = c#x, y = c#y, text = "miss"})))
                |> Option.toList;
        World.SimEvent.ViewFx(World.ViewFxKind.Sound("miss")) :: popup

    /// 命中時の view-fx（命中 SE ＋ 魔法武器の着弾爆発）。legacy applyHit:643-647 を踏襲＝SE→explosion の順で、
    /// その後に Damaged（数字ポップアップ／SetHp 相当）が続く。命中 SE 名は dmg/isCrit/weaponType 由来
    /// （`hitSoundName`：0 ダメ=guard / 必殺=critical / 魔法=magic / 通常=damage）。爆発は `allowExplosion`
    /// （player 攻撃のみ true。legacy 敵攻撃は爆発を出さない）かつ Magic 武器のとき防御側セルへ（dmg 非依存）。
    /// pos 未登録なら爆発を省く。武器なしは非魔法扱い。いずれも World 不変＝ViewFx。
    def hitFxEvents(world: World, defenderRef: World.EntityRef, atk: Combat.CombatView,
                    dmg: Int32, isCrit: Bool, allowExplosion: Bool): List[World.SimEvent] =
        let weaponType = atk#weapon |> Option.map(w -> w#weaponType);
        let sound = match weaponType {
            case Some(wt) => CombatRules.hitSoundName(dmg, isCrit, wt)
            case None     => if (dmg <= 0) "guard" else if (isCrit) "critical" else "damage"
        };
        let isMagic = match weaponType {
            case Some(WeaponCatalog.WeaponType.Magic) => true
            case _                                    => false
        };
        let explosion =
            if (allowExplosion and isMagic)
                World.posOf(defenderRef, world)
                    |> Option.map(c -> World.SimEvent.ViewFx(World.ViewFxKind.Explosion({x = c#x, y = c#y})))
                    |> Option.toList
            else Nil;
        World.SimEvent.ViewFx(World.ViewFxKind.Sound(sound)) :: explosion

    /// 結果優先順位 **finisher > crit > base** の選択（legacy CombatDriver:519-531 / :735-742 共通）。
    /// finisher（攻撃側 ring 装備＋防御側瀕死）は draw なしで確殺、crit は `critRoll` 判定、いずれも外れれば base strike。
    /// draw はここでは引かない（critRoll は呼び出し側で legacy 順に引いて渡す）。
    def combatOutcome(world: World, attacker: Combatant, defView: Combat.CombatView,
                      strike: {hit = Int32, dmg = Int32, newHp = Int32, killed = Bool, crit = Int32},
                      critRoll: Int32): Outcome =
        let finisherFired =
            Ring.finisherTriggers(defView#hp, defView#maxHp,
                Ring.finisherThreshold(World.equippedRingOf(attacker#ref, world)));
        let crit = Combat.isCrit(strike#crit, critRoll);
        let base =
            if (finisherFired)
                Combat.applyFinisher(strike#dmg, defView#hp)
            else if (crit)
                Combat.applyCrit(strike#dmg, defView#hp)
            else
                {dmg = strike#dmg, newHp = strike#newHp, killed = strike#killed};
        {dmg = base#dmg, newHp = base#newHp, killed = base#killed, isCrit = finisherFired or crit}

    /// ring-lifesteal（撃破時のみ・CombatDriver:560-567/761）＋ weapon-lifesteal（毎ヒット・:572-583/763）を
    /// **攻撃側 hp 基準（resolve 開始時の `atk#hp/maxHp`・自攻撃で不変）**で解く。emit 順は ring → weapon
    /// （legacy: 攻撃側 SetHp の last-write を weapon が勝つ）。player/enemy 両パス共通・draw なし。
    def lifestealEvents(world: World, attacker: Combatant, atk: Combat.CombatView, outcome: Outcome): List[World.SimEvent] =
        let ringLife = {
            let amt = Ring.lifestealAmount(World.equippedRingOf(attacker#ref, world));
            if (outcome#killed and amt > 0)
                World.SimEvent.Lifesteal(attacker#ref,
                    {newHp = Combat.heal(atk#hp, atk#maxHp, amt)#newHp, amt = amt}) :: Nil
            else Nil
        };
        let weaponLife =
            match atk#weapon {
                case None     => Nil
                case Some(wv) =>
                    let pct = WeaponCatalog.lifestealPercent(wv#effect, wv#effectValue);
                    let h   = (outcome#dmg * pct) / 100;
                    if (pct > 0 and outcome#dmg > 0)
                        World.SimEvent.Lifesteal(attacker#ref,
                            {newHp = Combat.heal(atk#hp, atk#maxHp, h)#newHp, amt = h}) :: Nil
                    else Nil
            };
        List.append(ringLife, weaponLife)

    /// 命中時の attacker 側 exp/level イベントを解く。legacy は**撃破でなくても命中なら EXP を付与**する
    /// （`battleExp(.., killed)`＝撃破なら kill exp・非撃破なら hit exp≥1）。exp 据置なら ExpGained、跨ぎなら LeveledUp。
    /// ★gap CLOSED: level-up 成長は `World.growthOf`（S-A0d）から読む＝resource threading 不要・World 完結。
    def expEvents(world: World, attacker: Combatant, defender: Combatant, killed: Bool): List[World.SimEvent] \ World.RngDraw =
        let expGain = Combat.battleExp(defender#level, attacker#level, killed);
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
                                              newExp = outcome#exp, newHp = newHp,
                                              grownStats = after, result = result}) :: Nil
                case None =>
                    // growth 未登録（enemy 等は level-up しない）＝防御的に exp 据置イベントに落とす。
                    World.SimEvent.ExpGained({entity = attacker#ref, newLevel = attacker#level, newExp = outcome#exp}) :: Nil
            }

    /// `attacker`（{ref, level}）→ `defender` の 1 撃を **sim 解決**し (World', [SimEvent]) を返す。
    /// World から combatView を読み、RngDraw で命中ロールを引き、SimEvent を産んで applyEventToWorld で畳む。
    /// scene も view も触らない＝これが Phase C の resolveCombat の最小形。
    ///
    /// P1a/P1b/P1c で ring/weapon 効果を追加（legacy CombatDriver:504-624 の draw 順・mutation 順を厳守）:
    ///   - **finisher**（死神のネックレス・draw なし）が crit に先行し kill を flip しうる（CombatDriver:519-531）。
    ///   - **ring-lifesteal**（みかえりのリング・撃破時のみ）と **weapon-lifesteal**（血吸いの剣・毎ヒット）が
    ///     攻撃側 hp を回復＝`Lifesteal`（CombatDriver:560-583）。攻撃側 hp 基準は resolve 開始時（自攻撃で不変）。
    ///   - **knockback**（如意棒/突風の書・敵生存時のみ）が敵 pos を `Moved`（CombatDriver:590-609）。draw なし。
    /// **二相 fold**: coreEvents→worldMid を先に畳み、`expEvents(worldMid)` で level-up hp を **post-lifesteal hp**
    /// に載せる（legacy applyExpGain は lifesteal 後の hp を読むため・CombatDriver:553-556）。
    /// thief（盗人の剣）は World 不変（floor-item は scene-only 副作用）＝draw 整合のため `_thiefRoll` のみ消費。
    pub def resolveAttack(world: World, attacker: Combatant, defender: Combatant):
            (World, List[World.SimEvent]) \ World.RngDraw =
        match (World.combatViewOf(attacker#ref, world), World.combatViewOf(defender#ref, world)) {
            case (Some(atk), Some(defView)) =>
                // draw 順は legacy 厳守: hit(1) → crit(2) → [命中時のみ] thief(3) → growth(4-12, expEvents)。
                // hit/crit は命中前に両方引く（legacy CombatDriver.flix:515-516）＝miss でも crit を消費する。
                let hitRoll  = World.RngDraw.nextPercent();
                let critRoll = World.RngDraw.nextPercent();
                let strike   = CombatRules.resolveStrike(atk, defView);
                let events =
                    if (not Combat.isHit(strike#hit, hitRoll))
                        missFxEvents(world, defender#ref)
                    else {
                        let fin = combatOutcome(world, attacker, defView, strike, critRoll);
                        // thief roll: legacy は命中時に必ず 1 draw 消費する（CombatDriver.flix:643 の rollPercent()）。
                        // draw 順を揃えるため hit(1)→crit(2) の後・draw 3 として引く。
                        // P1-b: isRogueOf read-model 追加で ViewFx(Thief) を emit 可能に（drop 実体は wrapper が引く）。
                        let thiefRoll = World.RngDraw.nextPercent();
                        // view-fx（命中 SE ＋ 魔法爆発）を先頭に置く（legacy applyHit:643-647 の SE→explosion→popup 順）。
                        let fx = hitFxEvents(world, defender#ref, atk, fin#dmg, fin#isCrit, true);
                        // core（敵への被弾）: 撃破=Damaged(hard 0)::Dying / 非撃破=Damaged::Alerted::Released。
                        // 撃破分岐の hard-0 clamp（legacy startDeathAnimation）を維持＝newHp=0 をベタ書き。
                        let coreEvents =
                            if (fin#killed)
                                // 撃破: hp=0（World）+ Dying（World 状態 SetDying）+ ViewFx(Died)（死亡演出＝ViewReplay が
                                // startDeathAnimation を引く）。ViewFx(Died) が無いと World は dying でも death_blink/撤去が
                                // 発火せず「HP 0 でも残存」になる（legacy startDeathAnimation は両者を兼ねていた）。
                                World.SimEvent.Damaged(defender#ref, {newHp = 0, dmg = fin#dmg})
                                    :: World.SimEvent.Dying(defender#ref)
                                    :: World.SimEvent.ViewFx(World.ViewFxKind.Died(defender#ref)) :: Nil
                            else
                                World.SimEvent.Damaged(defender#ref, {newHp = fin#newHp, dmg = fin#dmg})
                                    :: World.SimEvent.Alerted(defender#ref, true)
                                    :: World.SimEvent.Released(defender#ref) :: Nil;
                        // knockback（如意棒/突風の書・敵生存時のみ・CombatDriver:590-609）。draw なし。
                        let knock = knockbackEvents(world, attacker, defender, fin#killed);
                        // P1-b: thief drop（盗人の剣・敵生存時のみ・legacy CombatDriver:643）。ViewFx(Thief(敵セル))＝
                        // World 不変（eventToCmds→Nil）ゆえ worldMid 無影響。drop 実体は wrapper が引く。knock の後（legacy 順）。
                        let thiefFx = thiefDropEvents(world, attacker, defender, fin#killed, thiefRoll);
                        // 二相 fold: fx+core+lifesteal+knockback+thief を先に畳み、その worldMid から exp/level-up を解く
                        // （fx/thief は World identity ゆえ fold には無影響・順序のためログ先頭に積むだけ）。
                        let coreAll  = List.append(fx,
                                          List.append(coreEvents,
                                          List.append(lifestealEvents(world, attacker, atk, fin),
                                          List.append(knock, thiefFx))));
                        let worldMid = applyAll(coreAll, world);
                        let exps     = expEvents(worldMid, attacker, defender, fin#killed);
                        List.append(coreAll, exps)
                    };
                (applyAll(events, world), events)
            case (_, _) => (world, Nil)
        }

    /// P1c: 攻撃側の装備武器がノックバック武器で、かつ防御側が **生存** のとき、防御側を攻撃方向へ押し流す
    /// `Moved` を 1 つ返す（legacy applyAttackKnockback/pushEnemyBack・CombatDriver:590-609）。draw なし。
    /// 方向は攻撃側→防御側の delta を 4 方位に丸め、`Board.knockbackPathCapped` の最終着地へ。
    /// 武器なし / ノックバック武器でない / pos・board 未登録（empty()-world など）/ 撃破時は空＝no knockback。
    def knockbackEvents(world: World, attacker: Combatant, defender: Combatant, killed: Bool): List[World.SimEvent] =
        // 武器→ノックバック tiles を Option チェーンで先に確定し、pos×2＋board と合わせて 4-tuple match 1 段に畳む
        // （撃破 / 武器なし / 非ノックバック武器 / pos・board 未登録 はいずれも空＝no knockback）。
        let weaponTiles =
            World.combatViewOf(attacker#ref, world)
                |> Option.flatMap(cv -> cv#weapon)
                |> Option.flatMap(wv -> WeaponCatalog.knockbackTiles(wv#effect, wv#effectValue));
        match (killed, weaponTiles, World.posOf(attacker#ref, world), World.posOf(defender#ref, world), World.boardOf(world)) {
            case (false, Some(tiles), Some(a), Some(d), Some(board)) =>
                let dir = Staff.toVec2i(Staff.deltaToDirection(d#x - a#x, d#y - a#y));
                let cap = if (tiles <= 0) None else Some(tiles);
                Board.knockbackPathCapped(d, dir, board, cap)
                    |> List.last
                    |> Option.map(landing -> World.SimEvent.Moved(defender#ref, landing))
                    |> Option.toList
            case _ => Nil
        }

    /// P1-b: 盗人の剣の view-fx（`ViewFx(Thief(敵セル))`）を発火条件のとき 1 つ返す。legacy `maybeThiefDrop`
    /// （CombatDriver:708-719）の発火条件を厳密に映す＝装備武器の盗みドロップ率>0 かつ 攻撃側がローグ職 かつ
    /// 敵生存 かつ `roll < 率`。セルは敵の **元位置**（legacy は knockback 前の `enemy#gridPos` を渡す）＝初期 world の posOf。
    /// drop 実体（フロア落下＋ログ）は scene 権威ゆえ cutover wrapper（`applyEcsSceneEffects`）が ViewFx(Thief) を
    /// 見て `ThiefDropRequest` を引く。ViewFx は World 不変（eventToCmds→Nil）ゆえ event 列のどこに置いても sim 無影響。
    def thiefDropEvents(world: World, attacker: Combatant, defender: Combatant,
                         killed: Bool, roll: Int32): List[World.SimEvent] =
        let pct = World.combatViewOf(attacker#ref, world)
            |> Option.flatMap(cv -> cv#weapon)
            |> Option.map(wv -> WeaponCatalog.thiefDropChance(wv#effect, wv#effectValue))
            |> Option.getWithDefault(0);
        if (pct > 0 and World.isRogueOf(attacker#ref, world) and not killed and roll < pct)
            World.posOf(defender#ref, world)
                |> Option.map(cell -> World.SimEvent.ViewFx(World.ViewFxKind.Thief(cell)))
                |> Option.toList
        else Nil

    /// P2: 敵→プレイヤーの 1 撃を **sim 解決**し (World', [SimEvent]) を返す（legacy resolveEnemyAttack:706-778 の鏡像）。
    /// プレイヤーパス（resolveAttack）と異なる点:
    ///   - draw 構造: hit(1) → [命中時のみ] crit(2) → [rule 発火時のみ] effect(3)。**thief draw なし**。
    ///   - 被弾 hp は **RAW**（hard-0 clamp なし＝legacy:753 は raw を set）。プレイヤー死亡は **deferred** ＝
    ///     `ViewFx(Died)` のみ（`Dying`/`SetDying(player)` は World no-op の phantom ゆえ emit しない）。
    ///   - `Released` は撃破/非撃破とも **UNCONDITIONAL**（legacy:759）。`Alerted` なし・**level-up なし**（expEvents なし）。
    ///   - 命中後に敵 effectRule（毒/鈍足/かなしばり）を発火し status を `Afflicted(player, status)` で出荷
    ///     （`World.emitStatusAdds` の StatusAt/ImmobilizeAt マッピングを `planItemToAfflicted` で逐語踏襲）。
    ///   - 敵ノックバック（P1-c）: 味方生存時のみ faction-blind な `knockbackEvents` を再利用（lifesteal 後）。heal effectRule は P2b。
    pub def resolveEnemyAttack(world: World, attacker: Combatant, defender: Combatant):
            (World, List[World.SimEvent]) \ World.RngDraw =
        match (World.combatViewOf(attacker#ref, world), World.combatViewOf(defender#ref, world)) {
            case (Some(atk), Some(defView)) =>
                let hitRoll = World.RngDraw.nextPercent();
                let strike  = CombatRules.resolveStrike(atk, defView);
                let events =
                    if (not Combat.isHit(strike#hit, hitRoll))
                        missFxEvents(world, defender#ref)
                    else {
                        // crit は命中時のみ引く（プレイヤーパスと違い miss では引かない＝legacy:728）。
                        let critRoll = World.RngDraw.nextPercent();
                        let outcome  = combatOutcome(world, attacker, defView, strike, critRoll);
                        // view-fx（命中 SE のみ・爆発なし＝legacy 敵攻撃は ExplosionFx を出さない＝allowExplosion=false）。
                        let fx = hitFxEvents(world, defender#ref, atk, outcome#dmg, outcome#isCrit, false);
                        // core（味方への被弾）: RAW newHp（clamp なし）。撃破は deferred ＝ ViewFx(Died) のみ（Dying なし）。
                        // Released は UNCONDITIONAL（撃破でもかなしばり解除）。Alerted なし（敵は攻撃で alerted されない）。
                        let deathFx =
                            if (outcome#killed)
                                World.SimEvent.ViewFx(World.ViewFxKind.Died(defender#ref)) :: Nil
                            else Nil;
                        let coreBase =
                            World.SimEvent.Damaged(defender#ref, {newHp = outcome#newHp, dmg = outcome#dmg})
                                :: List.append(deathFx, World.SimEvent.Released(defender#ref) :: Nil);
                        // 敵 lifesteal（ring=撃破時のみ:761 / weapon=毎ヒット:763）は P1b プレイヤーパスと同形＝共通ヘルパー。
                        let steal = lifestealEvents(world, attacker, atk, outcome);
                        // P1-c: 敵ノックバック（如意棒等・味方生存時のみ）。faction-blind な knockbackEvents を再利用
                        // （legacy applyEnemyKnockback/pushPlayerBack CombatDriver:1056-1075 と同一計算＝味方を攻撃方向へ）。
                        // 位置は lifesteal の後・effectRule tail の前（legacy CombatDriver:888 の順）。
                        let knock = knockbackEvents(world, attacker, defender, outcome#killed);
                        let coreEvents = List.append(List.append(coreBase, steal), knock);
                        // effectRule tail（legacy applyEnemyEffectRule:785-822）: status を Afflicted で出荷。
                        let effectTail = enemyEffectRuleEvents(world, attacker, defender, atk, defView, outcome);
                        List.append(fx, List.append(coreEvents, effectTail))
                    };
                (applyAll(events, world), events)
            case (_, _) => (world, Nil)
        }

    /// P2: 命中後の敵 effectRule（毒/鈍足/かなしばり）を解いて `Afflicted` event 列を返す
    /// （legacy applyEnemyEffectRule:785-822）。rule なし/不正 Json/trigger 不一致/確率不発は空。
    /// effect roll は rule が確定し trigger が当たったときだけ **CONDITIONAL** に 1 draw（legacy:801 の短絡順序を保つ）。
    /// StatusAt/ImmobilizeAt のみ `planItemToAfflicted` で Afflicted へ写像（HealAt/FullHealAt=P2b、
    /// DamageAt/MaxHpUpAt/ReviveAt は legacy ハンドラ no-op ＝ World 不変ゆえ event なし）。
    def enemyEffectRuleEvents(world: World, attacker: Combatant, defender: Combatant,
                               atk: Combat.CombatView, defView: Combat.CombatView, outcome: Outcome):
            List[World.SimEvent] \ World.RngDraw =
        // None カスケード（rule 無し/不正/trigger 不一致）を 1 段に畳む。ここまで draw を引かない＝確定した敵だけ下で roll。
        let fired =
            (forM (
                j    <- World.effectRuleOf(attacker#ref, world);
                rule <- EffectBridge.fromComposer(j)
            ) yield rule)
                |> Option.filter(rule -> triggerFiresOnHit(rule#trigger, outcome#killed));
        match fired {
            case None       => Nil
            case Some(rule) =>
                let roll = World.RngDraw.nextPercent();   // CONDITIONAL effect draw（legacy:801）
                let predCtx = {selfHpPct       = hpPct(atk#hp, atk#maxHp),
                               targetHpPct     = hpPct(outcome#newHp, defView#maxHp),
                               targetAlive     = outcome#newHp > 0,
                               equippedIsRogue = false,
                               adjacent        = true};
                if (not EffectPlan.shouldFire(rule, predCtx, roll)) Nil
                else {
                    // ray 上の対象は被弾した味方駒 1 体（is-player ⇒ ally=true）。amount は CLOSED 4-field。
                    let rayUnits = ({id = rawId(defender#ref), ally = true, immobilized = false,
                                     alive = outcome#newHp > 0}: EffectRule.RayUnit) :: Nil;
                    let ctx = {selfId = rawId(attacker#ref), attackerId = rawId(attacker#ref),
                               actorIsPlayer = false, rayUnits = rayUnits,
                               amount = {max = defView#maxHp, dealt = outcome#dmg, incoming = 0, magic = 0}};
                    let plan = EffectPlan.planActions(rule, ctx);
                    List.filterMap(planItemToAfflicted, plan)
                }
        }

    /// P2: EffectPlan の status 項目を `Afflicted` event へ写像（`World.emitStatusAdds`:971-978 の
    /// StatusAt/ImmobilizeAt マッピングを逐語踏襲）。hp 系（heal/damage/maxHpUp/revive）と装飾は
    /// World 不変ゆえ event なし（None）。HealAt/FullHealAt の Healed 化は P2b で別途。
    def planItemToAfflicted(item: EffectPlan.PlanItem): Option[World.SimEvent] = match item {
        case EffectPlan.PlanItem.StatusAt(id, ally, se, m, t) =>
            Some(World.SimEvent.Afflicted(World.refOf(ally, id),
                {effect = se, magnitude = m, remaining = t}))
        case EffectPlan.PlanItem.ImmobilizeAt(id, ally, turns) =>
            Some(World.SimEvent.Afflicted(World.refOf(ally, id), StatusSystem.immobilizeFor(turns)))
        case _ => None
    }

    /// 戦闘ヒットパスで発火するトリガーか（legacy triggerFiresOnHit:826-831 を逐語踏襲）。
    /// 命中後ブランチゆえ OnHit/OnAttack は常に true、OnKill は撃破時のみ、他は false。
    def triggerFiresOnHit(t: EffectRule.Trigger, killed: Bool): Bool = match t {
        case EffectRule.Trigger.OnHit    => true
        case EffectRule.Trigger.OnAttack => true
        case EffectRule.Trigger.OnKill   => killed
        case _                           => false
    }

    /// HP 割合（0..100）。最大 HP が 0 以下なら 0（legacy hpPct:833-835 を踏襲・ゼロ除算回避）。
    def hpPct(hp: Int32, maxHp: Int32): Int32 =
        if (maxHp <= 0) 0 else (hp * 100) / maxHp

    /// EntityRef の **生 id**（scene 側の int）を取り出す。effectRule の ctx/rayUnit が要する
    /// （`World.toUid` は enemy に enemyUidBase を足すので effectRule の raw id には使えない）。
    def rawId(ref: World.EntityRef): Int32 = match ref {
        case World.EntityRef.Player(i) => i
        case World.EntityRef.Enemy(i)  => i
    }

}
