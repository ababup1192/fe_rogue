/// AutoMove — PlayerAutoMove フェーズで毎フレーム呼ばれる「自動移動の 1 step」ロジック
///
/// 旗 (`FlagScene`) を立てた瞬間に PlayerCursor → PlayerAutoMove に遷移し、以降は
/// このフェーズの間、`Game.gameLoop` が毎フレーム `AutoMove.step` を呼ぶ。
///
/// 動作モデル（FE 風 "号令"）:
///   - **1 フレームで動かすのは 1 体だけ**（並列でバラバラに進まない）
///   - 各味方は最大 `moveTiles` マスまで進んだら `waited = true` で交代
///   - BFS は **味方マスを通過可** とする（`Board.bfsPathSkipAllies`）
///   - 1 歩目が味方占有マスなら、その味方が先に動くのを待つ（このフレーム no-op）
///   - 旗との Manhattan 距離が近い順に動かす（先頭から行列を詰める）
///
/// 停止条件:
///   - 敵検知 → 全員停止 + ログ + PlayerCursor（旗は消す）
///   - 全アクティブ味方が `waited` になった → `EnemyTurn` に遷移（旗は残す → 次ターンで再開）
///   - 旗が無い（防御的） → PlayerCursor
mod AutoMove {

    /// 旗から見て「停止距離」と判定するマス数（BFS 距離）。
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
                    else if (not canAnyoneProgress(active, flag, board, scene))
                        // 全員が旗近く or 経路なし or 移動力使い切り → これ以上やることが
                        // 無い。EnemyTurn に渡しても次ターン即同じ状況で詰むので
                        // 旗を消して PlayerCursor に戻す。
                        exitToCursor(scene)
                    else pickAndStep(active, flag, board, scene)
        }

    /// アクティブ味方の中に「まだ進める」者が 1 人でも居るか。
    /// 進める = 旗から十分遠い かつ 移動力が残っている かつ BFS で経路が引ける。
    def canAnyoneProgress(active: List[PlayerScene.Data],
                           flag: {x = Int32, y = Int32},
                           board: Board,
                           scene: Scene[NodeTag]): Bool =
        List.exists(p -> {
            if (alreadyClose(p#gridPos, flag)) false
            else if (p#moveStepsTaken >= p#resource#moveTiles) false
            else
                let allyCells = allAllyPositionsExcept(p#id, scene);
                match Board.bfsPathSkipAllies(board, allyCells, p#gridPos, flag) {
                    case None       => false
                    case Some(path) =>
                        if (List.length(path) <= stopRadius()) false
                        else
                            // 「1 歩目が占有マス」なら実際には進めないので
                            // 進捗 false。これにより全員「次が占有」状態で詰んだ
                            // ときに exitToCursor が走り、無限ループを防ぐ。
                            match List.head(path) {
                                case None       => false
                                case Some(next) => not Board.isOccupied(next, board)
                            }
                }
        }, active)

    /// 旗との Manhattan 距離が近い順に並べ、先頭から 1 体だけ動かす。
    /// `active` が空でないことは呼び出し側で保証されているので head は常に Some。
    def pickAndStep(active: List[PlayerScene.Data], flag: {x = Int32, y = Int32},
                     board: Board, scene: Scene[NodeTag]):
            Scene[NodeTag] \ Tween.Scheduler =
        let sorted = List.sortBy(p ->
            Int32.abs(p#gridPos#x - flag#x) + Int32.abs(p#gridPos#y - flag#y),
            active);
        match List.head(sorted) {
            case None    => scene
            case Some(p) => stepOnePlayer(p, flag, board, scene)
        }

    // ────────────────────────────────────────────────────────
    // (B) 1 体ぶんの 1 歩
    // ────────────────────────────────────────────────────────

    /// この 1 体について「進める」「もう待機」「味方待ち（no-op）」のいずれか。
    def stepOnePlayer(p: PlayerScene.Data, flag: {x = Int32, y = Int32},
                       board: Board, scene: Scene[NodeTag]):
            Scene[NodeTag] \ Tween.Scheduler =
        // 移動力を使い切った or 既に旗近く → 待機にして次へ
        if (p#moveStepsTaken >= p#resource#moveTiles) finishPlayer(p#id, scene)
        else if (alreadyClose(p#gridPos, flag)) finishPlayer(p#id, scene)
        else
            // waited 済みの味方も通過可能にする（FE 流: 止まっている仲間の上も通れる）
            let allyCells = allAllyPositionsExcept(p#id, scene);
            match Board.bfsPathSkipAllies(board, allyCells, p#gridPos, flag) {
                case None       => finishPlayer(p#id, scene)   // 経路なし
                case Some(path) =>
                    if (List.length(path) <= stopRadius()) finishPlayer(p#id, scene)
                    else
                        match List.head(path) {
                            case None       => finishPlayer(p#id, scene)
                            case Some(next) =>
                                // 占有マス（味方 / 敵どちらでも）には侵入禁止 →
                                // 1 マス手前で待機確定する「キュー（行列）」挙動。
                                // BFS は味方を通過可として経路を引くが、実移動では
                                // 重なりを禁ずる。canAnyoneProgress 側も同じく
                                // 「次マスが占有なら進めない」と判定するので無限ループしない。
                                if (Board.isOccupied(next, board)) finishPlayer(p#id, scene)
                                else moveOneStep(p, next, board, scene)
                        }
            }

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
        let dx = Int32.abs(src#x - flag#x);
        let dy = Int32.abs(src#y - flag#y);
        dx + dy <= stopRadius()

    def anyTweenActive(active: List[PlayerScene.Data]): Bool \ Tween.Scheduler =
        List.exists(p -> Tween.Scheduler.isActive(PlayerScene.playerPath(p#id)), active)

    // ────────────────────────────────────────────────────────
    // (D) 終了処理
    // ────────────────────────────────────────────────────────

    /// PlayerAutoMove → PlayerCursor に戻す（旗 & AutoMove を中止する系統）。
    /// 旗無し / 敵検知 / キャンセル時に使う。
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

    /// 指定 id を除いた全味方のグリッド座標。waited 済みも含む。
    /// BFS の allyCells に渡すことで「止まっている味方の上も通過可」を実現する。
    def allAllyPositionsExcept(excludeId: Int32, scene: Scene[NodeTag]): List[{x = Int32, y = Int32}] =
        PlayerScene.getAll(scene)
            |> List.filter(o -> o#id != excludeId)
            |> List.map(o -> o#gridPos)
}
