/// CombatDriver — 攻守両対応の戦闘解決（攻撃モーション・命中判定・ダメージ・反撃・経験値）
///
/// `PlayerScene` / `EnemyScene` から戦闘解決ロジックを切り出した補助モジュール。
/// 両 Scene は状態所有（構築・移動・死亡演出・Data・Query effect）に専念し、
/// ここは「攻撃モーション → 命中判定 → ダメージ → 反撃判定 → 経験値」だけを担う。
/// 攻撃側の陣営は `Faction`（UnitView.flix）で渡し、内部の match で
/// `PlayerScene.*` / `EnemyScene.*` に振り分ける。
///
/// 配置基準: ノードを所有しないため `src/scenes/` ではなく `src/systems/` に置く。
/// `src/systems/` は「scene 結合の driver / orchestrator」（step()・シグナル配信で
/// Scene と World を橋渡しする層）、純 `World→World` System（scene 非依存）は
/// `src/ecs/systems/`（CombatSystem / StaffSystem）に置く分界。
/// 純 sim の戦闘解決は `CombatSystem.resolveCombat` が担い、ここは
/// signal 駆動の攻撃演出とターン進行の orchestration を受け持つ。
///
/// 攻撃の流れ（攻守共通）:
///   1. `startAttack(side, ...)` で `attack_lunge` アニメを登録し `attackTargetId` を立てる
///   2. アニメ中点の `attack:hit` メソッドで `onAttackHit(side, ...)`
///      （命中ロール → ダメージ → 味方攻撃なら EXP/レベルアップ、敵攻撃なら死亡/ゲームオーバー判定）
///   3. アニメ終端の finished で `onLungeDone(side, ...)` → 反撃/確定を分岐
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
/// `PlayerScene` と `EnemyScene` は `Data`/`get`/`mapXxx` を**両方が**持つため、
/// 味方側は `PlayerScene.`、敵側は `EnemyScene.` で完全修飾する（`use` は開かない）。
///
/// 注意（意図的な責務越境）: `onLungeDone` は「攻撃完了 → 次ターン進行判断」の orchestrator
/// で、`TurnFlow.commitWaitedAndAdvance`（汎用ターン進行）/ `PhaseTransitions` を跨ぐ。
/// 攻撃の完了がそのままターン遷移のトリガになるための設計。
mod CombatDriver {

