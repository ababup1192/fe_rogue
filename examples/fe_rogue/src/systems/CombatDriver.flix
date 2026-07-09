/// CombatDriver — 攻守両対応の戦闘解決（攻撃モーション・命中判定・ダメージ・反撃・経験値）
///
/// `PlayerScene` / `EnemyScene` から戦闘解決ロジックを切り出した補助モジュール。
/// 両モジュールは状態所有（構築・移動・死亡演出・Query effect）に専念し、
/// ここは「攻撃モーション → 命中判定 → ダメージ → 反撃判定 → 経験値」だけを担う。
/// 攻撃側の陣営は `Faction`（UnitView.flix）で渡し、内部の match で
/// `PlayerScene.*` / `EnemyScene.*` に振り分ける。
///
/// 配置基準: `src/systems/` は「World と各 resource を橋渡しする driver / orchestrator」
/// （step()・シグナル配信の層）、純 `World→World` System は
/// `src/world/systems/`（CombatSystem / StaffSystem）に置く分界。
/// 純 sim の戦闘解決は `CombatSystem.resolveCombat` が担い、ここは
/// signal 駆動の攻撃演出とターン進行の orchestration を受け持つ。
///
/// 攻撃の流れ（攻守共通）:
///   1. `startAttack(side, ...)` で `Cmd.StartLunge`（World の lunge store）を発行し `attackTarget` を立てる
///   2. lunge 中点（`World.stepAnimClocks` の AttackHit signal）で `onAttackHit(side, ...)`
///      （命中ロール → ダメージ → 味方攻撃なら EXP/レベルアップ、敵攻撃なら死亡/ゲームオーバー判定）
///   3. lunge 終端（LungeDone signal）で `onLungeDone(side, ...)` → 反撃/確定を分岐
///
/// `onLungeDone` の phase マトリクス（反撃の往復はこのモジュール内で完結する）:
///
///   | side   | TurnPhase        | 意味           | 動作                                            |
///   |--------|------------------|----------------|-------------------------------------------------|
///   | Player | PlayerAttackHold | 味方主攻撃完了 | CounterAttackRules.decide → Kill/Counter/Commit |
///   | Player | EnemyTurn        | 味方反撃完了   | clear + pendingLevelUp なら LevelUpView 割込（再反撃なし） |
///   | Enemy  | EnemyTurn        | 敵主攻撃完了   | decidePlayerCounter → 味方反撃 startAttack      |
///   | Enemy  | PlayerAttackHold | 敵反撃完了     | clear + commitWaitedAndAdvance                  |
///
/// `PlayerScene` と `EnemyScene` は `Data`/`get` を**両方が**持つため、
/// 味方側は `PlayerScene.`、敵側は `EnemyScene.` で完全修飾する（`use` は開かない）。
///
/// 注意（意図的な責務越境）: `onLungeDone` は「攻撃完了 → 次ターン進行判断」の orchestrator
/// で、`TurnFlow.commitWaitedAndAdvance`（汎用ターン進行）/ `PhaseTransitions` を跨ぐ。
/// 攻撃の完了がそのままターン遷移のトリガになるための設計。
mod CombatDriver {

    /// 攻撃ターゲットの敵 id を World の attackTarget store に記録する。
    /// 武器選択ウィンドウを開く前に呼ばれ、ウィンドウ確定後の
    /// フェーズが AttackForecast に進み、`BattlePanelUi.confirm` がこの値を読んで
    /// 実際の攻撃モーションを開始する。
    pub def setAttackTargetId(playerId: Int32, targetEnemyId: Int32): Unit \ World.Command =
        World.Command.emit(World.Cmd.SetAttackTarget(World.EntityRef.Player(playerId), targetEnemyId))

    /// `attackTarget` をクリアする（武器選択のキャンセル時や lunge 完了時）。
    pub def clearAttackTargetId(playerId: Int32): Unit \ World.Command =
        World.Command.emit(World.Cmd.ClearAttackTarget(World.EntityRef.Player(playerId)))

    /// 敵側の attackTarget をクリアする（clearAttackTargetId と対称）。
    def clearEnemyAttackTarget(enemyId: Int32): Unit \ World.Command =
        World.Command.emit(World.Cmd.ClearAttackTarget(World.EntityRef.Enemy(enemyId)))

    /// 攻撃対象 id を **World.attackTarget 権威** で読む（両 faction・単一 store）。
    def attackTargetFor(ref: World.EntityRef, world: World): Option[Int32] =
        World.attackTargetOf(ref, world)

    /// 体当たりの片道（origin → target）所要時間。Forward + Returning の合計が
    /// アニメ全長になる。視認性を保つため移動 (16/120) より速めに設定する。
    def attackPhaseDuration(): Duration.Duration =
        Duration.frames(count = 16, fps = 200)   // ≈ 0.08 秒 / 片道

