/// GameManager — フレーム毎のゲーム進行オーケストレーション (Stage 7-8 で消滅予定)
///
/// `Game.flix` の trait instance / start / gameLoop から呼ばれる「中央マネージャ」。
/// 単一ノードの per-node 処理 (XxxScene の process) には収まらない、
/// フレーム単位で 1 回ずつ走る orchestration をここに集約している:
///   - フェーズ別パイプラインの選択 (runFrame / tickXxxFrame)
///   - 入力 → 純粋判断 (TurnRules.decide) → Scene 適用の 3 段配線
///   - アニメーション完了イベントの dispatch (applyMethodEvent / applyFinishedEvent)
///   - ホットリロード時のフルリビルド (buildPlayingScene)
///
/// 既に Scene 側に移行済み:
///   - 敵ターン進行 → `EnemyTurnDriverScene` (stepOnce / beginTurn / endTurn)
///   - メニュー confirm/cancel → 各 Menu Scene 内
///   - Transition 適用 → 各 Scene の関数 (beginSelection / enterAttackPhase 等)
///   - 純粋ロジック → BoardSnapshot / CounterAttackRules / TurnContextBuilder
///   - ゲームオーバー時のフルリビルド → `CustomEffects.GameOverRequest` handler
///
/// 公開エントリ:
///   - `runFrame`              — gameLoop が毎フレーム呼ぶフレームエントリ
///   - `handleInput`           — InputHandler trait instance から呼ばれる入力エントリ
///   - `buildPlayingScene`     — start / GameOverRequest handler で使うフルリビルド
///   - `buildBoard`            — BoardQuery handler / AutoMove / MoveRangeScene 用
///   - `applyAttackHit`        — ForecastPanelScene.confirm から呼ばれる体当たり開始
///   - `applyEnterAttackPhase` — (Stage 3 完了で削除済み; 残存参照なし)
///   - `commitWaitedAndAdvance` — 各 Scene から呼ばれる「選択駒 waited → 次へ」
///   - `cancelAutoMove`        — AutoMove キャンセル (Stage 5 で AutoMoveDriverScene へ)
mod GameManager {

    // ════════════════════════════════════════════════════════
    // フレームエントリ — gameLoop が毎フレーム呼ぶ
    // ════════════════════════════════════════════════════════

    /// gameLoop から呼ばれるフレーム 1 回ぶんの処理。フェーズで分岐して該当の
    /// tickXxxFrame を呼ぶ。ゲームオーバー時のフルリビルドは
    /// `CustomEffects.GameOverRequest` handler が catalog を保持して実行するため、
    /// この関数は catalog を引き回さない。
    pub def runFrame(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameEngine.Game, GameEngine.Audio,
                               BoardQuery, Tween.Scheduler, AnimationPlayer.Scheduler,
                               GameLogger.GameLogger,
                               EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                               CustomEffects.GameOverRequest, Pacing.State} =
        let dt = GameEngine.Game.getDeltaTime();
        match TurnPhase.State.get() {
            case TurnPhase.Phase.EnemyTurn      => tickEnemyTurnFrame(dt, scene)
            case TurnPhase.Phase.PlayerAutoMove => tickAutoMoveFrame(dt, scene)
            case _                               => tickInputFrame(dt, scene)
        }

    /// 全フェーズに共通する描画準備の尾部（カメラ追従 → ログ反映 → スクロール）。
    /// delta はカメラ smoothing の毎フレーム補間に使う。
    /// `EnemyTurn.Queue` は CameraScene.update が「alerted な敵の動きを映す」ために peek する。
    /// `Pacing.State.tick` で演出の溜めカウンタを減らす（敵ターンの間隔調整）。
    /// UI レイアウト (Container) は scene.json のロード時に Layout.apply 済みなので
    /// 毎フレームの走査は不要。
    def commonEpilogue(dt: Duration.Duration, scene: Scene[NodeTag]): Scene[NodeTag]
            \ {GameEngine.Game, GameLogger.GameLogger,
                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                Pacing.State} =
        Pacing.State.tick(dt);
        scene
            |> CameraScene.update(dt)
            |> DamagePopupScene.tick(dt)
            |> UnitHPBarScene.tickAll(dt)
            |> ItemScene.tickAll(dt)
            |> UnitInfoPopupScene.update
            |> LogScene.flushFromEffect
            |> LogScene.tickScroll

