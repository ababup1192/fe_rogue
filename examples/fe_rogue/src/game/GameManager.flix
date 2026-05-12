/// GameManager — フレーム毎のゲーム進行オーケストレーション
///
/// `Game.flix` の trait instance / start / gameLoop から呼ばれる「中央マネージャ」。
/// 単一ノードの per-node 処理 (XxxScene の process) には収まらない、
/// フレーム単位で 1 回ずつ走る orchestration をここに集約している:
///   - キュー消化（敵ターン進行 / 自動移動）
///   - クロスシーン遷移（攻撃完了 → waited / 死亡 → ゲームオーバー）
///   - 入力 → 純粋判断 (TurnRules.decide) → Scene 適用の 3 段配線
///   - フェーズ別パイプラインの選択
///   - ホットリロード時のフルリビルド
///
/// 公開エントリ:
///   - `runFrame`           — gameLoop が毎フレーム呼ぶフレームエントリ
///   - `handleInput`        — InputHandler trait instance から呼ばれる入力エントリ
///   - `buildPlayingScene`  — start で初期シーンを構築するときに使う
///   - `buildBoard`         — start の BoardQuery handler closure と AutoMove が使う
///
/// 設計指針: Game.flix の `start` / `gameLoop` は **配線役** に徹し、ロジックは
/// すべてこのマネージャに置く。フレーム単位の固定パイプラインの「順番が意味を持つ」
/// ことを 1 か所で読み取れるようにするのが分割の意図。
mod GameManager {

    // ════════════════════════════════════════════════════════
    // フレームエントリ — gameLoop が毎フレーム呼ぶ
    // ════════════════════════════════════════════════════════

    /// gameLoop から呼ばれるフレーム 1 回ぶんの処理。tickFrame でゲーム更新を行い、
    /// scene.json が変わっていれば handleHotReload でフルリビルドする。
    pub def runFrame(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameEngine.Game, GameEngine.Audio,
                               Fs.FileRead, Fs.FileWrite,
                               Editor.EditorState, EditHistory.Rewind,
                               BoardQuery, Tween.Scheduler, AnimationPlayer.Scheduler,
                               GameLogger.GameLogger,
                               EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                               InitialSpawns.State, Pacing.State,
                               Math.Random, IO} =
        let dt = GameEngine.Game.getDeltaTime();
        let updated = tickFrame(dt, scene);
        if (Editor.pollReload()) handleHotReload() else updated

    /// フレーム 1 回ぶんの処理。エディタ入力を最優先で処理し、エディタ ON 中は
    /// ゲーム更新を止める。それ以外はフェーズで分岐して該当の tickXxxFrame を呼ぶ。
    def tickFrame(dt: Duration.Duration, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameEngine.Game, GameEngine.Audio,
                               Fs.FileRead, Fs.FileWrite,
                               Editor.EditorState, EditHistory.Rewind,
                               BoardQuery, Tween.Scheduler, AnimationPlayer.Scheduler,
                               GameLogger.GameLogger,
                               EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                               InitialSpawns.State, Pacing.State} =
        let afterEditor = Editor.handleInput(scene);
        if (Editor.isOn()) afterEditor
        else match TurnPhase.State.get() {
            case TurnPhase.Phase.EnemyTurn      => tickEnemyTurnFrame(dt, afterEditor)
            case TurnPhase.Phase.PlayerAutoMove => tickAutoMoveFrame(dt, afterEditor)
            case _                               => tickInputFrame(dt, afterEditor)
        }

    /// 全フェーズに共通する描画準備の尾部（カメラ追従 → ログ反映 → スクロール）。
    /// delta はカメラ smoothing の毎フレーム補間に使う。
    /// `EnemyTurn.Queue` は CameraScene.update が「alerted な敵の動きを映す」ために peek する。
    /// `Pacing.State.tick` で演出の溜めカウンタを減らす（敵ターンの間隔調整）。
    def commonEpilogue(dt: Duration.Duration, scene: Scene[NodeTag]): Scene[NodeTag]
            \ {GameEngine.Game, GameLogger.GameLogger,
                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                Pacing.State} =
        Pacing.State.tick(dt);
        scene
            |> CameraScene.update(dt)
            |> LogScene.flushFromEffect
            |> LogScene.tickScroll

