/// AutoMove — PlayerAutoMove フェーズで毎フレーム呼ばれる「自動移動の 1 step」ロジック
///
/// 旗 (`FlagScene`) を立てた瞬間に PlayerCursor → PlayerAutoMove に遷移し、以降は
/// このフェーズの間、`Game.gameLoop` が毎フレーム `AutoMove.step` を呼ぶ。
/// アクティブ（`waited = false`）な味方 1 体ごとに、敵の chase と同じ要領で BFS で
/// 旗への 1 歩目を計算し Tween で 1 マスだけ進める。Tween 中は次の step を見送る。
///
/// 停止条件:
///   - 敵検知（`alerted` と同じロジック: アクティブ味方と alive 敵が同モジュール）
///     → 全員停止 + ログ「敵に発見された」
///   - 全アクティブ味方が「旗の BFS 距離 ≤ 2 マス」または「経路無し」になる
///     → 全員到達済み扱いで終了
///
/// 終了処理（`exitToCursor`）:
///   - PlayerCursor に戻す + 旗を消す + カーソル復活 + 選択中味方位置にスナップ
///   - **moveTiles は変更しない**（移動力は不変。FE の通常移動と独立した「号令」扱い）
mod AutoMove {

    /// 旗から見て「停止距離」と判定するマス数（BFS 距離）。
    /// FE で言うなら「周囲 2 マス以内に入ったらそこで止まる」感覚。
    def stopRadius(): Int32 = 2

    // ────────────────────────────────────────────────────────
    // (A) 公開: 1 フレーム分の進行
    // ────────────────────────────────────────────────────────

    /// PlayerAutoMove フェーズ中に毎フレーム呼ぶ。`Game.gameLoop` のパイプライン要素。
    /// 旗が立っていない / アクティブ味方が居ない場合は防御的に PlayerCursor に戻す。
    pub def step(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {Tween.Scheduler, GameLogger.GameLogger,
                TurnPhase.State, SelectedPlayer.State} =
        match FlagScene.getTargetPos(scene) {
            case None       => exitToCursor(scene)   // 旗無し（防御的）
            case Some(flag) =>
                let board = Game.buildBoard(scene);
                if (anyEnemyDetected(scene, board)) {
                    GameLogger.playerLog("敵に発見された");
                    exitToCursor(scene)
                }
                else {
                    let active = activePlayers(scene);
                    let stepped = List.foldLeft(
                        (sc, p) -> stepOnePlayer(p#id, flag, sc),
                        scene, active);
                    if (allSettled(stepped, flag))
                        exitToCursor(stepped)
                    else stepped
                }
        }

    // ────────────────────────────────────────────────────────
    // (B) 1 体ぶんの 1 歩
    // ────────────────────────────────────────────────────────

    /// 味方 1 体を 1 マスだけ旗に近づける。Tween 中なら何もしない。
    /// 旗の BFS 距離 ≤ stopRadius() に達していれば動かない。
    /// 経路が無ければ動かない（settled 扱い）。
    def stepOnePlayer(id: Int32, flag: Vec2.Vec2i,
                       scene: Scene[NodeTag]): Scene[NodeTag] \ Tween.Scheduler =
        if (PlayerScene.isMoving(id)) scene
        else
            match PlayerScene.get(id, scene) {
                case None    => scene
                case Some(p) =>
                    if (alreadyClose(p#gridPos, flag)) scene
                    else
                        // 都度フレッシュな board で BFS する（直前の味方の移動を反映）。
                        let board = Game.buildBoard(scene);
                        match Board.bfsPath(board, p#gridPos, flag) {
                            case None       => scene   // 経路なし
                            case Some(path) =>
                                if (List.length(path) <= stopRadius()) scene
                                else
                                    match List.head(path) {
                                        case None       => scene
                                        case Some(next) =>
                                            PlayerScene.moveToById(id, next,
                                                                    board#map, scene)
                                    }
                        }
            }

    // ────────────────────────────────────────────────────────
    // (C) 停止判定
    // ────────────────────────────────────────────────────────

    /// アクティブな味方と「生きている」敵が同じモジュール idx に居るか。
    /// `EnemyAI.sameModuleAsAnyPlayer` と同じ条件を AutoMove 側からも使うため、
    /// 直接 EnemyScene / PlayerScene を見て判定する（dying は除外）。
    def anyEnemyDetected(scene: Scene[NodeTag], board: Board): Bool =
        let aliveEnemies = EnemyScene.getAll(scene)
            |> List.filter(d -> Option.isEmpty(d#dying));
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

    /// 全アクティブ味方が「旗の周囲 ≤ stopRadius」 or 「経路なし」かつ Tween も無し。
    /// True なら exitToCursor を発火する。
    def allSettled(scene: Scene[NodeTag], flag: Vec2.Vec2i): Bool \ Tween.Scheduler =
        let active = activePlayers(scene);
        if (List.isEmpty(active)) true
        else
            let board = Game.buildBoard(scene);
            List.forAll(p ->
                not Tween.Scheduler.isActive(PlayerScene.playerPath(p#id))
                and isSettledFor(board, p#gridPos, flag),
                active)

    /// 個別判定: 旗から見て近い or 経路なしなら settled。
    def isSettledFor(board: Board, src: Vec2.Vec2i, flag: Vec2.Vec2i): Bool =
        if (alreadyClose(src, flag)) true
        else
            match Board.bfsPath(board, src, flag) {
                case None       => true   // 経路なし → これ以上進めない
                case Some(path) => List.length(path) <= stopRadius()
            }

    /// 旗との Manhattan 距離が ≤ stopRadius なら「もう近い」扱い。
    /// BFS 距離 ≥ Manhattan のため、Manhattan で先に弾けば BFS を省略できる。
    def alreadyClose(src: Vec2.Vec2i, flag: Vec2.Vec2i): Bool =
        let dx = Int32.abs(src#x - flag#x);
        let dy = Int32.abs(src#y - flag#y);
        dx + dy <= stopRadius()

    // ────────────────────────────────────────────────────────
    // (D) 終了処理
    // ────────────────────────────────────────────────────────

    /// PlayerAutoMove → PlayerCursor に戻す共通処理。
    /// 旗を消し、カーソルを再表示、選択中（or アクティブ先頭）の味方にスナップする。
    def exitToCursor(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, TurnPhase.State,
                              SelectedPlayer.State} =
        TurnPhase.State.put(TurnPhase.Phase.PlayerCursor);
        scene
            |> FlagScene.clear
            |> CursorScene.setVisible(true)
            |> CursorScene.snapToPlayer

    // ────────────────────────────────────────────────────────
    // (E) ヘルパー
    // ────────────────────────────────────────────────────────

    /// アクティブ（waited = false）な味方一覧。
    def activePlayers(scene: Scene[NodeTag]): List[PlayerScene.Data] =
        PlayerScene.getAll(scene) |> List.filter(d -> not d#waited)
}
