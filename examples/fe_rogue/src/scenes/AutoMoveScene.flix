/// AutoMoveScene — ローグ移動モードの駆動（合流アニメ + 自由歩行の判定 + 解散）
///
/// `NodeTag.AutoMoveDriver` を持つ scene tree 常駐ノードと、それを駆動する step ロジックを
/// 同居させた scene mod。「しゅうごう」確定で PlayerAutoMove フェーズに入り、driver ノードの
/// `process` redef が毎フレーム phase を見て:
///   - `PlayerAutoMove` → `gatherStep`（合流アニメ）
///   - `RogueMove`      → `roamJudge`（敵範囲入りの監視 → 自動解散）
///
/// 公開 API:
///   - `process`        : Node[NodeTag] instance から dispatch される per-frame entry
///   - `cancel`         : 合流中の X/Esc で中止（= 解散）
///   - `disband`        : 隊列を解散して通常ターン制(PlayerCursor)に戻す（かいさん / 自動解除）
///   - `lordThreatened` : ロードが敵の移動到達範囲(赤マス)に入っているか（純粋判定）
///   - `add` / `driverPath` : 常駐 driver ノードの追加 / パス
///
/// 合流の動作モデル:
///   - **1 フレームで動かすのは 1 体だけ**（`anyTweenActive` で補間中は待つ）
///   - ロード(id 0)以外の表示中の味方を、ロード位置への BFS 経路（味方通過可）の 1 歩目で寄せる
///   - ロードに重なった味方はその次フレームで非表示(`setHidden`)にして退避（合流）
///   - 全員合流したら `RogueMove`（自由歩行）へ
///
/// 解散の動作モデル:
///   - 退避中の味方をロード周囲の空き床マス(`pickRespawnCells`)に snap して再表示
///   - 通常ターン制(PlayerCursor)に戻し、カーソルをロードに出す
mod AutoMoveScene {

    /// ロードとして扱うパーティ id。
    def lordId(): Int32 = 0

    // ────────────────────────────────────────────────────────
    // (A) per-frame entry
    // ────────────────────────────────────────────────────────

