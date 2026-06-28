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
                        TurnPhase.State, SelectedPlayer.State, GatherResume.State,
                        Pacing.State, PlayerData.PartyQuery, Math.Random,
                        CustomEffects.WandererSpawnRequest,
                        CustomEffects.RingTransformRequest,
                        CustomEffects.GameOverRequest,
                        CustomEffects.FloorAdvanceRequest, GameEngine.Audio,
                        World.Command, BoardQuery, World.WorldQuery} =
        let next = match TurnPhase.State.get() {
            case TurnPhase.Phase.EnemyTurn        => stepOnce(scene)
            case TurnPhase.Phase.PlayerAttackHold =>
                // PlayerAttackHold は (a) BattlePanelScene.confirm が攻撃モーション
                // 開始時にセット (b) onLungeDone の Kill 演出 (Pacing.hold で 700ms)
                // (c) Counter 反撃中、の 3 段階で居続けるため、commit 可否を 3 つの待ち条件で
                // gating する: 演出ホールド中 / 味方 attack_lunge 中 / 敵反撃 attack_lunge 中。
                // どれも抜けた瞬間に commitWaitedAndAdvance で味方を waited にして次フェーズへ。
                if (Pacing.State.isHolding()
                    or World.anyPlayerAttacking(World.WorldQuery.get())     // F8-slice1: 順序非依存に
                    or World.anyEnemyAttacking(World.WorldQuery.get())) scene
                else TurnFlow.commitWaitedAndAdvance(scene)
            // 移動中に「暗い新規部屋の未起動敵に接敵(隣接)」したら強制たいき。個別はその味方だけ、
            // 集合は全員。Tween（1マス滑走）中は着地を待ってから検出する。
            case TurnPhase.Phase.PlayerMoving =>
                if (selectedSliding()) scene
                else if (bumpedDarkRoomEnemy(scene)) TurnFlow.commitWaitedAndAdvance(scene)
                else scene
            case TurnPhase.Phase.GatherMove =>
                if (anyPlayerSliding(scene)) scene
                // 強制全員待機（接敵）は allowResume=false: 次ターンの集合自動継続を立てない
                // （接敵直後に集合再突入→即強制待機のループを断つ）。
                else if (bumpedDarkRoomEnemy(scene)) TurnFlow.commitAllWaitedAndAdvance(false, scene)
                else scene
            case _                                 => scene
        };
        (node, next)

    /// 選択中の味方が Tween（1マス滑走）中か。移動の着地を待ってから検出判定するためのガード。
    def selectedSliding(): Bool \ {Tween.Scheduler, SelectedPlayer.State} =
        match SelectedPlayer.State.get()#id {
            case Some(id) => PlayerScene.isMoving(id)
            case None     => false
        }

    /// いずれかの味方が Tween 中か（集合移動の着地待ちガード）。
    def anyPlayerSliding(scene: Scene[NodeTag]): Bool \ Tween.Scheduler =
        PlayerScene.getAll(scene) |> List.exists(d -> PlayerScene.isMoving(d#id))

    /// 「この移動ドラフトで誰かが origin から動いた」かつ「未起動の生存敵が、いま暗い新規部屋に
    /// 居てプレイヤーに隣接(接敵)している」瞬間だけ true。`anyMovedFromOrigin` ガードがターン頭
    /// （0歩）の暴発を防ぐ（1歩動いて初めて発火）。発火条件は「敵の視界」ではなく「接敵した
    /// キャラの隣接」なので、接敵していない他キャラの視界では発火しない。暗い判定は fog と同じ
    /// origin 基準（origin 同室の部屋は点灯済み＝対象外）。`not alerted` で既に起動済みの敵の傍
    /// では再発火しない。検出自体は純粋で effect は `SelectedPlayer.State`（drafts 読み）だけ。
    def bumpedDarkRoomEnemy(scene: Scene[NodeTag]): Bool \ {SelectedPlayer.State, BoardQuery} =
        let drafts  = SelectedPlayer.State.get()#drafts;
        let players = PlayerScene.getAll(scene);
        if (not MoveDraft.anyMovedFromOrigin(players, drafts)) false
        else {
            let placements = MapScene.getPlacements(scene);
            let roomCount  = MapScene.getRoomCount(scene);
            // いま点灯している room の集合 = origin 基準の点灯部屋（fog と一貫）。キャラのいない
            // 訪問済み部屋は暗い＝非永続なので litRooms に含めない。暗い部屋＝この集合外の room。
            let units = players
                |> List.map(d -> {gridPos = d#gridPos, hidden = d#hidden,
                                  origin = MoveDraft.originOf(d#id, drafts)
                                           |> Option.getWithDefault(d#gridPos)});
            let litRooms = MinimapScene.litRoomsDrafted(units, placements, roomCount);
            // P2: 接敵判定の board を World 由来へ（units stats は scene read-model・挙動不変）。
            let enc = EncounterBuilder.fromBoardQuery(scene);
            EnemyScene.getAll(scene)
                |> List.filter(e -> not e#isDying and not e#alerted)
                |> List.exists(e ->
                    EnemyAI.adjacentInDarkRoom(enc#board, EnemyScene.unitView(e), litRooms, roomCount))
        }

    /// 敵ターンの行動順を決める（**純粋**）。プレイヤー始点の距離場（壁のみ）で「経路最寄り」の敵から
    /// 動かす＝列の先頭（近い敵）が先に動いて前を空け、後続が同ターンに詰められる（1 マス幅通路の渋滞凍結を
    /// 減らす）。到達不能（∞）は id 順で末尾側へ。`boardOpt = None`（placements 空＝マップ未構築の
    /// テスト/初期化シーン）は盤面を組めないので **id 順フォールバック**。各 Step の remaining は moveTiles。
    pub def orderedSteps(boardOpt: Option[Board],
                          actives: List[EnemyScene.Data]): List[EnemyTurn.Step] =
        let ordered = match boardOpt {
            case None        => List.sortBy(e -> e#id, actives)
            case Some(board) =>
                let field0 = Board.distanceField(c -> Board.isWalkable(board, c),
                                                  Board.allPlayerCells(board), 4096);
                List.sortBy(e -> (Board.fieldDist(field0, e#gridPos), e#id), actives)
        };
        ordered |> List.map(e -> ({id = e#id, remaining = e#moveTiles}: EnemyTurn.Step))

    /// 敵ターン開始の共通処理。死亡演出 / 攻撃モーション中の敵はキューに含めない。
    /// `commitWaitedAndAdvance` (全味方 waited) や集合の「全員待機」(applyTurnEnd) の
    /// 流れから呼ばれる「敵ターン入口」。
    pub def beginTurn(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger, EnemyTurn.Queue,
                              TurnPhase.State, World.Command} =
        let actives = EnemyScene.getAll(scene)
            |> List.filter(e -> not e#isDying and Option.isEmpty(e#attackTargetId));
        // 行動順は純粋関数 `orderedSteps` で決める（下記）。board を組めるときだけ Some で渡す。
        // 据え置き: board は `BoardSnapshot.fromScene`（dual-write で World==scene・後日まとめて検討）。
        let boardOpt =
            if (List.isEmpty(MapScene.tryGetPlacements(scene))) None
            else Some(BoardSnapshot.fromScene(scene));
        let steps = orderedSteps(boardOpt, actives);
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
                TurnPhase.State, SelectedPlayer.State, GatherResume.State,
                Pacing.State, PlayerData.PartyQuery, Math.Random,
                CustomEffects.WandererSpawnRequest,
                CustomEffects.RingTransformRequest,
                CustomEffects.GameOverRequest,
                CustomEffects.FloorAdvanceRequest, GameEngine.Audio, World.Command, BoardQuery, World.WorldQuery} =
        // 敵ターン開始の「間」(TopBar の hold) 中は敵を動かさない（フェイズ切替が読めてから行動開始）。
        if (TopBarScene.isBusy(scene)) scene
        else if (Pacing.State.isHolding()) scene
        else if (not CameraScene.isSettled(scene)) scene
        else if (World.anyEnemyAttacking(World.WorldQuery.get())) scene      // F8-slice1
        else if (World.anyPlayerAttacking(World.WorldQuery.get())) scene     // F8-slice1
        else match EnemyTurn.Queue.peekFront() {
            case None       =>
                // キュー空 + 攻撃モーション無し → 敵ターン終了。
                // ただし敵 0 体だと敵ターンが同フレームに始まったばかりで、上部バーがまだ「敵ターン」を
                // 観測（赤へ切替＋hold 開始）していないことがある。観測するまで 1 フレーム待ってから
                // 閉じる（待たないとフェイズ表示が一度も赤にならずターンが閉じる）。
                if (not TopBarScene.hasObservedEnemy(scene)) scene
                else endTurn(scene)
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
                Pacing.State, Math.Random, GameLogger.GameLogger,
                CustomEffects.GameOverRequest, CustomEffects.RingTransformRequest,
                SelectedPlayer.State, GameEngine.Audio, World.Command, BoardQuery, World.WorldQuery} =
        match EnemyScene.get(step#id, scene) {
            case None       => scene   // 既に除外済み (死亡演出完了など)
            case Some(data) => applyStepForEnemy(step, data, scene)
        }

    /// 敵 1 体の行動分岐。優先順位:
    ///   ① かなしばり中 → 完全停止（何もせず行動済み）
    ///   ② 杖詠唱職（クレリック_T2/T3）で直線上に未停止の味方が居れば詠唱
    ///   ③ 未使用の瓶（ローグ_T3=爆発瓶 / クレリック_T3=火炎瓶）で直線上に味方が居れば投げる
    ///   ④ それ以外は通常 AI（Move / Attack / Wait / Skip / Wander）
    /// ネストした match を避けるため、各分岐は単一 match の小関数に切り出す。
    def applyStepForEnemy(step: EnemyTurn.Step, data: EnemyScene.Data,
                           scene: Scene[NodeTag]): Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler, EnemyTurn.Queue,
                Pacing.State, Math.Random, GameLogger.GameLogger,
                CustomEffects.GameOverRequest, CustomEffects.RingTransformRequest,
                SelectedPlayer.State, GameEngine.Audio, World.Command, BoardQuery, World.WorldQuery} =
        if (StatusSystem.isImmobilized(data#statuses))
            bindSkip(step, data, scene)
        else match StaffCastScene.enemyTryStaff(step#id, data#gridPos,
                                                 data#resource#description, scene) {
            case Some(afterCast) => castDone(step, afterCast)
            case None            => tryThrowOrNormal(step, data, scene)
        }

    /// かなしばり中の敵: 移動も攻撃も詠唱もせず行動済みにする。
    def bindSkip(step: EnemyTurn.Step, data: EnemyScene.Data, scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameLogger.GameLogger =
        GameLogger.enemyLog("${data#resource#description}は かなしばりで動けない");
        EnemyScene.setActed(step#id, scene)

    /// 詠唱が成立した敵: 軽く溜めて行動済みにする（詠唱がその敵の行動）。
    def castDone(step: EnemyTurn.Step, scene: Scene[NodeTag]):
            Scene[NodeTag] \ Pacing.State =
        Pacing.State.hold(450 |> Duration.millis);
        EnemyScene.setActed(step#id, scene)

    /// 詠唱しなかった敵: 未使用の瓶を投げられれば投げ、でなければ通常 AI。
    def tryThrowOrNormal(step: EnemyTurn.Step, data: EnemyScene.Data,
                          scene: Scene[NodeTag]): Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler, EnemyTurn.Queue,
                Pacing.State, Math.Random, GameLogger.GameLogger,
                CustomEffects.GameOverRequest, CustomEffects.RingTransformRequest,
                SelectedPlayer.State, GameEngine.Audio, World.Command, BoardQuery, World.WorldQuery} =
        // F7-slice2: bottleUsed を World 由来で読む（reader flip・WorldQuery 経由）。未登録は scene fallback。
        let curBottleUsed = World.bottleUsedOf(World.EntityRef.Enemy(step#id), World.WorldQuery.get())
                                |> Option.getWithDefault(data#bottleUsed);
        if (curBottleUsed)
            applyNormalStep(step, data, scene)
        else match StaffCastScene.enemyTryThrow(step#id, data#gridPos,
                                                 data#resource#description, scene) {
            case Some(afterThrow) =>
                // 投げた → このターンは投擲で終了。瓶を使用済みにして行動済み暗転。
                Pacing.State.hold(450 |> Duration.millis);
                World.Command.emit(World.Cmd.SetBottleUsed(World.EntityRef.Enemy(step#id), true));  // F7-slice2: World へ
                EnemyScene.setActed(step#id,
                    EnemyScene.mapEnemy(step#id, d -> {bottleUsed = true | d}, afterThrow))
            case None => applyNormalStep(step, data, scene)
        }

    /// 通常 AI の 1 step 適用（既存ロジック）。Move / Attack / Wait / Skip / Wander。
    def applyNormalStep(step: EnemyTurn.Step, data: EnemyScene.Data,
                         scene: Scene[NodeTag]): Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler, EnemyTurn.Queue,
                Pacing.State, Math.Random, CustomEffects.RingTransformRequest, World.Command, BoardQuery,
                World.WorldQuery} =
                // 盤面 + 盤上ユニットを 1 箇所で結合 (位置×ステータスの join は Encounter に集約)。
                // P2: EnemyAI 入力の board を World 由来へ（units stats は scene read-model・dual-write で位置一致・挙動不変）。
                let enc = EncounterBuilder.fromBoardQuery(scene);
                let board = enc#board;
                let self = EnemyScene.unitView(data);
                // F7: alerted を **World 由来**で読む（reader flip・汎用 WorldQuery 経由）。未登録は scene fallback。
                let w0 = World.WorldQuery.get();
                let curAlerted = World.alertedOf(World.EntityRef.Enemy(step#id), w0)
                                    |> Option.getWithDefault(data#alerted);
                let (action, updated) = EnemyAI.decideAction(enc, self, curAlerted);
                // F7-spike: alerted を World にも dual-write（scene 直書きと併発）。
                World.Command.emit(World.Cmd.SetAlerted(World.EntityRef.Enemy(step#id), updated#alerted));
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
                        // 敵が onEnemyTurn の effectRule(flow:replaceAttack) を持てば、攻撃の代わりに
                        // 差し替え行動（リング職人の指輪化など）をデータ駆動で取る（resolveEnemyAttack）。
                        // それ以外は体当たりモーションを開始するだけ。HP 適用 / 音 / 死亡判定は
                        // attack_lunge の `attack:hit` メソッド発火時に CombatScene.process が行う。
                        // 攻撃前後の溜め: lunge (~160ms) より長い hold で「攻撃終了の余韻」を作る
                        // Attack はその敵の最終行動 → 行動済み暗転。hold は差し替え/通常攻撃の両方の手前。
                        match PlayerScene.get(targetId, withAlert) {
                            case None    => EnemyScene.setActed(enemyId, withAlert)
                            case Some(p) =>
                                Pacing.State.hold(450 |> Duration.millis);
                                let resolved = resolveEnemyAttack(enemyId, data, targetId, p, withAlert);
                                EnemyScene.setActed(enemyId, resolved)
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
                        // F7-slice3: prevPos を World 由来で読む（reader flip・w0 は applyNormalStep 冒頭の WorldQuery snapshot）。
                        match RandomUtil.pick(EnemyAI.wanderCandidates(board, data#gridPos, World.prevPosOf(World.EntityRef.Enemy(step#id), w0))) {
                            case None         => EnemyScene.setActed(id, withAlert)
                            case Some(target) =>
                                let moved = EnemyScene.moveTo(id, target, board#map, withAlert);
                                Pacing.State.hold(150 |> Duration.millis);
                                EnemyScene.setActed(id, moved)
                        }
                }

    /// 敵ターンの攻撃解決（旧 isRingSpecial のデータ駆動版）。aiType ではなく effectRule で判定する：
    /// 敵が onEnemyTurn + flow:replaceAttack の effectRule を持てば差し替え行動（指輪化など）を、
    /// 持たなければ通常攻撃を取る。リング職人は enemies.json の effectRule で駆動される。
    def resolveEnemyAttack(enemyId: Int32, data: EnemyScene.Data, targetId: Int32,
                           p: PlayerScene.Data, scene: Scene[NodeTag]): Scene[NodeTag]
            \ {AnimationPlayer.Scheduler, Math.Random, CustomEffects.RingTransformRequest, World.Command} =
        match enemyTurnRule(data) {
            case Some(rule) => runEnemyTurnFlow(rule, enemyId, data, targetId, p, scene)
            case None       => normalEnemyAttack(enemyId, targetId, p, scene)
        }

    /// 敵が持つ onEnemyTurn の effectRule を decode（無し/trigger 不一致/不正は None）。
    /// ここでは RNG を引かない（短絡で乱数列を保つ＝effectRule を持たない敵は従来挙動）。
    def enemyTurnRule(data: EnemyScene.Data): Option[EffectRule.EffectRule] =
        (forM (
            j    <- data#resource#effectRule;
            rule <- EffectBridge.fromComposer(j)
        ) yield rule)
            |> Option.filter(rule -> rule#trigger == EffectRule.Trigger.OnEnemyTurn)

    /// onEnemyTurn の flow:replaceAttack を実行する。隣接 ∧ 差し替え可能 ∧ 確率成立なら差し替え
    /// action（ringify 等）を撒き、いずれか不成立なら通常攻撃。RNG は確率判定の1回だけ（隣接・
    /// 差し替え可否は RNG 前に判定して乱数列を保つ）。flow が replaceAttack 以外なら通常攻撃。
    ///
    /// 確率は flow 内の chance（applyReplace の roll<chance）のみで判定し、rule#chance（top-level）は
    /// 使わない: replaceForm が top-level chance を出さない＝常時 100＝「ルール自体は常時発火、差し替えだけ
    /// 確率」という設計のため。隣接限定は仕様（replaceForm が if:"adjacent" を暗黙付与。RingMan は近接前提）。
    def runEnemyTurnFlow(rule: EffectRule.EffectRule, enemyId: Int32, data: EnemyScene.Data,
                         targetId: Int32, p: PlayerScene.Data, scene: Scene[NodeTag]): Scene[NodeTag]
            \ {AnimationPlayer.Scheduler, Math.Random, CustomEffects.RingTransformRequest, World.Command} =
        match replaceFlowOf(rule) {
            case None       => normalEnemyAttack(enemyId, targetId, p, scene)
            case Some(flow) =>
                // cond は現状 replaceForm 経由で Adjacent のみだが、HP/alive も実値で埋めておく
                // （将来 cond に HP 述語が増えても静かに壊れないように）。
                let predCtx = { selfHpPct       = hpPct(data#hp, data#resource#hp),
                                targetHpPct     = hpPct(p#hp, p#resource#hp),
                                targetAlive     = true,
                                equippedIsRogue = false,
                                adjacent        = EnemyAI.isAdjacent(data#gridPos, p#gridPos) };
                if (not EffectDsl.evalPredicate(rule#cond, predCtx)
                        or not replaceFeasible(flow, targetId, scene))
                    normalEnemyAttack(enemyId, targetId, p, scene)
                else
                    applyReplaceResult(EffectFlow.applyReplace(flow, rollPercent()),
                                       enemyId, data, targetId, p, scene)
        }

    /// HP 割合（0..100）。最大 HP が 0 以下なら 0（ゼロ除算回避。CombatScene.hpPct と同式）。
    def hpPct(hp: Int32, maxHp: Int32): Int32 =
        if (maxHp <= 0) 0 else (hp * 100) / maxHp

    /// rule#flow が replaceAttack のときだけ Some。flow 無し / followUp は None（敵ターン非対応）。
    def replaceFlowOf(rule: EffectRule.EffectRule): Option[EffectRule.Flow] =
        rule#flow |> Option.filter(isReplaceAttack)

    def isReplaceAttack(flow: EffectRule.Flow): Bool = match flow {
        case EffectRule.Flow.ReplaceAttack(_, _) => true
        case _                                   => false
    }

    /// 差し替えが意味を持つか。ringify を含む差し替えは、対象に装備外アイテムが無ければ無意味なので
    /// 通常攻撃へ戻す（旧 isRingSpecial と同じ＝棒立ち回避 + roll 不消費で乱数列維持）。ringify 以外は常に可。
    def replaceFeasible(flow: EffectRule.Flow, targetId: Int32, scene: Scene[NodeTag]): Bool =
        if (replaceHasRingify(flow))
            not List.isEmpty(PlayerScene.transformableItems(targetId, scene))
        else
            true

    def replaceHasRingify(flow: EffectRule.Flow): Bool = match flow {
        case EffectRule.Flow.ReplaceAttack(_, acts) => List.exists(a -> a#op == EffectRule.Op.OpRingify, acts)
        case _                                      => false
    }

    /// applyReplace の結果を解釈。RequestReplace なら差し替え action を runPlan で撒く（通常攻撃せず）、
    /// NoFlow（確率不発）なら通常攻撃へ。
    def applyReplaceResult(effects: List[EffectFlow.FlowEffect], enemyId: Int32,
                           data: EnemyScene.Data, targetId: Int32, p: PlayerScene.Data,
                           scene: Scene[NodeTag]): Scene[NodeTag]
            \ {AnimationPlayer.Scheduler, CustomEffects.RingTransformRequest, World.Command} =
        match List.head(effects) {
            case Some(EffectFlow.FlowEffect.RequestReplace(actions)) =>
                let plan = List.flatMap(a -> EffectPlan.planAction(a, replacePlanCtx(enemyId, targetId, p)), actions);
                EffectRunner.runPlan(enemyTurnEffectHandlers(data), plan, scene)
                    !> (s -> World.emitHpSets(plan, s))  // F6a: hp も境界で World へ dual-write（tap）
            case _ => normalEnemyAttack(enemyId, targetId, p, scene)
        }

    /// 体当たり攻撃モーションを開始する（敵側）。
    def normalEnemyAttack(enemyId: Int32, targetId: Int32, p: PlayerScene.Data,
                          scene: Scene[NodeTag]): Scene[NodeTag] \ {AnimationPlayer.Scheduler, World.Command} =
        CombatScene.startAttack(Faction.Enemy, enemyId, targetId, p#gridPos, scene)

    /// 0..99 の一様乱数（CombatScene.rollPercent と同型。差し替え確率 roll に使う）。
    def rollPercent(): Int32 \ Math.Random =
        Float64.truncateToInt32(Float64.floor(Math.Random.randomFloat64() * 100.0))

    /// 敵 actor 視点の PlanCtx。`to:enemy`(FactionEnemy)+actorIsPlayer=false で対象は player 駒
    /// (is-player ⇒ ally=true) に解決される。ringify は amount を使わないので dealt=0。
    def replacePlanCtx(enemyId: Int32, targetId: Int32, p: PlayerScene.Data): EffectPlan.PlanCtx =
        {selfId = enemyId, attackerId = enemyId, actorIsPlayer = false,
         rayUnits = ({id = targetId, ally = true, immobilized = false, alive = true}: EffectRule.RayUnit) :: Nil,
         amount = {max = p#resource#hp, dealt = 0, incoming = 0, magic = 0}}

    /// 敵ターン effectRule 用 PlanHandlers。custom の "ringify" だけ RingTransformRequest へ結線し、
    /// 他は no-op（敵ターンの差し替えで使う op は現状 ringify のみ）。CombatScene.enemyEffectHandlers
    /// とは effect row が違う（こちらは RingTransformRequest を持つ）ため別関数。
    def enemyTurnEffectHandlers(data: EnemyScene.Data):
            EffectRunner.PlanHandlers[Scene[NodeTag], {CustomEffects.RingTransformRequest}] = {
        custom     = (sc, op, id, _) -> ringifyCustom(data, op, id, sc),
        heal       = (sc, _, _, _)       -> checked_ecast(sc),
        fullHeal   = (sc, _, _)          -> checked_ecast(sc),
        status     = (sc, _, _, _, _, _) -> checked_ecast(sc),
        maxHpUp    = (sc, _, _, _)       -> checked_ecast(sc),
        damage     = (sc, _, _, _)       -> checked_ecast(sc),
        immobilize = (sc, _, _, _)       -> checked_ecast(sc),
        revive     = (sc, _, _)          -> checked_ecast(sc),
        sfx        = (sc, _)             -> checked_ecast(sc),
        noOp       = (sc, _)             -> checked_ecast(sc)
    }

    /// custom op の "ringify" を RingTransformRequest へ結線（他 op は防御 no-op）。
    def ringifyCustom(data: EnemyScene.Data, op: String, id: Int32,
                      sc: Scene[NodeTag]): Scene[NodeTag] \ CustomEffects.RingTransformRequest =
        if (op == "ringify")
            CustomEffects.RingTransformRequest.transform(data#resource#description, id, sc)
        else
            checked_ecast(sc)

    /// 敵ターンの後始末: ターン番号繰り上げ + 全プレイヤーを `waited = false` にリセット +
    /// カーソル復活 + 味方ターン宣言。
    /// （反撃でのレベルアップは反撃ごとに `CombatScene.onLungeDone` がその場で表示するので、
    ///  ここに来る時点で保留は残っていない。）
    def endTurn(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                GameLogger.GameLogger, TurnPhase.State,
                SelectedPlayer.State, GatherResume.State, PlayerData.PartyQuery,
                CustomEffects.WandererSpawnRequest,
                CustomEffects.FloorAdvanceRequest, World.Command} =
        GameLogger.endTurn();
        // 敵ターンが 1 巡終わった節目に湧きクロックを進める（試練型の部屋湧きを試みる）。
        // 発生判断（周期 tick mod N・フロア上限・視界外の空き部屋セルの有無）は handler / EnemyScene 側。
        let spawned = CustomEffects.WandererSpawnRequest.maybeSpawn(scene);
        let reset = spawned
            |> PlayerScene.clearAllWaited        // 全員アクティブに戻す
            |> PlayerScene.resetAllMoveStepsTaken;
        // 湧き(maybeSpawn)・敵移動を反映した最新フォグをこのフレームで当てて敵可視を確定させる。
        // add 順（FogDriver が先）に頼らず、集合自動継続の「画面内に敵がいるか」判定を正確にする。
        let lit = FogScene.applyFog(reset);
        GameLogger.playerLog("味方のターン");
        // 集合モードのターン跨ぎ自動継続: 前ターンに集合中の全員待機で閉じ(resume)、主人公が
        // 率いられる状態で、フォグで見えている敵が 1 体もいなければ、カーソルを出さず集合へ自動再突入する。
        // resume は必ず消費（毎ターン再評価）。
        let resume = GatherResume.State.get();
        GatherResume.State.put(false);
        if (shouldResumeGather(resume, PlayerScene.lordReadyToGather(lit), EnemyScene.anyVisible(lit)))
            PlayerScene.beginGather(lit)
        else {
            // カーソル/カメラの初期スナップ先は `lit`(=clearAllWaited 後)から直接求める。
            // `enterPlayerCursor` の PartyQuery フォールバックはフレーム冒頭 snapshot を読むため、
            // 同フレームの clearAllWaited が反映されず active が空 → id=0 へフォールバックする。
            // リーダーが階段で退場(usedStairs=hidden)済みだと毎ターン階段にカーソルが飛ぶので、
            // フロアに残るアクティブな駒(`firstActive`)へ明示スナップする。
            match PlayerScene.firstActive(lit) {
                case Some(next) => PhaseTransitions.enterPlayerCursorAt(next#gridPos, lit)
                case None       =>
                    // フロアに残っていた味方が敵ターン中に全滅し、生存者が階段退場済み
                    // (usedStairs=hidden) だけになると操作できる駒が 0 になり詰む。
                    // この場合は allLivingUsedStairs が true（= フロア終了条件）なので、
                    // ロストした味方を置いて通常の階段退場と同じく次フロアへ進む。
                    if (PlayerScene.allLivingUsedStairs(lit))
                        CustomEffects.FloorAdvanceRequest.advance(lit)
                    else
                        PhaseTransitions.enterPlayerCursor(lit)
            }
        }

    /// 集合自動継続の判定（純粋）。前ターンが集合の自発全員待機(resume)で、主人公が率いられる状態
    /// (lordReady)で、フォグで見えている敵が 1 体もいない(not hasVisibleEnemy)とき true。
    pub def shouldResumeGather(resume: Bool, lordReady: Bool, hasVisibleEnemy: Bool): Bool =
        resume and lordReady and not hasVisibleEnemy

}