    /// 敵ターン中のフレーム: キューを 1 step 進めて Tween / Animation tick → 完了イベント発火 → エピローグ。
    /// 死亡演出 (death_blink) は敵ターン跨ぎでも継続させるため、AnimationPlayer.tickAll を毎フレーム呼ぶ。
    def tickEnemyTurnFrame(dt: Duration.Duration, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameEngine.Game, GameEngine.Audio,
                               Tween.Scheduler, AnimationPlayer.Scheduler,
                               GameLogger.GameLogger,
                               EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                               CustomEffects.GameOverRequest, Pacing.State} =
        scene
            |> EnemyTurnDriverScene.stepOnce
            |> Tween.tickAll(dt)
            |> AnimationPlayer.tickAll(dt)
            |> dispatchAnimationEvents
            |> commonEpilogue(dt)

    /// PlayerAutoMove 中のフレーム: 入力（X/Esc キャンセル用）→ AutoMove.step →
    /// Tween tick → AnimationPlayer tick → エピローグ。
    /// 自動移動中に攻撃モーションは発生し得ないが、敵の death_blink がここで完了する可能性があるので
    /// AnimationPlayer.tickAll は毎フレーム呼んでおく。
    /// `handleInput` を入れているのは `Game.InputHandler` の PlayerAutoMove 分岐
    /// （X / Esc で `cancelAutoMove`）を発火させるため。
    def tickAutoMoveFrame(dt: Duration.Duration, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameEngine.Game, GameEngine.Audio,
                               BoardQuery, Tween.Scheduler, AnimationPlayer.Scheduler,
                               GameLogger.GameLogger,
                               EnemyTurn.Queue, TurnPhase.State,
                               SelectedPlayer.State,
                               CustomEffects.GameOverRequest,
                               Pacing.State} =
        scene
            |> GameEngine.handleInput
            |> AutoMove.step
            |> Tween.tickAll(dt)
            |> AnimationPlayer.tickAll(dt)
            |> dispatchAnimationEvents
            |> commonEpilogue(dt)

    /// 通常入力フェーズ（PlayerCursor / PlayerMoving / WeaponSelect / PlayerAttack）の
    /// フレーム: 入力 → メニューイベント → process（WeaponMenu の inventory 反映）→
    /// 物理 → Tween / Animation / 完了イベント発火 → 武器メニュー visibility 反映
    /// → エピローグ。
    def tickInputFrame(dt: Duration.Duration, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameEngine.Game, GameEngine.Audio,
                               BoardQuery, Tween.Scheduler, AnimationPlayer.Scheduler,
                               GameLogger.GameLogger,
                               EnemyTurn.Queue, TurnPhase.State,
                               SelectedPlayer.State,
                               CustomEffects.GameOverRequest,
                               Pacing.State} =
        scene
            |> GameEngine.handleInput
            |> GameEngine.handleMenus
            |> GameEngine.process(delta = dt, paused = false)
            |> GameEngine.physicsProcess(delta = dt, paused = false,
                                          gravity = Vec2.zero())
            |> Tween.tickAll(dt)
            |> AnimationPlayer.tickAll(dt)
            |> dispatchAnimationEvents
            |> EnemyTurnDriverScene.tickPlayerAttackHold
            |> applyWeaponMenuVisibility
            |> commonEpilogue(dt)