    /// 攻撃ターゲットの敵 id を Data#attackTargetId に記録する。
    /// 武器選択ウィンドウを開く前に GameManager から呼ばれ、ウィンドウ確定後の
    /// フェーズが AttackForecast に進み、`BattlePanelScene.confirm` がこの値を読んで
    /// 実際の攻撃モーションを開始する。
    pub def setAttackTargetId(playerId: Int32, targetEnemyId: Int32,
                                scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        World.Command.emit(World.Cmd.SetAttackTarget(World.EntityRef.Player(playerId), targetEnemyId));
        PlayerScene.mapPlayer(playerId, d -> {attackTargetId = Some(targetEnemyId) | d}, scene)

    /// `attackTargetId` をクリアする（武器選択のキャンセル時や `attack_lunge` finished 時）。
    pub def clearAttackTargetId(playerId: Int32,
                                  scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        World.Command.emit(World.Cmd.ClearAttackTarget(World.EntityRef.Player(playerId)));
        PlayerScene.mapPlayer(playerId, d -> {attackTargetId = None | d}, scene)

    /// 敵側の attackTargetId をクリアする（clearAttackTargetId と対称）。
    def clearEnemyAttackTarget(enemyId: Int32,
                                scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        World.Command.emit(World.Cmd.ClearAttackTarget(World.EntityRef.Enemy(enemyId)));
        EnemyScene.mapEnemy(enemyId, d -> {attackTargetId = None | d}, scene)

    /// 体当たりの片道（origin → target）所要時間。Forward + Returning の合計が
    /// アニメ全長になる。視認性を保つため移動 (16/120) より速めに設定する。
    def attackPhaseDuration(): Duration.Duration =
        Duration.frames(count = 16, fps = 200)   // ≈ 0.08 秒 / 片道

    /// `attack_lunge` アニメーション。
    /// - position track: origin → target → origin の 3 keyframe
    /// - method "attack:hit": 中点（target に重なる瞬間）で発火 → ダメージ適用 + SE 再生
    /// - finished: 攻撃モーション終了 → waited 確定 / 次状態へ
    ///
    /// `targetPath` は攻撃側マーカー（`playerPath(id)` / `enemyPath(id)`）。
    /// アニメ全長は 2 phase 分で、method "attack:hit" は phase 1 つぶん経過した時点
    /// （正規化 t = 0.5）で発火する。
    pub def attackLungeAnimation(targetPath: NodePath,
                                  originGrid: {x = Int32, y = Int32},
                                  targetGrid: {x = Int32, y = Int32}):
                                 AnimationPlayer.Animation =
        let phase    = attackPhaseDuration();
        let total    = Duration.add(phase, phase);
        let originW  = MapSnapshot.cellCenter(originGrid);
        let targetW  = MapSnapshot.cellCenter(targetGrid);
        let posKeys: List[AnimationPlayer.PosKey] =
            ({time = 0.0, pos = originW}: AnimationPlayer.PosKey) ::
            ({time = 0.5, pos = targetW}: AnimationPlayer.PosKey) ::
            ({time = 1.0, pos = originW}: AnimationPlayer.PosKey) ::
            Nil;
        let track: AnimationPlayer.Track = {
            target = targetPath,
            prop   = AnimationPlayer.Property.Position(posKeys)
        };
        let methodHit: AnimationPlayer.MethodKey = {
            time = phase,
            name = AnimEvent.tagToString(AnimEvent.Tag.AttackHit)
        };
        {
            name    = AnimEvent.tagToString(AnimEvent.Tag.AttackLunge),
            length  = total,
            tracks  = track :: Nil,
            methods = methodHit :: Nil
        }

    /// 体当たり攻撃モーションを開始する（攻守共通の入口）。
    /// `attack_lunge` を AnimationPlayer に登録し `attackTargetId = Some(defenderId)` を立てる。
    /// 中点で `attack:hit` メソッド、終端で finished が届き、それぞれ
    /// `onAttackHit` / `onLungeDone` が解決する。
    /// 武器を持たないユニットは攻撃に到達してはいけない設計で、防御的に no-op する
    /// （味方: PlayerAttackRangeScene/TurnRules、敵: EnemyAI が禁止する）。
    /// 攻撃開始（faction-blind）。武器なし（`weaponRange = None`）は filter で弾いて no-op。
    /// faction dispatch は **`EntityScene`（scene 集約点）／`World.refOfSide`** に閉じ込め、ここは faction-blind。
    pub def startAttack(side: Faction, attackerId: Int32, defenderId: Int32,
                         targetGrid: {x = Int32, y = Int32},
                         scene: Scene[NodeTag]): Scene[NodeTag]
            \ {AnimationPlayer.Scheduler, World.Command, World.WorldQuery} =
        let attacker = World.refOfSide(side, attackerId);
        let path     = EntityScene.path(attacker);
        let started = forM (
            uv <- EntityScene.unitView(attacker, scene) |> Option.filter(u -> Option.nonEmpty(u#weaponRange))
        ) yield {
            AnimationPlayer.play(path, attackLungeAnimation(path, uv#pos, targetGrid));
            World.Command.emit(World.Cmd.SetAttackTarget(attacker, defenderId));
            EntityScene.setAttackTargetId(attacker, defenderId, scene)
        };
        Option.getWithDefault(scene, started)

    /// AnimationPlayer の `attack:hit` method イベント受信時の処理（攻守共通の入口）。
    /// - Player: `applyAttackHit` で敵への攻撃を解決（命中ロール → ダメージ/EXP → レベルアップ）。
    /// - Enemy: `applyEnemyAttackHit` の killed リストを `PlayerScene.removeDeadAndCheckGameOver`
    ///   に流し、全滅時は `CustomEffects.GameOverRequest` でフルリビルドさせる。
    pub def onAttackHit(side: Faction, id: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameEngine.Audio,
                              GameLogger.GameLogger,
                              CustomEffects.GameOverRequest,
                              SelectedPlayer.State, World.RngDraw,
                              CustomEffects.ThiefDropRequest, World.Command, World.WorldQuery} =
        match side {
            case Faction.Player => applyAttackHit(id, scene)
            case Faction.Enemy  =>
                let (next, killed) = applyEnemyAttackHit(id, scene);
                PlayerScene.removeDeadAndCheckGameOver(killed, next)
        }

    /// 味方の `attack:hit` のダメージ適用。
    /// 当該 player の `attackTargetId` を読み、対応する敵への攻撃を解決する。
    /// 命中ロールは ECS（CombatSystem.resolveCombat）側で行い、命中なら SE + ダメージ + ログ、
    /// 回避なら SE を鳴らさず "miss" 表示のみ。HP <= 0 なら death_blink を開始する。
    pub def applyAttackHit(playerId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameEngine.Audio,
                              GameLogger.GameLogger, World.RngDraw,
                              CustomEffects.ThiefDropRequest, World.Command, World.WorldQuery} =
        let resolved = forM (
            d       <- PlayerScene.get(playerId, scene);
            enemyId <- d#attackTargetId
        ) yield applyDamageToEnemy(playerId, d, enemyId, scene);
        Option.getWithDefault(scene, resolved)

    /// 敵の `attack:hit` のダメージ適用（ECS 一本）。
    /// 戻り値は (新 scene, HP=0 になったプレイヤー id のリスト)。
    /// killedIds が空でないとき呼び出し側は死亡処理（removeDeadAndCheckGameOver）を発火する。
    pub def applyEnemyAttackHit(enemyId: Int32, scene: Scene[NodeTag]):
            (Scene[NodeTag], List[Int32]) \
            {AnimationPlayer.Scheduler, GameEngine.Audio, World.RngDraw,
             World.Command, World.WorldQuery} =
        let resolved = forM (
            d              <- EnemyScene.get(enemyId, scene);
            targetPlayerId <- d#attackTargetId
        ) yield applyDamageToPlayer(enemyId, d, targetPlayerId, scene);
        Option.getWithDefault((scene, Nil), resolved)

    /// AnimationPlayer の `attack_lunge` finished イベント受信時の処理（攻守共通の入口）。
    /// 反撃の往復（味方攻撃 → 敵反撃 / 敵攻撃 → 味方反撃）はこの関数の中で完結する。
    /// FE 風で「反撃の反撃」は実装しない（反撃完了側の分岐は clear + 進行のみ）。
    pub def onLungeDone(side: Faction, id: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameLogger.GameLogger,
                              EnemyTurn.Queue, TurnPhase.State,
                              SelectedPlayer.State, Pacing.State, World.RngDraw, World.Command, World.PhaseQuery, World.WorldQuery} =
        match side {
            case Faction.Player => playerLungeDone(id, scene)
            case Faction.Enemy  => enemyLungeDone(id, scene)
        }

    /// 味方の `attack_lunge` finished。2 通りある:
    ///   - `PlayerAttackHold` (= 味方主攻撃の完了) → CounterAttackRules.decide で分岐:
    ///       Kill (敵瀕死) / Counter (敵反撃) / Commit (waited 確定)。
    ///   - `EnemyTurn` (= 敵攻撃に対する味方反撃の完了) → 単純に attackTargetId クリア。
    ///       次フレーム以降で EnemyTurnDriver が PlayerScene.anyAttacking が false に
    ///       なったのを見て次の step に進む。
    def playerLungeDone(playerId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameLogger.GameLogger,
                              EnemyTurn.Queue, TurnPhase.State,
                              SelectedPlayer.State, Pacing.State, World.RngDraw, World.Command, World.PhaseQuery, World.WorldQuery} =
        // 「敵ターンか」の sim-phase 判定は World 由来（19-case 詳細は不要ゆえ 3-case で足りる）。
        if (World.PhaseQuery.phase() == SimPhase.EnemyTurn) {
            // 敵ターン中の味方反撃が完了した。反撃でレベルアップしていれば、その場で
            // （反撃ごとに）ステータス変化パネルへ割り込む。閉じると敵ターンに戻って続行する。
            let cleared = clearAttackTargetId(playerId, scene);
            if (PlayerScene.anyPendingLevelUp(cleared))
                PhaseTransitions.enterLevelUpView(cleared)
            else
                cleared
        } else {
            // 味方主攻撃の完了。まず追撃リング判定（補正後speed差+3 & 15% & 未追撃 & 敵生存）。
            // 追撃するなら decide（反撃/確定）より前に同じ敵へもう一度攻撃する（追撃→反撃の直列）。
            match playerFollowUpEnemy(playerId, scene, rollPercent(), World.WorldQuery.get()) {
                case Some(enemyId) =>
                    // followUpUsed は World 権威。scene 直書きはしない（reader は World 優先）。
                    World.Command.emit(World.Cmd.SetFollowUpUsed(World.EntityRef.Player(playerId), true));
                    startPlayerFollowUp(playerId, enemyId, scene)
                case None =>
                    resolvePlayerMainAttack(playerId, scene)
            }
        }

    // 追撃判定 shouldFollowUp / braveFollowUp は純 leaf として CombatRules.flix へ移動（A1）。

    /// 味方が追撃すべきなら対象の敵 id を返す（しないなら None）。speed は combatView の補正後値。
    /// 攻撃者・対象の敵が揃ったときだけ判定する（match は入れ子にしない）。
    def playerFollowUpEnemy(playerId: Int32, scene: Scene[NodeTag], roll: Int32, world: World): Option[Int32] =
        let pOpt = PlayerScene.get(playerId, scene);
        let eOpt = pOpt |> Option.flatMap(p -> p#attackTargetId)
                        |> Option.flatMap(eid -> EnemyScene.get(eid, scene));
        match (pOpt, eOpt) {
            case (Some(p), Some(e)) =>
                let braveT = PlayerData.equippedWeapon(p#weapons)
                    |> Option.flatMap(w -> WeaponCatalog.braveThreshold(w#effect, w#effectValue));
                // 速度判定は World の combatViewOf 由来（followUpUsed と同じ read。
                // world は WorldQuery snapshot=read-after-write 正・None は scene fallback）。
                let atkSpd = World.combatViewOf(World.EntityRef.Player(playerId), world)
                                 |> Option.map(cv -> cv#speed)
                                 |> Option.getWithDefault(PlayerScene.combatView(p)#speed);
                let defSpd = World.combatViewOf(World.EntityRef.Enemy(e#id), world)
                                 |> Option.map(cv -> cv#speed)
                                 |> Option.getWithDefault(EnemyScene.combatView(e)#speed);
                // 追撃判定を DSL の flow 層（EffectFlow.followUpDecision）へ寄せる。brave/pursuit の
                // どちらかが成立すれば追撃（ロジックは shouldFollowUp/braveFollowUp と同一・テスト済）。
                let fctx = {atkSpd = atkSpd, defSpd = defSpd, roll = roll,
                            // followUpUsed を World 由来で読む（world は caller の WorldQuery snapshot）。
                            followUpUsed = World.followUpUsedOf(World.EntityRef.Player(playerId), world)
                                              |> Option.getWithDefault(false),  // World 権威・未登録=未使用
                            brave = braveT,
                            pursuit = Ring.hasPursuit(PlayerData.equippedRing(p))};
                if (EffectFlow.followUpDecision(EffectRule.Flow.FollowUp(EffectRule.FollowKind.Brave), fctx)
                    or EffectFlow.followUpDecision(EffectRule.Flow.FollowUp(EffectRule.FollowKind.Pursuit), fctx))
                    p#attackTargetId
                else None
            case _ => None
        }

    /// 味方の追撃モーションを開始する（同じ敵へ再突進）。敵が消えていれば通常進行に落とす。
    def startPlayerFollowUp(playerId: Int32, enemyId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameLogger.GameLogger, EnemyTurn.Queue, TurnPhase.State,
                              SelectedPlayer.State, Pacing.State, World.Command, World.WorldQuery} =
        match EnemyScene.getWithWorldPos(enemyId, scene) {
            case Some(e) =>
                GameLogger.playerLog("追撃！");
                startAttack(Faction.Player, playerId, enemyId, e#gridPos, scene)
            case None =>
                resolvePlayerMainAttack(playerId, scene)
        }

    /// 味方主攻撃完了の従来分岐（追撃なし）。CounterAttackRules.decideView（faction-blind）で Kill/Counter/Commit。
    def resolvePlayerMainAttack(playerId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameLogger.GameLogger, EnemyTurn.Queue, TurnPhase.State,
                              SelectedPlayer.State, Pacing.State, World.Command, World.WorldQuery} =
        // faction-blind な decideView（UnitView ベース）で分岐する（味方→敵）。
        // view は World 由来（unitViewFromWorld）。ECS 戦闘は hp を World にしか書かないため、
        // 直前の攻撃結果（Kill/Counter 分岐の hp）を scene view で読むと stale になる。
        let w0 = World.WorldQuery.get();
        let outcome = PlayerScene.get(playerId, scene)
            |> Option.map(player -> CounterAttackRules.decideView(
                   World.unitViewFromWorld(World.EntityRef.Player(playerId), w0, scene)
                       |> Option.getWithDefault(PlayerScene.unitView(player)),
                   player#attackTargetId
                       |> Option.flatMap(eid ->
                           // World 未登録（テスト/spawn 過渡）のみ scene fallback。
                           match World.unitViewFromWorld(World.EntityRef.Enemy(eid), w0, scene) {
                               case Some(v) => Some(v)
                               case None    => EnemyScene.get(eid, scene) |> Option.map(EnemyScene.unitView)
                           })));
        match outcome {
            case None => scene
            case Some(CounterAttackRules.Outcome.Kill) =>
                let cleared = clearAttackTargetId(playerId, scene);
                TurnPhase.State.put(TurnPhase.Phase.PlayerAttackHold);
                Pacing.State.hold(700 |> Duration.millis);
                cleared
            case Some(CounterAttackRules.Outcome.Counter(enemyId)) =>
                startEnemyCounter(enemyId, playerId, clearAttackTargetId(playerId, scene))
            case Some(CounterAttackRules.Outcome.Commit) =>
                TurnFlow.commitWaitedAndAdvance(clearAttackTargetId(playerId, scene))
        }

    /// 敵 enemyId による反撃モーションを開始する（Counter 分岐の本体）。
    /// 反撃対象の味方が消えていれば反撃せず通常のターン確定に落とす。
    def startEnemyCounter(enemyId: Int32, playerId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameLogger.GameLogger,
                              EnemyTurn.Queue, TurnPhase.State,
                              SelectedPlayer.State, World.Command, World.WorldQuery} =
        let countered = forM (
            p <- PlayerScene.getWithWorldPos(playerId, scene)
        ) yield {
            GameLogger.enemyLog("${EnemyScene.displayName(enemyId, scene)}の反撃");
            startAttack(Faction.Enemy, enemyId, playerId, p#gridPos, scene)
        };
        match countered {
            case Some(next) => next
            case None       => TurnFlow.commitWaitedAndAdvance(scene)
        }

    /// 敵の `attack_lunge` finished。2 通りある:
    ///   - `PlayerAttackHold` (= 味方攻撃に対する敵反撃の完了) → commit
    ///   - `EnemyTurn` (= 敵ターン中の主攻撃完了) → 味方反撃判定。
    ///       CounterAttackRules.decideView（faction-blind）を回し、Counter(playerId) なら
    ///       `startAttack(Faction.Player, ...)` で反撃モーション開始。
    ///       それ以外は単純に attackTargetId クリアして EnemyTurnDriver に制御を戻す。
    /// `PlayerAttackHold` は「攻撃を振った側が先に attack_lunge を開始する瞬間から
    /// 反撃 attack_lunge が終わるまで」を Hold させるための設計で、往復の間ずっと Hold が続く。
    def enemyLungeDone(enemyId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameLogger.GameLogger,
                              EnemyTurn.Queue, TurnPhase.State,
                              SelectedPlayer.State, World.RngDraw, World.Command, World.WorldQuery} =
        if (TurnPhase.State.get() == TurnPhase.Phase.PlayerAttackHold) {
            let cleared = clearEnemyAttackTarget(enemyId, scene);
            TurnFlow.commitWaitedAndAdvance(cleared)
        } else {
            // EnemyTurn 中の敵主攻撃完了。先に追撃リング判定（敵 speed 差+3 & 15% & 未追撃 & 味方生存）。
            // 追撃するなら反撃判定より前に同じ味方へもう一度攻撃する。
            match enemyFollowUpPlayer(enemyId, scene, rollPercent(), World.WorldQuery.get()) {
                case Some(playerId) =>
                    // followUpUsed は World 権威。scene 直書きはしない（reader は World 優先）。
                    World.Command.emit(World.Cmd.SetFollowUpUsed(World.EntityRef.Enemy(enemyId), true));
                    startEnemyFollowUp(enemyId, playerId, scene)
                case None =>
                    resolveEnemyMainAttack(enemyId, scene)
            }
        }

    /// 敵が追撃すべきなら対象の味方 id を返す（しないなら None）。speed は combatView の補正後値。
    def enemyFollowUpPlayer(enemyId: Int32, scene: Scene[NodeTag], roll: Int32, world: World): Option[Int32] =
        let eOpt = EnemyScene.get(enemyId, scene);
        let pOpt = eOpt |> Option.flatMap(e -> e#attackTargetId)
                        |> Option.flatMap(pid -> PlayerScene.get(pid, scene));
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
                            // followUpUsed を World 由来で読む。
                            followUpUsed = World.followUpUsedOf(World.EntityRef.Enemy(enemyId), world)
                                              |> Option.getWithDefault(false),  // World 権威・未登録=未使用
                            brave = braveT,
                            pursuit = Ring.hasPursuit(e#ring)};
                if (EffectFlow.followUpDecision(EffectRule.Flow.FollowUp(EffectRule.FollowKind.Brave), fctx)
                    or EffectFlow.followUpDecision(EffectRule.Flow.FollowUp(EffectRule.FollowKind.Pursuit), fctx))
                    e#attackTargetId
                else None
            case _ => None
        }

    /// 敵の追撃モーションを開始する（同じ味方へ再突進）。味方が消えていれば反撃判定に落とす。
    def startEnemyFollowUp(enemyId: Int32, playerId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameLogger.GameLogger, World.Command, World.WorldQuery} =
        match PlayerScene.getWithWorldPos(playerId, scene) {
            case Some(p) =>
                GameLogger.enemyLog("追撃！");
                startAttack(Faction.Enemy, enemyId, playerId, p#gridPos, scene)
            case None =>
                resolveEnemyMainAttack(enemyId, scene)
        }

    /// 敵主攻撃完了の従来分岐（追撃なし）。味方反撃の対象を決め、反撃なら startAttack。
    def resolveEnemyMainAttack(enemyId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameLogger.GameLogger, World.Command, World.WorldQuery} =
        // faction-blind な decideView で分岐する（敵→味方）。
        // view は World 由来（resolvePlayerMainAttack と同じ理由＝直前ダメージの hp が scene では stale）。
        let w0 = World.WorldQuery.get();
        let decision = forM (
            e <- EnemyScene.getWithWorldPos(enemyId, scene)
        ) yield (e, CounterAttackRules.decideView(
                     World.unitViewFromWorld(World.EntityRef.Enemy(enemyId), w0, scene)
                         |> Option.getWithDefault(EnemyScene.unitView(e)),
                     e#attackTargetId
                         |> Option.flatMap(pid ->
                             // World 未登録（テスト/spawn 過渡）のみ scene fallback。
                             match World.unitViewFromWorld(World.EntityRef.Player(pid), w0, scene) {
                                 case Some(v) => Some(v)
                                 case None    => PlayerScene.get(pid, scene) |> Option.map(PlayerScene.unitView)
                             })));
        match decision {
            case Some((e, CounterAttackRules.Outcome.Counter(playerId))) =>
                let cleared = clearEnemyAttackTarget(enemyId, scene);
                GameLogger.playerLog("${PlayerScene.displayName(playerId, scene)}の反撃");
                startAttack(Faction.Player, playerId, enemyId, e#gridPos, cleared)
            case _ => clearEnemyAttackTarget(enemyId, scene)
        }

    /// Player / Enemy ノードの毎フレーム process。AnimationPlayer から自分宛
    /// (`playerPath(id)` / `enemyPath(id)`) の signal だけ pull し、
    /// attack:hit (中点) / attack_lunge (完了) / death_blink (敵のみ、完了) に反応する。
    /// Game.flix の `dispatchEntities` から Player / Enemy 両ノードに dispatch される
    /// (per-node)。owner 完全一致なので他ユニットの signal は取りこぼさない。
    /// 「Sceneのライフサイクルで処理が完結」する Godot 流の per-node signal モデル。
    pub def process(_delta: Duration.Duration,
                     node: EngineNode[NodeTag],
                     path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag])
                    \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                        GameEngine.Audio,
                        GameLogger.GameLogger,
                        CustomEffects.GameOverRequest,
                        CustomEffects.ThiefDropRequest,
                        EnemyTurn.Queue, TurnPhase.State,
                        SelectedPlayer.State, Pacing.State, World.RngDraw, World.Command, World.PhaseQuery, World.WorldQuery} =
        match (PlayerScene.idFromPath(path), EnemyScene.idFromPath(path)) {
            case (Some(playerId), _) => drainAndDispatch(Faction.Player, playerId, node, path, scene)
            case (_, Some(enemyId))  => drainAndDispatch(Faction.Enemy, enemyId, node, path, scene)
            case _                   => (node, scene)
        }

    /// 自ノード宛 signal を drain して side 別に振り分ける。
    /// 死亡演出 (death_blink) は敵のライフサイクルなので `EnemyScene.onDeathBlinkDone` に委譲。
    /// 待機モーションへの復帰は Tween 完了をトリガーにせず、
    /// setWaited / clearAllWaited (= 待機確定 / 次ターン開始) に集約している。
    def drainAndDispatch(side: Faction, id: Int32,
                          node: EngineNode[NodeTag],
                          path: NodePath, scene: Scene[NodeTag]):
                         (EngineNode[NodeTag], Scene[NodeTag])
                         \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                             GameEngine.Audio,
                             GameLogger.GameLogger,
                             CustomEffects.GameOverRequest,
                             CustomEffects.ThiefDropRequest,
                             EnemyTurn.Queue, TurnPhase.State,
                             SelectedPlayer.State, Pacing.State, World.RngDraw, World.Command, World.PhaseQuery, World.WorldQuery} =
        let ownerPath = EntityScene.path(World.refOfSide(side, id));  // faction dispatch は EntityScene/World に集約
        let bundle = AnimationPlayer.Scheduler.drainSignals(ownerPath);
        let afterMethods = List.foldLeft(
            (sc, ev) -> match AnimEvent.parseTag(ev#name) {
                case Some(AnimEvent.Tag.AttackHit) => onAttackHit(side, id, sc)
                case _                              => sc
            },
            scene, bundle#methods);
        let afterFinished = List.foldLeft(
            (sc, ev) -> match (AnimEvent.parseTag(ev#name), side) {
                case (Some(AnimEvent.Tag.AttackLunge), _)            => onLungeDone(side, id, sc)
                case (Some(AnimEvent.Tag.DeathBlink), Faction.Enemy) => EnemyScene.onDeathBlinkDone(id, sc)
                case _                                                => sc
            },
            afterMethods, bundle#finished);
        // signal handler が scene 経由で self (ノード) を更新する可能性が
        // あるため、最新ノードを取り直して返す (古い node で打ち消されないように)
        let latest = Scene.getEngineNode(path, afterFinished) |> Option.getWithDefault(node);
        (latest, afterFinished)

    /// 命中ロール用の 0..99 の一様乱数。`Combat.isHit(hitRate, roll)` に渡す。
    def rollPercent(): Int32 \ World.RngDraw =
        World.RngDraw.nextPercent()

    /// 攻撃 1 回の純粋な算出結果（命中率・与ダメージ・撃破後 HP・撃破か・経験値）。
    /// 乱数も Scene も使わないので、これ単体で命中率やダメージ式をテストできる。
    pub type alias AttackForecast = {
        hitRate = Int32,   // 命中率 0..100（命中ロールと比較する）
        dmg     = Int32,   // 命中時の与ダメージ
        newHp   = Int32,   // 命中後の敵 HP（0 以上）
        killed  = Bool,    // この命中で敵を撃破するか
        exp     = Int32,   // 命中で得る経験値
        crit    = Int32    // 必殺率 0..100（必殺ロールと比較する）
    }

    // 1 撃解決 resolveStrike は純 leaf として CombatRules.flix へ移動（A1）。

    /// 装備武器と敵から、命中率・与ダメージ・経験値を**純粋に**算出する（乱数・Scene 非依存）。
    /// 計算は `CombatRules.resolveStrike`（= `Combat.estimate`）に委譲し、武器タイプ習熟・武器相性・
    /// 物理/魔法の解決を戦闘予報と実ダメージで一致させる。テストしやすいよう pub。
    /// 攻撃側・防御側の `CombatView`（+ レベル）から forecast を組む（faction/source 非依存・純粋）。
    /// scene 由来（`attackForecast`）も World 由来（`resolveAttack` の flip）も共有＝式の単一源泉。
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
    /// level-up モーダルは `applyEcsSceneEffects` の pendingLevelUp で発火、thief drop は `applyThiefDrop`。
    /// 前提（武器あり・敵あり）の解決だけを担い、ネストを避けるため Option を `forM` で短絡的に畳む。
    def applyDamageToEnemy(playerId: Int32, player: PlayerScene.Data, enemyId: Int32,
                            scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameEngine.Audio,
                               GameLogger.GameLogger, World.RngDraw,
                               CustomEffects.ThiefDropRequest, World.Command, World.WorldQuery} =
        let resolved = forM (
            weapon <- PlayerData.equippedWeapon(player#weapons);
            enemy  <- EnemyScene.get(enemyId, scene)
        ) yield ecsResolvePlayerAttack(playerId, player, weapon, enemyId, enemy, scene);
        Option.getWithDefault(scene, resolved)

    /// ECS 経路の **scene-authoritative 反映**: World に Cmd を流すだけでは反映しきれない scene 権威の状態を
    /// SimEvent から scene へ適用する。対象:
    ///   - `statusEffects`（scene 権威・refreshMirror が scene #statuses から re-mirror・tick も scene 側）:
    ///     Afflicted=`StatusSystem.add` / Released=`clearImmobilized`。Cmd だけだと次フレームに上書きされ消える。
    ///   - `pendingLevelUp`（scene-only・level-up モーダルの trigger）: LeveledUp で `Some(result)` を立てる。
    ///     これで `onLungeDone` の `anyPendingLevelUp` → `enterLevelUpView`（signal 駆動・既存）が発火する＝modal-gate。
    /// level/exp/hp 自体は eventToCmds（Cmd.Progress/SetHp→World）で World 権威に反映される。純粋 scene 変換。
    def applyEcsSceneEffects(events: List[World.SimEvent], scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        List.foldLeft((sc, ev) -> match ev {
            case World.SimEvent.Afflicted(World.EntityRef.Player(id), s) =>
                let sc1 = PlayerScene.mapPlayer(id, d -> {statuses = StatusSystem.add(s, d#statuses) | d}, sc);
                PlayerScene.emitStatusesFromScene(id, sc1); sc1  // 付与後 statuses を World へ Seed
            case World.SimEvent.Afflicted(World.EntityRef.Enemy(id), s) =>
                let sc1 = EnemyScene.mapEnemy(id, d -> {statuses = StatusSystem.add(s, d#statuses) | d}, sc);
                EnemyScene.emitStatusesFromScene(id, sc1); sc1
            case World.SimEvent.Released(World.EntityRef.Player(id)) =>
                let sc1 = PlayerScene.mapPlayer(id, d -> {statuses = StatusSystem.clearImmobilized(d#statuses) | d}, sc);
                PlayerScene.emitStatusesFromScene(id, sc1); sc1
            case World.SimEvent.Released(World.EntityRef.Enemy(id)) =>
                let sc1 = EnemyScene.mapEnemy(id, d -> {statuses = StatusSystem.clearImmobilized(d#statuses) | d}, sc);
                EnemyScene.emitStatusesFromScene(id, sc1); sc1
            case World.SimEvent.LeveledUp(p) =>
                // pendingLevelUp（panel trigger）＋ resource の成長後 stat 反映（legacy applyLevelUp の withStats 相当）。
                // level/exp/hp は eventToCmds→World→derive 済み。resource は scene 権威（baseStats の source）ゆえここで。
                match p#entity {
                    case World.EntityRef.Player(id) =>
                        let updated = PlayerScene.mapPlayer(id, d ->
                            {pendingLevelUp = Some(p#result),
                             resource = LevelSystem.withStats(p#grownStats, d#resource) | d}, sc);
                        // level-up で resource が成長＝baseStats の source が変わる。command-derive store へ dual-write
                        // （read-after-mutate で適用後 resource を読む）。
                        PlayerScene.emitBaseStatsFromScene(id, updated);
                        updated
                    case World.EntityRef.Enemy(_)   => sc
                }
            case _ => sc
        }, scene, events)

    /// sim が発火した `ViewFx(Thief(cell))` を見て、盗み drop の
    /// scene 副作用（フロア落下＋『…が アイテムを落とした』ログ）を引く。発火判定（ローグ職・敵生存・確率）は
    /// sim（`thiefDropEvents`）が済ませ、ここは drop 実体だけ担う。enemyId は wrapper が持つ＝ログの敵名に使う。
    /// ViewReplay（純 view）でなく wrapper で処理するのは、ドロップが scene 状態変更（consumeEquippedWeapon と同レーン）だから。
    def applyThiefDrop(events: List[World.SimEvent], enemyId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {CustomEffects.ThiefDropRequest, GameLogger.GameLogger} =
        let thiefCells = events |> List.filterMap(ev -> match ev {
            case World.SimEvent.ViewFx(World.ViewFxKind.Thief(cell)) => Some(cell)
            case _                                                   => None
        });
        List.foldLeft((sc, cell) -> {
            GameLogger.playerLog("${EnemyScene.displayName(enemyId, sc)}が アイテムを落とした");
            CustomEffects.ThiefDropRequest.drop(cell, sc)
        }, scene, thiefCells)

    /// ECS 経路（味方攻撃）: `CombatSystem.resolveAttack` で 1 撃の sim を解いて [SimEvent] を得、
    /// `eventToCmds` で World へ反映（live mirror と同じ Cmd 経路＝golden で final-World 等価を証明済み）し、
    /// `ViewReplay.replay` で演出を再生する。`applyEcsSceneEffects` で scene 権威（statuses/pendingLevelUp）も反映。
    /// `applyThiefDrop` で盗人の剣のフロア落下（legacy 順＝knockback 後・武器耐久前）、最後に `consumeEquippedWeapon` で
    /// 武器耐久を消費（legacy は命中/回避とも毎攻撃で消費＝sim 非依存の scene 副作用）。
    /// 演出進行（lunge/counter/follow-up）は signal が引く。
    def ecsResolvePlayerAttack(playerId: Int32, player: PlayerScene.Data,
                                weapon: UnitCatalog.WeaponResource, enemyId: Int32,
                                enemy: EnemyScene.Data, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameEngine.Audio,
                               GameLogger.GameLogger, World.RngDraw, World.Command,
                               World.WorldQuery, CustomEffects.ThiefDropRequest} =
        let world = World.WorldQuery.get();
        let (_, events) = CombatSystem.resolveAttack(world,
            {ref = World.EntityRef.Player(playerId), level = player#level},
            {ref = World.EntityRef.Enemy(enemyId), level = enemy#resource#level});
        List.forEach(c -> World.Command.emit(c), events |> List.flatMap(World.eventToCmds));
        let withFx = applyEcsSceneEffects(events, ViewReplay.replay(events, scene));
        let afterThief = applyThiefDrop(events, enemyId, withFx);
        consumeEquippedWeapon(playerId, weapon, afterThief)

    /// ノックバックの攻撃側・被攻撃側セル（同型 {x,y} が 2 つで誤順しやすいので名前渡し）。
    type alias KnockbackPos = {attacker = {x = Int32, y = Int32}, defender = {x = Int32, y = Int32}}

    /// FE ルールに従い、攻撃を振った時点で装備武器（先頭）の耐久を 1 減らす（回避されても同様）。
    /// 耐久が 0 になったら先頭を取り除き破損ログを出す。
    def consumeEquippedWeapon(playerId: Int32, weapon: UnitCatalog.WeaponResource,
                               scene: Scene[NodeTag]): Scene[NodeTag] \ {GameLogger.GameLogger, World.Command} =
        let consumed = Weapon.consume(weapon);
        if (Option.isEmpty(consumed))
            GameLogger.playerLog("${PlayerScene.displayName(playerId, scene)}の ${weapon#name}がこわれた")
        else ();
        let newWeapons = CombatRules.replaceOrDropHead(consumed, PlayerScene.getWeapons(playerId, scene));
        // 耐久消費後の weapons を World へ dual-write（[WEAPONS DIFF] を塞ぐ）。
        World.Command.emit(World.Cmd.SetWeapons(World.EntityRef.Player(playerId), newWeapons));
        let updated = PlayerScene.mapPlayer(playerId, d -> {weapons = newWeapons | d}, scene);
        // 耐久消費で装備武器（先頭）が変わり得る＝SetWeapons と 1:1 で weaponView も dual-write（[WEAPONVIEW DIFF] を塞ぐ）。
        PlayerScene.emitWeaponViewFromScene(playerId, updated);
        updated

    // 武器リスト先頭差し替え replaceOrDropHead は純 leaf として CombatRules.flix へ移動（A1）。

    /// プレイヤー targetId にダメージを与える。命中率・素ダメージは `CombatRules.resolveStrike`
    /// （= `Combat.estimate`、武器相性・物理/魔法込み）で算出し、`Combat.damage` 適用後の
    /// HP に更新する。攻撃成立後は武器の `durability` を 1 減らし、
    /// 0 になったら `weapon = None` に切り替え、ログに「敵N の {武器名} がこわれた」を出す。
    /// ログはスペック準拠で「敵{N} → P{M} に Xダメージ」、撃破時「敵{N} → P{M} を撃破」。
    /// HP=0 なら killedIds に追加して返す（呼び出し側が死亡処理を発火する）。
    /// 武器なし（None）でここに到達した場合は防御的に何もしない。
    def applyDamageToPlayer(enemyId: Int32, enemy: EnemyScene.Data, targetId: Int32,
                             scene: Scene[NodeTag]):
            (Scene[NodeTag], List[Int32]) \
            {AnimationPlayer.Scheduler, GameEngine.Audio, World.RngDraw,
             World.Command, World.WorldQuery} =
        // 前提（武器あり・対象あり）の解決だけを担う。実体は ECS 経路のみ。
        let resolved = forM (
            _weapon <- enemy#weapon;
            player  <- PlayerScene.get(targetId, scene)
        ) yield ecsResolveEnemyAttack(enemyId, enemy, targetId, player, scene);
        Option.getWithDefault((scene, Nil), resolved)

    /// ECS 経路（敵攻撃）: `CombatSystem.resolveEnemyAttack` で 1 撃を解き events→Cmds で World 反映・
    /// `ViewReplay.replay` で演出。味方死亡は **deferred**（`ViewFx(Died(Player))`）ゆえ killedIds をそこから導出して
    /// 返す（呼び出し側の `removeDeadAndCheckGameOver` ＝ game-over 経路へ。execution model は不変）。
    def ecsResolveEnemyAttack(enemyId: Int32, enemy: EnemyScene.Data, targetId: Int32,
                               player: PlayerScene.Data, scene: Scene[NodeTag]):
            (Scene[NodeTag], List[Int32]) \ {AnimationPlayer.Scheduler, GameEngine.Audio,
                               World.RngDraw, World.Command, World.WorldQuery} =
        let world = World.WorldQuery.get();
        let (_, events) = CombatSystem.resolveEnemyAttack(world,
            {ref = World.EntityRef.Enemy(enemyId), level = enemy#resource#level},
            {ref = World.EntityRef.Player(targetId), level = player#level});
        List.forEach(c -> World.Command.emit(c), events |> List.flatMap(World.eventToCmds));
        let next = applyEcsSceneEffects(events, ViewReplay.replay(events, scene));
        let killed = List.filterMap(ev -> match ev {
            case World.SimEvent.ViewFx(World.ViewFxKind.Died(World.EntityRef.Player(pid))) => Some(pid)
            case _                                                                          => None
        }, events);
        (next, killed)

}
