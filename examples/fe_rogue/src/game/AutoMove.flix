/// AutoMove — PlayerAutoMove フェーズで毎フレーム呼ばれる「自動移動の 1 step」ロジック
///
/// 旗 (`FlagScene`) を立てた瞬間に PlayerCursor → PlayerAutoMove に遷移し、以降は
/// このフェーズの間、`Game.gameLoop` が毎フレーム `AutoMove.step` を呼ぶ。
///
/// 動作モデル（FE 風 "号令"）:
///   - **1 フレームで動かすのは 1 体だけ**（並列でバラバラに進まない）
///   - 各味方は最大 `moveTiles` マスまで進んだら `waited = true` で交代
///   - 味方マスの扱いは **通常移動と同じ**: 通過可、ただし重なって停止 NG。
///     active / waited は区別せず、`Board.reachableForUnit` / `stoppableForUnit` /
///     `nextStepToward` 経由でモデルを共通化する。
///   - 旗との Manhattan 距離が近い順に動かす（先頭から行列を詰める）
///   - 行き先 (destination) は **stoppable な中で旗に最も近いマス** をフレームごとに選ぶ。
///     停止できるマスが「現在地より旗に近い」候補に絞られていれば必ず空きマス。
///
/// 停止条件:
///   - 敵検知 → 全員停止 + ログ + PlayerCursor（旗は消す）
///   - 全アクティブ味方が旗近くに集合 or 進めない → PlayerCursor（旗は消す = 集合完了 / 詰み）
///   - 全アクティブ味方が `waited` になった → `EnemyTurn` に遷移（旗は残す → 次ターンで再開）
mod AutoMove {

    /// 旗から見て「停止距離」と判定するマス数（Manhattan 距離）。
    /// FE で言うなら「周囲 2 マス以内に入ったらそこで止まる」感覚。
    def stopRadius(): Int32 = 2

    // ────────────────────────────────────────────────────────
    // (A) 公開: 1 フレーム分の進行
    // ────────────────────────────────────────────────────────

    /// PlayerAutoMove フェーズ中に毎フレーム呼ぶ。`GameManager.tickAutoMoveFrame` のパイプライン要素。
    pub def step(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                GameLogger.GameLogger,
                EnemyTurn.Queue,
                TurnPhase.State, SelectedPlayer.State} =
        // 入力ハンドラ（cancelAutoMove 等）でこのフレーム中に既に他フェーズに
        // 抜けた場合は no-op で抜ける。
        if (TurnPhase.State.get() != TurnPhase.Phase.PlayerAutoMove) scene
        else match FlagScene.getTargetPos(scene) {
            case None       => exitToCursor(scene)
            case Some(flag) =>
                let board = GameManager.buildBoard(scene);
                if (anyEnemyDetected(scene, board)) {
                    GameLogger.playerLog("敵に発見された");
                    exitToCursor(scene)
                }
                else
                    let active = activePlayers(scene);
                    if (List.isEmpty(active)) exitForTurnEnd(scene)
                    else if (anyTweenActive(active)) scene
                    else if (not anyoneCanProgress(active, flag, board))
                        // 全員が旗近く or 経路なし or 移動力使い切り → 集合完了 or 詰み。
                        // EnemyTurn に渡しても次ターン同じ状況になる可能性が高いので
                        // 旗を消して PlayerCursor に戻す。
                        exitToCursor(scene)
                    else pickAndStep(active, flag, board, scene)
        }

    /// アクティブ味方の中に「まだ進める」者が 1 人でも居るか。
    /// 進める = 旗から十分遠い かつ 移動力が残っている かつ
    ///         stoppable な中に「現在より旗に近い空きマス」が存在する。
    def anyoneCanProgress(active: List[PlayerScene.Data],
                           flag: {x = Int32, y = Int32},
                           board: Board): Bool =
        List.exists(p -> canProgress(p, flag, board), active)