    /// 現フェーズに応じた WeaponMenu / ForecastPanel の visible/focused を毎フレーム適用する。
    /// Push モデルではなく毎フレーム適用にしているのは、フェーズ遷移を行う関数が
    /// 複数箇所に散らばっていて漏れやすいため。コストは各 UI ノードの map で軽量。
    def applyWeaponMenuVisibility(scene: Scene[NodeTag]):
            Scene[NodeTag] \ TurnPhase.State =
        let phase = TurnPhase.State.get();
        scene
            |> WeaponMenuScene.applyVisibility(phase)
            |> ActionMenuScene.applyVisibility(phase)
            |> ForecastPanelScene.applyVisibility(phase)

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
    /// 実装は `TurnContextBuilder.build` に委譲。
    def buildTurnContext(input: TurnRules.Input, scene: Scene[NodeTag]):
            TurnRules.Context \ {BoardQuery, Tween.Scheduler,
                                  TurnPhase.State, SelectedPlayer.State} =
        TurnContextBuilder.build(input, scene)

    /// `decide` が返した `Transition` をシーンに適用する。
    /// このマッチが「ゲームの中心ルールが画面にどう反映されるか」を一覧できる窓口。
    /// 各 case の本体は対応する 1 つの Scene 関数に痩せている。
    def applyTransition(transition: TurnRules.Transition,
                         scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameLogger.GameLogger,
                              EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State} =
        match transition {
            case TurnRules.Transition.Stay                              => scene
            case TurnRules.Transition.CursorSelectPlayer(playerId)      =>
                PlayerScene.beginSelection(playerId, scene)
            case TurnRules.Transition.CursorPlantFlag(targetX, targetY) =>
                FlagScene.plant({x = targetX, y = targetY}, scene)
            case TurnRules.Transition.MovingOpenActionMenu              =>
                ActionMenuScene.openFromMoving(scene)
            case TurnRules.Transition.MovingCancel                      =>
                PlayerScene.cancelSelection(scene)
            case TurnRules.Transition.OpenWeaponMenu(attackerId, defenderId, _defX, _defY) =>
                WeaponMenuScene.openFor(attackerId, defenderId, scene)
            case TurnRules.Transition.AttackSkip                        =>
                commitWaitedAndAdvance(scene)
        }

    /// AutoMove 中 X/Esc キャンセル: 旗を消し、moveStepsTaken を全員 0 に戻し、
    /// PlayerCursor に復帰してカーソルを再表示する。`waited` 状態はそのまま残す
    /// （AutoMove 途中まで動いたキャラは既に waited になっている可能性がある）。
    pub def cancelAutoMove(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameLogger.GameLogger,
                              TurnPhase.State, SelectedPlayer.State} =
        GameLogger.playerLog("自動移動を中止");
        TurnPhase.State.put(TurnPhase.Phase.PlayerCursor);
        scene
            |> FlagScene.clear
            |> PlayerScene.resetAllMoveStepsTaken
            |> CursorScene.setVisible(true)
            |> CursorScene.snapToPlayer

    /// PlayerAttack + 敵マスで Z: 体当たりモーションを開始する。
    /// 中点での HP 適用 / 終端の waited セットは `dispatchAnimationEvents` の
    /// applyMethodEvent / applyFinishedEvent が `attack_lunge` のイベント発火を
    /// 受けて行う。ここでは開始のみ。
    /// ForecastPanelScene が攻撃確定時に呼ぶため pub。
    pub def applyAttackHit(attackerId: Int32, defenderId: Int32,
                            defenderPos: {x = Int32, y = Int32}, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameLogger.GameLogger} =
        GameLogger.playerLog("味方${attackerId}の攻撃");
        PlayerScene.startAttack(attackerId, defenderId, defenderPos, scene)

