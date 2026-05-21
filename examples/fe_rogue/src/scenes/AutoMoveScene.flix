/// AutoMoveScene — PlayerAutoMove フェーズの「自動移動」機能一式
///
/// `NodeTag.AutoMoveDriver` を持つ scene tree 常駐ノードと、それを駆動する step ロジックを
/// 同居させた scene mod。旗 (`FlagScene`) を立てた瞬間に PlayerCursor → PlayerAutoMove に
/// 遷移し、以降はこのフェーズの間、driver ノードの `process` redef が毎フレーム
/// `step` を呼ぶ。
///
/// 公開 API:
///   - `step`     : 1 フレーム分の自動移動を進める純粋寄りの主ロジック
///   - `cancel`   : X/Esc 押下で AutoMove を中止 (PlayerCursor に戻す + ログ)
///   - `add`      : scene tree に driver ノードを追加 (起動時に 1 度だけ)
///   - `process`  : Node[NodeTag] instance から dispatch される per-frame entry
///   - `driverPath`: driver ノードの NodePath (テストデバッグ用)
///
/// 動作モデル（FE 風 "号令"）:
///   - **1 フレームで動かすのは 1 体だけ**（並列でバラバラに進まない）
///   - 各味方は最大 `moveTiles` マスまで進んだら `waited = true` で交代
///   - 味方マスの扱いは **通常移動と同じ**: 通過可、ただし重なって停止 NG。
///     active / waited は区別せず、味方は常に「通過可能・停止不可」として扱う。
///   - 旗との Manhattan 距離が近い順に動かす（先頭から行列を詰める）
///   - 進む先は **旗への BFS 経路（味方通過可）の 1 歩目**。Manhattan ヒューリスティクスは
///     使わず、L 字 / U 字の回り込みルートも素直に追従する。
///   - **重なり停止は構造的に防ぐ**:
///       - 「踏み出すか止まるか」を `Board.isOverlappingAlly` で常時チェックし、
///         オーバーラップ中は alreadyClose / 予算切れでも `setWaited` せず必ず 1 歩進む
///       - `moveOneStep` の auto-`setWaited` は「次マスが非味方」のときだけ発火
///       - BFS 経路が詰まったときの保険として、隣接 4 マスの空きマスへ
///         横ステップする `stepOffAlly` を最終手段で使う
///
/// 停止条件:
///   - 敵検知 → 全員停止 + ログ + PlayerCursor（旗は消す）
///   - 全アクティブ味方が旗近くに集合 or 進めない → PlayerCursor（旗は消す = 集合完了 / 詰み）
///   - 全アクティブ味方が `waited` になった → `EnemyTurn` に遷移（旗は残す → 次ターンで再開）
mod AutoMoveScene {

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
        // 入力ハンドラ (`AutoMoveScene.cancel` 等) でこのフレーム中に
        // 既に他フェーズに抜けた場合は no-op で抜ける。
        if (TurnPhase.State.get() != TurnPhase.Phase.PlayerAutoMove) scene
        else match FlagScene.getTargetPos(scene) {
            case None       => exitToCursor(scene)
            case Some(flag) =>
                let board = BoardSnapshot.fromScene(scene);
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
    ///         旗への BFS 経路の `remaining` 先までに「非味方マス」が 1 つでも有る。
    def anyoneCanProgress(active: List[PlayerScene.Data],
                           flag: {x = Int32, y = Int32},
                           board: Board): Bool =
        List.exists(p -> canProgress(p, flag, board), active)

    def canProgress(p: PlayerScene.Data,
                     flag: {x = Int32, y = Int32},
                     board: Board): Bool =
        // 重なって停止できないので、オーバーラップ中は必ず「進む余地あり」扱い
        // （stepOnePlayer 側で BFS or 横ステップで必ず 1 歩動かす）
        if (Board.isOverlappingAlly(p#id, board)) true
        else if (alreadyClose(p#gridPos, flag)) false
        else
            let remaining = p#resource#moveTiles - p#moveStepsTaken;
            if (remaining <= 0) false
            else
                let allyCells = Board.allPlayerCells(board);
                match Board.bfsPathSkipAllies(board, allyCells, p#gridPos, flag) {
                    case None       => false
                    case Some(path) =>
                        List.take(remaining, path)
                            |> hasFreeStop(allyCells)
                }

    /// 旗との Manhattan 距離が近い順にソートし、先頭 1 体だけ動かす。
    /// `active` が空でないことは呼び出し側で保証されているので head は常に Some。
    def pickAndStep(active: List[PlayerScene.Data],
                     flag: {x = Int32, y = Int32},
                     board: Board,
                     scene: Scene[NodeTag]):
            Scene[NodeTag] \ Tween.Scheduler =
        let sorted = List.sortBy(p -> Weapon.manhattan(p#gridPos, flag), active);
        match List.head(sorted) {
            case None    => scene
            case Some(p) => stepOnePlayer(p, flag, board, scene)
        }

    // ────────────────────────────────────────────────────────
    // (B) 1 体ぶんの 1 歩
    // ────────────────────────────────────────────────────────

    /// この 1 体について「進める」「もう待機」のいずれか。
    /// オーバーラップ中は budget / alreadyClose に関わらず必ず 1 歩進めて非味方マスへ抜ける。
    /// それ以外は旗への BFS 経路 (味方通過可) の 1 歩目を踏み、
    /// 「`remaining` マスぶんの先頭部分に非味方が 1 つでも有る」場合のみ前進する。
    def stepOnePlayer(p: PlayerScene.Data,
                       flag: {x = Int32, y = Int32},
                       board: Board,
                       scene: Scene[NodeTag]):
            Scene[NodeTag] \ Tween.Scheduler =
        let isOverlap = Board.isOverlappingAlly(p#id, board);
        if (not isOverlap and alreadyClose(p#gridPos, flag)) finishPlayer(p#id, scene)
        else
            let remaining = p#resource#moveTiles - p#moveStepsTaken;
            if (not isOverlap and remaining <= 0) finishPlayer(p#id, scene)
            else
                let allyCells = Board.allPlayerCells(board);
                // オーバーラップ中は予算 0 でも最低 1 マスは進める
                let budget = if (isOverlap) Int32.max(remaining, 1) else remaining;
                match Board.bfsPathSkipAllies(board, allyCells, p#gridPos, flag) {
                    case None       =>
                        if (isOverlap) stepOffAlly(p, board, scene)
                        else finishPlayer(p#id, scene)
                    case Some(path) =>
                        let subpath = List.take(budget, path);
                        if (not isOverlap and not hasFreeStop(allyCells, subpath))
                            finishPlayer(p#id, scene)
                        else match List.head(subpath) {
                            case None       =>
                                if (isOverlap) stepOffAlly(p, board, scene)
                                else finishPlayer(p#id, scene)
                            case Some(next) => moveOneStep(p, next, board, scene)
                        }
                }

    /// 旗への BFS 経路から外れてでも、隣接 4 マスのうち空きマス（壁・敵・味方が居ない）
    /// に 1 マス横ステップする最終手段。重なり中で BFS 経路が詰まったときに使う。
    def stepOffAlly(p: PlayerScene.Data, board: Board, scene: Scene[NodeTag]):
            Scene[NodeTag] \ Tween.Scheduler =
        let dirs = Vec2i.up() :: Vec2i.down() :: Vec2i.left() :: Vec2i.right() :: Nil;
        let candidates = List.filterMap(d -> {
            let target = Vec2i.add(p#gridPos, d);
            if (Board.isWalkable(board, target) and not Board.isOccupied(target, board))
                Some(target) else None
        }, dirs);
        match List.head(candidates) {
            // 4 マスとも詰まっている真に動けない状態 → やむを得ず重なったまま waited
            case None       => finishPlayer(p#id, scene)
            case Some(next) => moveOneStep(p, next, board, scene)
        }

    /// `cells` に 1 つでも非味方マスがあれば true。AutoMove の budget 内で
    /// 「止まれる場所がある」ことを確認するガード。
    def hasFreeStop(allyCells: List[{x = Int32, y = Int32}],
                     cells: List[{x = Int32, y = Int32}]): Bool =
        List.exists(c -> not Board.containsCell(c, allyCells), cells)

    /// 実際に 1 マス Tween で進める。`moveStepsTaken += 1`。
    /// 上限到達したときも **次マスが非味方の場合だけ** waited にする。
    /// 味方マスに乗ったまま waited になると重なって停止してしまうため、
    /// その場合は waited を保留して次フレームの stepOnePlayer に委ねる
    /// （`isOverlappingAlly = true` 経路で必ず非味方マスへ抜ける）。
    def moveOneStep(p: PlayerScene.Data, next: {x = Int32, y = Int32},
                     board: Board, scene: Scene[NodeTag]): Scene[NodeTag] \ Tween.Scheduler =
        let moved = PlayerScene.moveToById(p#id, next, board#map, scene);
        let newSteps = p#moveStepsTaken + 1;
        let recorded = PlayerScene.setMoveStepsTaken(p#id, newSteps, moved);
        // 移動前の allyCells (= 自分の旧位置 + 他味方の位置) で next を判定。
        // p#gridPos != next（実移動なので）なので、next が allyCells に含まれる
        // = 他味方が next に居る、と判定できる。
        let allyCells = Board.allPlayerCells(board);
        let nextIsAlly = Board.containsCell(next, allyCells);
        if (newSteps >= p#resource#moveTiles and not nextIsAlly)
            PlayerScene.setWaited(p#id, recorded)
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
        Weapon.manhattan(src, flag) <= stopRadius()

    def anyTweenActive(active: List[PlayerScene.Data]): Bool \ Tween.Scheduler =
        List.exists(p -> Tween.Scheduler.isActive(PlayerScene.playerPath(p#id)), active)

    // ────────────────────────────────────────────────────────
    // (D) 終了処理
    // ────────────────────────────────────────────────────────

    /// PlayerAutoMove → PlayerCursor に戻す共通処理。
    /// `step` 内のフォールバック (旗無し / 敵検知 / 集合完了 / 詰み) からは log なしで
    /// 呼び、`cancel` (X/Esc 押下) はこれをラップしてログを足す。
    /// 旗の片付け (AutoMove の責務) と move step リセット (味方データの責務) を自分で行い、
    /// overlay / cursor の整理は `PhaseTransitions.enterPlayerCursor` に委ねる。
    def exitToCursor(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              TurnPhase.State, SelectedPlayer.State} =
        scene
            |> FlagScene.clear
            |> PlayerScene.resetAllMoveStepsTaken
            |> PhaseTransitions.enterPlayerCursor

    /// X/Esc 押下時の AutoMove キャンセル: ログ + 共通の exit 処理。
    /// `exitToCursor` との差分はログ 1 行だけなので、本体を共有する。
    /// `waited` 状態は残す (AutoMove 途中まで動いた味方は既に waited の可能性あり)。
    pub def cancel(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameLogger.GameLogger,
                              TurnPhase.State, SelectedPlayer.State} =
        GameLogger.playerLog("自動移動を中止");
        exitToCursor(scene)

    /// PlayerAutoMove → EnemyTurn（旗を残して通常のターン終了）。
    /// 全アクティブ味方が waited になった時に使う。旗は次ターン開始時に
    /// AutoMove 再開のトリガとして残す。
    def exitForTurnEnd(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger, EnemyTurn.Queue,
                              TurnPhase.State, SelectedPlayer.State} =
        SelectedPlayer.State.put(SelectedPlayer.cleared());
        EnemyTurnDriverScene.beginTurn(scene)

    // ────────────────────────────────────────────────────────
    // (E) ヘルパー
    // ────────────────────────────────────────────────────────

    /// アクティブ（waited = false）な味方一覧。
    def activePlayers(scene: Scene[NodeTag]): List[PlayerScene.Data] =
        PlayerScene.getAll(scene) |> List.filter(d -> not d#waited)

    // ────────────────────────────────────────────────────────
    // (F) scene tree 統合
    // ────────────────────────────────────────────────────────

    /// 常駐タグ専用ノードの名前。Marker2D を World 配下に置く。
    def driverName(): String = "AutoMoveDriver"
    pub def driverPath(): NodePath = MapScene.worldName() :: driverName() :: Nil

    /// scene tree に常駐ノードを追加する。`GameLifecycle.buildPlayingScene` で 1 回だけ呼ぶ。
    /// engine の `Scene.processAll` が preorder で各ノードを巡回するとき、この driver の
    /// `process` redef が phase 判定 + `step` を起動する。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] =
        let marker = Marker2D.make(Vec2.zero());
        Scene.addChild(MapScene.worldName(), driverName(),
            EngineNode.Marker2DWithState(marker, NodeTag.AutoMoveDriver), scene)

    /// per-frame entry。Game.flix の `Node[NodeTag] instance` の `process` redef から
    /// `NodeTag.AutoMoveDriver` ノードに対して dispatch される。
    /// phase=PlayerAutoMove のときだけ `step` を呼ぶ。それ以外は no-op。
    pub def process(_delta: Duration.Duration,
                     node: EngineNode[NodeTag],
                     _path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag])
                    \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                        GameLogger.GameLogger,
                        EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State} =
        let next = match TurnPhase.State.get() {
            case TurnPhase.Phase.PlayerAutoMove => step(scene)
            case _                               => scene
        };
        (node, next)
}