    /// 敵ターン中のフレーム: キューを 1 step 進めて Tween / Animation tick → 完了イベント発火 → エピローグ。
    /// 死亡演出 (death_blink) は敵ターン跨ぎでも継続させるため、AnimationPlayer.tickAll を毎フレーム呼ぶ。
    def tickEnemyTurnFrame(dt: Duration.Duration, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameEngine.Game, GameEngine.Audio,
                               Tween.Scheduler, AnimationPlayer.Scheduler,
                               GameLogger.GameLogger,
                               EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                               InitialSpawns.State, Pacing.State} =
        scene
            |> stepEnemyTurn
            |> Tween.tickAll(dt)
            |> AnimationPlayer.tickAll(dt)
            |> dispatchAnimationEvents
            |> commonEpilogue(dt)

    /// PlayerAutoMove 中のフレーム: AutoMove.step + Tween tick + AnimationPlayer tick → エピローグ。
    /// 自動移動中に攻撃モーションは発生し得ないが、敵の death_blink がここで完了する可能性があるので
    /// AnimationPlayer.tickAll は毎フレーム呼んでおく。
    def tickAutoMoveFrame(dt: Duration.Duration, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameEngine.Game, GameEngine.Audio,
                               Tween.Scheduler, AnimationPlayer.Scheduler,
                               GameLogger.GameLogger,
                               EnemyTurn.Queue, TurnPhase.State,
                               SelectedPlayer.State, InitialSpawns.State,
                               Pacing.State} =
        scene
            |> AutoMove.step
            |> Tween.tickAll(dt)
            |> AnimationPlayer.tickAll(dt)
            |> dispatchAnimationEvents
            |> commonEpilogue(dt)

    /// 通常入力フェーズ（PlayerCursor / PlayerMoving / PlayerAttack）のフレーム:
    /// 入力 → 物理 → Tween / Animation / 完了イベント発火 → エピローグ。
    def tickInputFrame(dt: Duration.Duration, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameEngine.Game, GameEngine.Audio,
                               BoardQuery, Tween.Scheduler, AnimationPlayer.Scheduler,
                               GameLogger.GameLogger,
                               EnemyTurn.Queue, TurnPhase.State,
                               SelectedPlayer.State, InitialSpawns.State,
                               Pacing.State} =
        scene
            |> GameEngine.handleInput
            |> GameEngine.physicsProcess(delta = dt, paused = false,
                                          gravity = Vec2.zero())
            |> Tween.tickAll(dt)
            |> AnimationPlayer.tickAll(dt)
            |> dispatchAnimationEvents
            |> tickPlayerAttackHold
            |> commonEpilogue(dt)

    /// scene.json 変更を検知したときの再構築。敵ターンキュー・選択・フェーズを
    /// 初期状態に戻し、buildPlayingScene でフルリビルド → 初期 spawn を保存し直す。
    /// プレイ中状態はリセットされる。
    /// 旧シーンの playback は AnimationPlayer.tickAll の auto-stop が
    /// 「owner ノードが scene から消えたら自動停止」してくれるので、ここでは
    /// 明示的に cancelAll を呼ばない。
    def handleHotReload(): Scene[NodeTag]
            \ {GameEngine.Game, Fs.FileRead, Math.Random, IO,
                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                InitialSpawns.State} =
        EnemyTurn.Queue.replace(Nil);
        TurnPhase.State.put(TurnPhase.Phase.PlayerCursor);
        SelectedPlayer.State.put(SelectedPlayer.cleared());
        let rebuilt = buildPlayingScene();
        InitialSpawns.State.put({
            enemies = EnemyScene.snapshotSpawns(rebuilt),
            players = PlayerScene.snapshotSpawns(rebuilt)
        });
        rebuilt

    // ════════════════════════════════════════════════════════
    // 入力ハンドラ — TurnRules.decide に判断を委譲し、結果を Scene に反映する
    // ════════════════════════════════════════════════════════