    def canProgress(p: PlayerScene.Data,
                     flag: {x = Int32, y = Int32},
                     board: Board): Bool =
        if (alreadyClose(p#gridPos, flag)) false
        else
            let remaining = p#resource#moveTiles - p#moveStepsTaken;
            if (remaining <= 0) false
            else
                match chooseDestination(p#gridPos, remaining, flag, board) {
                    case None    => false
                    case Some(_) => true
                }

    /// 旗との Manhattan 距離が近い順にソートし、先頭 1 体だけ動かす。
    /// `active` が空でないことは呼び出し側で保証されているので head は常に Some。
    def pickAndStep(active: List[PlayerScene.Data],
                     flag: {x = Int32, y = Int32},
                     board: Board,
                     scene: Scene[NodeTag]):
            Scene[NodeTag] \ Tween.Scheduler =
        let sorted = List.sortBy(p -> manhattan(p#gridPos, flag), active);
        match List.head(sorted) {
            case None    => scene
            case Some(p) => stepOnePlayer(p, flag, board, scene)
        }

    // ────────────────────────────────────────────────────────
    // (B) 1 体ぶんの 1 歩
    // ────────────────────────────────────────────────────────

    /// この 1 体について「進める」「もう待機」のいずれか。
    /// destination は stoppable から「旗に最も近い空きマス」を選ぶので、
    /// 1 歩目が味方マスでも通過可（`Board.nextStepToward` が pass-through）。
    def stepOnePlayer(p: PlayerScene.Data,
                       flag: {x = Int32, y = Int32},
                       board: Board,
                       scene: Scene[NodeTag]):
            Scene[NodeTag] \ Tween.Scheduler =
        if (alreadyClose(p#gridPos, flag)) finishPlayer(p#id, scene)
        else
            let remaining = p#resource#moveTiles - p#moveStepsTaken;
            if (remaining <= 0) finishPlayer(p#id, scene)
            else match chooseDestination(p#gridPos, remaining, flag, board) {
                case None       => finishPlayer(p#id, scene)
                case Some(dest) =>
                    match Board.nextStepToward(board, p#gridPos, dest) {
                        case None       => finishPlayer(p#id, scene)
                        case Some(next) => moveOneStep(p, next, board, scene)
                    }
            }

    /// 「停止できる」マスの中から、旗との Manhattan 距離が最も近いものを選ぶ。
    /// 「現在地より旗に近い」候補だけに絞ることで、無駄打ち（壁際で原地停滞）を防ぐ。
    /// 候補ゼロ → None（呼び出し側が finishPlayer する）。
    def chooseDestination(origin: {x = Int32, y = Int32},
                           remaining: Int32,
                           flag: {x = Int32, y = Int32},
                           board: Board):
            Option[{x = Int32, y = Int32}] =
        let curDist = manhattan(origin, flag);
        let candidates = Board.stoppableForUnit(board, origin, remaining)
            |> List.filter(c -> manhattan(c, flag) < curDist);
        candidates |> List.minimumBy((a, b) ->
            Order.compare(manhattan(a, flag), manhattan(b, flag)))

    /// 実際に 1 マス Tween で進める。`moveStepsTaken += 1`。
    /// 上限到達なら同時に waited にする。
    def moveOneStep(p: PlayerScene.Data, next: {x = Int32, y = Int32},
                     board: Board, scene: Scene[NodeTag]): Scene[NodeTag] \ Tween.Scheduler =
        let moved = PlayerScene.moveToById(p#id, next, board#map, scene);
        let newSteps = p#moveStepsTaken + 1;
        let recorded = PlayerScene.setMoveStepsTaken(p#id, newSteps, moved);
        if (newSteps >= p#resource#moveTiles) PlayerScene.setWaited(p#id, recorded)
        else recorded

    /// この味方は今ターンの AutoMove では「もう動けない / 動かない」→ waited にして次へ。
    def finishPlayer(id: Int32, scene: Scene[NodeTag]): Scene[NodeTag] =
        PlayerScene.setWaited(id, scene)

    // ────────────────────────────────────────────────────────
    // (C) 停止判定
    // ────────────────────────────────────────────────────────

    /// アクティブな味方と「生きている」敵が同じモジュール idx に居るか。
    def anyEnemyDetected(scene: Scene[NodeTag], board: Board): Bool =
        let aliveEnemies = EnemyScene.getAll(scene)
            |> List.filter(d -> not d#isDying);
        let active = activePlayers(scene);
        List.exists(e -> {
            match board#map#moduleOfCell(e#gridPos) {
                case None     => false
                case Some(em) =>
                    List.exists(p ->
                        match board#map#moduleOfCell(p#gridPos) {
                            case Some(pm) => pm == em
                            case None     => false
                        },
                        active)
            }
        }, aliveEnemies)

    /// 旗との Manhattan 距離が ≤ stopRadius なら「もう近い」扱い。
    def alreadyClose(src: {x = Int32, y = Int32}, flag: {x = Int32, y = Int32}): Bool =
        manhattan(src, flag) <= stopRadius()

    def manhattan(a: {x = Int32, y = Int32}, b: {x = Int32, y = Int32}): Int32 =
        Int32.abs(a#x - b#x) + Int32.abs(a#y - b#y)

    def anyTweenActive(active: List[PlayerScene.Data]): Bool \ Tween.Scheduler =
        List.exists(p -> Tween.Scheduler.isActive(PlayerScene.playerPath(p#id)), active)

    // ────────────────────────────────────────────────────────
    // (D) 終了処理
    // ────────────────────────────────────────────────────────

    /// PlayerAutoMove → PlayerCursor に戻す（旗 & AutoMove を中止する系統）。
    /// 旗無し / 敵検知 / キャンセル / 集合完了 時に使う。
    def exitToCursor(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              TurnPhase.State, SelectedPlayer.State} =
        TurnPhase.State.put(TurnPhase.Phase.PlayerCursor);
        scene
            |> FlagScene.clear
            |> PlayerScene.resetAllMoveStepsTaken
            |> CursorScene.setVisible(true)
            |> CursorScene.snapToPlayer

    /// PlayerAutoMove → EnemyTurn（旗を残して通常のターン終了）。
    /// 全アクティブ味方が waited になった時に使う。旗は次ターン開始時に
    /// AutoMove 再開のトリガとして残す。
    def exitForTurnEnd(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger, EnemyTurn.Queue,
                              TurnPhase.State, SelectedPlayer.State} =
        SelectedPlayer.State.put(SelectedPlayer.cleared());
        GameManager.goToEnemyTurn(scene)

    // ────────────────────────────────────────────────────────
    // (E) ヘルパー
    // ────────────────────────────────────────────────────────

    /// アクティブ（waited = false）な味方一覧。
    def activePlayers(scene: Scene[NodeTag]): List[PlayerScene.Data] =
        PlayerScene.getAll(scene) |> List.filter(d -> not d#waited)
}
