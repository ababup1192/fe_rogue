/// EnemyTurnDriverScene — 敵ターン進行のオーケストレーション
///
/// 「敵ターンキューを 1 step ずつ消化して画面に反映する」役割を scene tree 上の
/// 専用タグノード (`NodeTag.EnemyTurnDriver`) に常駐させ、`process` redef が phase を
/// 見て自分が動くべきタイミングを判断する。Godot 流の Node 自完結モデル。
///
/// `process` redef の phase 別動作:
///   - `EnemyTurn`        → `stepOnce` (敵キュー 1 step 進行)
///   - `PlayerAttackHold` → `Pacing` の hold が抜けたら `commitWaitedAndAdvance`
///   - その他              → no-op
///
/// 公開 API:
///   - `add(scene)`       — `GameLifecycle.buildPlayingScene` で scene tree に常駐ノードを追加
///   - `process(...)`     — `Node[NodeTag]` instance から per-frame で呼ばれる。phase 判定。
///   - `beginTurn(scene)` — 敵ターン開始 (敵キュー構築 + フェーズ遷移 + 周辺片付け)
///     `PlayerScene.commitWaitedAndAdvance` から「全員 waited」のときに呼ばれる
///
/// 3 段 gating (stepOnce の冒頭):
///   1. 演出の溜め (`Pacing.isHolding`) 中 → scene 据え置き
///   2. カメラが target に追いついていない (新しい敵にカメラがパン中) → 据え置き
///   3. `attack_lunge` 中の敵が居る (モーション完了待ち) → 据え置き
/// これにより「キャラ行動 → 溜め → カメラ移動 → 到達 → 次のキャラ行動」のリズムを作る。
mod EnemyTurnDriverScene {

    /// 常駐タグ専用ノードの NodePath。Marker2D を World 配下に置く。
    def driverName(): String = "EnemyTurnDriver"
    pub def driverPath(): NodePath =
        MapScene.worldName() :: driverName() :: Nil

    /// scene tree に常駐ノードを追加する。`GameLifecycle.buildPlayingScene` で 1 回だけ呼ぶ。
    /// engine の `Scene.processAll` が preorder で各ノードを巡回するとき、この driver の
    /// `process` redef が phase 判定 + stepOnce / tickPlayerAttackHold を起動する。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] =
        let marker = Marker2D.make(Vec2.zero());
        Scene.addChild(MapScene.worldName(), driverName(),
            EngineNode.Marker2DWithState(marker, NodeTag.EnemyTurnDriver), scene)

