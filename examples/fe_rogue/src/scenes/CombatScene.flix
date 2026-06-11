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
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameEngine.Audio,
                              GameEngine.Game, GameLogger.GameLogger,
                              CustomEffects.GameOverRequest,
                              SelectedPlayer.State, Math.Random} =
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
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameEngine.Audio,
                              GameEngine.Game,
                              GameLogger.GameLogger, Math.Random} =
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
            {GameEngine.Audio, GameEngine.Game, GameLogger.GameLogger, Math.Random} =
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
                              SelectedPlayer.State, Pacing.State} =
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
                              SelectedPlayer.State, Pacing.State} =
        if (TurnPhase.State.get() == TurnPhase.Phase.EnemyTurn) {
            // 敵ターン中の味方反撃が完了した。反撃でレベルアップしていれば、その場で
            // （反撃ごとに）ステータス変化パネルへ割り込む。閉じると敵ターンに戻って続行する。
            let cleared = clearAttackTargetId(playerId, scene);
            if (PlayerScene.anyPendingLevelUp(cleared))
                PhaseTransitions.enterLevelUpView(cleared)
            else
                cleared
        } else {
            // 味方主攻撃の完了。攻撃者が消えていれば (None) 何もしない。
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
            GameLogger.enemyLog("敵${enemyId} の反撃");
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
                              SelectedPlayer.State} =
        if (TurnPhase.State.get() == TurnPhase.Phase.PlayerAttackHold) {
            let cleared = clearEnemyAttackTarget(enemyId, scene);
            TurnFlow.commitWaitedAndAdvance(cleared)
        } else {
            // EnemyTurn 中の敵主攻撃完了。clear する前に attackTargetId を読み、
            // 味方反撃の対象を決める（e#gridPos も clear 前の読み取りが必要）。
            let decision = forM (
                e <- EnemyScene.get(enemyId, scene)
            ) yield (e, CounterAttackRules.decidePlayerCounter(e,
                         e#attackTargetId
                             |> Option.flatMap(pid -> PlayerScene.get(pid, scene))));
            match decision {
                case Some((e, CounterAttackRules.Outcome.Counter(playerId))) =>
                    let cleared = clearEnemyAttackTarget(enemyId, scene);
                    GameLogger.playerLog("P${playerId} の反撃");
                    startAttack(Faction.Player, playerId, enemyId, e#gridPos, cleared)
                case _ => clearEnemyAttackTarget(enemyId, scene)
            }
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
        exp     = Int32    // 命中で得る経験値
    }

    /// 攻守共通の 1 撃解決（純粋）。`Combat.estimate` で命中率・素ダメージを出し、
    /// `Combat.damage` で防御側 HP に適用した結果を 1 レコードで返す。
    /// 味方→敵（`attackForecast`）と敵→味方（`applyDamageToPlayer`）の両方向が
    /// 必ずここを通ることで、攻守の式ドリフトを防ぐ。
    def resolveStrike(attacker: Combat.CombatView, defender: Combat.CombatView):
            {hit = Int32, dmg = Int32, newHp = Int32, killed = Bool} =
        let est    = Combat.estimate(attacker, defender);
        let result = Combat.damage(hp = defender#hp, amount = est#damage);
        {hit = est#hit, dmg = est#damage, newHp = result#newHp, killed = result#isDead}

    /// 装備武器と敵から、命中率・与ダメージ・経験値を**純粋に**算出する（乱数・Scene 非依存）。
    /// 計算は `resolveStrike`（= `Combat.estimate`）に委譲し、武器タイプ習熟・武器相性・
    /// 物理/魔法の解決を戦闘予報と実ダメージで一致させる。テストしやすいよう pub。
    pub def attackForecast(player: PlayerScene.Data, weapon: UnitCatalog.WeaponResource,
                            enemy: EnemyScene.Data): AttackForecast =
        let strike = resolveStrike(PlayerScene.combatViewWith(player, weapon),
                                   EnemyScene.combatView(enemy));
        {hitRate = strike#hit, dmg = strike#dmg, newHp = strike#newHp, killed = strike#killed,
         exp = Combat.battleExp(enemy#resource#level, player#level, strike#killed)}

    /// 敵 id にダメージを与える。装備武器（`weapons.head`）と敵が揃っていなければ no-op。
    /// 実体は `resolveAttack`。ここは前提（武器あり・敵あり）の解決だけを担い、
    /// ネストを避けるため Option を `forM` で短絡的に畳む。
    def applyDamageToEnemy(playerId: Int32, player: PlayerScene.Data, enemyId: Int32,
                            scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameEngine.Audio,
                               GameEngine.Game, GameLogger.GameLogger, Math.Random} =
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
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameEngine.Audio,
                               GameEngine.Game, GameLogger.GameLogger, Math.Random} =
        let plan       = attackForecast(player, weapon, enemy);
        let popupPos   = MapSnapshot.cellCenter(enemy#gridPos);
        let popupColor = DamagePopupScene.damageToEnemyColor();
        let (afterDamage, expGain) =
            if (Combat.isHit(plan#hitRate, rollPercent()))
                (applyHit(playerId, enemyId, plan, popupPos, popupColor, scene), plan#exp)
            else
                (applyMiss(playerId, enemyId, popupPos, popupColor, scene), 0);
        let afterWeapon = consumeEquippedWeapon(playerId, weapon, afterDamage);
        // 自分の攻撃でも敵ターンの反撃でも同様（反撃 EXP で即レベルアップした場合は
        // 敵ターン終了後にまとめてパネル表示する）。
        if (expGain <= 0) afterWeapon
        else applyExpGain(playerId, expGain, afterWeapon)

    /// 回避: miss SE を鳴らし "miss" を浮かす。HP も死亡演出も変えない。
    def applyMiss(playerId: Int32, enemyId: Int32, popupPos: Vec2.Vec2, color: Color,
                   scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameEngine.Audio, GameEngine.Game, GameLogger.GameLogger} =
        GameLogger.playerLog("P${playerId} → 敵${enemyId} ミス");
        AudioStreamPlayer.play("miss");
        DamagePopupScene.emitText(popupPos, "miss", color, scene)

    /// 命中: damage SE を鳴らしダメージを適用。撃破なら死亡演出、生存なら敵 HP を更新。
    /// どちらでも与ダメージの数値ポップアップを浮かす。
    def applyHit(playerId: Int32, enemyId: Int32, plan: AttackForecast,
                  popupPos: Vec2.Vec2, color: Color, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameEngine.Audio,
                               GameEngine.Game, GameLogger.GameLogger} =
        AudioStreamPlayer.play("damage");
        let withPopup = DamagePopupScene.emit(popupPos, plan#dmg, color, scene);
        if (plan#killed) {
            GameLogger.playerLog("P${playerId} → 敵${enemyId} を撃破");
            withPopup
                |> UnitHPBarScene.update(EnemyScene.enemyPath(enemyId), plan#newHp)
                |> EnemyScene.startDeathAnimation(enemyId)
        } else {
            GameLogger.playerLog("P${playerId} → 敵${enemyId} に ${plan#dmg}ダメージ");
            // 攻撃を受けた敵は起動する（GuardUntilInRange を射程外から射ても動き出す）。
            // alerted は一方向フラグなので、ここで立てれば次の敵ターン以降ずっと追跡に入る。
            withPopup
                |> EnemyScene.mapEnemy(enemyId, enemyData -> {hp = plan#newHp, alerted = true | enemyData})
                |> UnitHPBarScene.update(EnemyScene.enemyPath(enemyId), plan#newHp)
        }

    /// FE ルールに従い、攻撃を振った時点で装備武器（先頭）の耐久を 1 減らす（回避されても同様）。
    /// 耐久が 0 になったら先頭を取り除き破損ログを出す。
    def consumeEquippedWeapon(playerId: Int32, weapon: UnitCatalog.WeaponResource,
                               scene: Scene[NodeTag]): Scene[NodeTag] \ GameLogger.GameLogger =
        let consumed = Weapon.consume(weapon);
        if (Option.isEmpty(consumed))
            GameLogger.playerLog("P${playerId} の ${weapon#name} がこわれた")
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
            {GameEngine.Audio, GameEngine.Game, GameLogger.GameLogger, Math.Random} =
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
            {GameEngine.Audio, GameEngine.Game, GameLogger.GameLogger, Math.Random} =
        let strike = resolveStrike(EnemyScene.combatView(enemy),
                                   PlayerScene.combatView(player));
        let roll = rollPercent();
        let popupPos = MapSnapshot.cellCenter(player#gridPos);
        let popupColor = DamagePopupScene.damageToPlayerColor();
        let (damaged, killed) =
            if (not Combat.isHit(strike#hit, roll)) {
                // 回避: miss SE を鳴らして "miss" を浮かす。HP は変えない。
                GameLogger.enemyLog("敵${enemyId} → P${targetId} ミス");
                AudioStreamPlayer.play("miss");
                (DamagePopupScene.emitText(popupPos, "miss", popupColor, scene), Nil)
            } else {
                // 命中: SE を鳴らしダメージ適用 + 数値ポップアップ。
                AudioStreamPlayer.play("damage");
                if (strike#killed) {
                    GameLogger.enemyLog("敵${enemyId} → P${targetId} を撃破")
                } else {
                    GameLogger.enemyLog("敵${enemyId} → P${targetId} に ${strike#dmg}ダメージ")
                };
                let withPopup = DamagePopupScene.emit(popupPos, strike#dmg, popupColor, scene);
                let dmgScene = withPopup
                    |> PlayerScene.mapPlayer(targetId,
                        playerData -> {hp = strike#newHp | playerData})
                    |> UnitHPBarScene.update(PlayerScene.playerPath(targetId), strike#newHp);
                if (strike#killed) (dmgScene, targetId :: Nil)
                else (dmgScene, Nil)
            };
        // FE ルールでは攻撃を振った時点で耐久を消費する（回避されても同様）
        let consumed = Weapon.consume(weapon);
        if (Option.isEmpty(consumed))
            GameLogger.enemyLog("敵${enemyId} の ${weapon#name} がこわれた")
        else ();
        let withWeaponUpdate = EnemyScene.mapEnemy(enemyId,
            d -> {weapon = consumed | d}, damaged);
        (withWeaponUpdate, killed)

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
        GameLogger.playerLog("P${playerId} Lv${d#level} → Lv${d#level + 1}");
        PlayerScene.mapPlayer(playerId, dd ->
            {exp            = newExp,
             level          = dd#level + 1,
             resource       = LevelSystem.withStats(after, dd#resource),
             hp             = newHp,
             pendingLevelUp = Some(result) | dd}, scene)
            |> UnitHPBarScene.update(PlayerScene.playerPath(playerId), newHp)
}