    /// Game.flix の `Node[NodeTag] instance` の `process` redef から `NodeTag.AutoMoveDriver`
    /// ノードに対して dispatch される。phase で合流 / 自由歩行判定に振り分ける。
    pub def process(_delta: Duration.Duration,
                     node: EngineNode[NodeTag],
                     _path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag])
                    \ {GameLogger.GameLogger, Tween.Scheduler,
                        AnimationPlayer.Scheduler, TurnPhase.State,
                        GameEngine.Game, GameEngine.Audio, Pacing.State} =
        let next = match TurnPhase.State.get() {
            case TurnPhase.Phase.PlayerAutoMove => gatherStep(scene)
            case TurnPhase.Phase.RogueMove      => roamJudge(scene)
            case TurnPhase.Phase.RogueAlert     => alertStep(scene)
            case _                               => scene
        };
        (node, next)

    // ────────────────────────────────────────────────────────
    // (B) 合流 (PlayerAutoMove)
    // ────────────────────────────────────────────────────────

    /// 合流の 1 フレーム分。1 フレーム 1 操作（1 歩 or 1 体の非表示化）。
    def gatherStep(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, TurnPhase.State} =
        // 入力ハンドラ等でこのフレーム中に既に他フェーズへ抜けたら no-op。
        if (TurnPhase.State.get() != TurnPhase.Phase.PlayerAutoMove) scene
        else
            let lordPos = PlayerScene.getGridPos(lordId(), scene);
            let movers  = PlayerScene.mergeableAllies(scene);
            if (List.isEmpty(movers))
                // 全員合流完了 → 1 キャラ自由歩行へ
                PhaseTransitions.enterRogueMove(scene)
            else if (anyTweenActive(movers)) scene
            else
                // ロードに重なった者が居れば、まずそれを非表示にして退避（重なり→次フレで消す）
                match List.find(p -> samePos(p#gridPos, lordPos), movers) {
                    case Some(p) => PlayerScene.setHidden(p#id, true, scene)
                    case None    => stepOneToward(lordPos, movers, scene)
                }

    /// ロードに最も近い 1 体を、ロード位置への BFS 経路の 1 歩目へ進める。
    /// 経路が無い（壁・敵で詰み）場合はその場で非表示にして合流完了に近づける。
    def stepOneToward(lordPos: {x = Int32, y = Int32},
                       movers: List[PlayerScene.Data],
                       scene: Scene[NodeTag]):
            Scene[NodeTag] \ Tween.Scheduler =
        match PlayerScene.nearestMover(lordPos, movers) {
            case None    => scene
            case Some(p) =>
                let board     = BoardSnapshot.fromScene(scene);
                let allyCells = Board.allPlayerCells(board);
                match Board.bfsPathSkipAllies(board, allyCells, p#gridPos, lordPos) {
                    case Some(next :: _) =>
                        PlayerScene.moveToById(p#id, next, board#map, scene)
                    case _               =>
                        PlayerScene.setHidden(p#id, true, scene)
                }
        }

    /// 合流対象に Tween 中の味方が 1 人でも居るか（補間完了を待つガード）。
    def anyTweenActive(movers: List[PlayerScene.Data]): Bool \ Tween.Scheduler =
        List.exists(p -> PlayerScene.isMoving(p#id), movers)

    // ────────────────────────────────────────────────────────
    // (C) 自由歩行の監視 (RogueMove)
    // ────────────────────────────────────────────────────────

    /// 自由歩行中、ロードが敵に検知された(同じ部屋 or 索敵範囲内)瞬間に発見演出へ入る。
    /// 歩行 Tween 中（移動成立フレーム）は判定を 1 フレーム遅らせて、gridPos 確定後に見る。
    def roamJudge(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameEngine.Game, GameEngine.Audio, Tween.Scheduler,
                              Pacing.State, TurnPhase.State} =
        if (TurnPhase.State.get() != TurnPhase.Phase.RogueMove) scene
        else if (PlayerScene.isMoving(lordId())) scene
        else if (lordDetected(scene)) triggerAlert(scene)
        else scene

    /// 発見演出フェーズ(RogueAlert)の進行。hold 中はカメラ・「！」を見せて待ち、
    /// hold が抜けたら隊列を解散して通常ターン制に戻る。
    def alertStep(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger, Tween.Scheduler,
                              AnimationPlayer.Scheduler, TurnPhase.State, Pacing.State} =
        if (TurnPhase.State.get() != TurnPhase.Phase.RogueAlert) scene
        else if (Pacing.State.isHolding()) scene
        else disband("敵に見つかった", scene)

    // ────────────────────────────────────────────────────────
    // (D) 敵検知（純粋）と発見演出
    // ────────────────────────────────────────────────────────

    /// ロードが生存敵に検知されるか（同じ部屋 or 索敵範囲(移動到達範囲)内）。
    /// `Board.cellDetectedByEnemy` に委譲する純粋判定。
    /// 「しゅうごう」をメニューに出す条件 / 自由歩行中の発見判定の両方で使う。
    pub def lordDetected(scene: Scene[NodeTag]): Bool =
        let board   = BoardSnapshot.fromScene(scene);
        let enemies = EnemyScene.getAll(scene)
            |> List.map(e -> {gridPos = e#gridPos, moveTiles = e#moveTiles,
                              isDying = e#isDying});
        let lordPos = PlayerScene.getGridPos(lordId(), scene);
        Board.cellDetectedByEnemy(board#map#moduleOfCell, board#map#isFloor,
                                   enemies, lordPos)

    /// 「！」を出す対象の敵と、カメラの焦点(ワールド座標)をまとめて返す純粋関数。
    ///   - ロードが敵の居る部屋に居る → 対象 = その部屋の全生存敵 / 焦点 = 部屋の中心
    ///   - そうでなく索敵範囲で見つかった → 対象 = ロードを範囲に収める生存敵 / 焦点 = その先頭の敵
    /// 「！」表示(`triggerAlert`)とカメラ注視(`CameraScene`)が同じ判断を共有するための単一窓口。
    pub def alertInfo(scene: Scene[NodeTag]):
            {enemies = List[EnemyScene.Data], focus = Vec2.Vec2} =
        let board      = BoardSnapshot.fromScene(scene);
        let placements = MapScene.getPlacements(scene);
        let lordPos    = PlayerScene.getGridPos(lordId(), scene);
        let alive      = EnemyScene.getAll(scene) |> List.filter(e -> not e#isDying);
        let lordMod    = board#map#moduleOfCell(lordPos);
        let inRoom     = match lordMod {
            case Some(m) => alive |> List.filter(e -> board#map#moduleOfCell(e#gridPos) == Some(m))
            case None    => Nil
        };
        if (not List.isEmpty(inRoom)) {
            let centerCell = match lordMod {
                case Some(m) => MapScene.moduleCenter(m, placements)
                                    |> Option.getWithDefault(lordPos)
                case None    => lordPos
            };
            {enemies = inRoom, focus = board#map#gridToWorld(centerCell)}
        } else {
            let detectors = alive |> List.filter(e ->
                Board.containsCell(lordPos,
                    Board.reachableCells(board#map#isFloor, e#gridPos, e#moveTiles)));
            let focus = match List.head(detectors) {
                case Some(e) => board#map#gridToWorld(e#gridPos)
                case None    => board#map#gridToWorld(lordPos)
            };
            {enemies = detectors, focus = focus}
        }

    /// 「！」を対象の敵の上に出し、find SE を鳴らし、hold をセットして RogueAlert へ入る。
    def triggerAlert(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameEngine.Game, GameEngine.Audio,
                              Pacing.State, TurnPhase.State} =
        let info  = alertInfo(scene);
        let board = BoardSnapshot.fromScene(scene);
        let withMarks = List.foldLeft((sc, e) ->
            DamagePopupScene.emitText(board#map#gridToWorld(e#gridPos), "！",
                                       exclaimColor(), sc),
            scene, info#enemies);
        AudioStreamPlayer.play("find");
        Pacing.State.hold(alertHold());
        PhaseTransitions.enterRogueAlert(withMarks)

    /// 「！」の色（黄色）。
    def exclaimColor(): Color = {r = 1.0f32, g = 0.9f32, b = 0.2f32}

    /// 発見演出の hold 時間。DamagePopupScene の寿命(700ms)に合わせ、「！」が出ている間
    /// カメラを焦点に留めてから解散する。
    def alertHold(): Duration.Duration = Duration.millis(700)

    // ────────────────────────────────────────────────────────
    // (E) 解散（かいさん / 自動解除 / 合流中止）
    // ────────────────────────────────────────────────────────

    /// 退避中の味方をロードから歩いて分かれる演出で再出現させ、通常ターン制(PlayerCursor)に戻す。
    /// `msg` だけが「かいさん」「敵の部屋に入った」「中止」で異なる。持ち物・HP は Data に残るので保持される。
    pub def disband(msg: String, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger, Tween.Scheduler,
                              AnimationPlayer.Scheduler, TurnPhase.State} =
        GameLogger.playerLog(msg);
        let lordPos = PlayerScene.getGridPos(lordId(), scene);
        let hidden  = PlayerScene.hiddenAllies(scene);
        let board   = BoardSnapshot.fromScene(scene);
        let cells   = PlayerScene.pickRespawnCells(lordPos, List.length(hidden), board);
        let placed  = emergeAll(hidden, cells, lordPos, board#map, scene);
        PhaseTransitions.enterPlayerCursorAt(lordPos, placed)

    /// 退避中の味方を 1 体ずつ「ロード位置から再表示 → 各セルへ歩いて移動」で分かれさせる。
    /// snapTo でロードに重ねてから setHidden(false) で見せ、moveToById で 1 マス先へ Tween。
    /// これで「急に出現」ではなく「ロードから別れ出る」見た目になる(合流の逆再生)。
    def emergeAll(hidden: List[PlayerScene.Data],
                   cells: List[{x = Int32, y = Int32}],
                   lordPos: {x = Int32, y = Int32},
                   map: MapSnapshot,
                   scene: Scene[NodeTag]): Scene[NodeTag] \ Tween.Scheduler =
        List.foldLeft((sc, pair) -> {
            let (d, cell) = pair;
            sc
                |> PlayerScene.snapTo(d#id, lordPos)
                |> PlayerScene.setHidden(d#id, false)
                |> PlayerScene.moveToById(d#id, cell, map)
        }, scene, List.zip(hidden, cells))

    /// 合流中の X/Esc キャンセル: 解散して PlayerCursor に戻す。
    pub def cancel(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger, Tween.Scheduler,
                              AnimationPlayer.Scheduler, TurnPhase.State} =
        disband("自動移動を中止", scene)

    // ────────────────────────────────────────────────────────
    // (F) ヘルパー
    // ────────────────────────────────────────────────────────

    def samePos(a: {x = Int32, y = Int32}, b: {x = Int32, y = Int32}): Bool =
        a#x == b#x and a#y == b#y

    // ────────────────────────────────────────────────────────
    // (G) scene tree 統合
    // ────────────────────────────────────────────────────────

    /// 常駐タグ専用ノードの名前。Marker2D を World 配下に置く。
    def driverName(): String = "AutoMoveDriver"
    pub def driverPath(): NodePath = MapScene.worldName() :: driverName() :: Nil

    /// scene tree に常駐ノードを追加する。`GameLifecycle.buildPlayingScene` で 1 回だけ呼ぶ。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] =
        let marker = Marker2D.make(Vec2.zero());
        Scene.addChild(MapScene.worldName(), driverName(),
            EngineNode.Marker2DWithState(marker, NodeTag.AutoMoveDriver), scene)
}