    /// lunge の再生パラメータ（World の lunge store へ seed する値）。
    /// - origin/target: 攻撃側セル中心 → 対象セル中心（位置は elapsed から `World.lungeRenderPos` が導出）
    /// - hitAt: 中点（target に重なる瞬間）＝片道 1 phase の秒数 → AttackHit signal（ダメージ適用 + SE）
    /// - total: 2 phase 分の全長 → LungeDone signal（waited 確定 / 次状態へ）
    pub def lungeSpec(originGrid: {x = Int32, y = Int32},
                       targetGrid: {x = Int32, y = Int32}):
                      {origin = Vec2.Vec2, target = Vec2.Vec2, hitAt = Float64, total = Float64} =
        let phase = attackPhaseDuration();
        {origin = MapSnapshot.cellCenter(originGrid),
         target = MapSnapshot.cellCenter(targetGrid),
         hitAt  = Duration.toSeconds(phase),
         total  = Duration.toSeconds(Duration.add(phase, phase))}

    /// 体当たり攻撃モーションを開始する（攻守共通の入口）。
    /// `Cmd.StartLunge` で World の lunge store に往復演出を積み、`attackTarget = Some(defenderId)` を立てる。
    /// 中点で AttackHit、終端で LungeDone signal が届き（`World.stepAnimClocks`）、それぞれ
    /// `onAttackHit` / `onLungeDone` が解決する。
    /// 武器を持たないユニットは攻撃に到達してはいけない設計で、防御的に no-op する
    /// （味方: PlayerAttackRangeScene/TurnRules、敵: EnemyAI が禁止する）。
    /// 攻撃開始（faction-blind）。武器なし（`weaponRange = None`）は filter で弾いて no-op。
    /// faction dispatch は **`World.refOfSide`** に閉じ込め、ここは faction-blind。
    pub def startAttack(side: Faction, attackerId: Int32, defenderId: Int32,
                         targetGrid: {x = Int32, y = Int32}):
            Unit \ {World.Command, World.WorldQuery} =
        let attacker = World.refOfSide(side, attackerId);
        match (EntityScene.unitView(attacker) |> Option.filter(u -> Option.nonEmpty(u#weaponRange))) {
            case Some(uv) =>
                World.Command.emit(World.Cmd.StartLunge(attacker, lungeSpec(uv#pos, targetGrid)));
                World.Command.emit(World.Cmd.SetAttackTarget(attacker, defenderId))
            case None => ()
        }

    /// lunge 中点の AttackHit signal 受信時の処理（攻守共通の入口）。
    /// - Player: `applyAttackHit` で敵への攻撃を解決（命中ロール → ダメージ/EXP → レベルアップ）。
    /// - Enemy: `applyEnemyAttackHit` の killed リストを `PlayerScene.removeDeadAndCheckGameOver`
    ///   に流し、全滅時は `CustomEffects.GameOverRequest` でフルリビルドさせる。
    pub def onAttackHit(side: Faction, id: Int32):
            Unit \ {GameEngine.Audio,
                    GameLogger.GameLogger,
                    CustomEffects.GameOverRequest,
                    SelectedPlayer.State, World.RngDraw,
                    CustomEffects.ThiefDropRequest, World.Command, World.WorldQuery} =
        match side {
            case Faction.Player => applyAttackHit(id)
            case Faction.Enemy  =>
                let killed = applyEnemyAttackHit(id);
                PlayerScene.removeDeadAndCheckGameOver(killed)
        }

    /// 味方の AttackHit のダメージ適用。
    /// 当該 player の攻撃対象 id を **World.attackTarget** から読み、対応する敵への攻撃を解決する。
    /// 命中ロールは ECS（CombatSystem.resolveCombat）側で行い、命中なら SE + ダメージ + ログ、
    /// 回避なら SE を鳴らさず "miss" 表示のみ。HP <= 0 なら death_blink を開始する。
    pub def applyAttackHit(playerId: Int32):
            Unit \ {GameEngine.Audio,
                    GameLogger.GameLogger, World.RngDraw,
                    CustomEffects.ThiefDropRequest, World.Command, World.WorldQuery} =
        let world = World.WorldQuery.get();
        let resolved = forM (
            d       <- PlayerScene.get(playerId);
            enemyId <- attackTargetFor(World.EntityRef.Player(playerId), world)
        ) yield applyDamageToEnemy(playerId, d, enemyId);
        Option.getWithDefault((), resolved)

    /// 敵の AttackHit のダメージ適用（ECS 一本）。
    /// 戻り値は HP=0 になったプレイヤー id のリスト。
    /// killedIds が空でないとき呼び出し側は死亡処理（removeDeadAndCheckGameOver）を発火する。
    pub def applyEnemyAttackHit(enemyId: Int32):
            List[Int32] \
            {GameEngine.Audio, World.RngDraw,
             World.Command, World.WorldQuery} =
        let world = World.WorldQuery.get();
        let resolved = forM (
            d              <- EnemyScene.get(enemyId);
            targetPlayerId <- attackTargetFor(World.EntityRef.Enemy(enemyId), world)
        ) yield applyDamageToPlayer(enemyId, d, targetPlayerId);
        Option.getWithDefault(Nil, resolved)

    /// lunge 終端の LungeDone signal 受信時の処理（攻守共通の入口）。
    /// 反撃の往復（味方攻撃 → 敵反撃 / 敵攻撃 → 味方反撃）はこの関数の中で完結する。
    /// FE 風で「反撃の反撃」は実装しない（反撃完了側の分岐は clear + 進行のみ）。
    pub def onLungeDone(side: Faction, id: Int32):
            Unit \ {RangeOverlayState.State,
                    GameLogger.GameLogger,
                    EnemyTurn.Queue, TurnPhase.State,
                    SelectedPlayer.State, CursorState.State, Pacing.State, World.RngDraw, World.Command, World.PhaseQuery, World.WorldQuery} =
        match side {
            case Faction.Player => playerLungeDone(id)
            case Faction.Enemy  => enemyLungeDone(id)
        }

    /// 味方の LungeDone。2 通りある:
    ///   - `PlayerAttackHold` (= 味方主攻撃の完了) → CounterAttackRules.decide で分岐:
    ///       Kill (敵瀕死) / Counter (敵反撃) / Commit (waited 確定)。
    ///   - `EnemyTurn` (= 敵攻撃に対する味方反撃の完了) → 単純に attackTarget クリア。
    ///       次フレーム以降で EnemyTurnDriver が World.anyPlayerAttacking が false に
    ///       なったのを見て次の step に進む。
    def playerLungeDone(playerId: Int32):
            Unit \ {RangeOverlayState.State,
                    GameLogger.GameLogger,
                    EnemyTurn.Queue, TurnPhase.State,
                    SelectedPlayer.State, CursorState.State, Pacing.State, World.RngDraw, World.Command, World.PhaseQuery, World.WorldQuery} =
        // 「敵ターンか」の sim-phase 判定は World 由来（19-case 詳細は不要ゆえ 3-case で足りる）。
        if (World.PhaseQuery.phase() == SimPhase.EnemyTurn) {
            // 敵ターン中の味方反撃が完了した。反撃でレベルアップしていれば、その場で
            // （反撃ごとに）ステータス変化パネルへ割り込む。閉じると敵ターンに戻って続行する。
            clearAttackTargetId(playerId);
            if (PlayerScene.anyPendingLevelUp())
                PhaseTransitions.enterLevelUpView()
            else
                ()
        } else {
            // 味方主攻撃の完了。まず追撃リング判定（補正後speed差+3 & 15% & 未追撃 & 敵生存）。
            // 追撃するなら decide（反撃/確定）より前に同じ敵へもう一度攻撃する（追撃→反撃の直列）。
            match playerFollowUpEnemy(playerId, rollPercent(), World.WorldQuery.get()) {
                case Some(enemyId) =>
                    // followUpUsed は World 権威。
                    World.Command.emit(World.Cmd.SetFollowUpUsed(World.EntityRef.Player(playerId), true));
                    startPlayerFollowUp(playerId, enemyId)
                case None =>
                    resolvePlayerMainAttack(playerId)
            }
        }

    // 追撃判定 shouldFollowUp / braveFollowUp は純 leaf として CombatRules.flix にある。

    /// 味方が追撃すべきなら対象の敵 id を返す（しないなら None）。speed は combatView の補正後値。
    /// 攻撃者・対象の敵が揃ったときだけ判定する（match は入れ子にしない）。
    def playerFollowUpEnemy(playerId: Int32, roll: Int32, world: World): Option[Int32] =
        let pOpt = World.dataFromWorld(playerId, world);
        let eOpt = pOpt |> Option.flatMap(_ -> attackTargetFor(World.EntityRef.Player(playerId), world))
                        |> Option.flatMap(eid -> World.dataFromWorldEnemy(eid, world));
        match (pOpt, eOpt) {
            case (Some(p), Some(e)) =>
                let braveT = PlayerData.equippedWeapon(p#weapons)
                    |> Option.flatMap(w -> WeaponCatalog.braveThreshold(w#effect, w#effectValue));
                // 速度判定は World の combatViewOf 由来（followUpUsed と同じ read）。
                let atkSpd = World.combatViewOf(World.EntityRef.Player(playerId), world)
                                 |> Option.map(cv -> cv#speed)
                                 |> Option.getWithDefault(PlayerScene.combatView(p)#speed);
                let defSpd = World.combatViewOf(World.EntityRef.Enemy(e#id), world)
                                 |> Option.map(cv -> cv#speed)
                                 |> Option.getWithDefault(EnemyScene.combatView(e)#speed);
                // 追撃判定を DSL の flow 層（EffectFlow.followUpDecision）へ寄せる。brave/pursuit の
                // どちらかが成立すれば追撃（ロジックは shouldFollowUp/braveFollowUp と同一・テスト済）。
                let fctx = {atkSpd = atkSpd, defSpd = defSpd, roll = roll,
                            followUpUsed = World.followUpUsedOf(World.EntityRef.Player(playerId), world)
                                              |> Option.getWithDefault(false),  // World 権威・未登録=未使用
                            brave = braveT,
                            pursuit = Ring.hasPursuit(PlayerData.equippedRing(p))};
                if (EffectFlow.followUpDecision(EffectRule.Flow.FollowUp(EffectRule.FollowKind.Brave), fctx)
                    or EffectFlow.followUpDecision(EffectRule.Flow.FollowUp(EffectRule.FollowKind.Pursuit), fctx))
                    attackTargetFor(World.EntityRef.Player(playerId), world)
                else None
            case _ => None
        }

    /// 味方の追撃モーションを開始する（同じ敵へ再突進）。敵が消えていれば通常進行に落とす。
    def startPlayerFollowUp(playerId: Int32, enemyId: Int32):
            Unit \ {RangeOverlayState.State,
                    GameLogger.GameLogger, EnemyTurn.Queue, TurnPhase.State,
                    SelectedPlayer.State, CursorState.State, Pacing.State, World.Command, World.WorldQuery} =
        match EnemyScene.get(enemyId) {
            case Some(e) =>
                GameLogger.playerLog("追撃！");
                startAttack(Faction.Player, playerId, enemyId, e#gridPos)
            case None =>
                resolvePlayerMainAttack(playerId)
        }

    /// 味方主攻撃完了の従来分岐（追撃なし）。CounterAttackRules.decideView（faction-blind）で Kill/Counter/Commit。
    def resolvePlayerMainAttack(playerId: Int32):
            Unit \ {RangeOverlayState.State,
                    GameLogger.GameLogger, EnemyTurn.Queue, TurnPhase.State,
                    SelectedPlayer.State, CursorState.State, Pacing.State, World.Command, World.WorldQuery} =
        // faction-blind な decideView（UnitView ベース）で分岐する（味方→敵）。
        // view は World 由来（unitViewFromWorld）。ECS 戦闘は hp を World にしか書かないため
        // 直前の攻撃結果（Kill/Counter 分岐の hp）が正しく読める。
        let w0 = World.WorldQuery.get();
        let outcome = PlayerScene.get(playerId)
            |> Option.map(player -> CounterAttackRules.decideView(
                   World.unitViewFromWorld(World.EntityRef.Player(playerId), w0)
                       |> Option.getWithDefault(PlayerScene.unitView(player)),
                   attackTargetFor(World.EntityRef.Player(playerId), w0)
                       |> Option.flatMap(eid -> World.unitViewFromWorld(World.EntityRef.Enemy(eid), w0))));
        match outcome {
            case None => ()
            case Some(CounterAttackRules.Outcome.Kill) =>
                clearAttackTargetId(playerId);
                TurnPhase.State.put(TurnPhase.Phase.PlayerAttackHold);
                Pacing.State.hold(700 |> Duration.millis)
            case Some(CounterAttackRules.Outcome.Counter(enemyId)) =>
                clearAttackTargetId(playerId);
                startEnemyCounter(enemyId, playerId)
            case Some(CounterAttackRules.Outcome.Commit) =>
                clearAttackTargetId(playerId);
                TurnFlow.commitWaitedAndAdvance()
        }

    /// 敵 enemyId による反撃モーションを開始する（Counter 分岐の本体）。
    /// 反撃対象の味方が消えていれば反撃せず通常のターン確定に落とす。
    def startEnemyCounter(enemyId: Int32, playerId: Int32):
            Unit \ {RangeOverlayState.State,
                    GameLogger.GameLogger,
                    EnemyTurn.Queue, TurnPhase.State,
                    SelectedPlayer.State, CursorState.State, World.Command, World.WorldQuery} =
        match PlayerScene.get(playerId) {
            case Some(p) =>
                GameLogger.enemyLog("${EnemyScene.displayName(enemyId)}の反撃");
                startAttack(Faction.Enemy, enemyId, playerId, p#gridPos)
            case None =>
                TurnFlow.commitWaitedAndAdvance()
        }

    /// 敵の LungeDone。2 通りある:
    ///   - `PlayerAttackHold` (= 味方攻撃に対する敵反撃の完了) → commit
    ///   - `EnemyTurn` (= 敵ターン中の主攻撃完了) → 味方反撃判定。
    ///       CounterAttackRules.decideView（faction-blind）を回し、Counter(playerId) なら
    ///       `startAttack(Faction.Player, ...)` で反撃モーション開始。
    ///       それ以外は単純に attackTarget クリアして EnemyTurnDriver に制御を戻す。
    /// `PlayerAttackHold` は「攻撃を振った側が lunge を開始する瞬間から
    /// 反撃 lunge が終わるまで」を Hold させるための設計で、往復の間ずっと Hold が続く。
    def enemyLungeDone(enemyId: Int32):
            Unit \ {RangeOverlayState.State,
                    GameLogger.GameLogger,
                    EnemyTurn.Queue, TurnPhase.State,
                    SelectedPlayer.State, CursorState.State, World.RngDraw, World.Command, World.WorldQuery} =
        if (TurnPhase.State.get() == TurnPhase.Phase.PlayerAttackHold) {
            clearEnemyAttackTarget(enemyId);
            TurnFlow.commitWaitedAndAdvance()
        } else {
            // EnemyTurn 中の敵主攻撃完了。先に追撃リング判定（敵 speed 差+3 & 15% & 未追撃 & 味方生存）。
            // 追撃するなら反撃判定より前に同じ味方へもう一度攻撃する。
            match enemyFollowUpPlayer(enemyId, rollPercent(), World.WorldQuery.get()) {
                case Some(playerId) =>
                    // followUpUsed は World 権威。
                    World.Command.emit(World.Cmd.SetFollowUpUsed(World.EntityRef.Enemy(enemyId), true));
                    startEnemyFollowUp(enemyId, playerId)
                case None =>
                    resolveEnemyMainAttack(enemyId)
            }
        }

    /// 敵が追撃すべきなら対象の味方 id を返す（しないなら None）。speed は combatView の補正後値。
    def enemyFollowUpPlayer(enemyId: Int32, roll: Int32, world: World): Option[Int32] =
        let eOpt = World.dataFromWorldEnemy(enemyId, world);
        let pOpt = eOpt |> Option.flatMap(_ -> attackTargetFor(World.EntityRef.Enemy(enemyId), world))
                        |> Option.flatMap(pid -> World.dataFromWorld(pid, world));
        match (eOpt, pOpt) {
            case (Some(e), Some(p)) =>
                let braveT = e#weapon
                    |> Option.flatMap(w -> WeaponCatalog.braveThreshold(w#effect, w#effectValue));
                // 速度判定は World の combatViewOf 由来（followUpUsed と同じ read・fallback 安全）。
                let atkSpd = World.combatViewOf(World.EntityRef.Enemy(enemyId), world)
                                 |> Option.map(cv -> cv#speed)
                                 |> Option.getWithDefault(EnemyScene.combatView(e)#speed);
                let defSpd = World.combatViewOf(World.EntityRef.Player(p#id), world)
                                 |> Option.map(cv -> cv#speed)
                                 |> Option.getWithDefault(PlayerScene.combatView(p)#speed);
                let fctx = {atkSpd = atkSpd, defSpd = defSpd, roll = roll,
                            followUpUsed = World.followUpUsedOf(World.EntityRef.Enemy(enemyId), world)
                                              |> Option.getWithDefault(false),  // World 権威・未登録=未使用
                            brave = braveT,
                            pursuit = Ring.hasPursuit(e#ring)};
                if (EffectFlow.followUpDecision(EffectRule.Flow.FollowUp(EffectRule.FollowKind.Brave), fctx)
                    or EffectFlow.followUpDecision(EffectRule.Flow.FollowUp(EffectRule.FollowKind.Pursuit), fctx))
                    attackTargetFor(World.EntityRef.Enemy(enemyId), world)
                else None
            case _ => None
        }

    /// 敵の追撃モーションを開始する（同じ味方へ再突進）。味方が消えていれば反撃判定に落とす。
    def startEnemyFollowUp(enemyId: Int32, playerId: Int32):
            Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery} =
        match PlayerScene.get(playerId) {
            case Some(p) =>
                GameLogger.enemyLog("追撃！");
                startAttack(Faction.Enemy, enemyId, playerId, p#gridPos)
            case None =>
                resolveEnemyMainAttack(enemyId)
        }

    /// 敵主攻撃完了の従来分岐（追撃なし）。味方反撃の対象を決め、反撃なら startAttack。
    def resolveEnemyMainAttack(enemyId: Int32):
            Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery} =
        // faction-blind な decideView で分岐する（敵→味方）。
        // view は World 由来（resolvePlayerMainAttack と同じ理由＝直前ダメージの hp を正しく読む）。
        let w0 = World.WorldQuery.get();
        let decision = forM (
            e <- EnemyScene.get(enemyId)
        ) yield (e, CounterAttackRules.decideView(
                     World.unitViewFromWorld(World.EntityRef.Enemy(enemyId), w0)
                         |> Option.getWithDefault(EnemyScene.unitView(e)),
                     attackTargetFor(World.EntityRef.Enemy(enemyId), w0)
                         |> Option.flatMap(pid -> World.unitViewFromWorld(World.EntityRef.Player(pid), w0))));
        match decision {
            case Some((e, CounterAttackRules.Outcome.Counter(playerId))) =>
                clearEnemyAttackTarget(enemyId);
                GameLogger.playerLog("${PlayerScene.displayName(playerId)}の反撃");
                startAttack(Faction.Player, playerId, enemyId, e#gridPos)
            case _ => clearEnemyAttackTarget(enemyId)
        }

    /// entity 1 体ぶんの戦闘シグナル解決。フレームの signal 一括
    /// （`World.stepAnimClocks` の出力）から自 entity 宛だけを拾い、
    /// AttackHit (中点) / LungeDone (完了) / DeathBlinkDone (敵のみ、完了) に反応する。
    /// `stepEntities` が在籍 id を辿り (per-entity) ここへ渡す。
    /// EntityRef 完全一致なので他ユニットの signal は取りこぼさない。
    /// 死亡演出 (DeathBlinkDone) は敵のライフサイクルなので `EnemyScene.onDeathBlinkDone` に委譲。
    /// GameOver 中は全 signal を無視する（全滅モーダルの盤面フリーズ。GameOver を引き起こした
    /// dispatch より後の entity から即座に効く）。
    /// 待機モーションへの復帰は Tween 完了をトリガーにせず、
    /// setWaited / clearAllWaited (= 待機確定 / 次ターン開始) に集約している。
    def drainAndDispatch(signals: List[World.AnimSignal], side: Faction, id: Int32):
            Unit \ {RangeOverlayState.State,
                    GameEngine.Audio,
                    GameLogger.GameLogger,
                    CustomEffects.GameOverRequest,
                    CustomEffects.ThiefDropRequest,
                    EnemyTurn.Queue, TurnPhase.State,
                    SelectedPlayer.State, CursorState.State, Pacing.State, World.RngDraw, World.Command, World.PhaseQuery, World.WorldQuery} =
        if (TurnPhase.State.get() == TurnPhase.Phase.GameOver) ()
        else {
            let ownerRef = World.refOfSide(side, id);   // faction dispatch は World.refOfSide に集約
            List.forEach(s -> match s {
                case World.AnimSignal.AttackHit(r) =>
                    if (r == ownerRef) onAttackHit(side, id) else ()
                case _ => ()
            }, signals);
            List.forEach(s -> match (s, side) {
                case (World.AnimSignal.LungeDone(r), _) =>
                    if (r == ownerRef) onLungeDone(side, id) else ()
                case (World.AnimSignal.DeathBlinkDone(r), Faction.Enemy) =>
                    if (r == ownerRef) EnemyScene.onDeathBlinkDone(id) else ()
                case _ => ()
            }, signals)
        }

    /// Player / Enemy の戦闘シグナル解決を明示 System として毎フレーム 1 回回す
    /// （gameLoop の固定パイプライン段）。在籍 id を「味方 id 昇順 → 敵 id 昇順」で辿り、
    /// 各 entity を `drainAndDispatch` に渡す。各 entity は signal 一括から自 entity 宛だけを
    /// 拾うため、巡回順に依らず取りこぼさない。
    /// 巡回中に signal 処理で despawn した entity（敵撃破など）は、fresh な在籍集合を
    /// 読み直して読み飛ばす。
    pub def stepEntities(signals: List[World.AnimSignal]):
            Unit \ {RangeOverlayState.State,
                    GameEngine.Audio, GameLogger.GameLogger,
                    CustomEffects.GameOverRequest, CustomEffects.ThiefDropRequest,
                    EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State, CursorState.State,
                    Pacing.State, World.RngDraw, World.Command, World.PhaseQuery, World.WorldQuery} =
        let w0 = World.WorldQuery.get();
        let refs = List.append(
            World.playerIdsOf(w0) |> List.map(id -> (Faction.Player, id)),
            World.enemyIdsOf(w0)  |> List.map(id -> (Faction.Enemy, id)));
        List.forEach(pr -> {
            let (side, id) = pr;
            // 途中の despawn（敵撃破・味方脱落）を fresh な在籍集合で読み飛ばす。
            let w = World.WorldQuery.get();
            let alive = match side {
                case Faction.Player => List.memberOf(id, World.playerIdsOf(w))
                case Faction.Enemy  => List.memberOf(id, World.enemyIdsOf(w))
            };
            if (alive) drainAndDispatch(signals, side, id) else ()
        }, refs)

    /// 命中ロール用の 0..99 の一様乱数。`Combat.isHit(hitRate, roll)` に渡す。
    def rollPercent(): Int32 \ World.RngDraw =
        World.RngDraw.nextPercent()

    /// 攻撃 1 回の純粋な算出結果（命中率・与ダメージ・撃破後 HP・撃破か・経験値）。
    /// 乱数も World も使わないので、これ単体で命中率やダメージ式をテストできる。
    pub type alias AttackForecast = {
        hitRate = Int32,   // 命中率 0..100（命中ロールと比較する）
        dmg     = Int32,   // 命中時の与ダメージ
        newHp   = Int32,   // 命中後の敵 HP（0 以上）
        killed  = Bool,    // この命中で敵を撃破するか
        exp     = Int32,   // 命中で得る経験値
        crit    = Int32    // 必殺率 0..100（必殺ロールと比較する）
    }

    // 1 撃解決 resolveStrike は純 leaf として CombatRules.flix にある。

    /// 装備武器と敵から、命中率・与ダメージ・経験値を**純粋に**算出する（乱数非依存）。
    /// 計算は `CombatRules.resolveStrike`（= `Combat.estimate`）に委譲し、武器タイプ習熟・武器相性・
    /// 物理/魔法の解決を戦闘予報と実ダメージで一致させる。テストしやすいよう pub。
    /// 攻撃側・防御側の `CombatView`（+ レベル）から forecast を組む（faction/source 非依存・純粋）。
    /// 予報（`attackForecast`）も実解決（`resolveAttack`）も共有＝式の単一源泉。
    pub def forecastFromViews(attacker: Combat.CombatView, defender: Combat.CombatView,
                              atkLevel: Int32, defLevel: Int32): AttackForecast =
        let strike = CombatRules.resolveStrike(attacker, defender);
        {hitRate = strike#hit, dmg = strike#dmg, newHp = strike#newHp, killed = strike#killed,
         exp = Combat.battleExp(defLevel, atkLevel, strike#killed), crit = strike#crit}

    pub def attackForecast(player: PlayerScene.Data, weapon: UnitCatalog.WeaponResource,
                            enemy: EnemyScene.Data): AttackForecast =
        forecastFromViews(PlayerScene.combatViewWith(player, weapon), EnemyScene.combatView(enemy),
                          player#level, enemy#resource#level)

    /// 敵 id にダメージを与える（装備武器 `weapons.head` と敵が揃っていなければ no-op）。
    /// `CombatSystem.resolveAttack` で sim を解き、events→Cmds で World へ反映し、`ViewReplay.replay` で演出を再生する。
    /// level-up モーダルは `applyEcsWorldEffects` の pendingLevelUp で発火、thief drop は `applyThiefDrop`。
    /// 前提（武器あり・敵あり）の解決だけを担い、ネストを避けるため Option を `forM` で短絡的に畳む。
    def applyDamageToEnemy(playerId: Int32, player: PlayerScene.Data, enemyId: Int32):
            Unit \ {GameEngine.Audio,
                    GameLogger.GameLogger, World.RngDraw,
                    CustomEffects.ThiefDropRequest, World.Command, World.WorldQuery} =
        let resolved = forM (
            weapon <- PlayerData.equippedWeapon(player#weapons);
            enemy  <- EnemyScene.get(enemyId)
        ) yield ecsResolvePlayerAttack(playerId, player, weapon, enemyId, enemy);
        Option.getWithDefault((), resolved)

    /// ECS 経路の event 後処理。statuses は World 権威:
    ///   - Afflicted/Released は直前の eventToCmds（Cmd.Add / ClearImmobilized）で World へ適用済み。
    ///     ここでは適用後の全リストを `Cmd.Seed`（全置換）で確定 emit する＝Cmd-stream 上の Seed は
    ///     「event 反映後の statuses スナップショット」として golden が凍結する契約の一部。
    ///   - `pendingLevelUp`（level-up モーダルの trigger）: LeveledUp で SetPendingLevelUp(Some) を emit。
    /// level/exp/hp 自体は eventToCmds（Cmd.Progress/SetHp→World）で World 権威に反映される。
    def applyEcsWorldEffects(events: List[World.SimEvent]): Unit \ {World.Command, World.WorldQuery} =
        List.forEach(ev -> match ev {
            case World.SimEvent.Afflicted(World.EntityRef.Player(id), _) =>
                PlayerScene.updateStatuses(id, xs -> xs)
            case World.SimEvent.Afflicted(World.EntityRef.Enemy(id), _) =>
                EnemyScene.updateStatuses(id, xs -> xs)
            case World.SimEvent.Released(World.EntityRef.Player(id)) =>
                PlayerScene.updateStatuses(id, xs -> xs)
            case World.SimEvent.Released(World.EntityRef.Enemy(id)) =>
                EnemyScene.updateStatuses(id, xs -> xs)
            case World.SimEvent.LeveledUp(p) =>
                // pendingLevelUp（panel trigger・World 権威）＋ resource の成長後 stat 反映。
                // level/exp/hp は eventToCmds→World→derive 済み。resource テンプレ（playerResource store）を
                // 成長後値で更新する。
                match p#entity {
                    case World.EntityRef.Player(id) =>
                        World.Command.emit(World.Cmd.SetPendingLevelUp(id, Some(p#result)));
                        match World.playerResourceOf(World.EntityRef.Player(id), World.WorldQuery.get()) {
                            case Some(res) => World.Command.emit(World.Cmd.SetPlayerResource(id, LevelSystem.withStats(p#grownStats, res)))
                            case None      => ()
                        };
                        // level-up で resource が成長＝baseStats の source が変わる。command-derive store へ
                        // read-after-mutate で emit（適用後 resource を読む）。
                        PlayerScene.emitBaseStatsFromWorld(id)
                    case World.EntityRef.Enemy(_)   => ()
                }
            case _ => ()
        }, events)

    /// sim が発火した `ViewFx(Thief(cell))` を見て、盗み drop の
    /// 副作用（フロア落下＋『…が アイテムを落とした』ログ）を引く。発火判定（ローグ職・敵生存・確率）は
    /// sim（`thiefDropEvents`）が済ませ、ここは drop 実体だけ担う。enemyId は wrapper が持つ＝ログの敵名に使う。
    /// ViewReplay（純 view）でなく wrapper で処理するのは、ドロップが在庫/床の状態変更だから。
    def applyThiefDrop(events: List[World.SimEvent], enemyId: Int32):
            Unit \ {CustomEffects.ThiefDropRequest, GameLogger.GameLogger, World.WorldQuery} =
        let thiefCells = events |> List.filterMap(ev -> match ev {
            case World.SimEvent.ViewFx(World.ViewFxKind.Thief(cell)) => Some(cell)
            case _                                                   => None
        });
        List.forEach(cell -> {
            GameLogger.playerLog("${EnemyScene.displayName(enemyId)}が アイテムを落とした");
            CustomEffects.ThiefDropRequest.drop(cell)
        }, thiefCells)

    /// ECS 経路（味方攻撃）: `CombatSystem.resolveAttack` で 1 撃の sim を解いて [SimEvent] を得、
    /// `eventToCmds` で World へ反映し、`ViewReplay.replay` で演出を再生する。
    /// `applyEcsWorldEffects` で statuses/pendingLevelUp も確定する。
    /// `applyThiefDrop` で盗人の剣のフロア落下（knockback 後・武器耐久前の順）、最後に `consumeEquippedWeapon` で
    /// 武器耐久を消費（命中/回避とも毎攻撃で消費）。
    /// 演出進行（lunge/counter/follow-up）は signal が引く。
    def ecsResolvePlayerAttack(playerId: Int32, player: PlayerScene.Data,
                                weapon: UnitCatalog.WeaponResource, enemyId: Int32,
                                enemy: EnemyScene.Data):
            Unit \ {GameEngine.Audio,
                    GameLogger.GameLogger, World.RngDraw, World.Command,
                    World.WorldQuery, CustomEffects.ThiefDropRequest} =
        let world = World.WorldQuery.get();
        let (_, events) = CombatSystem.resolveAttack(world,
            {ref = World.EntityRef.Player(playerId), level = player#level},
            {ref = World.EntityRef.Enemy(enemyId), level = enemy#resource#level});
        List.forEach(c -> World.Command.emit(c), events |> List.flatMap(World.eventToCmds));
        ViewReplay.replay(events);
        applyEcsWorldEffects(events);
        applyThiefDrop(events, enemyId);
        consumeEquippedWeapon(playerId, weapon)

    /// ノックバックの攻撃側・被攻撃側セル（同型 {x,y} が 2 つで誤順しやすいので名前渡し）。
    type alias KnockbackPos = {attacker = {x = Int32, y = Int32}, defender = {x = Int32, y = Int32}}

    /// FE ルールに従い、攻撃を振った時点で装備武器（先頭）の耐久を 1 減らす（回避されても同様）。
    /// 耐久が 0 になったら先頭を取り除き破損ログを出す。
    def consumeEquippedWeapon(playerId: Int32, weapon: UnitCatalog.WeaponResource):
            Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery} =
        let consumed = Weapon.consume(weapon);
        if (Option.isEmpty(consumed))
            GameLogger.playerLog("${PlayerScene.displayName(playerId)}の ${weapon#name}がこわれた")
        else ();
        // 在庫は World 権威＝現在値を読んで耐久消費後の並びを Cmd で書く。
        // 装備武器（先頭）が変わり得る＝putWeapons が weaponView も 1:1 co-emit する。
        let newWeapons = CombatRules.replaceOrDropHead(consumed, PlayerScene.weaponsW(playerId));
        PlayerScene.putWeapons(playerId, newWeapons)

    // 武器リスト先頭差し替え replaceOrDropHead は純 leaf として CombatRules.flix にある。

    /// プレイヤー targetId にダメージを与える。命中率・素ダメージは `CombatRules.resolveStrike`
    /// （= `Combat.estimate`、武器相性・物理/魔法込み）で算出し、`Combat.damage` 適用後の
    /// HP に更新する。攻撃成立後は武器の `durability` を 1 減らし、
    /// 0 になったら `weapon = None` に切り替え、ログに「敵N の {武器名} がこわれた」を出す。
    /// ログはスペック準拠で「敵{N} → P{M} に Xダメージ」、撃破時「敵{N} → P{M} を撃破」。
    /// HP=0 なら killedIds に追加して返す（呼び出し側が死亡処理を発火する）。
    /// 武器なし（None）でここに到達した場合は防御的に何もしない。
    def applyDamageToPlayer(enemyId: Int32, enemy: EnemyScene.Data, targetId: Int32):
            List[Int32] \
            {GameEngine.Audio, World.RngDraw,
             World.Command, World.WorldQuery} =
        // 前提（武器あり・対象あり）の解決だけを担う。実体は ECS 経路のみ。
        let resolved = forM (
            _weapon <- enemy#weapon;
            player  <- PlayerScene.get(targetId)
        ) yield ecsResolveEnemyAttack(enemyId, enemy, targetId, player);
        Option.getWithDefault(Nil, resolved)

    /// ECS 経路（敵攻撃）: `CombatSystem.resolveEnemyAttack` で 1 撃を解き events→Cmds で World 反映・
    /// `ViewReplay.replay` で演出。味方死亡は **deferred**（`ViewFx(Died(Player))`）ゆえ killedIds をそこから導出して
    /// 返す（呼び出し側の `removeDeadAndCheckGameOver` ＝ game-over 経路へ）。
    def ecsResolveEnemyAttack(enemyId: Int32, enemy: EnemyScene.Data, targetId: Int32,
                               player: PlayerScene.Data):
            List[Int32] \ {GameEngine.Audio,
                           World.RngDraw, World.Command, World.WorldQuery} =
        let world = World.WorldQuery.get();
        let (_, events) = CombatSystem.resolveEnemyAttack(world,
            {ref = World.EntityRef.Enemy(enemyId), level = enemy#resource#level},
            {ref = World.EntityRef.Player(targetId), level = player#level});
        List.forEach(c -> World.Command.emit(c), events |> List.flatMap(World.eventToCmds));
        ViewReplay.replay(events);
        applyEcsWorldEffects(events);
        List.filterMap(ev -> match ev {
            case World.SimEvent.ViewFx(World.ViewFxKind.Died(World.EntityRef.Player(pid))) => Some(pid)
            case _                                                                          => None
        }, events)

}
