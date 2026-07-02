/// CombatScene — 攻守両対応の戦闘解決（攻撃モーション・命中判定・ダメージ・反撃・経験値）
///
/// `PlayerScene` / `EnemyScene` から戦闘解決ロジックを切り出した補助モジュール。
/// 両 Scene は状態所有（構築・移動・死亡演出・Data・Query effect）に専念し、
/// ここは「攻撃モーション → 命中判定 → ダメージ → 反撃判定 → 経験値」だけを担う。
/// 攻撃側の陣営は `Faction`（UnitView.flix）で渡し、内部の match で
/// `PlayerScene.*` / `EnemyScene.*` に振り分ける。
///
/// 配置基準: ノードは所有しないが、シグナル配信（process）を持ち Game.flix の
/// dispatch 表から呼ばれるため `src/scenes/` に置く（process を持たない
/// オーケストレータは `src/game/`）。
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
mod CombatScene {

    /// 攻撃ターゲットの敵 id を Data#attackTargetId に記録する。
    /// 武器選択ウィンドウを開く前に GameManager から呼ばれ、ウィンドウ確定後の
    /// フェーズが AttackForecast に進み、`BattlePanelScene.confirm` がこの値を読んで
    /// 実際の攻撃モーションを開始する。
    pub def setAttackTargetId(playerId: Int32, targetEnemyId: Int32,
                                scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        World.Command.emit(World.Cmd.SetAttackTarget(World.EntityRef.Player(playerId), targetEnemyId));  // F8-slice1
        PlayerScene.mapPlayer(playerId, d -> {attackTargetId = Some(targetEnemyId) | d}, scene)

    /// `attackTargetId` をクリアする（武器選択のキャンセル時や `attack_lunge` finished 時）。
    pub def clearAttackTargetId(playerId: Int32,
                                  scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        World.Command.emit(World.Cmd.ClearAttackTarget(World.EntityRef.Player(playerId)));  // F8-slice1
        PlayerScene.mapPlayer(playerId, d -> {attackTargetId = None | d}, scene)

    /// 敵側の attackTargetId をクリアする（clearAttackTargetId と対称）。
    def clearEnemyAttackTarget(enemyId: Int32,
                                scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        World.Command.emit(World.Cmd.ClearAttackTarget(World.EntityRef.Enemy(enemyId)));  // F8-slice1
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
    /// 旧 startPlayerAttack/startEnemyAttack（path/Data/scene-write だけ違う near-duplicate）を統合。
    /// faction dispatch は **`EntityScene`（scene 集約点）／`World.refOfSide`** に閉じ込め、ここは faction-blind。
    pub def startAttack(side: Faction, attackerId: Int32, defenderId: Int32,
                         targetGrid: {x = Int32, y = Int32},
                         scene: Scene[NodeTag]): Scene[NodeTag]
            \ {AnimationPlayer.Scheduler, World.Command} =
        let attacker = World.refOfSide(side, attackerId);
        let path     = EntityScene.path(attacker);
        let started = forM (
            uv <- EntityScene.unitView(attacker, scene) |> Option.filter(u -> Option.nonEmpty(u#weaponRange))
        ) yield {
            AnimationPlayer.play(path, attackLungeAnimation(path, uv#pos, targetGrid));
            World.Command.emit(World.Cmd.SetAttackTarget(attacker, defenderId));  // F8-slice1
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
                              CustomEffects.ThiefDropRequest, World.Command, World.WorldQuery, BoardQuery} =
        match side {
            case Faction.Player => applyAttackHit(id, scene)
            case Faction.Enemy  =>
                let (next, killed) = applyEnemyAttackHit(id, scene);
                PlayerScene.removeDeadAndCheckGameOver(killed, next)
        }

    /// 味方の `attack:hit` のダメージ適用。
    /// 当該 player の `attackTargetId` を読み、対応する敵への攻撃を解決する。
    /// 命中ロールは `applyDamageToEnemy` 側で行い、命中なら SE + ダメージ + ログ、
    /// 回避なら SE を鳴らさず "miss" 表示のみ。HP <= 0 なら death_blink を開始する。
    /// ゲーム本体の味方攻撃適用（`useEcsCombat()` で ECS/legacy を選ぶ＝既定 ECS）。
    pub def applyAttackHit(playerId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameEngine.Audio,
                              GameLogger.GameLogger, World.RngDraw,
                              CustomEffects.ThiefDropRequest, World.Command, World.WorldQuery, BoardQuery} =
        applyAttackHitWith(useEcsCombat(), playerId, scene)

    /// **legacy 直叩き**（トグル非依存）。golden-trace 等が legacy 経路を oracle として pin するため。
    pub def applyAttackHitLegacy(playerId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameEngine.Audio,
                              GameLogger.GameLogger, World.RngDraw,
                              CustomEffects.ThiefDropRequest, World.Command, World.WorldQuery, BoardQuery} =
        applyAttackHitWith(false, playerId, scene)

    def applyAttackHitWith(useEcs: Bool, playerId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameEngine.Audio,
                              GameLogger.GameLogger, World.RngDraw,
                              CustomEffects.ThiefDropRequest, World.Command, World.WorldQuery, BoardQuery} =
        let resolved = forM (
            d       <- PlayerScene.get(playerId, scene);
            enemyId <- d#attackTargetId
        ) yield applyDamageToEnemy(useEcs, playerId, d, enemyId, scene);
        Option.getWithDefault(scene, resolved)

    /// 敵の `attack:hit` のダメージ適用（`useEcsCombat()` で ECS/legacy を選ぶ＝既定 ECS）。
    /// 戻り値は (新 scene, HP=0 になったプレイヤー id のリスト)。
    /// killedIds が空でないとき呼び出し側は死亡処理（removeDeadAndCheckGameOver）を発火する。
    pub def applyEnemyAttackHit(enemyId: Int32, scene: Scene[NodeTag]):
            (Scene[NodeTag], List[Int32]) \
            {AnimationPlayer.Scheduler, GameEngine.Audio, GameLogger.GameLogger, World.RngDraw,
             World.Command, World.WorldQuery, BoardQuery} =
        applyEnemyAttackHitWith(useEcsCombat(), enemyId, scene)

    /// **legacy 直叩き**（トグル非依存・テスト oracle 用）。
    pub def applyEnemyAttackHitLegacy(enemyId: Int32, scene: Scene[NodeTag]):
            (Scene[NodeTag], List[Int32]) \
            {AnimationPlayer.Scheduler, GameEngine.Audio, GameLogger.GameLogger, World.RngDraw,
             World.Command, World.WorldQuery, BoardQuery} =
        applyEnemyAttackHitWith(false, enemyId, scene)

    def applyEnemyAttackHitWith(useEcs: Bool, enemyId: Int32, scene: Scene[NodeTag]):
            (Scene[NodeTag], List[Int32]) \
            {AnimationPlayer.Scheduler, GameEngine.Audio, GameLogger.GameLogger, World.RngDraw,
             World.Command, World.WorldQuery, BoardQuery} =
        let resolved = forM (
            d              <- EnemyScene.get(enemyId, scene);
            targetPlayerId <- d#attackTargetId
        ) yield applyDamageToPlayer(useEcs, enemyId, d, targetPlayerId, scene);
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
        // F2c: 「敵ターンか」の sim-phase 判定を World 由来へ flip（19-case 詳細は不要ゆえ 3-case で足りる）。
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
                    // S6: followUpUsed は World 権威。scene 直書きは撤去（reader は World 優先・syncTree が derive）。
                    World.Command.emit(World.Cmd.SetFollowUpUsed(World.EntityRef.Player(playerId), true));  // F7-slice4
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
                // S-A0/B1: 速度判定を World の combatViewOf 由来へ flip（followUpUsed と同じ dual-read。
                // world は WorldQuery snapshot=read-after-write 正。parity 証明済みゆえ同値・None は scene fallback）。
                let atkSpd = World.combatViewOf(World.EntityRef.Player(playerId), world)
                                 |> Option.map(cv -> cv#speed)
                                 |> Option.getWithDefault(PlayerScene.combatView(p)#speed);
                let defSpd = World.combatViewOf(World.EntityRef.Enemy(e#id), world)
                                 |> Option.map(cv -> cv#speed)
                                 |> Option.getWithDefault(EnemyScene.combatView(e)#speed);
                // 追撃判定を DSL の flow 層（EffectFlow.followUpDecision）へ寄せる。brave/pursuit の
                // どちらかが成立すれば追撃（ロジックは shouldFollowUp/braveFollowUp と同一・テスト済）。
                let fctx = {atkSpd = atkSpd, defSpd = defSpd, roll = roll,
                            // F7-slice4: followUpUsed を World 由来で読む（world は caller の WorldQuery snapshot）。
                            followUpUsed = World.followUpUsedOf(World.EntityRef.Player(playerId), world)
                                              |> Option.getWithDefault(false),  // P2: World 権威・未登録=未使用
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
        match EnemyScene.get(enemyId, scene) {
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
        // Track A: faction-blind な decideView（UnitView ベース）へ移行。旧 decide(味方→敵) と等価。
        // P6-2b: view は World 由来（unitViewFromWorld）。ECS 戦闘は hp を World にしか書かないため、
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
            p <- PlayerScene.get(playerId, scene)
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
                    // S6: followUpUsed は World 権威。scene 直書きは撤去（reader は World 優先・syncTree が derive）。
                    World.Command.emit(World.Cmd.SetFollowUpUsed(World.EntityRef.Enemy(enemyId), true));  // F7-slice4
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
                // S-A0/B1: 速度判定を World の combatViewOf 由来へ flip（followUpUsed と同じ dual-read・fallback 安全）。
                let atkSpd = World.combatViewOf(World.EntityRef.Enemy(enemyId), world)
                                 |> Option.map(cv -> cv#speed)
                                 |> Option.getWithDefault(EnemyScene.combatView(e)#speed);
                let defSpd = World.combatViewOf(World.EntityRef.Player(p#id), world)
                                 |> Option.map(cv -> cv#speed)
                                 |> Option.getWithDefault(PlayerScene.combatView(p)#speed);
                let fctx = {atkSpd = atkSpd, defSpd = defSpd, roll = roll,
                            // F7-slice4: followUpUsed を World 由来で読む。
                            followUpUsed = World.followUpUsedOf(World.EntityRef.Enemy(enemyId), world)
                                              |> Option.getWithDefault(false),  // P2: World 権威・未登録=未使用
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
        match PlayerScene.get(playerId, scene) {
            case Some(p) =>
                GameLogger.enemyLog("追撃！");
                startAttack(Faction.Enemy, enemyId, playerId, p#gridPos, scene)
            case None =>
                resolveEnemyMainAttack(enemyId, scene)
        }

    /// 敵主攻撃完了の従来分岐（追撃なし）。味方反撃の対象を決め、反撃なら startAttack。
    def resolveEnemyMainAttack(enemyId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameLogger.GameLogger, World.Command, World.WorldQuery} =
        // Track A: faction-blind な decideView へ移行。旧 decidePlayerCounter(敵→味方) と等価。
        // P6-2b: view は World 由来（resolvePlayerMainAttack と同じ理由＝直前ダメージの hp が scene では stale）。
        let w0 = World.WorldQuery.get();
        let decision = forM (
            e <- EnemyScene.get(enemyId, scene)
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
                        SelectedPlayer.State, Pacing.State, World.RngDraw, World.Command, BoardQuery, World.PhaseQuery, World.WorldQuery} =
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
                             SelectedPlayer.State, Pacing.State, World.RngDraw, World.Command, BoardQuery, World.PhaseQuery, World.WorldQuery} =
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

    /// ViewReplay cutover の **A/B トグル**（run 検証用・branch 温存）。`true`=ECS 経路（既定・出荷／
    /// `CombatSystem.resolveAttack`/`resolveEnemyAttack` で sim を解き events→Cmds で World 反映・`ViewReplay.replay`
    /// で演出）、`false`=legacy 演出（oracle 温存）。味方・敵攻撃とも ECS 経路。
    /// P1 で cutover ギャップを解消済み: level-up モーダル（`applyEcsSceneEffects` の pendingLevelUp で発火）・
    /// thief drop（`applyThiefDrop`・P1-b）・敵ノックバック（P1-c）。残る view 演出は Alerted tint / Released 表示のみ。
    def useEcsCombat(): Bool = true

    /// 敵 id にダメージを与える。装備武器（`weapons.head`）と敵が揃っていなければ no-op。
    /// 実体は legacy `resolveAttack` または（トグル時）ECS 経路。前提（武器あり・敵あり）の解決だけを担い、
    /// ネストを避けるため Option を `forM` で短絡的に畳む。
    def applyDamageToEnemy(useEcs: Bool, playerId: Int32, player: PlayerScene.Data, enemyId: Int32,
                            scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameEngine.Audio,
                               GameLogger.GameLogger, World.RngDraw,
                               CustomEffects.ThiefDropRequest, World.Command, World.WorldQuery, BoardQuery} =
        let resolved = forM (
            weapon <- PlayerData.equippedWeapon(player#weapons);
            enemy  <- EnemyScene.get(enemyId, scene)
        ) yield
            if (useEcs)
                ecsResolvePlayerAttack(playerId, player, weapon, enemyId, enemy, scene)
            else
                resolveAttack(playerId, player, weapon, enemy, enemyId, scene);
        Option.getWithDefault(scene, resolved)

    /// ECS 経路の **scene-authoritative 反映**: World に Cmd を流すだけでは反映しきれない scene 権威の状態を
    /// SimEvent から scene へ適用する。対象:
    ///   - `statusEffects`（scene 権威・refreshMirror が scene #statuses から re-mirror・tick も scene 側）:
    ///     Afflicted=`StatusSystem.add` / Released=`clearImmobilized`。Cmd だけだと次フレームに上書きされ消える。
    ///   - `pendingLevelUp`（scene-only・level-up モーダルの trigger）: LeveledUp で `Some(result)` を立てる。
    ///     これで `onLungeDone` の `anyPendingLevelUp` → `enterLevelUpView`（signal 駆動・既存）が発火する＝modal-gate。
    /// level/exp/hp 自体は eventToCmds（Cmd.Progress/SetHp→World）→ syncTreeFromWorld で scene へ derive される。純粋 scene 変換。
    def applyEcsSceneEffects(events: List[World.SimEvent], scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        List.foldLeft((sc, ev) -> match ev {
            case World.SimEvent.Afflicted(World.EntityRef.Player(id), s) =>
                let sc1 = PlayerScene.mapPlayer(id, d -> {statuses = StatusSystem.add(s, d#statuses) | d}, sc);
                PlayerScene.emitStatusesFromScene(id, sc1); sc1  // S3: 付与後 statuses を World へ Seed
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
                        // S2.3: level-up で resource が成長＝baseStats の source が変わる。command-derive store へ dual-write
                        // （F6 で hp を emit し忘れた震源ゆえ最優先で漏らさない・read-after-mutate で適用後 resource を読む）。
                        PlayerScene.emitBaseStatsFromScene(id, updated);
                        updated
                    case World.EntityRef.Enemy(_)   => sc
                }
            case _ => sc
        }, scene, events)

    /// P1-b: sim が発火した `ViewFx(Thief(cell))` を見て legacy `maybeThiefDrop`（CombatScene:708-719）相当の
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

    /// ECS cutover 経路（味方攻撃）: `CombatSystem.resolveAttack` で 1 撃の sim を解いて [SimEvent] を得、
    /// `eventToCmds` で World へ反映（live mirror と同じ Cmd 経路＝golden で final-World 等価を証明済み）し、
    /// `ViewReplay.replay` で演出を再生する。`applyEcsSceneEffects` で scene 権威（statuses/pendingLevelUp）も反映。
    /// `applyThiefDrop` で盗人の剣のフロア落下（legacy 順＝knockback 後・武器耐久前）、最後に `consumeEquippedWeapon` で
    /// 武器耐久を消費（legacy は命中/回避とも毎攻撃で消費＝sim 非依存の scene 副作用）。
    /// 演出進行（lunge/counter/follow-up）は従来どおり signal が引く（C5）。
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

    /// 装備武器と敵が揃ったときの攻撃解決の流れ:
    ///   命中率を算出 → 乱数ロール → 命中なら `applyHit` / 回避なら `applyMiss`
    ///   → 武器の耐久を 1 減らす → 命中していれば経験値を加算。
    def resolveAttack(playerId: Int32, player: PlayerScene.Data,
                       weapon: UnitCatalog.WeaponResource, enemy: EnemyScene.Data,
                       enemyId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameEngine.Audio,
                               GameLogger.GameLogger, World.RngDraw,
                               CustomEffects.ThiefDropRequest, World.Command, World.WorldQuery, BoardQuery} =
        // S-A0/B1: 攻撃の combat view を World 由来へ flip（weapon=equipped ゆえ combatViewOf と一致・
        // WorldQuery=read-after-write 正・None は scene fallback）。レベルは scene（progress と dual-write 同値）。
        let world      = World.WorldQuery.get();
        let atkView    = World.combatViewOf(World.EntityRef.Player(playerId), world)
                             |> Option.getWithDefault(PlayerScene.combatViewWith(player, weapon));
        let defView    = World.combatViewOf(World.EntityRef.Enemy(enemyId), world)
                             |> Option.getWithDefault(EnemyScene.combatView(enemy));
        let plan       = forecastFromViews(atkView, defView, player#level, enemy#resource#level);
        let popupPos   = MapSnapshot.cellCenter(enemy#gridPos);
        let popupColor = DamagePopupScene.damageToEnemyColor();
        // 命中ロールと必殺ロールは別の乱数で独立に引く。
        let hitRoll    = rollPercent();
        let critRoll   = rollPercent();
        // 死神のネックレス: 対象が瀕死（残 HP が割合以下）なら必殺にする。
        let finisherPct = Ring.finisherThreshold(PlayerData.equippedRing(player));
        let finisherFired = Ring.finisherTriggers(enemy#hp, enemy#resource#hp, finisherPct);
        let (afterDamage, expGain) =
            if (Combat.isHit(plan#hitRate, hitRoll)) {
                let isCrit = Combat.isCrit(plan#crit, critRoll) or finisherFired;
                // Finisher は確殺（防御で 0 ダメでも倒す）。通常必殺は 3 倍。撃破判定をやり直し plan を差し替える。
                let finalPlan =
                    if (finisherFired) {
                        let finPlan = Combat.applyFinisher(plan#dmg, enemy#hp);
                        {dmg = finPlan#dmg, newHp = finPlan#newHp, killed = finPlan#killed | plan}
                    } else if (isCrit) {
                        let critPlan = Combat.applyCrit(plan#dmg, enemy#hp);
                        {dmg = critPlan#dmg, newHp = critPlan#newHp, killed = critPlan#killed | plan}
                    } else plan;
                // 「ベースでは倒せないが必殺で倒せた」ときだけ経験値を作り直す
                // （二重加算しないよう、それ以外は plan#exp をそのまま使う）。
                let expGained =
                    if (isCrit and finalPlan#killed and not plan#killed)
                        Combat.battleExp(enemy#resource#level, player#level, true)
                    else plan#exp;
                let afterHit = applyHit(playerId, enemyId, finalPlan, isCrit, weapon#weaponType, popupPos, popupColor, scene);
                // みかえりのリング: 撃破したら攻撃側（味方）の HP を回復する。
                let afterSteal =
                    if (finalPlan#killed) applyPlayerLifesteal(playerId, player, afterHit)
                    else afterHit;
                // 血吸いの剣: 与ダメージの一定%を毎ヒット回復（撃破非依存）。
                let afterWSteal = applyPlayerWeaponLifesteal(playerId, player, weapon, finalPlan#dmg, afterSteal);
                // 如意棒 / 突風の書: 生存している敵をノックバック。
                let afterKnock = applyAttackKnockback(weapon, {attacker = player#gridPos, defender = enemy#gridPos}, enemyId, finalPlan#killed, afterWSteal);
                // 盗人の剣: ローグ装備時、命中・生存時に確率でフロア表からアイテムを落とす。
                let afterThief = maybeThiefDrop(playerId, player, weapon, enemyId, enemy#gridPos, finalPlan#killed, rollPercent(), afterKnock);
                (afterThief, expGained)
            } else
                (applyMiss(playerId, enemyId, popupPos, popupColor, scene), 0);
        let afterWeapon = consumeEquippedWeapon(playerId, weapon, afterDamage);
        // 自分の攻撃でも敵ターンの反撃でも同様（反撃 EXP で即レベルアップした場合は
        // 敵ターン終了後にまとめてパネル表示する）。
        if (expGain <= 0) afterWeapon
        else applyExpGain(playerId, expGain, afterWeapon)

    /// みかえりのリングを装備した味方が撃破したとき、その味方の HP を回復する（最大 HP でクランプ）。
    /// リング未装備 / Lifesteal 以外なら回復量 0 で no-op。
    def applyPlayerLifesteal(playerId: Int32, player: PlayerScene.Data,
                              scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        let amt = Ring.lifestealAmount(PlayerData.equippedRing(player));
        if (amt <= 0) scene
        else
            let newHp = Combat.heal(player#hp, player#resource#hp, amt)#newHp;
            scene
                |> PlayerScene.setHp(playerId, newHp)

    /// 血吸いの剣: 与えたダメージの `effectValue`% を攻撃側へ回復（毎ヒット・撃破非依存）。
    /// 攻撃側の HP は自分の攻撃では変わらないので `player#hp` をそのまま基準にしてよい。
    def applyPlayerWeaponLifesteal(playerId: Int32, player: PlayerScene.Data,
                                    weapon: UnitCatalog.WeaponResource, dmgDealt: Int32,
                                    scene: Scene[NodeTag]): Scene[NodeTag] \ {GameLogger.GameLogger, World.Command} =
        let pct = WeaponCatalog.lifestealPercent(weapon#effect, weapon#effectValue);
        if (pct <= 0 or dmgDealt <= 0) scene
        else
            let amt = (dmgDealt * pct) / 100;
            let newHp = Combat.heal(player#hp, player#resource#hp, amt)#newHp;
            GameLogger.playerLog("${PlayerScene.displayName(playerId, scene)}は 血を吸って HP+${newHp - player#hp}");
            scene
                |> PlayerScene.setHp(playerId, newHp)

    /// ノックバックの攻撃側・被攻撃側セル（同型 {x,y} が 2 つで誤順しやすいので名前渡し）。
    type alias KnockbackPos = {attacker = {x = Int32, y = Int32}, defender = {x = Int32, y = Int32}}

    /// 如意棒 / 突風の書: ノックバック武器なら、生存している敵を攻撃方向へ押し流す。
    /// 上限マス数は `effectValue`（0=無制限）。`Staff.deltaToDirection` で 4 方位に丸める。
    def applyAttackKnockback(weapon: UnitCatalog.WeaponResource, pos: KnockbackPos,
                              enemyId: Int32, killed: Bool,
                              scene: Scene[NodeTag]): Scene[NodeTag] \ {World.Command, BoardQuery} =
        match WeaponCatalog.knockbackTiles(weapon#effect, weapon#effectValue) {
            case None        => scene
            case Some(tiles) => if (killed) scene else pushEnemyBack(tiles, pos, enemyId, scene)
        }

    /// ノックバック本体: 方向算出 → `knockbackPathCapped` の最終着地へ `snapTo`。
    def pushEnemyBack(tiles: Int32, pos: KnockbackPos, enemyId: Int32,
                       scene: Scene[NodeTag]): Scene[NodeTag] \ {World.Command, BoardQuery} =
        let dir = Staff.toVec2i(Staff.deltaToDirection(
                    pos#defender#x - pos#attacker#x, pos#defender#y - pos#attacker#y));
        // P1b: 敵ノックバック（mid-frame）の board 読みを World 由来へ（dual-write で World==scene・挙動不変）。
        let board: Board = BoardQuery.board();
        let cap = if (tiles <= 0) None else Some(tiles);
        match List.last(Board.knockbackPathCapped(pos#defender, dir, board, cap)) {
            case None       => scene
            case Some(last) => EnemyScene.snapTo(enemyId, last, scene)
        }

    /// 盗人の剣: 装備者がローグ かつ 命中・敵生存 かつ `roll < effectValue`% のとき、
    /// `ThiefDropRequest` を emit してフロアのドロップ表からアイテムを敵の足元に落とす。
    def maybeThiefDrop(_playerId: Int32, player: PlayerScene.Data,
                        weapon: UnitCatalog.WeaponResource, enemyId: Int32,
                        enemyCell: {x = Int32, y = Int32}, killed: Bool, roll: Int32,
                        scene: Scene[NodeTag]):
            Scene[NodeTag] \ {CustomEffects.ThiefDropRequest, GameLogger.GameLogger} =
        let pct = WeaponCatalog.thiefDropChance(weapon#effect, weapon#effectValue);
        let isRogue = player#resource#description == "ローグ";
        if (pct <= 0 or not isRogue or killed or roll >= pct) scene
        else {
            GameLogger.playerLog("${EnemyScene.displayName(enemyId, scene)}が アイテムを落とした");
            CustomEffects.ThiefDropRequest.drop(enemyCell, scene)
        }

    /// 回避: miss SE を鳴らし "miss" を浮かす。HP も死亡演出も変えない。
    def applyMiss(playerId: Int32, enemyId: Int32, popupPos: Vec2.Vec2, color: Color,
                   scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameEngine.Audio, GameLogger.GameLogger, World.Command} =
        GameLogger.playerLog("${PlayerScene.displayName(playerId, scene)}は ${EnemyScene.displayName(enemyId, scene)}に攻撃を外した");
        AudioStreamPlayer.play("miss");
        DamagePopupScene.emitText(popupPos, "miss", color, scene)

    // 命中 SE 名 hitSoundName は純 leaf として CombatRules.flix へ移動（A1）。

    /// 命中: 与ダメージ/武器タイプに応じた SE を鳴らしダメージを適用。撃破なら死亡演出、
    /// 生存なら敵 HP を更新。どちらでも与ダメージの数値ポップアップを浮かす。
    def applyHit(playerId: Int32, enemyId: Int32, plan: AttackForecast, isCrit: Bool,
                  weaponType: WeaponCatalog.WeaponType,
                  popupPos: Vec2.Vec2, color: Color, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameEngine.Audio,
                               GameLogger.GameLogger, World.Command} =
        AudioStreamPlayer.play(CombatRules.hitSoundName(plan#dmg, isCrit, weaponType));
        // 魔法攻撃（マージ等）の着弾時は敵中心に爆発エフェクトを出す。
        let withFx = match weaponType {
            case WeaponCatalog.WeaponType.Magic => ExplosionScene.emitNormal(popupPos, scene)
            case _                              => scene
        };
        let withPopup = DamagePopupScene.emit(popupPos, plan#dmg, color, withFx);
        // 必殺のときはログ先頭に「必殺！」を付ける。
        let critTag = if (isCrit) "必殺！ " else "";
        // F6a: 敵 hp を World にも dual-write（両分岐とも newHp）。scene 直書きは下の mapEnemy / 死亡演出で継続。
        World.Command.emit(World.Cmd.SetHp(World.EntityRef.Enemy(enemyId), plan#newHp));
        if (plan#killed) {
            GameLogger.playerLog("${critTag}${PlayerScene.displayName(playerId, scene)}は ${EnemyScene.displayName(enemyId, scene)}を倒した");
            withPopup
                |> EnemyScene.startDeathAnimation(enemyId)
        } else {
            GameLogger.playerLog("${critTag}${PlayerScene.displayName(playerId, scene)}は ${EnemyScene.displayName(enemyId, scene)}に ${plan#dmg}ダメージ与えた");
            // 攻撃を受けた敵は起動する（GuardUntilInRange を射程外から射ても動き出す）。
            // alerted は一方向フラグなので、ここで立てれば次の敵ターン以降ずっと追跡に入る。
            // 殴られたので、かなしばり中なら完全停止を解除する。
            World.Command.emit(World.Cmd.SetAlerted(World.EntityRef.Enemy(enemyId), true));  // F7-spike: 被弾で起動を World へ
            withPopup
                |> EnemyScene.mapEnemy(enemyId, enemyData -> {hp = plan#newHp, alerted = true | enemyData})
                |> EnemyScene.releaseBind(enemyId)
        }

    /// FE ルールに従い、攻撃を振った時点で装備武器（先頭）の耐久を 1 減らす（回避されても同様）。
    /// 耐久が 0 になったら先頭を取り除き破損ログを出す。
    def consumeEquippedWeapon(playerId: Int32, weapon: UnitCatalog.WeaponResource,
                               scene: Scene[NodeTag]): Scene[NodeTag] \ {GameLogger.GameLogger, World.Command} =
        let consumed = Weapon.consume(weapon);
        if (Option.isEmpty(consumed))
            GameLogger.playerLog("${PlayerScene.displayName(playerId, scene)}の ${weapon#name}がこわれた")
        else ();
        let newWeapons = CombatRules.replaceOrDropHead(consumed, PlayerScene.getWeapons(playerId, scene));
        // D3: 耐久消費後の weapons を World へ dual-write（[WEAPONS DIFF] を塞ぐ）。
        World.Command.emit(World.Cmd.SetWeapons(World.EntityRef.Player(playerId), newWeapons));
        let updated = PlayerScene.mapPlayer(playerId, d -> {weapons = newWeapons | d}, scene);
        // S2.4: 耐久消費で装備武器（先頭）が変わり得る＝SetWeapons と 1:1 で weaponView も dual-write（[WEAPONVIEW DIFF] を塞ぐ）。
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
    def applyDamageToPlayer(useEcs: Bool, enemyId: Int32, enemy: EnemyScene.Data, targetId: Int32,
                             scene: Scene[NodeTag]):
            (Scene[NodeTag], List[Int32]) \
            {AnimationPlayer.Scheduler, GameEngine.Audio, GameLogger.GameLogger, World.RngDraw,
             World.Command, World.WorldQuery, BoardQuery} =
        // 前提（武器あり・対象あり）の解決だけを担う。実体は legacy resolveEnemyAttack または（useEcs 時）ECS 経路。
        let resolved = forM (
            weapon <- enemy#weapon;
            player <- PlayerScene.get(targetId, scene)
        ) yield
            if (useEcs)
                ecsResolveEnemyAttack(enemyId, enemy, targetId, player, scene)
            else
                resolveEnemyAttack(enemyId, enemy, weapon, player, targetId, scene);
        Option.getWithDefault((scene, Nil), resolved)

    /// ECS cutover 経路（敵攻撃）: `CombatSystem.resolveEnemyAttack` で 1 撃を解き events→Cmds で World 反映・
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

    /// 武器と対象が揃ったときの敵攻撃解決の流れ:
    ///   resolveStrike で命中率・ダメージを算出 → 乱数ロール → 命中/回避を適用
    ///   → 武器の耐久を 1 減らす。
    def resolveEnemyAttack(enemyId: Int32, enemy: EnemyScene.Data,
                            weapon: UnitCatalog.WeaponResource, player: PlayerScene.Data,
                            targetId: Int32, scene: Scene[NodeTag]):
            (Scene[NodeTag], List[Int32]) \
            {GameEngine.Audio, GameLogger.GameLogger, World.RngDraw,
             World.Command, World.WorldQuery, BoardQuery} =
        // S-A0/B1: ダメージ計算の combat view を World 由来へ flip（WorldQuery=read-after-write 正・parity 同値）。
        let world = World.WorldQuery.get();
        let strike = CombatRules.resolveStrike(
            World.combatViewOf(World.EntityRef.Enemy(enemyId), world) |> Option.getWithDefault(EnemyScene.combatView(enemy)),
            World.combatViewOf(World.EntityRef.Player(targetId), world) |> Option.getWithDefault(PlayerScene.combatView(player)));
        let roll = rollPercent();
        let popupPos = MapSnapshot.cellCenter(player#gridPos);
        let popupColor = DamagePopupScene.damageToPlayerColor();
        let (damaged, killed) =
            if (not Combat.isHit(strike#hit, roll)) {
                // 回避: miss SE を鳴らして "miss" を浮かす。HP は変えない。
                GameLogger.enemyLog("${enemy#resource#description}は ${player#resource#description}に攻撃を外した");
                AudioStreamPlayer.play("miss");
                (DamagePopupScene.emitText(popupPos, "miss", popupColor, scene), Nil)
            } else {
                // 命中: 必殺ロールを引く。死神のネックレスを敵が持ち味方が瀕死なら必殺。
                let critRoll = rollPercent();
                let finisherFired = Ring.finisherTriggers(player#hp, player#resource#hp,
                                                          Ring.finisherThreshold(enemy#ring));
                let crit = Combat.isCrit(strike#crit, critRoll) or finisherFired;
                // ベース(非必殺)の dmg/newHp/killed を 1 レコードにまとめ、Finisher は確殺・
                // 通常必殺は applyCrit の値で更新する（resolveAttack と同じ record-update 形）。
                let baseOutcome = {dmg = strike#dmg, newHp = strike#newHp, killed = strike#killed};
                let outcome =
                    if (finisherFired) {
                        let finEff = Combat.applyFinisher(strike#dmg, player#hp);
                        {dmg = finEff#dmg, newHp = finEff#newHp, killed = finEff#killed | baseOutcome}
                    } else if (crit) {
                        let critEff = Combat.applyCrit(strike#dmg, player#hp);
                        {dmg = critEff#dmg, newHp = critEff#newHp, killed = critEff#killed | baseOutcome}
                    } else baseOutcome;
                // 与ダメージ/必殺/武器タイプに応じた SE を鳴らしダメージ適用 + 数値ポップアップ。
                AudioStreamPlayer.play(CombatRules.hitSoundName(outcome#dmg, crit, weapon#weaponType));
                let critTag = if (crit) "必殺！ " else "";
                if (outcome#killed) {
                    GameLogger.enemyLog("${critTag}${enemy#resource#description}は ${player#resource#description}を倒した")
                } else {
                    GameLogger.enemyLog("${critTag}${enemy#resource#description}は ${player#resource#description}に ${outcome#dmg}ダメージ与えた")
                };
                let withPopup = DamagePopupScene.emit(popupPos, outcome#dmg, popupColor, scene);
                // F6a: 被弾した味方 hp を World にも dual-write（scene 直書きは下の mapPlayer で継続）。
                World.Command.emit(World.Cmd.SetHp(World.EntityRef.Player(targetId), outcome#newHp));
                // 殴られたので、かなしばり中なら完全停止を解除する。
                let dmgScene = withPopup
                    |> PlayerScene.mapPlayer(targetId,
                        playerData -> {hp = outcome#newHp | playerData})
                    |> PlayerScene.releaseBind(targetId);
                // みかえりのリング: 敵が味方を倒したら、その敵の HP を回復する。
                let afterRingSteal = if (outcome#killed) applyEnemyLifesteal(enemyId, enemy, dmgScene) else dmgScene;
                // 血吸いの剣（敵装備時）: 与ダメージの一定%を回復（撃破非依存）。
                let afterWSteal = applyEnemyWeaponLifesteal(enemyId, enemy, weapon, outcome#dmg, afterRingSteal);
                // 如意棒 / 突風の書（敵装備時）: 生存している味方をノックバック。
                let afterKnock = applyEnemyKnockback(weapon, {attacker = enemy#gridPos, defender = player#gridPos}, targetId, outcome#killed, afterWSteal);
                // 敵固有の特殊能力（effectRule = データ駆動）: 命中後に毒/鈍足/吸血などを発火。
                let afterEffect = applyEnemyEffectRule(enemy, enemyId, targetId, player,
                                                       outcome#dmg, outcome#newHp, outcome#killed, afterKnock);
                if (outcome#killed) (afterEffect, targetId :: Nil) else (afterEffect, Nil)
            };
        // FE ルールでは攻撃を振った時点で耐久を消費する（回避されても同様）
        let consumed = Weapon.consume(weapon);
        if (Option.isEmpty(consumed))
            GameLogger.enemyLog("${enemy#resource#description}の ${weapon#name}がこわれた")
        else ();
        // D3: 敵の耐久消費後 weapon を World へ dual-write（単数→0/1 List 射影）。
        World.Command.emit(World.Cmd.SetWeapons(World.EntityRef.Enemy(enemyId), Option.toList(consumed)));
        // S2.4: 敵の装備武器投影も SetWeapons と 1:1 で dual-write（敵 proficient は常に true）＝[WEAPONVIEW DIFF] を塞ぐ。
        World.Command.emit(World.Cmd.SetWeaponView(World.EntityRef.Enemy(enemyId), Combat.weaponView(consumed, true)));
        let withWeaponUpdate = EnemyScene.mapEnemy(enemyId,
            d -> {weapon = consumed | d}, damaged);
        (withWeaponUpdate, killed)

    /// 敵固有の特殊能力（effectRule = enemies.json のデータ駆動ルール）を命中後に発火する。
    /// effectRule 無し / 不正 JSON / トリガー不一致 / 確率不発のときは scene をそのまま返す（fail-safe）。
    /// 対象解決は敵 actor 視点（actorIsPlayer=false）。`to:enemy` は ray 上の味方駒（is-player）へ、
    /// `to:self` は敵自身（EnemyScene 側）へ正しく流れる。毒/鈍足/命中低下（status）と吸血（heal）に対応。
    /// 固定追加ダメージ等の撃破を伴う op は未対応（PlanHandlers が killedIds を運べないため将来課題）。
    def applyEnemyEffectRule(enemy: EnemyScene.Data, enemyId: Int32, targetId: Int32,
                              player: PlayerScene.Data, dmgDealt: Int32, targetNewHp: Int32,
                              killed: Bool, scene: Scene[NodeTag]): Scene[NodeTag] \ {World.RngDraw, World.Command} =
        // None カスケード（effectRule 無し / 不正 JSON / トリガー不一致）を 1 段に畳む。
        // ここまでは RNG を引かない＝ rule が確定し trigger が当たった敵だけが下で roll する
        // （無い敵は短絡＝既存乱数列を保つ。roll を forM 内に入れると短絡順序が崩れるため厳禁）。
        let fired =
            (forM (
                j    <- enemy#resource#effectRule;
                rule <- EffectBridge.fromComposer(j)
            ) yield rule)
                |> Option.filter(rule -> triggerFiresOnHit(rule#trigger, killed));
        match fired {
            case None       => scene  // fail-safe no-op（effectRule 無し / 不正ルール / トリガー不一致）
            case Some(rule) =>
                // ここで初めて追加ロールを引く（effectRule を持ち trigger が当たった敵だけ）。
                let roll = rollPercent();
                let predCtx = {selfHpPct       = hpPct(enemy#hp, enemy#resource#hp),
                               targetHpPct     = hpPct(targetNewHp, player#resource#hp),
                               targetAlive     = targetNewHp > 0,
                               equippedIsRogue = false,
                               adjacent        = true};
                if (not EffectPlan.shouldFire(rule, predCtx, roll)) scene  // 確率不発も no-op
                else {
                    // ray 上の対象は被弾した味方駒 1 体（is-player ⇒ ally=true）。
                    let rayUnits = ({id = targetId, ally = true, immobilized = false,
                                     alive = targetNewHp > 0}: EffectRule.RayUnit) :: Nil;
                    let ctx = {selfId = enemyId, attackerId = enemyId, actorIsPlayer = false,
                               rayUnits = rayUnits,
                               amount = {max = player#resource#hp, dealt = dmgDealt,
                                         incoming = 0, magic = 0}};
                    let plan = EffectPlan.planActions(rule, ctx);
                    World.emitStatusAdds(plan);  // emit-flip(E2, dual-write): 境界で World へ status を発行
                    // F6a: hp も境界で World へ dual-write（handler は pure）。`!>` は tap（副作用後に左辺を返す）。
                    EffectRunner.runPlan(enemyEffectHandlers(), plan, scene)
                        !> (s -> World.emitHpSets(plan, s))
                }
        }

    /// 戦闘ヒットパスで発火するトリガーか。命中後ブランチなので OnHit/OnAttack は常に true、
    /// OnKill は撃破時のみ。それ以外（OnUse/OnCast/OnTurnStart 等）は戦闘では発火しない。
    def triggerFiresOnHit(t: EffectRule.Trigger, killed: Bool): Bool = match t {
        case EffectRule.Trigger.OnHit    => true
        case EffectRule.Trigger.OnAttack => true
        case EffectRule.Trigger.OnKill   => killed
        case _                           => false
    }

    /// HP 割合（0..100）。最大 HP が 0 以下なら 0（ゼロ除算回避）。
    def hpPct(hp: Int32, maxHp: Int32): Int32 =
        if (maxHp <= 0) 0 else (hp * 100) / maxHp

    /// 敵 actor の effectRule 用 PlanHandlers。`ally`=is-player の規約は杖と同一
    /// （ally=true ⇒ PlayerScene、ally=false ⇒ EnemyScene）。吸血(heal)・状態異常(status)・
    /// 全回復(fullHeal) に対応。撃破を伴う damage / 盤面副作用 custom 等は戦闘トリガーでは未対応 no-op。
    def enemyEffectHandlers(): EffectRunner.PlanHandlers[Scene[NodeTag], {World.Command}] = {
        heal       = (sc, id, ally, n)        -> checked_ecast(effectHeal(id, ally, n, sc)),
        fullHeal   = (sc, id, ally)           -> checked_ecast(effectFullHeal(id, ally, sc)),
        status     = (sc, id, ally, se, m, t) -> effectStatus(id, ally, se, m, t, sc),  // S3: World.Command（Seed）
        maxHpUp    = (sc, _, _, _)            -> checked_ecast(sc),
        damage     = (sc, _, _, _)            -> checked_ecast(sc),
        immobilize = (sc, _, _, _)            -> checked_ecast(sc),
        revive     = (sc, _, _)               -> checked_ecast(sc),
        custom     = (sc, _, _, _)            -> checked_ecast(sc),
        sfx        = (sc, _)                  -> checked_ecast(sc),
        noOp       = (sc, _)                  -> checked_ecast(sc)
    }

    /// HP 回復を ally で出し分け（最大 HP でクランプ）。吸血（OpLifesteal → HealAt）の着地点。
    // F6a 保留: PlanHandlers は全 handler の effect 統一を要求し、pure handler を World.Command へ widen 不可。
    // ゆえに effect-runner 経由の heal はまだ scene-only（refreshMirror re-mirror で invariant）。後続スライスで対応。
    def effectHeal(id: Int32, ally: Bool, n: Int32, sc: Scene[NodeTag]): Scene[NodeTag] =
        if (ally)
            match PlayerScene.get(id, sc) {
                case Some(p) =>
                    let r = Combat.heal(p#hp, p#resource#hp, n);
                    sc |> PlayerScene.mapPlayer(id, d -> {hp = r#newHp | d})
                case None => sc
            }
        else
            match EnemyScene.get(id, sc) {
                case Some(e) =>
                    let r = Combat.heal(e#hp, e#resource#hp, n);
                    sc |> EnemyScene.mapEnemy(id, d -> {hp = r#newHp | d})
                case None => sc
            }

    /// 全回復を ally で出し分け。
    def effectFullHeal(id: Int32, ally: Bool, sc: Scene[NodeTag]): Scene[NodeTag] =
        if (ally)
            match PlayerScene.get(id, sc) {
                case Some(p) =>
                    sc |> PlayerScene.mapPlayer(id, d -> {hp = p#resource#hp | d})
                case None => sc
            }
        else
            match EnemyScene.get(id, sc) {
                case Some(e) =>
                    sc |> EnemyScene.mapEnemy(id, d -> {hp = e#resource#hp | d})
                case None => sc
            }

    /// 時限ステータス付与を ally で出し分け（毒/鈍足/命中低下など）。
    def effectStatus(id: Int32, ally: Bool, kind: StatusSystem.StatusEffect,
                     mag: Int32, turns: Int32, sc: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        let status = {effect = kind, magnitude = mag, remaining = turns};
        if (ally)
            let sc1 = PlayerScene.mapPlayer(id, d -> {statuses = StatusSystem.add(status, d#statuses) | d}, sc);
            PlayerScene.emitStatusesFromScene(id, sc1); sc1  // S3: 付与後 statuses を World へ Seed
        else
            let sc1 = EnemyScene.mapEnemy(id, d -> {statuses = StatusSystem.add(status, d#statuses) | d}, sc);
            EnemyScene.emitStatusesFromScene(id, sc1); sc1

    /// みかえりのリングを装備した敵が撃破したとき、その敵の HP を回復する（最大 HP でクランプ）。
    /// リング未装備 / Lifesteal 以外なら回復量 0 で no-op。
    def applyEnemyLifesteal(enemyId: Int32, enemy: EnemyScene.Data,
                             scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        let amt = Ring.lifestealAmount(enemy#ring);
        if (amt <= 0) scene
        else
            let newHp = Combat.heal(enemy#hp, enemy#resource#hp, amt)#newHp;
            scene
                |> EnemyScene.setHp(enemyId, newHp)

    /// 血吸いの剣を敵が装備していたとき: 与ダメージの `effectValue`% を敵へ回復（毎ヒット）。
    def applyEnemyWeaponLifesteal(enemyId: Int32, enemy: EnemyScene.Data,
                                   weapon: UnitCatalog.WeaponResource, dmgDealt: Int32,
                                   scene: Scene[NodeTag]): Scene[NodeTag] \ {GameLogger.GameLogger, World.Command} =
        let pct = WeaponCatalog.lifestealPercent(weapon#effect, weapon#effectValue);
        if (pct <= 0 or dmgDealt <= 0) scene
        else
            let amt = (dmgDealt * pct) / 100;
            let newHp = Combat.heal(enemy#hp, enemy#resource#hp, amt)#newHp;
            GameLogger.enemyLog("${enemy#resource#description}は 血を吸って HP+${newHp - enemy#hp}");
            scene
                |> EnemyScene.setHp(enemyId, newHp)

    /// 敵の如意棒 / 突風の書: ノックバック武器なら、生存している味方を攻撃方向へ押し流す。
    def applyEnemyKnockback(weapon: UnitCatalog.WeaponResource, pos: KnockbackPos,
                             targetId: Int32, killed: Bool,
                             scene: Scene[NodeTag]): Scene[NodeTag] \ {World.Command, BoardQuery} =
        match WeaponCatalog.knockbackTiles(weapon#effect, weapon#effectValue) {
            case None        => scene
            case Some(tiles) => if (killed) scene else pushPlayerBack(tiles, pos, targetId, scene)
        }

    /// 味方ノックバック本体: 方向算出 → `knockbackPathCapped` の最終着地へ `snapTo`。
    def pushPlayerBack(tiles: Int32, pos: KnockbackPos, targetId: Int32,
                        scene: Scene[NodeTag]): Scene[NodeTag] \ {World.Command, BoardQuery} =
        let dir = Staff.toVec2i(Staff.deltaToDirection(
                    pos#defender#x - pos#attacker#x, pos#defender#y - pos#attacker#y));
        // P1b: 味方ノックバック（mid-frame）の board 読みを World 由来へ（dual-write で World==scene・挙動不変）。
        let board: Board = BoardQuery.board();
        let cap = if (tiles <= 0) None else Some(tiles);
        match List.last(Board.knockbackPathCapped(pos#defender, dir, board, cap)) {
            case None       => scene
            case Some(last) => PlayerScene.snapTo(targetId, last, scene)
        }

    /// 9 ステータスぶんの成長判定用乱数 (各 0..99) をまとめて振る。
    /// 値の意味づけ・成長判定は LevelSystem 側のピュア関数が行う。
    def rollGrowth(): LevelSystem.Rolls \ World.RngDraw =
        {hp           = rollPercent(),
         attack       = rollPercent(),
         defense      = rollPercent(),
         magicAttack  = rollPercent(),
         magicDefense = rollPercent(),
         speed        = rollPercent(),
         skill        = rollPercent(),
         luck         = rollPercent(),
         constitution = rollPercent()}

    /// 味方 id に EXP を加算し、100 到達ならレベルアップを解決する。
    ///   - レベルアップしない → `exp` だけ更新。
    ///   - レベルアップする   → 成長ロールを振って各ステータスを成長させ、最大 HP が
    ///     増えた分だけ現在 HP も増やし、`pendingLevelUp` に結果を積む（パネル表示の合図）。
    /// `pendingLevelUp` が立つと commitWaitedAndAdvance がターンを進めずパネルへ割り込む。
    def applyExpGain(playerId: Int32, expGain: Int32,
                      scene: Scene[NodeTag]): Scene[NodeTag] \ {World.RngDraw, GameLogger.GameLogger, World.Command} =
        let gained = forM (
            d <- PlayerScene.get(playerId, scene)
        ) yield {
            GameLogger.playerLog("${d#resource#description}は ${expGain} の経験値を得た");
            let outcome = LevelSystem.gainExp(d#exp, expGain);
            if (not outcome#levelUp) {
                // World 拡張: exp 増（レベル据置）も World へ dual-write。
                World.Command.emit(World.Cmd.SetProgress(World.EntityRef.Player(playerId), d#level, outcome#exp));
                PlayerScene.mapPlayer(playerId, dd -> {exp = outcome#exp | dd}, scene)
            } else
                applyLevelUp(playerId, d, outcome#exp, scene)
        };
        Option.getWithDefault(scene, gained)

    /// レベルアップの解決: 成長ロールを振って各ステータスを成長させ、最大 HP が増えた分だけ
    /// 現在 HP も増やし、`pendingLevelUp` に結果を積む（パネル表示の合図）。
    /// `pub`: HP 増分の World dual-write（過去に漏れて [F6 HP DIFF] を出した不変条件）を
    /// `TestCombatScene` が単体検証できるように公開している。
    pub def applyLevelUp(playerId: Int32, d: PlayerScene.Data, newExp: Int32,
                      scene: Scene[NodeTag]): Scene[NodeTag] \ {World.RngDraw, GameLogger.GameLogger, World.Command} =
        let rolls  = rollGrowth();
        let before = LevelSystem.statsOf(d#resource);
        let after  = LevelSystem.applyGrowth(before, d#resource#growthRates, rolls);
        let hpGain = after#hp - before#hp;
        let result = LevelSystem.buildResult(d#resource#description, d#level,
                                             before, after);
        let newHp  = d#hp + hpGain;
        GameLogger.playerLog("${d#resource#description}が Lv${d#level} ▶ Lv${d#level + 1}");
        // F6a: レベルアップで増えた現在 HP も World へ dual-write（これが漏れていて [F6 HP DIFF] の原因だった）。
        World.Command.emit(World.Cmd.SetHp(World.EntityRef.Player(playerId), newHp));
        // World 拡張: level+1・exp も World へ dual-write。
        World.Command.emit(World.Cmd.SetProgress(World.EntityRef.Player(playerId), d#level + 1, newExp));
        let grown = PlayerScene.mapPlayer(playerId, dd ->
            {exp            = newExp,
             level          = dd#level + 1,
             resource       = LevelSystem.withStats(after, dd#resource),
             hp             = newHp,
             pendingLevelUp = Some(result) | dd}, scene);
        // S2.3: legacy 経路でも level-up で resource（baseStats の source）が成長する。ECS 経路
        // （applyEcsSceneEffects の emitBaseStatsFromScene）と対称に command-derive store へ dual-write する。
        // 漏らすと useEcsCombat()=false に戻したとき level-up で [BASESTATS DIFF]（hp/progress は :1115/:1117 で
        // emit 済みだが baseStats だけ欠けていた＝F6 と同型の latent drift）。read-after-mutate で成長後 resource を読む。
        PlayerScene.emitBaseStatsFromScene(playerId, grown);
        grown
}