    /// per-frame entry。Game.flix の Node[NodeTag] instance の process redef から呼ばれる。
    /// phase 別に動作を分岐 (EnemyTurn → stepOnce / PlayerAttackHold → hold 終了判定 / 他 → no-op)。
    pub def process(_delta: Duration.Duration,
                     node: EngineNode[NodeTag],
                     _path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag])
                    \ {GameEngine.Game,
                        Tween.Scheduler, AnimationPlayer.Scheduler,
                        GameLogger.GameLogger, EnemyTurn.Queue,
                        TurnPhase.State, SelectedPlayer.State,
                        Pacing.State, PlayerScene.PartyQuery} =
        let next = match TurnPhase.State.get() {
            case TurnPhase.Phase.EnemyTurn        => stepOnce(scene)
            case TurnPhase.Phase.PlayerAttackHold =>
                if (Pacing.State.isHolding()) scene
                else PlayerScene.commitWaitedAndAdvance(scene)
            case _                                 => scene
        };
        (node, next)

    /// 敵ターン開始の共通処理。死亡演出 / 攻撃モーション中の敵はキューに含めない。
    /// `commitWaitedAndAdvance` (全味方 waited) や `endTurn` (旗で AutoMove 継続) の
    /// 流れから呼ばれる「敵ターン入口」。
    pub def beginTurn(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger, EnemyTurn.Queue,
                              TurnPhase.State} =
        let steps = EnemyScene.getAll(scene)
            |> List.filter(e -> not e#isDying
                                 and Option.isEmpty(e#attackTargetId))
            |> List.sortBy(e -> e#id)
            |> List.map(e -> ({id = e#id, remaining = e#moveTiles}: EnemyTurn.Step));
        EnemyTurn.Queue.replace(steps);
        GameLogger.enemyLog("敵のターン");
        PhaseTransitions.enterEnemyTurn(scene)

    /// 敵ターンキューの先頭 step を 1 つ進める。`process` redef から phase=EnemyTurn のとき呼ぶ。
    /// 動作:
    ///   1) キュー先頭が居る敵の Tween がアクティブ (前の step が再生中) なら待つ
    ///   2) 先頭 step を pop して `EnemyAI.decideAction` で 1 マス分の行動を決める
    ///   3) 行動を適用 (Move なら Tween 開始 + remaining-1 で pushFront、Attack なら
    ///      ログのみ、Skip/Wait は無動作)
    ///   4) キューが空になったらターン終了処理 (フェーズを PlayerCursor に戻す)
    def stepOnce(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {GameEngine.Game,
                Tween.Scheduler, AnimationPlayer.Scheduler,
                GameLogger.GameLogger, EnemyTurn.Queue,
                TurnPhase.State, SelectedPlayer.State,
                Pacing.State, PlayerScene.PartyQuery} =
        if (Pacing.State.isHolding()) scene
        else if (not CameraScene.isSettled(scene)) scene
        else if (EnemyScene.anyAttacking(scene)) scene
        else match EnemyTurn.Queue.peekFront() {
            case None       =>
                // キュー空 + 攻撃モーション無し → 敵ターン終了
                endTurn(scene)
            case Some(step) =>
                if (Tween.Scheduler.isActive(EnemyScene.enemyPath(step#id))) scene
                else
                    // 先頭 step を消費して 1 マス進める
                    let _ = EnemyTurn.Queue.popFront();
                    applyStep(step, scene)
                    // endTurn は次フレームの「キュー空 + 攻撃なし」分岐で呼ぶ
                    // (Attack の場合は attack_lunge の完了を待つ必要があるため)
        }

    /// step 1 つぶんの行動を適用する。Move なら Tween で 1 マス進めて remaining-1 を
    /// pushFront、Attack なら **体当たり攻撃モーションを開始** するだけ。HP 適用 / 音 /
    /// 死亡判定は AnimationPlayer の `attack:hit` メソッドが発火されたとき
    /// `dispatchAnimationEvents` 側で行われる。
    /// Skip/Wait は無動作 (remaining も捨てる)。
    def applyStep(step: EnemyTurn.Step, scene: Scene[NodeTag]): Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler, EnemyTurn.Queue,
                Pacing.State} =
        match EnemyScene.get(step#id, scene) {
            case None       => scene   // 既に除外済み (死亡演出完了など)
            case Some(data) =>
                let board = BoardSnapshot.fromScene(scene);
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

    /// 敵ターンの後始末: ターン番号繰り上げ + 全プレイヤーを `waited = false` にリセット +
    /// カーソル復活 + 味方ターン宣言。旗が残っていれば AutoMove に再突入する
    /// (プレイヤーが旗を立てたまま敵ターンが終わった → 続けて行進)。
    def endTurn(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                GameLogger.GameLogger, TurnPhase.State,
                SelectedPlayer.State, PlayerScene.PartyQuery} =
        GameLogger.endTurn();
        let reset = scene
            |> PlayerScene.clearAllWaited        // 全員アクティブに戻す
            |> PlayerScene.resetAllMoveStepsTaken;
        GameLogger.playerLog("味方のターン");
        if (FlagScene.isPlanted(reset))
            // 旗が立ったまま → AutoMove 継続 (カーソルは消したまま)
            PhaseTransitions.enterPlayerAutoMove(reset)
        else
            PhaseTransitions.enterPlayerCursor(reset)

}