    /// 1 回のキー入力（Confirm / Cancel）を処理する。
    /// 1. 現フレームの状態から `TurnRules.Context` を組み立てる
    /// 2. `TurnRules.decide` で次の遷移を決める（純粋関数）
    /// 3. `applyTransition` で実際の Scene 更新と effect 起動を行う
    pub def handleInput(input: TurnRules.Input, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {BoardQuery, Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameLogger.GameLogger,
                              EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State} =
        let context = buildTurnContext(input, scene);
        applyTransition(TurnRules.decide(context), scene)

    /// 現在のシーンと各 effect handler から `TurnRules.Context` を組み立てる。
    /// 「判断に必要な値だけ」を抜き出し、判断ロジック自身は純粋に保つための入口。
    def buildTurnContext(input: TurnRules.Input, scene: Scene[NodeTag]):
            TurnRules.Context \ {BoardQuery, Tween.Scheduler,
                                  TurnPhase.State, SelectedPlayer.State} =
        let selected = SelectedPlayer.State.get()#id;
        let busy = match selected {
            case Some(id) => Tween.Scheduler.isActive(PlayerScene.playerPath(id))
            case None     => false
        };
        let waitedIds = PlayerScene.getAll(scene)
            |> List.filterMap(d -> if (d#waited) Some(d#id) else None);
        let dyingIds = EnemyScene.getAll(scene)
            |> List.filterMap(e -> if (e#isDying) Some(e#id) else None);
        {
            phase           = TurnPhase.State.get(),
            input           = input,
            board           = BoardQuery.board(),
            cursor          = CursorScene.getGridPos(scene),
            selected        = selected,
            waitedPlayerIds = waitedIds,
            dyingEnemyIds   = dyingIds,
            playerBusy      = busy
        }

    /// `decide` が返した `Transition` をシーンに適用する。
    /// このマッチが「ゲームの中心ルールが画面にどう反映されるか」を一覧できる窓口。
    def applyTransition(transition: TurnRules.Transition,
                         scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameLogger.GameLogger,
                              EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State} =
        match transition {
            case TurnRules.Transition.Stay                       => scene
            case TurnRules.Transition.CursorSelectPlayer(playerId) =>
                applySelectPlayer(playerId, scene)
            case TurnRules.Transition.CursorPlantFlag(targetX, targetY) =>
                applyPlantFlag({x = targetX, y = targetY}, scene)
            case TurnRules.Transition.MovingEnterAttack          =>
                applyEnterAttackPhase(scene)
            case TurnRules.Transition.MovingCancel               =>
                applyCancelMove(scene)
            case TurnRules.Transition.AttackHit(attackerId, defenderId, defX, defY) =>
                applyAttackHit(attackerId, defenderId, {x = defX, y = defY}, scene)
            case TurnRules.Transition.AttackSkip                 =>
                commitWaitedAndAdvance(scene)
        }

    // ────────────────────────────────────────────────────────
    // Transition 各バリアントの適用
    // ────────────────────────────────────────────────────────

    /// アクティブな味方マスで Z: 選択して PlayerMoving へ。
    /// 選択時のグリッド位置を origin として記録（X キャンセルで戻すため）。
    def applySelectPlayer(playerId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {TurnPhase.State, SelectedPlayer.State} =
        SelectedPlayer.State.put({
            id     = Some(playerId),
            origin = Some(PlayerScene.getGridPos(playerId, scene))
        });
        TurnPhase.State.put(TurnPhase.Phase.PlayerMoving);
        scene
            |> EnemyRangeScene.clear
            |> MoveRangeScene.refresh   // 選択駒の青マスを構築
            |> CursorScene.setVisible(false)

    /// 空マスで Z: 旗を立てて PlayerAutoMove へ（号令）。
    /// 自動移動中は赤レンジを出さないので EnemyRangeScene を消し、カーソルも隠す。
    def applyPlantFlag(target: {x = Int32, y = Int32}, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger, TurnPhase.State} =
        GameLogger.playerLog("旗を立てた");
        TurnPhase.State.put(TurnPhase.Phase.PlayerAutoMove);
        scene
            |> EnemyRangeScene.clear
            |> FlagScene.plant(target)
            |> CursorScene.setVisible(false)

    /// PlayerMoving + Z: 攻撃フェーズへ。選択は維持し、青マスを消して赤マスを出す。
    /// カーソルを選択中駒の位置にスナップする。
    def applyEnterAttackPhase(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              TurnPhase.State, SelectedPlayer.State} =
        TurnPhase.State.put(TurnPhase.Phase.PlayerAttack);
        scene
            |> MoveRangeScene.clear
            |> PlayerAttackRangeScene.show
            |> CursorScene.setVisible(true)
            |> CursorScene.snapToPlayer

    /// PlayerMoving + X: 選択駒を **選択時の位置に瞬間移動で戻し**、選択解除して PlayerCursor。
    /// キャンセル → 再選択の繰り返しで「実質ターン制限なしの自由移動」を防ぐ。
    def applyCancelMove(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              TurnPhase.State, SelectedPlayer.State} =
        let selection = SelectedPlayer.State.get();
        let restored = match (selection#id, selection#origin) {
            case (Some(id), Some(origin)) => PlayerScene.snapTo(id, origin, scene)
            case _                         => scene
        };
        SelectedPlayer.State.put(SelectedPlayer.cleared());
        TurnPhase.State.put(TurnPhase.Phase.PlayerCursor);
        restored
            |> MoveRangeScene.clear
            |> CursorScene.setVisible(true)
            |> CursorScene.snapToPlayer

    /// PlayerAttack + 敵マスで Z: 体当たりモーションを開始する。
    /// 中点での HP 適用 / 終端の waited セットは `dispatchAnimationEvents` の
    /// applyMethodEvent / applyFinishedEvent が `attack_lunge` のイベント発火を
    /// 受けて行う。ここでは開始のみ。
    def applyAttackHit(attackerId: Int32, defenderId: Int32,
                        defenderPos: {x = Int32, y = Int32}, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameLogger.GameLogger} =
        GameLogger.playerLog("味方${attackerId}の攻撃");
        PlayerScene.startAttack(attackerId, defenderId, defenderPos, scene)

    /// PlayerAttack を抜けるときの共通処理:
    ///   1) 選択中駒を waited に（灰色 modulate）
    ///   2) 選択クリア
    ///   3) 残ったアクティブが居れば PlayerCursor に戻り、次セレクト準備
    ///      居なければ goToEnemyTurn で敵ターン開始
    def commitWaitedAndAdvance(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameLogger.GameLogger,
                              EnemyTurn.Queue, TurnPhase.State,
                              SelectedPlayer.State} =
        let withWaited = match SelectedPlayer.State.get()#id {
            case Some(id) => PlayerScene.setWaited(id, scene)
            case None     => scene   // 防御的（選択なしで Attack に入ることは想定外）
        };
        SelectedPlayer.State.put(SelectedPlayer.cleared());
        if (PlayerScene.anyActive(withWaited)) {
            TurnPhase.State.put(TurnPhase.Phase.PlayerCursor);
            withWaited
                |> PlayerAttackRangeScene.clear
                |> CursorScene.setVisible(true)
                |> CursorScene.snapToPlayer
        }
        else goToEnemyTurn(withWaited)

    /// 敵ターン開始の共通処理。死亡演出 / 攻撃モーション中の敵はキューに含めない。
    def goToEnemyTurn(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger, EnemyTurn.Queue,
                              TurnPhase.State} =
        let steps = EnemyScene.getAll(scene)
            |> List.filter(e -> not e#isDying
                                 and Option.isEmpty(e#attackTargetId))
            |> List.sortBy(e -> e#id)
            |> List.map(e -> ({id = e#id, remaining = e#moveTiles}: EnemyTurn.Step));
        EnemyTurn.Queue.replace(steps);
        TurnPhase.State.put(TurnPhase.Phase.EnemyTurn);
        GameLogger.enemyLog("敵のターン");
        scene |> PlayerAttackRangeScene.clear

    // ════════════════════════════════════════════════════════
    // 敵ターン進行 — tickEnemyTurnFrame が毎フレーム 1 step ずつ呼ぶ
    // ════════════════════════════════════════════════════════

    /// 敵ターンキューの先頭 step を 1 つ進める。Tween がアクティブなら何もしない。
    /// 動作:
    ///   1) キュー先頭が居る敵の Tween がアクティブ（前の step が再生中）なら待つ
    ///   2) 先頭 step を pop して `EnemyAI.decideAction` で 1 マス分の行動を決める
    ///   3) 行動を適用（Move なら Tween 開始 + remaining-1 で pushFront、Attack なら
    ///      ログのみ、Skip/Wait は無動作）
    ///   4) キューが空になったらターン終了処理（フェーズを PlayerCursor に戻す）
    def stepEnemyTurn(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {GameEngine.Game,
                Tween.Scheduler, AnimationPlayer.Scheduler,
                GameLogger.GameLogger, EnemyTurn.Queue,
                TurnPhase.State, SelectedPlayer.State,
                Pacing.State} =
        // 3 段の gating (どれか 1 つでも true なら scene 据え置きで進行を止める):
        //   1. 演出の溜め (Pacing.hold) 中
        //   2. **カメラが target に追いついていない** (新しい敵にカメラがパン中)
        //   3. attack_lunge 中の敵が居る（モーション完了待ち）
        // 「キャラ行動 → 溜め → カメラ移動 → 到達 → 次のキャラ行動」のリズムを作る
        if (Pacing.State.isHolding()) scene
        else if (not CameraScene.isSettled(scene)) scene
        else if (EnemyScene.anyAttacking(scene)) scene
        else match EnemyTurn.Queue.peekFront() {
            case None       =>
                // キュー空 + 攻撃モーション無し → 敵ターン終了
                finishEnemyTurn(scene)
            case Some(step) =>
                if (Tween.Scheduler.isActive(EnemyScene.enemyPath(step#id))) scene
                else
                    // 先頭 step を消費して 1 マス進める
                    let _ = EnemyTurn.Queue.popFront();
                    applyOneStep(step, scene)
                    // finishEnemyTurn は次フレームの「キュー空 + 攻撃なし」分岐で呼ぶ
                    // （Attack の場合は attack_lunge の完了を待つ必要があるため）
        }

    /// step 1 つぶんの行動を適用する。Move なら Tween で 1 マス進めて remaining-1 を
    /// pushFront、Attack なら **体当たり攻撃モーションを開始** するだけ。HP 適用 / 音 /
    /// 死亡判定は AnimationPlayer の `attack:hit` メソッドが発火されたとき
    /// `dispatchAnimationEvents` 側で行われる。
    /// Skip/Wait は無動作（remaining も捨てる）。
    def applyOneStep(step: EnemyTurn.Step, scene: Scene[NodeTag]): Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler, EnemyTurn.Queue,
                Pacing.State} =
        match EnemyScene.get(step#id, scene) {
            case None       => scene   // 既に除外済み（死亡演出完了など）
            case Some(data) =>
                let board = buildBoard(scene);
                let (action, updated) = EnemyAI.decideAction(board, data);
                let withAlert = EnemyScene.mapEnemy(step#id,
                    d -> {alerted = updated#alerted | d}, scene);
                match action {
                    case EnemyAI.EnemyAction.Move(id, target) =>
                        let moved = EnemyScene.moveTo(id, target, board#map, withAlert);
                        // 残り step があれば次の 1 マス分を継続して pushFront
                        if (step#remaining > 1)
                            EnemyTurn.Queue.pushFront({id = id,
                                                        remaining = step#remaining - 1})
                        else ();
                        // 移動後の溜め: tween (~133ms) 終了後に 100ms ほど静止して区切る
                        Pacing.State.hold(250 |> Duration.millis);
                        moved
                    case EnemyAI.EnemyAction.Attack(enemyId, targetId) =>
                        // 体当たりモーションを開始するだけ。HP 適用 / 音 / 死亡判定は
                        // attack_lunge の `attack:hit` メソッド発火時に dispatchAnimationEvents が行う。
                        // 攻撃前後の溜め: lunge (~160ms) より長い hold で「攻撃終了の余韻」を作る
                        match PlayerScene.get(targetId, withAlert) {
                            case None    => withAlert
                            case Some(p) =>
                                Pacing.State.hold(450 |> Duration.millis);
                                EnemyScene.startAttack(enemyId, targetId,
                                                        p#gridPos, withAlert)
                        }
                    case EnemyAI.EnemyAction.Wait(_) =>
                        // Wait も「動こうとして詰まった」演出の一部なので軽く溜める
                        Pacing.State.hold(150 |> Duration.millis);
                        withAlert
                    case EnemyAI.EnemyAction.Skip(_) => withAlert
                }
        }

    /// いずれかのプレイヤー HP が 0 になったときの処理。ログに濃赤の「ゲームオーバー」を残し、
    /// 同マップで初期状態（プレイヤー全員 HP=10・waited=false・初期位置、敵も初期 spawn）に戻す。
    /// 敵ターンキュー・選択もクリアして、次フレームから `PlayerCursor` で操作再開できるように。
    /// マップやログは保持される（GameLogger / Map のノードは scene を再構築しない）。
    def handlePlayerDeath(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameLogger.GameLogger,
                              EnemyTurn.Queue, TurnPhase.State,
                              InitialSpawns.State,
                              SelectedPlayer.State} =
        GameLogger.gameOverLog("ゲームオーバー");
        EnemyTurn.Queue.replace(Nil);
        TurnPhase.State.put(TurnPhase.Phase.PlayerCursor);
        SelectedPlayer.State.put(SelectedPlayer.cleared());
        // 進行中アニメ（敵 attack_lunge / 敵 death_blink 等）は AnimationPlayer.tickAll の
        // auto-stop が次フレームで掃除する（owner ノードが respawn 時に一度 removeAt されるため）。
        let initial = InitialSpawns.State.get();
        scene
            |> PlayerScene.respawnFromInitial(initial#players)
            |> EnemyScene.respawnFromInitial(initial#enemies)
            |> MoveRangeScene.clear
            |> PlayerAttackRangeScene.clear
            |> EnemyRangeScene.clear
            |> CursorScene.setVisible(true)
            |> CursorScene.snapToPlayer

    // ════════════════════════════════════════════════════════
    // 攻撃モーション完了時の後始末は dispatchAnimationEvents に集約してある。
    // tick系の per-frame 進行は AnimationPlayer.tickAll が担当。
    // ════════════════════════════════════════════════════════

    /// 敵ターンの後始末: ターン番号繰り上げ + 全プレイヤーを `waited = false` にリセット +
    /// カーソル復活 + 味方ターン宣言。
    def finishEnemyTurn(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                GameLogger.GameLogger, TurnPhase.State,
                SelectedPlayer.State} =
        GameLogger.endTurn();
        TurnPhase.State.put(TurnPhase.Phase.PlayerCursor);
        let next = scene
            |> PlayerScene.clearAllWaited        // 全員アクティブに戻す
            |> MoveRangeScene.clear              // 未選択につき青マスは無し
            |> CursorScene.setVisible(true)
            |> CursorScene.snapToPlayer;
        GameLogger.playerLog("味方のターン");
        next

    // ════════════════════════════════════════════════════════
    // AnimationPlayer の完了 / メソッドイベントを scene に反映する
    // ════════════════════════════════════════════════════════

    /// `AnimationPlayer.tickAll` の直後に呼ぶ。drainEvents で蓄積されたメソッド発火 /
    /// finished 通知を取り出し、owner NodePath と name で振り分けて適切な処理を実行する。
    /// ここがゲーム側「アニメ完了 → ゲームロジック」の唯一の窓口。
    def dispatchAnimationEvents(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameEngine.Audio,
                              GameLogger.GameLogger, Tween.Scheduler,
                              EnemyTurn.Queue, TurnPhase.State,
                              SelectedPlayer.State, InitialSpawns.State,
                              Pacing.State} =
        let bundle = AnimationPlayer.Scheduler.drainEvents();
        // method イベント → finished イベントの順に処理する。
        // method の代表例は attack:hit のダメージ判定で、finished はその後で発火する。
        let afterMethods  = List.foldLeft(applyMethodEvent, scene, bundle#methods);
        let afterFinished = List.foldLeft(applyFinishedEvent, afterMethods, bundle#finished);
        afterFinished

    /// 1 つの method イベントを適用する。owner と AnimEvent.Tag で分岐する。
    /// `Tag.AttackHit` 中点発火: owner が Player_<id> ならその味方からターゲット敵へ、
    /// Enemy_<id> ならその敵からターゲット味方へ 1 ダメージ + SE + ログ。
    /// 敵攻撃で味方 HP=0 のときはこの場で `handlePlayerDeath` を発火する（即時リセット）。
    /// 未知の name は `parseTag = None` で no-op。
    def applyMethodEvent(scene: Scene[NodeTag], event: AnimationPlayer.Event):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameEngine.Audio,
                              GameLogger.GameLogger, Tween.Scheduler,
                              EnemyTurn.Queue, TurnPhase.State,
                              SelectedPlayer.State, InitialSpawns.State} =
        match AnimEvent.parseTag(event#name) {
            case Some(AnimEvent.Tag.AttackHit) =>
                match PlayerScene.idFromPath(event#owner) {
                    case Some(playerId) =>
                        PlayerScene.applyAttackHit(playerId, scene)
                    case None =>
                        match EnemyScene.idFromPath(event#owner) {
                            case Some(enemyId) =>
                                let (next, killed) =
                                    EnemyScene.applyAttackHit(enemyId, scene);
                                if (List.nonEmpty(killed)) handlePlayerDeath(next)
                                else next
                            case None => scene
                        }
                }
            // 他の Tag は method として発火しない設計（finished のみ）
            case _ => scene
        }

    /// 1 つの finished イベントを適用する。owner で「どの Scene のノードか」を判定し、
    /// AnimEvent.Tag で「どのアニメーションだったか」を確認して後始末を呼ぶ。
    /// 未知の name は `parseTag = None` で no-op（防御的）。
    def applyFinishedEvent(scene: Scene[NodeTag], event: AnimationPlayer.Event):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameEngine.Audio, GameLogger.GameLogger,
                              EnemyTurn.Queue, TurnPhase.State,
                              SelectedPlayer.State, Pacing.State} =
        match AnimEvent.parseTag(event#name) {
            case Some(AnimEvent.Tag.DeathBlink) =>
                match EnemyScene.idFromPath(event#owner) {
                    case Some(id) => EnemyScene.completeDeath(id, scene)
                    case None     => scene
                }
            case Some(AnimEvent.Tag.AttackLunge) =>
                match PlayerScene.idFromPath(event#owner) {
                    case Some(playerId) =>
                        // 味方攻撃完了 → attackTargetId をクリア。
                        // ここで「狙った敵が瀕死 (death_blink 中)」なら、即フェーズ遷移
                        // すると camera が次の味方へパンしてしまい kill 演出を見逃す。
                        // → PlayerAttackHold + Pacing.hold(700ms) で camera を据え置き、
                        //    `tickPlayerAttackHold` が hold 終了時に commitWaitedAndAdvance
                        //    を呼ぶ。倒していない攻撃なら従来通り即遷移する。
                        let killed = killedTargetEnemyId(playerId, scene);
                        let cleared = PlayerScene.clearAttackTarget(playerId, scene);
                        match killed {
                            case Some(_) =>
                                TurnPhase.State.put(TurnPhase.Phase.PlayerAttackHold);
                                Pacing.State.hold(700 |> Duration.millis);
                                cleared
                            case None    => commitWaitedAndAdvance(cleared)
                        }
                    case None =>
                        match EnemyScene.idFromPath(event#owner) {
                            case Some(enemyId) =>
                                EnemyScene.clearAttackTarget(enemyId, scene)
                            case None => scene
                        }
                }
            // Tag.AttackHit は method 専用、Tag.Snag は finished で何もしない
            case _ => scene
        }

    /// `playerId` の現 `attackTargetId` を読み、その敵が `isDying` なら id を返す。
    /// 「いま完了した attack_lunge が敵を倒したか」を attack_lunge finished 時に
    /// 判定するために使う（attackTargetId は直後の clearAttackTarget で消える）。
    def killedTargetEnemyId(playerId: Int32, scene: Scene[NodeTag]): Option[Int32] =
        match PlayerScene.get(playerId, scene) {
            case None    => None
            case Some(d) =>
                match d#attackTargetId {
                    case None         => None
                    case Some(enemyId) =>
                        match EnemyScene.get(enemyId, scene) {
                            case Some(e) => if (e#isDying) Some(enemyId) else None
                            case None    => None
                        }
                }
        }

    /// `PlayerAttackHold` 中に毎フレーム呼ぶ。`Pacing.State` の hold が抜けたら
    /// `commitWaitedAndAdvance` を発火して PlayerCursor or EnemyTurn に遷移する。
    /// それ以外のフェーズなら何もしない。
    def tickPlayerAttackHold(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                GameLogger.GameLogger,
                EnemyTurn.Queue, TurnPhase.State,
                SelectedPlayer.State, Pacing.State} =
        match TurnPhase.State.get() {
            case TurnPhase.Phase.PlayerAttackHold =>
                if (Pacing.State.isHolding()) scene
                else commitWaitedAndAdvance(scene)
            case _ => scene
        }

    // ════════════════════════════════════════════════════════
    // シーン構築 / 盤面組み立て
    // ════════════════════════════════════════════════════════

    /// 現在の scene から Board (MapSnapshot + 駒一覧) を組み立てる。
    /// BoardQuery handler と「敵ターン処理」「AutoMove」の双方が呼ぶ。
    /// 後者は 1 体動かすたびに最新の scene から組み直して、駒の更新を反映させる。
    pub def buildBoard(scene: Scene[NodeTag]): Board =
        let layer       = MapScene.getMapLayer(scene);
        let mapGlobal   = Scene.globalPositionAt(MapScene.mapPath(), scene);
        let placements  = MapScene.getPlacements(scene);
        let map: MapSnapshot = {
            tileSize     = TileMapLayer.tileSize(layer),
            usedRect     = TileMapLayer.getUsedRect(layer),
            isWall       = c -> TileMapLayer.isWall(c, layer),
            isFloor      = c -> TileMapLayer.isFloor(c, layer),
            mapToLocal   = c -> TileMapLayer.mapToLocal(c, layer),
            gridToWorld  = c -> Vec2.add(mapGlobal, TileMapLayer.mapToLocal(c, layer)),
            moduleOfCell = c -> MapScene.moduleOfCellIn(c, placements)
        };
        let players = PlayerScene.getAll(scene)
            |> List.map(d -> (Piece.Player(d#id), d#gridPos));
        let enemies = EnemyScene.getAll(scene)
            |> List.map(e -> (Piece.Enemy(e#id), e#gridPos));
        {
            map    = map,
            pieces = List.append(players, enemies)
        }

    /// 起動時 / ホットリロード時にプレイ用シーンを組み立てる。
    /// 順序が意味を持つ（後段が前段の登録結果を参照する）。
    /// MapScene.add が `IO` を要求するため戻り値の Aef にも `IO` を含める。
    pub def buildPlayingScene(): Scene[NodeTag]
            \ {GameEngine.Game, Fs.FileRead, Math.Random, IO,
                SelectedPlayer.State} =
        Scene.empty()
            |> MapScene.add
            |> PlayerScene.add
            |> EnemyScene.add
            |> MoveRangeScene.add       // SelectedPlayer 未設定なら no-op
            |> CursorScene.add
            |> FlagScene.add            // 自動移動先マーカー（初期は非表示）
            |> CameraScene.add
            |> LogScene.add
}