    /// PlayerAttack / WeaponSelect を抜けるときの共通処理:
    ///   1) 選択中駒を waited に（灰色 modulate）
    ///   2) 選択クリア
    ///   3) 残ったアクティブが居れば PlayerCursor に戻り、次セレクト準備
    ///      居なければ goToEnemyTurn で敵ターン開始
    /// WeaponMenuScene からも呼ばれるため `pub`。
    pub def commitWaitedAndAdvance(scene: Scene[NodeTag]):
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
                |> MoveRangeScene.clear
                |> MoveAttackRangeScene.clear
                |> PlayerAttackRangeScene.clear
                |> CursorScene.setVisible(true)
                |> CursorScene.snapToPlayer
        }
        else EnemyTurnDriverScene.beginTurn(withWaited)

    // ════════════════════════════════════════════════════════
    // AnimationPlayer の完了 / メソッドイベントを scene に反映する
    // ════════════════════════════════════════════════════════

    /// `AnimationPlayer.tickAll` の直後に呼ぶ。drainEvents で蓄積されたメソッド発火 /
    /// finished 通知を取り出し、owner NodePath と name で振り分けて適切な処理を実行する。
    /// ここがゲーム側「アニメ完了 → ゲームロジック」の唯一の窓口。
    /// 全員死亡時のフルリビルドは `CustomEffects.GameOverRequest` 経由で行うため
    /// この関数は catalog を引き回さない。
    def dispatchAnimationEvents(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameEngine.Audio,
                              GameEngine.Game,
                              GameLogger.GameLogger, Tween.Scheduler,
                              EnemyTurn.Queue, TurnPhase.State,
                              SelectedPlayer.State,
                              CustomEffects.GameOverRequest,
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
    /// 敵攻撃で味方 HP=0 のときは `PlayerScene.removeDeadAndCheckGameOver` が
    /// 該当ノードを取り除き、全員脱落していれば `CustomEffects.GameOverRequest` を
    /// emit する (handler 側でフルリビルド)。
    /// 未知の name は `parseTag = None` で no-op。
    def applyMethodEvent(scene: Scene[NodeTag], event: AnimationPlayer.Event):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameEngine.Audio,
                              GameEngine.Game,
                              GameLogger.GameLogger,
                              CustomEffects.GameOverRequest,
                              SelectedPlayer.State} =
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
                                PlayerScene.removeDeadAndCheckGameOver(killed, next)
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
                        // 味方攻撃完了 → 結果に応じて分岐:
                        //   1) 狙った敵が瀕死 (death_blink 中) なら kill 演出を見せる
                        //      → PlayerAttackHold + Pacing.hold(700ms)、後で commit
                        //   2) 敵が生存 + 隣接 + 武器あり → 反撃モーション開始
                        //   3) それ以外（敵生存だが反撃不能）→ そのまま commit
                        let killed = killedTargetEnemyId(playerId, scene);
                        match killed {
                            case Some(_) =>
                                let cleared = PlayerScene.clearAttackTarget(playerId, scene);
                                TurnPhase.State.put(TurnPhase.Phase.PlayerAttackHold);
                                Pacing.State.hold(700 |> Duration.millis);
                                cleared
                            case None    =>
                                match counterAttackerForPlayer(playerId, scene) {
                                    case Some(enemyId) =>
                                        // 反撃: 味方の attackTargetId をクリアし、
                                        // 敵の AttackLunge を発火する。
                                        // 完了は applyFinishedEvent の EnemyScene 分岐で受ける。
                                        let cleared = PlayerScene.clearAttackTarget(playerId, scene);
                                        match PlayerScene.get(playerId, cleared) {
                                            case None         => commitWaitedAndAdvance(cleared)
                                            case Some(player) =>
                                                GameLogger.enemyLog("敵${enemyId} の反撃");
                                                EnemyScene.startAttack(enemyId, playerId,
                                                                          player#gridPos, cleared)
                                        }
                                    case None =>
                                        let cleared = PlayerScene.clearAttackTarget(playerId, scene);
                                        commitWaitedAndAdvance(cleared)
                                }
                        }
                    case None =>
                        match EnemyScene.idFromPath(event#owner) {
                            case Some(enemyId) =>
                                let cleared = EnemyScene.clearAttackTarget(enemyId, scene);
                                // 敵の AttackLunge 完了。フェーズが PlayerAttack のままなら
                                // これは「味方攻撃に対する反撃」の完了 → commit。
                                // EnemyTurn なら通常の敵ターン中の攻撃なので既存通り何もしない。
                                if (TurnPhase.State.get() == TurnPhase.Phase.PlayerAttack)
                                    commitWaitedAndAdvance(cleared)
                                else cleared
                            case None => scene
                        }
                }
            // Tag.AttackHit は method 専用、Tag.Snag は finished で何もしない
            case _ => scene
        }

    /// 味方の攻撃完了時に「敵が反撃するか」を判定。
    /// scene からの取り出しはここで済ませ、判断は `CounterAttackRules.attackerForPlayer`
    /// (純粋関数) に委譲する。
    def counterAttackerForPlayer(playerId: Int32, scene: Scene[NodeTag]): Option[Int32] =
        match PlayerScene.get(playerId, scene) {
            case None         => None
            case Some(player) =>
                let target = player#attackTargetId
                    |> Option.flatMap(eid -> EnemyScene.get(eid, scene));
                CounterAttackRules.attackerForPlayer(player, target)
        }

    /// `playerId` の現 `attackTargetId` を読み、その敵が `isDying` なら id を返す。
    /// scene からの取り出しはここで済ませ、判断は `CounterAttackRules.killedTargetEnemyId`
    /// (純粋関数) に委譲する。
    def killedTargetEnemyId(playerId: Int32, scene: Scene[NodeTag]): Option[Int32] =
        match PlayerScene.get(playerId, scene) {
            case None    => None
            case Some(d) =>
                let target = d#attackTargetId
                    |> Option.flatMap(eid -> EnemyScene.get(eid, scene));
                CounterAttackRules.killedTargetEnemyId(target)
        }

    // ════════════════════════════════════════════════════════
    // シーン構築 / 盤面組み立て
    // ════════════════════════════════════════════════════════

    /// 現在の scene から Board (MapSnapshot + 駒一覧) を組み立てる。
    /// BoardQuery handler と「敵ターン処理」「AutoMove」の双方が呼ぶ。
    /// 実装は `BoardSnapshot.fromScene` に委譲。
    pub def buildBoard(scene: Scene[NodeTag]): Board =
        BoardSnapshot.fromScene(scene)

    /// 起動時 / ホットリロード時にプレイ用シーンを組み立てる。
    /// 順序が意味を持つ（後段が前段の登録結果を参照する）。
    /// MapScene.add が `IO` を要求するため戻り値の Aef にも `IO` を含める。
    /// `catalog` は `Game.start` でロード済みのユニットカタログ。PlayerScene と
    /// EnemyScene にプール定義（"party" / "enemyTier1"）を辿らせる。
    pub def buildPlayingScene(catalog: UnitCatalog.UnitCatalog): Scene[NodeTag]
            \ {GameEngine.Game, Fs.FileRead, Math.Random, IO,
                SelectedPlayer.State} =
        Scene.empty()
            |> MapScene.add
            |> DamagePopupScene.add     // World 配下に空の Marker2D 親を 1 つ生やす
            |> PlayerScene.add(catalog)
            |> EnemyScene.add(catalog)
            |> ItemScene.add(catalog)   // 部屋の床に武器をランダムドロップ
            |> MoveRangeScene.add       // SelectedPlayer 未設定なら no-op
            |> CursorScene.add
            |> FlagScene.add            // 自動移動先マーカー（初期は非表示）
            |> CameraScene.add
            |> WeaponMenuScene.add      // 武器選択ウィンドウ（初期は非表示）
            |> ActionMenuScene.add      // 行動選択ウィンドウ（初期は非表示）
            |> ForecastPanelScene.add   // 戦闘予報パネル（初期は非表示）
            |> UnitInfoPopupScene.add   // カーソル上のユニット情報パネル（初期は非表示）
}
