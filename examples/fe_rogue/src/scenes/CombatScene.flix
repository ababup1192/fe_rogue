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
                                scene: Scene[NodeTag]): Scene[NodeTag] =
        PlayerScene.mapPlayer(playerId, d -> {attackTargetId = Some(targetEnemyId) | d}, scene)

    /// `attackTargetId` をクリアする（武器選択のキャンセル時や `attack_lunge` finished 時）。
    pub def clearAttackTargetId(playerId: Int32,
                                  scene: Scene[NodeTag]): Scene[NodeTag] =
        PlayerScene.mapPlayer(playerId, d -> {attackTargetId = None | d}, scene)

    /// 敵側の attackTargetId をクリアする（clearAttackTargetId と対称）。
    def clearEnemyAttackTarget(enemyId: Int32,
                                scene: Scene[NodeTag]): Scene[NodeTag] =
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
    pub def startAttack(side: Faction, attackerId: Int32, defenderId: Int32,
                         targetGrid: {x = Int32, y = Int32},
                         scene: Scene[NodeTag]): Scene[NodeTag]
            \ AnimationPlayer.Scheduler =
        match side {
            case Faction.Player => startPlayerAttack(attackerId, defenderId, targetGrid, scene)
            case Faction.Enemy  => startEnemyAttack(attackerId, defenderId, targetGrid, scene)
        }

    /// 味方側の攻撃開始。武器を持たない（`weapons = Nil`）味方は filter で弾いて no-op。
    def startPlayerAttack(attackerId: Int32, defenderId: Int32,
                           targetGrid: {x = Int32, y = Int32},
                           scene: Scene[NodeTag]): Scene[NodeTag]
            \ AnimationPlayer.Scheduler =
        let started = forM (
            d <- PlayerScene.get(attackerId, scene)
                     |> Option.filter(dd -> not List.isEmpty(dd#weapons))
        ) yield {
            AnimationPlayer.play(PlayerScene.playerPath(attackerId),
                attackLungeAnimation(PlayerScene.playerPath(attackerId),
                                     d#gridPos, targetGrid));
            PlayerScene.mapPlayer(attackerId,
                dd -> {attackTargetId = Some(defenderId) | dd}, scene)
        };
        Option.getWithDefault(scene, started)

    /// 敵側の攻撃開始。武器が壊れている（`weapon = None`）敵は filter で弾いて no-op。
    def startEnemyAttack(attackerId: Int32, defenderId: Int32,
                          targetGrid: {x = Int32, y = Int32},
                          scene: Scene[NodeTag]): Scene[NodeTag]
            \ AnimationPlayer.Scheduler =
        let started = forM (
            d <- EnemyScene.get(attackerId, scene)
                     |> Option.filter(dd -> Option.nonEmpty(dd#weapon))
        ) yield {
            AnimationPlayer.play(EnemyScene.enemyPath(attackerId),
                attackLungeAnimation(EnemyScene.enemyPath(attackerId),
                                     d#gridPos, targetGrid));
            EnemyScene.mapEnemy(attackerId,
                dd -> {attackTargetId = Some(defenderId) | dd}, scene)
        };
        Option.getWithDefault(scene, started)

    /// AnimationPlayer の `attack:hit` method イベント受信時の処理（攻守共通の入口）。
    /// - Player: `applyAttackHit` で敵への攻撃を解決（命中ロール → ダメージ/EXP → レベルアップ）。
    /// - Enemy: `applyEnemyAttackHit` の killed リストを `PlayerScene.removeDeadAndCheckGameOver`
    ///   に流し、全滅時は `CustomEffects.GameOverRequest` でフルリビルドさせる。
    pub def onAttackHit(side: Faction, id: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, Tween.Scheduler, GameEngine.Audio,
                              GameEngine.Game, GameLogger.GameLogger,
                              CustomEffects.GameOverRequest,
                              SelectedPlayer.State, Math.Random,
                              CustomEffects.ThiefDropRequest} =
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
    pub def applyAttackHit(playerId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, Tween.Scheduler, GameEngine.Audio,
                              GameEngine.Game,
                              GameLogger.GameLogger, Math.Random,
                              CustomEffects.ThiefDropRequest} =
        let resolved = forM (
            d       <- PlayerScene.get(playerId, scene);
            enemyId <- d#attackTargetId
        ) yield applyDamageToEnemy(playerId, d, enemyId, scene);
        Option.getWithDefault(scene, resolved)

    /// 敵の `attack:hit` のダメージ適用。
    /// 戻り値は (新 scene, HP=0 になったプレイヤー id のリスト)。
    /// killedIds が空でないとき呼び出し側は死亡処理（removeDeadAndCheckGameOver）を発火する。
    pub def applyEnemyAttackHit(enemyId: Int32, scene: Scene[NodeTag]):
            (Scene[NodeTag], List[Int32]) \
            {GameEngine.Audio, GameEngine.Game, GameLogger.GameLogger, Math.Random,
             Tween.Scheduler} =
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
                              SelectedPlayer.State, Pacing.State, Math.Random} =
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
                              SelectedPlayer.State, Pacing.State, Math.Random} =
        if (TurnPhase.State.get() == TurnPhase.Phase.EnemyTurn) {
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
            match playerFollowUpEnemy(playerId, scene, rollPercent()) {
                case Some(enemyId) =>
                    let marked = PlayerScene.mapPlayer(playerId, d -> {followUpUsed = true | d}, scene);
                    startPlayerFollowUp(playerId, enemyId, marked)
                case None =>
                    resolvePlayerMainAttack(playerId, scene)
            }
        }

    /// 追撃するか（純粋）。攻撃側 speed が防御側 speed +3 以上、追撃リング所持、15% 抽選命中、
    /// かつまだこの攻撃で追撃していない。`roll` は 0..99。
    pub def shouldFollowUp(atkSpeed: Int32, defSpeed: Int32, roll: Int32,
                            hasPursuit: Bool, alreadyFollowedUp: Bool): Bool =
        hasPursuit and not alreadyFollowedUp and atkSpeed >= defSpeed + 3 and roll < 15

    /// はやぶさの剣などブレイブ武器による 2 回攻撃判定（純粋）。攻撃側 speed が防御側 speed +d
    /// 以上なら**確定**で追撃（指輪 Pursuit の 15% 抽選とは別。乱数なし）。`braveThreshold` は
    /// 装備武器から導く（None=ブレイブ武器でない）。`alreadyFollowedUp` で 1 攻撃 1 回に制限。
    pub def braveFollowUp(atkSpeed: Int32, defSpeed: Int32, alreadyFollowedUp: Bool,
                           braveThreshold: Option[Int32]): Bool =
        not alreadyFollowedUp and (match braveThreshold {
            case Some(d) => atkSpeed >= defSpeed + d
            case None    => false
        })

    /// 味方が追撃すべきなら対象の敵 id を返す（しないなら None）。speed は combatView の補正後値。
    /// 攻撃者・対象の敵が揃ったときだけ判定する（match は入れ子にしない）。
    def playerFollowUpEnemy(playerId: Int32, scene: Scene[NodeTag], roll: Int32): Option[Int32] =
        let pOpt = PlayerScene.get(playerId, scene);
        let eOpt = pOpt |> Option.flatMap(p -> p#attackTargetId)
                        |> Option.flatMap(eid -> EnemyScene.get(eid, scene));
        match (pOpt, eOpt) {
            case (Some(p), Some(e)) =>
                let braveT = PlayerData.equippedWeapon(p#weapons)
                    |> Option.flatMap(w -> WeaponCatalog.braveThreshold(w#effect, w#effectValue));
                let atkSpd = PlayerScene.combatView(p)#speed;
                let defSpd = EnemyScene.combatView(e)#speed;
                if (shouldFollowUp(atkSpd, defSpd, roll, Ring.hasPursuit(PlayerData.equippedRing(p)), p#followUpUsed)
                    or braveFollowUp(atkSpd, defSpd, p#followUpUsed, braveT))
                    p#attackTargetId
                else None
            case _ => None
        }

    /// 味方の追撃モーションを開始する（同じ敵へ再突進）。敵が消えていれば通常進行に落とす。
    def startPlayerFollowUp(playerId: Int32, enemyId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameLogger.GameLogger, EnemyTurn.Queue, TurnPhase.State,
                              SelectedPlayer.State, Pacing.State} =
        match EnemyScene.get(enemyId, scene) {
            case Some(e) =>
                GameLogger.playerLog("追撃！");
                startAttack(Faction.Player, playerId, enemyId, e#gridPos, scene)
            case None =>
                resolvePlayerMainAttack(playerId, scene)
        }

    /// 味方主攻撃完了の従来分岐（追撃なし）。CounterAttackRules.decide で Kill/Counter/Commit。
    def resolvePlayerMainAttack(playerId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameLogger.GameLogger, EnemyTurn.Queue, TurnPhase.State,
                              SelectedPlayer.State, Pacing.State} =
        let outcome = PlayerScene.get(playerId, scene)
            |> Option.map(player -> CounterAttackRules.decide(player,
                   player#attackTargetId
                       |> Option.flatMap(eid -> EnemyScene.get(eid, scene))));
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
                              SelectedPlayer.State} =
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
    ///       CounterAttackRules.decidePlayerCounter を回し、Counter(playerId) なら
    ///       `startAttack(Faction.Player, ...)` で反撃モーション開始。
    ///       それ以外は単純に attackTargetId クリアして EnemyTurnDriver に制御を戻す。
    /// `PlayerAttackHold` は「攻撃を振った側が先に attack_lunge を開始する瞬間から
    /// 反撃 attack_lunge が終わるまで」を Hold させるための設計で、往復の間ずっと Hold が続く。
    def enemyLungeDone(enemyId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameLogger.GameLogger,
                              EnemyTurn.Queue, TurnPhase.State,
                              SelectedPlayer.State, Math.Random} =
        if (TurnPhase.State.get() == TurnPhase.Phase.PlayerAttackHold) {
            let cleared = clearEnemyAttackTarget(enemyId, scene);
            TurnFlow.commitWaitedAndAdvance(cleared)
        } else {
            // EnemyTurn 中の敵主攻撃完了。先に追撃リング判定（敵 speed 差+3 & 15% & 未追撃 & 味方生存）。
            // 追撃するなら反撃判定より前に同じ味方へもう一度攻撃する。
            match enemyFollowUpPlayer(enemyId, scene, rollPercent()) {
                case Some(playerId) =>
                    let marked = EnemyScene.mapEnemy(enemyId, d -> {followUpUsed = true | d}, scene);
                    startEnemyFollowUp(enemyId, playerId, marked)
                case None =>
                    resolveEnemyMainAttack(enemyId, scene)
            }
        }

    /// 敵が追撃すべきなら対象の味方 id を返す（しないなら None）。speed は combatView の補正後値。
    def enemyFollowUpPlayer(enemyId: Int32, scene: Scene[NodeTag], roll: Int32): Option[Int32] =
        let eOpt = EnemyScene.get(enemyId, scene);
        let pOpt = eOpt |> Option.flatMap(e -> e#attackTargetId)
                        |> Option.flatMap(pid -> PlayerScene.get(pid, scene));
        match (eOpt, pOpt) {
            case (Some(e), Some(p)) =>
                let braveT = e#weapon
                    |> Option.flatMap(w -> WeaponCatalog.braveThreshold(w#effect, w#effectValue));
                let atkSpd = EnemyScene.combatView(e)#speed;
                let defSpd = PlayerScene.combatView(p)#speed;
                if (shouldFollowUp(atkSpd, defSpd, roll, Ring.hasPursuit(e#ring), e#followUpUsed)
                    or braveFollowUp(atkSpd, defSpd, e#followUpUsed, braveT))
                    e#attackTargetId
                else None
            case _ => None
        }

    /// 敵の追撃モーションを開始する（同じ味方へ再突進）。味方が消えていれば反撃判定に落とす。
    def startEnemyFollowUp(enemyId: Int32, playerId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameLogger.GameLogger} =
        match PlayerScene.get(playerId, scene) {
            case Some(p) =>
                GameLogger.enemyLog("追撃！");
                startAttack(Faction.Enemy, enemyId, playerId, p#gridPos, scene)
            case None =>
                resolveEnemyMainAttack(enemyId, scene)
        }

    /// 敵主攻撃完了の従来分岐（追撃なし）。味方反撃の対象を決め、反撃なら startAttack。
    def resolveEnemyMainAttack(enemyId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameLogger.GameLogger} =
        let decision = forM (
            e <- EnemyScene.get(enemyId, scene)
        ) yield (e, CounterAttackRules.decidePlayerCounter(e,
                     e#attackTargetId
                         |> Option.flatMap(pid -> PlayerScene.get(pid, scene))));
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
                        GameEngine.Audio, GameEngine.Game,
                        GameLogger.GameLogger,
                        CustomEffects.GameOverRequest,
                        CustomEffects.ThiefDropRequest,
                        EnemyTurn.Queue, TurnPhase.State,
                        SelectedPlayer.State, Pacing.State, Math.Random} =
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
                             GameEngine.Audio, GameEngine.Game,
                             GameLogger.GameLogger,
                             CustomEffects.GameOverRequest,
                             CustomEffects.ThiefDropRequest,
                             EnemyTurn.Queue, TurnPhase.State,
                             SelectedPlayer.State, Pacing.State, Math.Random} =
        let ownerPath = match side {
            case Faction.Player => PlayerScene.playerPath(id)
            case Faction.Enemy  => EnemyScene.enemyPath(id)
        };
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
    def rollPercent(): Int32 \ Math.Random =
        Float64.truncateToInt32(Float64.floor(Math.Random.randomFloat64() * 100.0))

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

    /// 攻守共通の 1 撃解決（純粋）。`Combat.estimate` で命中率・素ダメージを出し、
    /// `Combat.damage` で防御側 HP に適用した結果を 1 レコードで返す。
    /// 味方→敵（`attackForecast`）と敵→味方（`applyDamageToPlayer`）の両方向が
    /// 必ずここを通ることで、攻守の式ドリフトを防ぐ。
    def resolveStrike(attacker: Combat.CombatView, defender: Combat.CombatView):
            {hit = Int32, dmg = Int32, newHp = Int32, killed = Bool, crit = Int32} =
        let est    = Combat.estimate(attacker, defender);
        let result = Combat.damage(hp = defender#hp, amount = est#damage);
        {hit = est#hit, dmg = est#damage, newHp = result#newHp, killed = result#isDead,
         crit = est#crit}

    /// 装備武器と敵から、命中率・与ダメージ・経験値を**純粋に**算出する（乱数・Scene 非依存）。
    /// 計算は `resolveStrike`（= `Combat.estimate`）に委譲し、武器タイプ習熟・武器相性・
    /// 物理/魔法の解決を戦闘予報と実ダメージで一致させる。テストしやすいよう pub。
    pub def attackForecast(player: PlayerScene.Data, weapon: UnitCatalog.WeaponResource,
                            enemy: EnemyScene.Data): AttackForecast =
        let strike = resolveStrike(PlayerScene.combatViewWith(player, weapon),
                                   EnemyScene.combatView(enemy));
        {hitRate = strike#hit, dmg = strike#dmg, newHp = strike#newHp, killed = strike#killed,
         exp = Combat.battleExp(enemy#resource#level, player#level, strike#killed),
         crit = strike#crit}

    /// 敵 id にダメージを与える。装備武器（`weapons.head`）と敵が揃っていなければ no-op。
    /// 実体は `resolveAttack`。ここは前提（武器あり・敵あり）の解決だけを担い、
    /// ネストを避けるため Option を `forM` で短絡的に畳む。
    def applyDamageToEnemy(playerId: Int32, player: PlayerScene.Data, enemyId: Int32,
                            scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, Tween.Scheduler, GameEngine.Audio,
                               GameEngine.Game, GameLogger.GameLogger, Math.Random,
                               CustomEffects.ThiefDropRequest} =
        let resolved = forM (
            weapon <- PlayerData.equippedWeapon(player#weapons);
            enemy  <- EnemyScene.get(enemyId, scene)
        ) yield resolveAttack(playerId, player, weapon, enemy, enemyId, scene);
        Option.getWithDefault(scene, resolved)

    /// 装備武器と敵が揃ったときの攻撃解決の流れ:
    ///   命中率を算出 → 乱数ロール → 命中なら `applyHit` / 回避なら `applyMiss`
    ///   → 武器の耐久を 1 減らす → 命中していれば経験値を加算。
    def resolveAttack(playerId: Int32, player: PlayerScene.Data,
                       weapon: UnitCatalog.WeaponResource, enemy: EnemyScene.Data,
                       enemyId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, Tween.Scheduler, GameEngine.Audio,
                               GameEngine.Game, GameLogger.GameLogger, Math.Random,
                               CustomEffects.ThiefDropRequest} =
        let plan       = attackForecast(player, weapon, enemy);
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
                let afterKnock = applyAttackKnockback(weapon, player#gridPos, enemy#gridPos, enemyId, finalPlan#killed, afterWSteal);
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
                              scene: Scene[NodeTag]): Scene[NodeTag] =
        let amt = Ring.lifestealAmount(PlayerData.equippedRing(player));
        if (amt <= 0) scene
        else
            let newHp = Combat.heal(player#hp, player#resource#hp, amt)#newHp;
            scene
                |> PlayerScene.mapPlayer(playerId, d -> {hp = newHp | d})
                |> UnitHPBarScene.update(PlayerScene.playerPath(playerId), newHp)

    /// 血吸いの剣: 与えたダメージの `effectValue`% を攻撃側へ回復（毎ヒット・撃破非依存）。
    /// 攻撃側の HP は自分の攻撃では変わらないので `player#hp` をそのまま基準にしてよい。
    def applyPlayerWeaponLifesteal(playerId: Int32, player: PlayerScene.Data,
                                    weapon: UnitCatalog.WeaponResource, dmgDealt: Int32,
                                    scene: Scene[NodeTag]): Scene[NodeTag] \ GameLogger.GameLogger =
        let pct = WeaponCatalog.lifestealPercent(weapon#effect, weapon#effectValue);
        if (pct <= 0 or dmgDealt <= 0) scene
        else
            let amt = (dmgDealt * pct) / 100;
            let newHp = Combat.heal(player#hp, player#resource#hp, amt)#newHp;
            GameLogger.playerLog("${PlayerScene.displayName(playerId, scene)}は 血を吸って HP+${newHp - player#hp}");
            scene
                |> PlayerScene.mapPlayer(playerId, d -> {hp = newHp | d})
                |> UnitHPBarScene.update(PlayerScene.playerPath(playerId), newHp)

    /// 如意棒 / 突風の書: ノックバック武器なら、生存している敵を攻撃方向へ押し流す。
    /// 上限マス数は `effectValue`（0=無制限）。`Staff.deltaToDirection` で 4 方位に丸める。
    def applyAttackKnockback(weapon: UnitCatalog.WeaponResource,
                              attackerPos: {x = Int32, y = Int32},
                              defenderPos: {x = Int32, y = Int32},
                              enemyId: Int32, killed: Bool,
                              scene: Scene[NodeTag]): Scene[NodeTag] \ Tween.Scheduler =
        match WeaponCatalog.knockbackTiles(weapon#effect, weapon#effectValue) {
            case None        => scene
            case Some(tiles) => if (killed) scene else pushEnemyBack(tiles, attackerPos, defenderPos, enemyId, scene)
        }

    /// ノックバック本体: 方向算出 → `knockbackPathCapped` の最終着地へ `snapTo`。
    def pushEnemyBack(tiles: Int32, attackerPos: {x = Int32, y = Int32},
                       defenderPos: {x = Int32, y = Int32}, enemyId: Int32,
                       scene: Scene[NodeTag]): Scene[NodeTag] \ Tween.Scheduler =
        let dir = Staff.toVec2i(Staff.deltaToDirection(
                    defenderPos#x - attackerPos#x, defenderPos#y - attackerPos#y));
        let board: Board = BoardSnapshot.fromScene(scene);
        let cap = if (tiles <= 0) None else Some(tiles);
        match List.last(Board.knockbackPathCapped(defenderPos, dir, board, cap)) {
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
            Scene[NodeTag] \ {GameEngine.Audio, GameEngine.Game, GameLogger.GameLogger} =
        GameLogger.playerLog("${PlayerScene.displayName(playerId, scene)}は ${EnemyScene.displayName(enemyId, scene)}に攻撃を外した");
        AudioStreamPlayer.play("miss");
        DamagePopupScene.emitText(popupPos, "miss", color, scene)

    /// 命中時に鳴らす SE 名を決める（純粋）。優先順位は上から:
    ///   - ダメージ 0（防御で防がれた）→ "guard"
    ///   - 必殺（クリティカル）発動    → "critical"
    ///   - 魔法武器の命中             → "magic"
    ///   - それ以外（物理で 1 以上）   → "damage"
    /// ダメージ 0 判定を最優先する（必殺でも魔法でも 0 なら防がれた音を出す）。
    pub def hitSoundName(damage: Int32, isCrit: Bool,
                          weaponType: WeaponCatalog.WeaponType): String =
        if (damage <= 0) "guard"
        else if (isCrit) "critical"
        else match weaponType {
            case WeaponCatalog.WeaponType.Magic => "magic"
            case _                              => "damage"
        }

    /// 命中: 与ダメージ/武器タイプに応じた SE を鳴らしダメージを適用。撃破なら死亡演出、
    /// 生存なら敵 HP を更新。どちらでも与ダメージの数値ポップアップを浮かす。
    def applyHit(playerId: Int32, enemyId: Int32, plan: AttackForecast, isCrit: Bool,
                  weaponType: WeaponCatalog.WeaponType,
                  popupPos: Vec2.Vec2, color: Color, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameEngine.Audio,
                               GameEngine.Game, GameLogger.GameLogger} =
        AudioStreamPlayer.play(hitSoundName(plan#dmg, isCrit, weaponType));
        // 魔法攻撃（マージ等）の着弾時は敵中心に爆発エフェクトを出す。
        let withFx = match weaponType {
            case WeaponCatalog.WeaponType.Magic => ExplosionScene.emitNormal(popupPos, scene)
            case _                              => scene
        };
        let withPopup = DamagePopupScene.emit(popupPos, plan#dmg, color, withFx);
        // 必殺のときはログ先頭に「必殺！」を付ける。
        let critTag = if (isCrit) "必殺！ " else "";
        if (plan#killed) {
            GameLogger.playerLog("${critTag}${PlayerScene.displayName(playerId, scene)}は ${EnemyScene.displayName(enemyId, scene)}を倒した");
            withPopup
                |> UnitHPBarScene.update(EnemyScene.enemyPath(enemyId), plan#newHp)
                |> EnemyScene.startDeathAnimation(enemyId)
        } else {
            GameLogger.playerLog("${critTag}${PlayerScene.displayName(playerId, scene)}は ${EnemyScene.displayName(enemyId, scene)}に ${plan#dmg}ダメージ与えた");
            // 攻撃を受けた敵は起動する（GuardUntilInRange を射程外から射ても動き出す）。
            // alerted は一方向フラグなので、ここで立てれば次の敵ターン以降ずっと追跡に入る。
            // 殴られたので、かなしばり中なら完全停止を解除する。
            withPopup
                |> EnemyScene.mapEnemy(enemyId, enemyData -> {hp = plan#newHp, alerted = true | enemyData})
                |> UnitHPBarScene.update(EnemyScene.enemyPath(enemyId), plan#newHp)
                |> EnemyScene.releaseBind(enemyId)
        }

    /// FE ルールに従い、攻撃を振った時点で装備武器（先頭）の耐久を 1 減らす（回避されても同様）。
    /// 耐久が 0 になったら先頭を取り除き破損ログを出す。
    def consumeEquippedWeapon(playerId: Int32, weapon: UnitCatalog.WeaponResource,
                               scene: Scene[NodeTag]): Scene[NodeTag] \ GameLogger.GameLogger =
        let consumed = Weapon.consume(weapon);
        if (Option.isEmpty(consumed))
            GameLogger.playerLog("${PlayerScene.displayName(playerId, scene)}の ${weapon#name}がこわれた")
        else ();
        PlayerScene.mapPlayer(playerId,
            d -> {weapons = replaceOrDropHead(consumed, d#weapons) | d}, scene)

    /// 先頭要素を `updated` の中身で差し替える。`None`（耐久 0 で破損）なら先頭を取り除く。
    def replaceOrDropHead(updated: Option[a], list: List[a]): List[a] =
        match (updated, list) {
            case (Some(w), _ :: rest) => w :: rest
            case (None,    _ :: rest) => rest
            case (_,       Nil)       => list
        }

    /// プレイヤー targetId にダメージを与える。命中率・素ダメージは `resolveStrike`
    /// （= `Combat.estimate`、武器相性・物理/魔法込み）で算出し、`Combat.damage` 適用後の
    /// HP に更新する。攻撃成立後は武器の `durability` を 1 減らし、
    /// 0 になったら `weapon = None` に切り替え、ログに「敵N の {武器名} がこわれた」を出す。
    /// ログはスペック準拠で「敵{N} → P{M} に Xダメージ」、撃破時「敵{N} → P{M} を撃破」。
    /// HP=0 なら killedIds に追加して返す（呼び出し側が死亡処理を発火する）。
    /// 武器なし（None）でここに到達した場合は防御的に何もしない。
    def applyDamageToPlayer(enemyId: Int32, enemy: EnemyScene.Data, targetId: Int32,
                             scene: Scene[NodeTag]):
            (Scene[NodeTag], List[Int32]) \
            {GameEngine.Audio, GameEngine.Game, GameLogger.GameLogger, Math.Random,
             Tween.Scheduler} =
        // 前提（武器あり・対象あり）の解決だけを担う。実体は resolveEnemyAttack に委譲。
        let resolved = forM (
            weapon <- enemy#weapon;
            player <- PlayerScene.get(targetId, scene)
        ) yield resolveEnemyAttack(enemyId, enemy, weapon, player, targetId, scene);
        Option.getWithDefault((scene, Nil), resolved)

    /// 武器と対象が揃ったときの敵攻撃解決の流れ:
    ///   resolveStrike で命中率・ダメージを算出 → 乱数ロール → 命中/回避を適用
    ///   → 武器の耐久を 1 減らす。
    def resolveEnemyAttack(enemyId: Int32, enemy: EnemyScene.Data,
                            weapon: UnitCatalog.WeaponResource, player: PlayerScene.Data,
                            targetId: Int32, scene: Scene[NodeTag]):
            (Scene[NodeTag], List[Int32]) \
            {GameEngine.Audio, GameEngine.Game, GameLogger.GameLogger, Math.Random,
             Tween.Scheduler} =
        let strike = resolveStrike(EnemyScene.combatView(enemy),
                                   PlayerScene.combatView(player));
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
                AudioStreamPlayer.play(hitSoundName(outcome#dmg, crit, weapon#weaponType));
                let critTag = if (crit) "必殺！ " else "";
                if (outcome#killed) {
                    GameLogger.enemyLog("${critTag}${enemy#resource#description}は ${player#resource#description}を倒した")
                } else {
                    GameLogger.enemyLog("${critTag}${enemy#resource#description}は ${player#resource#description}に ${outcome#dmg}ダメージ与えた")
                };
                let withPopup = DamagePopupScene.emit(popupPos, outcome#dmg, popupColor, scene);
                // 殴られたので、かなしばり中なら完全停止を解除する。
                let dmgScene = withPopup
                    |> PlayerScene.mapPlayer(targetId,
                        playerData -> {hp = outcome#newHp | playerData})
                    |> UnitHPBarScene.update(PlayerScene.playerPath(targetId), outcome#newHp)
                    |> PlayerScene.releaseBind(targetId);
                // みかえりのリング: 敵が味方を倒したら、その敵の HP を回復する。
                let afterRingSteal = if (outcome#killed) applyEnemyLifesteal(enemyId, enemy, dmgScene) else dmgScene;
                // 血吸いの剣（敵装備時）: 与ダメージの一定%を回復（撃破非依存）。
                let afterWSteal = applyEnemyWeaponLifesteal(enemyId, enemy, weapon, outcome#dmg, afterRingSteal);
                // 如意棒 / 突風の書（敵装備時）: 生存している味方をノックバック。
                let afterKnock = applyEnemyKnockback(weapon, enemy#gridPos, player#gridPos, targetId, outcome#killed, afterWSteal);
                if (outcome#killed) (afterKnock, targetId :: Nil) else (afterKnock, Nil)
            };
        // FE ルールでは攻撃を振った時点で耐久を消費する（回避されても同様）
        let consumed = Weapon.consume(weapon);
        if (Option.isEmpty(consumed))
            GameLogger.enemyLog("${enemy#resource#description}の ${weapon#name}がこわれた")
        else ();
        let withWeaponUpdate = EnemyScene.mapEnemy(enemyId,
            d -> {weapon = consumed | d}, damaged);
        (withWeaponUpdate, killed)

    /// みかえりのリングを装備した敵が撃破したとき、その敵の HP を回復する（最大 HP でクランプ）。
    /// リング未装備 / Lifesteal 以外なら回復量 0 で no-op。
    def applyEnemyLifesteal(enemyId: Int32, enemy: EnemyScene.Data,
                             scene: Scene[NodeTag]): Scene[NodeTag] =
        let amt = Ring.lifestealAmount(enemy#ring);
        if (amt <= 0) scene
        else
            let newHp = Combat.heal(enemy#hp, enemy#resource#hp, amt)#newHp;
            scene
                |> EnemyScene.mapEnemy(enemyId, d -> {hp = newHp | d})
                |> UnitHPBarScene.update(EnemyScene.enemyPath(enemyId), newHp)

    /// 血吸いの剣を敵が装備していたとき: 与ダメージの `effectValue`% を敵へ回復（毎ヒット）。
    def applyEnemyWeaponLifesteal(enemyId: Int32, enemy: EnemyScene.Data,
                                   weapon: UnitCatalog.WeaponResource, dmgDealt: Int32,
                                   scene: Scene[NodeTag]): Scene[NodeTag] \ GameLogger.GameLogger =
        let pct = WeaponCatalog.lifestealPercent(weapon#effect, weapon#effectValue);
        if (pct <= 0 or dmgDealt <= 0) scene
        else
            let amt = (dmgDealt * pct) / 100;
            let newHp = Combat.heal(enemy#hp, enemy#resource#hp, amt)#newHp;
            GameLogger.enemyLog("${enemy#resource#description}は 血を吸って HP+${newHp - enemy#hp}");
            scene
                |> EnemyScene.mapEnemy(enemyId, d -> {hp = newHp | d})
                |> UnitHPBarScene.update(EnemyScene.enemyPath(enemyId), newHp)

    /// 敵の如意棒 / 突風の書: ノックバック武器なら、生存している味方を攻撃方向へ押し流す。
    def applyEnemyKnockback(weapon: UnitCatalog.WeaponResource,
                             attackerPos: {x = Int32, y = Int32},
                             defenderPos: {x = Int32, y = Int32},
                             targetId: Int32, killed: Bool,
                             scene: Scene[NodeTag]): Scene[NodeTag] \ Tween.Scheduler =
        match WeaponCatalog.knockbackTiles(weapon#effect, weapon#effectValue) {
            case None        => scene
            case Some(tiles) => if (killed) scene else pushPlayerBack(tiles, attackerPos, defenderPos, targetId, scene)
        }

    /// 味方ノックバック本体: 方向算出 → `knockbackPathCapped` の最終着地へ `snapTo`。
    def pushPlayerBack(tiles: Int32, attackerPos: {x = Int32, y = Int32},
                        defenderPos: {x = Int32, y = Int32}, targetId: Int32,
                        scene: Scene[NodeTag]): Scene[NodeTag] \ Tween.Scheduler =
        let dir = Staff.toVec2i(Staff.deltaToDirection(
                    defenderPos#x - attackerPos#x, defenderPos#y - attackerPos#y));
        let board: Board = BoardSnapshot.fromScene(scene);
        let cap = if (tiles <= 0) None else Some(tiles);
        match List.last(Board.knockbackPathCapped(defenderPos, dir, board, cap)) {
            case None       => scene
            case Some(last) => PlayerScene.snapTo(targetId, last, scene)
        }

    /// 6 ステータスぶんの成長判定用乱数 (各 0..99) をまとめて振る。
    /// 値の意味づけ・成長判定は LevelSystem 側のピュア関数が行う。
    def rollGrowth(): LevelSystem.Rolls \ Math.Random =
        {hp           = rollPercent(),
         attack       = rollPercent(),
         defense      = rollPercent(),
         magicAttack  = rollPercent(),
         magicDefense = rollPercent(),
         speed        = rollPercent(),
         skill        = rollPercent(),
         luck         = rollPercent()}

    /// 味方 id に EXP を加算し、100 到達ならレベルアップを解決する。
    ///   - レベルアップしない → `exp` だけ更新。
    ///   - レベルアップする   → 成長ロールを振って各ステータスを成長させ、最大 HP が
    ///     増えた分だけ現在 HP も増やし、`pendingLevelUp` に結果を積む（パネル表示の合図）。
    /// `pendingLevelUp` が立つと commitWaitedAndAdvance がターンを進めずパネルへ割り込む。
    def applyExpGain(playerId: Int32, expGain: Int32,
                      scene: Scene[NodeTag]): Scene[NodeTag] \ {Math.Random, GameLogger.GameLogger} =
        let gained = forM (
            d <- PlayerScene.get(playerId, scene)
        ) yield {
            let outcome = LevelSystem.gainExp(d#exp, expGain);
            if (not outcome#levelUp)
                PlayerScene.mapPlayer(playerId, dd -> {exp = outcome#exp | dd}, scene)
            else
                applyLevelUp(playerId, d, outcome#exp, scene)
        };
        Option.getWithDefault(scene, gained)

    /// レベルアップの解決: 成長ロールを振って各ステータスを成長させ、最大 HP が増えた分だけ
    /// 現在 HP も増やし、`pendingLevelUp` に結果を積む（パネル表示の合図）。
    def applyLevelUp(playerId: Int32, d: PlayerScene.Data, newExp: Int32,
                      scene: Scene[NodeTag]): Scene[NodeTag] \ {Math.Random, GameLogger.GameLogger} =
        let rolls  = rollGrowth();
        let before = LevelSystem.statsOf(d#resource);
        let after  = LevelSystem.applyGrowth(before, d#resource#growthRates, rolls);
        let hpGain = after#hp - before#hp;
        let result = LevelSystem.buildResult(d#resource#description, d#level,
                                             before, after);
        let newHp  = d#hp + hpGain;
        GameLogger.playerLog("${d#resource#description}が Lv${d#level} → Lv${d#level + 1}");
        PlayerScene.mapPlayer(playerId, dd ->
            {exp            = newExp,
             level          = dd#level + 1,
             resource       = LevelSystem.withStats(after, dd#resource),
             hp             = newHp,
             pendingLevelUp = Some(result) | dd}, scene)
            |> UnitHPBarScene.updateMaxHp(PlayerScene.playerPath(playerId), newHp, after#hp)
}
