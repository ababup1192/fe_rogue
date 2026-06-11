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
///     `TurnFlow.commitWaitedAndAdvance` から「全員 waited」のときに呼ばれる
///
/// 4 段 gating (stepOnce の冒頭):
///   1. 演出の溜め (`Pacing.isHolding`) 中 → scene 据え置き
///   2. カメラが target に追いついていない (新しい敵にカメラがパン中) → 据え置き
///   3. `attack_lunge` 中の敵が居る (モーション完了待ち) → 据え置き
///   4. `attack_lunge` 中の味方が居る (= 味方反撃モーション中) → 据え置き
/// これにより「キャラ行動 → 溜め → カメラ移動 → 到達 → 次のキャラ行動」のリズムを作る。
///
/// 許容している相互参照（ターン編成ペア）: 本モジュールは `TurnFlow.commitWaitedAndAdvance`
/// を呼び、`commitWaitedAndAdvance` は全員 waited のとき `beginTurn` を呼び返す。
/// 「味方ターンの終わり」と「敵ターンの始まり」が表裏一体であるための設計的サイクル
/// （詳細は TurnFlow.flix ヘッダ参照）。
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
                        Pacing.State, PlayerData.PartyQuery, Math.Random,
                        CustomEffects.WandererSpawnRequest} =
        let next = match TurnPhase.State.get() {
            case TurnPhase.Phase.EnemyTurn        => stepOnce(scene)
            case TurnPhase.Phase.PlayerAttackHold =>
                // PlayerAttackHold は (a) BattlePanelScene.confirm が攻撃モーション
                // 開始時にセット (b) onLungeDone の Kill 演出 (Pacing.hold で 700ms)
                // (c) Counter 反撃中、の 3 段階で居続けるため、commit 可否を 3 つの待ち条件で
                // gating する: 演出ホールド中 / 味方 attack_lunge 中 / 敵反撃 attack_lunge 中。
                // どれも抜けた瞬間に commitWaitedAndAdvance で味方を waited にして次フェーズへ。
                if (Pacing.State.isHolding()
                    or PlayerScene.anyAttacking(scene)
                    or EnemyScene.anyAttacking(scene)) scene
                else TurnFlow.commitWaitedAndAdvance(scene)
            case _                                 => scene
        };
        (node, next)

    /// 敵ターン開始の共通処理。死亡演出 / 攻撃モーション中の敵はキューに含めない。
    /// `commitWaitedAndAdvance` (全味方 waited) や AutoMove の `disband` (集合→解散で
    /// 全員 waited) の流れから呼ばれる「敵ターン入口」。
    pub def beginTurn(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger, EnemyTurn.Queue,
                              TurnPhase.State} =
        let actives = EnemyScene.getAll(scene)
            |> List.filter(e -> not e#isDying and Option.isEmpty(e#attackTargetId));
        // プレイヤー始点の距離フィールド（壁のみ）で「経路最寄り」の敵から動かす。
        // 列の先頭（プレイヤーに近い敵）が先に動いて前を空けるので、後続が同ターンに詰められ、
        // 1 マス幅通路の渋滞凍結が減る。到達不能（∞）は id 順で末尾側に回る。
        // マップ未構築のテスト/初期化シーン（placements 空）では盤面を組めないので id 順へフォールバック。
        let ordered =
            if (List.isEmpty(MapScene.tryGetPlacements(scene)))
                List.sortBy(e -> e#id, actives)
            else {
                let board0 = BoardSnapshot.fromScene(scene);
                let field0 = Board.distanceField(c -> Board.isWalkable(board0, c),
                                                  Board.allPlayerCells(board0), 4096);
                List.sortBy(e -> (Board.fieldDist(field0, e#gridPos), e#id), actives)
            };
        let steps = ordered
            |> List.map(e -> ({id = e#id, remaining = e#moveTiles}: EnemyTurn.Step));
        // 敵ターン開始時に全敵の「行動済み」暗転を解除（プレイヤーの clearAllWaited と対称）。
        let cleared = EnemyScene.clearActedAll(scene);
        EnemyTurn.Queue.replace(steps);
        GameLogger.enemyLog("敵のターン");
        PhaseTransitions.enterEnemyTurn(cleared)

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
                Pacing.State, PlayerData.PartyQuery, Math.Random,
                CustomEffects.WandererSpawnRequest} =
        // 「エネミーフェーズ」の帯が出ている間は敵を動かさない（帯が出終わってから行動開始）。
        if (PhaseBannerScene.isBusy(scene)) scene
        else if (Pacing.State.isHolding()) scene
        else if (not CameraScene.isSettled(scene)) scene
        else if (EnemyScene.anyAttacking(scene)) scene
        else if (PlayerScene.anyAttacking(scene)) scene
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
    /// `CombatScene.process` 側で行われる。
    /// Skip/Wait は無動作 (remaining も捨てる)。
    def applyStep(step: EnemyTurn.Step, scene: Scene[NodeTag]): Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler, EnemyTurn.Queue,
                Pacing.State, Math.Random} =
        match EnemyScene.get(step#id, scene) {
            case None       => scene   // 既に除外済み (死亡演出完了など)
            case Some(data) =>
                // 盤面 + 盤上ユニットを 1 箇所で結合 (位置×ステータスの join は Encounter に集約)。
                // driver は手元の (mid-frame mutation 済み) scene に live で適用する。
                let enc = EncounterBuilder.fromScene(scene);
                let board = enc#board;
                let self = EnemyScene.unitView(data);
                let (action, updated) = EnemyAI.decideAction(enc, self, data#alerted);
                let withAlert = EnemyScene.mapEnemy(step#id,
                    d -> {alerted = updated#alerted | d}, scene);
                match action {
                    case EnemyAI.EnemyAction.Move(id, target) =>
                        if (step#remaining <= 0)
                            // 移動予算を使い切ったうえで隣接できなかった
                            // (decideAction が Move を返す = 非隣接) → 攻撃せず終了。行動済み暗転。
                            EnemyScene.setActed(id, withAlert)
                        else {
                            let moved = EnemyScene.moveTo(id, target, board#map, withAlert);
                            // 残り step を 1 減らして継続。0 になっても 1 度だけ積むことで、
                            // 「移動しきって隣接 → 次 step で攻撃」を可能にする
                            // (次 step は隣接なら Attack、非隣接なら上の <=0 分岐で終了)。
                            EnemyTurn.Queue.pushFront({id = id,
                                                        remaining = step#remaining - 1});
                            // 移動後の溜め: tween (~133ms) 終了後に 100ms ほど静止して区切る
                            Pacing.State.hold(250 |> Duration.millis);
                            moved
                        }
                    case EnemyAI.EnemyAction.Attack(enemyId, targetId) =>
                        // 狙う相手は EnemyAI の評価軸（仕留め > 反撃不能 > 低HP > 近さ）で決定済み。
                        // ここでは体当たりモーションを開始するだけ。HP 適用 / 音 / 死亡判定は
                        // attack_lunge の `attack:hit` メソッド発火時に CombatScene.process が行う。
                        // 攻撃前後の溜め: lunge (~160ms) より長い hold で「攻撃終了の余韻」を作る
                        // Attack はその敵の最終行動 → 行動済み暗転。
                        match PlayerScene.get(targetId, withAlert) {
                            case None    => EnemyScene.setActed(enemyId, withAlert)
                            case Some(p) =>
                                Pacing.State.hold(450 |> Duration.millis);
                                EnemyScene.setActed(enemyId,
                                    CombatScene.startAttack(Faction.Enemy, enemyId, targetId,
                                                            p#gridPos, withAlert))
                        }
                    case EnemyAI.EnemyAction.Wait(_) =>
                        // Wait も「動こうとして詰まった」演出の一部なので軽く溜める。行動済み暗転。
                        Pacing.State.hold(150 |> Duration.millis);
                        EnemyScene.setActed(step#id, withAlert)
                    case EnemyAI.EnemyAction.Skip(_) => EnemyScene.setActed(step#id, withAlert)
                    case EnemyAI.EnemyAction.Wander(id) =>
                        // 未起動の徘徊型: 同モジュール内の歩ける 1 マスへ乱数で動く（1 ターン 1 マス）。
                        // 行先選択にだけ乱数が要るため decideAction でなくここで選ぶ（decideAction は pure）。
                        // 候補なし（袋小路・包囲）なら静止。徘徊しても remaining は使わず即行動済み。
                        match RandomUtil.pick(EnemyAI.wanderCandidates(board, data#gridPos, data#prevPos)) {
                            case None         => EnemyScene.setActed(id, withAlert)
                            case Some(target) =>
                                let moved = EnemyScene.moveTo(id, target, board#map, withAlert);
                                Pacing.State.hold(150 |> Duration.millis);
                                EnemyScene.setActed(id, moved)
                        }
                }
        }

    /// 敵ターンの後始末: ターン番号繰り上げ + 全プレイヤーを `waited = false` にリセット +
    /// カーソル復活 + 味方ターン宣言。
    /// （反撃でのレベルアップは反撃ごとに `CombatScene.onLungeDone` がその場で表示するので、
    ///  ここに来る時点で保留は残っていない。）
    def endTurn(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                GameLogger.GameLogger, TurnPhase.State,
                SelectedPlayer.State, PlayerData.PartyQuery,
                CustomEffects.WandererSpawnRequest} =
        GameLogger.endTurn();
        // 敵ターンが 1 巡終わった節目に湧きクロックを進める（試練型の部屋湧きを試みる）。
        // 発生判断（周期 tick mod N・フロア上限・視界外の空き部屋セルの有無）は handler / EnemyScene 側。
        let spawned = CustomEffects.WandererSpawnRequest.maybeSpawn(scene);
        let reset = spawned
            |> PlayerScene.clearAllWaited        // 全員アクティブに戻す
            |> PlayerScene.resetAllMoveStepsTaken;
        GameLogger.playerLog("味方のターン");
        PhaseTransitions.enterPlayerCursor(reset)

}
