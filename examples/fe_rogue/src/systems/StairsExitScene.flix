/// StairsExitScene — 集合「階段」の順次退場ドライバ
///
/// 集合(GatherMove)の隣接メニューで「階段」を選ぶと、生存味方（主人公含む）を 1 体ずつ
/// 階段へ歩かせる。残り移動で階段に届く味方は階段に乗って `useStairs` で退場し、届かない味方も
/// 残り移動の範囲で**階段にできるだけ近づいて**止まる（その場に残る）。
/// 全員退場できたら次フロアへ（`FloorAdvanceRequest`）、届かず残った味方が居ればターンエンド
/// （`ActionMenuScene.turnEndShortcut` = 敵ターンへ）。
///
/// 自走モデルは `EnemyTurnDriverScene` と同型: 専用タグノード `NodeTag.StairsExitDriver` を
/// World 配下に常駐させ、`process` redef が phase==StairsExit のとき `stepOnce` を回す。
/// 退場キュー (id, 残り移動) と停滞カウンタは driver ノードの NodeTag 状態(`Data`)に持つ。
///
/// 4 段 gating は敵ターンと同じ（バナー / Pacing / カメラ / 攻撃中）。
mod StairsExitScene {

    /// 退場進行の状態。`queue`=これから階段へ向かう (id, 残り移動歩数) 列（階段に近い順）、
    /// `idleRounds`=連続で誰も前進できなかった回数（1 巡で誰も進めなければ finalize＝無限ループ防止）。
    pub type alias Data = { queue = List[(Int32, Int32)], idleRounds = Int32 }

    /// 先頭 1 体の次手（純粋判定・テスト対象）。座標は Eq 導出のため Int32 ペアで持つ。
    pub enum StepDecision with Eq, ToString {
        case Finalize              // キュー空 → 後始末へ
        case Exit(Int32)           // 先頭 id は階段上 → 退場
        case StepTo(Int32, Int32, Int32)  // 先頭 id を (x,y) へ 1 歩（残り移動 -1）
        case Stop(Int32)           // 残り移動を使い切った → その場に残す（pop）
        case Skip(Int32)           // 前進不可（占有/壁）→ 末尾へ回してリトライ
    }

    def driverName(): String = "StairsExitDriver"
    pub def driverPath(): NodePath = MapScene.worldName() :: driverName() :: Nil

    /// 距離フィールドのフラッド上限（マップ全域を覆う。EnemyAI/Board と同値）。
    def floodSteps(): Int32 = 4096

    def initialData(): Data = {queue = Nil, idleRounds = 0}

    /// World 配下に常駐ドライバノードを追加する。`GameLifecycle.buildPlayingScene` で 1 回。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] =
        let marker = Marker2D.make(Vec2.zero());
        Scene.addChild(MapScene.worldName(), driverName(),
            EngineNode.Marker2DWithState(marker, NodeTag.StairsExitDriver(initialData())), scene)

    // ────────────────────────────────────────────────────────
    // 到達判定・キュー構築（純粋・テスト対象）
    // ────────────────────────────────────────────────────────

    /// 階段始点・味方透過（壁/敵のみ障害物）の距離フィールド。到達判定と次の 1 歩の両方に使う。
    def stairsField(board: Board, stairs: {x = Int32, y = Int32}): Map[(Int32, Int32), Int32] =
        Board.distanceField(c -> Board.isWalkable(board, c) and not Board.isEnemyAt(c, board),
                             stairs :: Nil, floodSteps())

    /// (id, 現在マス, 残り移動) のうち「残り移動以内で階段に届く」id を、
    /// 階段に近い順（同距離は id 昇順）で返す。味方は透過＝届く全員を広く拾う。
    /// 「階段」メニューを出してよいか（＝実際に降りられる味方が居るか）の判定に使う。
    pub def eligibleExiters(board: Board, stairs: {x = Int32, y = Int32},
                             units: List[(Int32, {x = Int32, y = Int32}, Int32)]): List[Int32] =
        let field = stairsField(board, stairs);
        units
            |> List.filter(u -> { let (_, pos, rem) = u; Board.fieldDist(field, pos) <= rem })
            |> List.sortBy(u -> { let (id, pos, _) = u; (Board.fieldDist(field, pos), id) })
            |> List.map(u -> { let (id, _, _) = u; id })

    /// 全味方を階段に近い順（同距離 id 昇順）に並べ (id, 残り移動) の退場キューにする。
    /// 届かない味方も含む（残り移動の範囲で階段へ近づき、使い切ったらその場で止まる）。
    pub def exitQueue(board: Board, stairs: {x = Int32, y = Int32},
                       units: List[(Int32, {x = Int32, y = Int32}, Int32)]): List[(Int32, Int32)] =
        let field = stairsField(board, stairs);
        units
            |> List.sortBy(u -> { let (id, pos, _) = u; (Board.fieldDist(field, pos), id) })
            |> List.map(u -> { let (id, _, rem) = u; (id, rem) })

    /// 先頭 1 体の次手を純粋に決める。`frontPos`/`stairs` は現在マス・階段マス、
    /// `rem` は残り移動、`nextCell` は「階段へ近づく空きマス（無ければ None）」。
    pub def decideStep(queue: List[(Int32, Int32)], frontPos: {x = Int32, y = Int32},
                        stairs: {x = Int32, y = Int32},
                        nextCell: Option[{x = Int32, y = Int32}]): StepDecision =
        match queue {
            case Nil           => StepDecision.Finalize
            case (u, rem) :: _ =>
                if (frontPos#x == stairs#x and frontPos#y == stairs#y)
                    StepDecision.Exit(u)             // 階段に到着 → 退場
                else if (rem <= 0)
                    StepDecision.Stop(u)             // 移動力切れ → その場に残す
                else match nextCell {
                    case Some(c) => StepDecision.StepTo(u, c#x, c#y)
                    case None    => StepDecision.Skip(u)
                }
        }

    // ────────────────────────────────────────────────────────
    // 開始（メニュー確定）
    // ────────────────────────────────────────────────────────

    /// 生存・非 hidden の味方を (id, 現在マス, 残り移動) で集める。
    /// 残り移動は積載ペナルティ込みの実効移動力で計算する（青マス表示と階段到達判定を揃える）。
    def livingUnits(scene: Scene[NodeTag]): List[(Int32, {x = Int32, y = Int32}, Int32)] \ World.WorldQuery =
        PlayerScene.getAllWithWorldPos(scene)
            |> List.filter(d -> d#hp > 0 and not d#hidden)
            |> List.map(d -> (d#id, d#gridPos,
                              PlayerScene.effectiveMoveTilesOf(d) - d#moveStepsTaken))

    /// 「階段」確定。降りられる味方が 1 人以上居れば、全味方を退場キューに積み StairsExit フェーズへ。
    /// 届かない味方も含めてキューに入れる（近づけるところまで近づいて止まる）。
    pub def begin(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger, GameEngine.Audio,
                              TurnPhase.State, SelectedPlayer.State, BoardQuery, World.WorldQuery} =
        // P3-a: 階段位置は World 権威（stairsPosOf）を読む（scene 直読み撤去）。
        match World.stairsPosOf(World.WorldQuery.get()) {
            case None         => scene
            case Some(stairs) =>
                // P1a: frame-head の board 読みを World 由来へ（move 前ゆえ World==scene・挙動不変）。
                let board = BoardQuery.board();
                let units = livingUnits(scene);
                // 誰も階段に届かないなら何もしない（メニューは主人公が階段の上に居るときだけ出すので通常来ない）。
                if (List.isEmpty(eligibleExiters(board, stairs, units))) scene
                else {
                    AudioStreamPlayer.play("change_floor");
                    GameLogger.playerLog("階段へ向かう");
                    SelectedPlayer.State.put(SelectedPlayer.cleared());
                    scene
                        |> setState({queue = exitQueue(board, stairs, units), idleRounds = 0})
                        |> PhaseTransitions.enterStairsExit
                }
        }

    // ────────────────────────────────────────────────────────
    // 毎フレーム進行
    // ────────────────────────────────────────────────────────

    /// F8: 階段退場 System（`Scene → Scene`）。EnemyTurnDriver と同様、OOP node callback でなく
    /// gameLoop パイプラインが明示的に呼ぶ frame-paced System。driver の `Data`（queue/idleRounds）は
    /// `driverPath()` のノード state から取り出し、`stepOnce` が `setState` で同ノードへ書き戻す
    /// （node 引数不要＝`Scene.getState` で読み、戻りは scene のみ）。phase==StairsExit のとき 1 step 進める。
    pub def step(scene: Scene[NodeTag]):
                    Scene[NodeTag]
                    \ {GameEngine.Game, Pacing.State, GameLogger.GameLogger,
                       EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                       GatherResume.State, CustomEffects.FloorAdvanceRequest, World.Command, BoardQuery,
                       World.WorldQuery} =
        match Scene.getState(driverPath(), scene) {
            case Some(NodeTag.StairsExitDriver(data)) =>
                match TurnPhase.State.get() {
                    case TurnPhase.Phase.StairsExit => stepOnce(data, scene)
                    case _                          => scene
                }
            case _ => scene
        }

    /// 先頭 1 体を 1 マス進める / 退場させる / その場に残す。敵ターンと同じ 4 段 gating。
    def stepOnce(data: Data, scene: Scene[NodeTag]): Scene[NodeTag]
            \ {GameEngine.Game, Pacing.State, GameLogger.GameLogger,
               EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
               GatherResume.State, CustomEffects.FloorAdvanceRequest, World.Command, BoardQuery,
               World.WorldQuery} =
        if (Pacing.State.isHolding()) scene
        else if (not CameraScene.isSettled(scene)) scene
        else if (World.anyEnemyAttacking(World.WorldQuery.get())) scene      // F8-slice1
        else if (World.anyPlayerAttacking(World.WorldQuery.get())) scene     // F8-slice1
        else match data#queue {
            case Nil         => finalize(scene)
            case (u, _) :: _ =>
                if (PlayerScene.isMoving(u)) scene
                else match World.stairsPosOf(World.WorldQuery.get()) {   // P3-a: World 権威
                    case None         => finalize(scene)   // 階段消失(通常来ない)→後始末
                    case Some(stairs) => advanceFront(data, stairs, scene)
                }
        }

    /// 先頭の (id, 残り移動) について次手を決めて適用する。
    def advanceFront(data: Data, stairs: {x = Int32, y = Int32},
                      scene: Scene[NodeTag]): Scene[NodeTag]
            \ {Pacing.State, GameLogger.GameLogger,
               EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
               GatherResume.State, CustomEffects.FloorAdvanceRequest,
               World.Command, World.WorldQuery, BoardQuery} =
        match data#queue {
            case Nil              => finalize(scene)
            case (u, rem) :: rest =>
                // P1a: frame-head の board 読みを World 由来へ（この frame の move 前ゆえ World==scene・挙動不変）。
                let board    = BoardQuery.board();
                // P6-2b fix: 現在位置は World.posOf（scene twin は stale）。
                let frontPos = World.posOf(World.EntityRef.Player(u), World.WorldQuery.get())
                                   |> Option.getWithDefault(PlayerScene.getGridPos(u, scene));
                let field    = stairsField(board, stairs);
                // 階段へ近づく「空きマス」へ 1 歩（占有/壁は ok で除外＝停止できないマスを避ける）。
                let nextCell = Board.stepDownhill(field, frontPos, c -> not Board.isOccupied(c, board));
                match decideStep(data#queue, frontPos, stairs, nextCell) {
                    case StepDecision.Finalize         => finalize(scene)
                    case StepDecision.Exit(id)         =>
                        // 階段に到着 → 退場。先頭を外し idleRounds リセット。
                        let exited = PlayerScene.useStairs(id, scene);
                        setState({queue = rest, idleRounds = 0}, exited)
                    case StepDecision.Stop(_)          =>
                        // 移動力を使い切った → その場に残す（先頭を外す）。
                        setState({queue = rest, idleRounds = 0}, scene)
                    case StepDecision.StepTo(id, x, y) =>
                        let moved = PlayerScene.moveToById(id, {x = x, y = y}, board#map,
                                                           PlayerScene.selectedSlideDuration(), scene);
                        Pacing.State.hold(180 |> Duration.millis);
                        // 残り移動を 1 減らして先頭継続。
                        setState({queue = (id, rem - 1) :: rest, idleRounds = 0}, moved)
                    case StepDecision.Skip(_)          =>
                        // 前進不可 → 末尾へ回してリトライ。1 巡して誰も進めなければ finalize。
                        let rotated = List.append(rest, (u, rem) :: Nil);
                        let nd: Data = {queue = rotated, idleRounds = data#idleRounds + 1};
                        if (nd#idleRounds >= List.length(rotated)) finalize(scene)
                        else setState(nd, scene)
                }
        }

    /// 全員退場できたら次フロア、残れば敵ターンへ。driver の queue は空に戻す。
    def finalize(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {GameLogger.GameLogger, EnemyTurn.Queue, TurnPhase.State,
               SelectedPlayer.State, GatherResume.State, CustomEffects.FloorAdvanceRequest,
               World.Command, World.WorldQuery} =
        let cleared = setState(initialData(), scene);
        if (PlayerScene.allLivingUsedStairs(cleared))
            CustomEffects.FloorAdvanceRequest.advance(cleared)
        else
            ActionMenuScene.turnEndShortcut(cleared)

    /// driver ノードの状態を書き換える（HoldGauge/PhaseBanner と同手法）。
    def setState(data: Data, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(driverPath(), node -> match node {
            case EngineNode.Marker2DWithState(m, NodeTag.StairsExitDriver(_)) =>
                EngineNode.Marker2DWithState(m, NodeTag.StairsExitDriver(data))
            case other => other
        }, scene)
}
