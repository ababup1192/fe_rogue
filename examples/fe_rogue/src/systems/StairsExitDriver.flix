/// StairsExitDriver — 集合「階段」の順次退場ドライバ
///
/// 集合(GatherMove)の隣接メニューで「階段」を選ぶと、生存味方（主人公含む）を 1 体ずつ
/// 階段へ歩かせる。残り移動で階段に届く味方は階段に乗って `useStairs` で退場し、届かない味方も
/// 残り移動の範囲で**階段にできるだけ近づいて**止まる（その場に残る）。
/// 全員退場できたら次フロアへ（`FloorAdvanceRequest`）、届かず残った味方が居ればターンエンド
/// （`ActionMenuUi.turnEndShortcut` = 敵ターンへ）。
///
/// 自走モデルは `EnemyTurnDriver` と同型: gameLoop のフレームパイプラインが `step` を毎フレーム
/// 1 回呼び、phase==StairsExit のとき `stepOnce` を回す。
/// 退場キュー (id, 残り移動) と停滞カウンタは `State` resource に持つ。
///
/// 4 段 gating は敵ターンと同じ（バナー / Pacing / カメラ / 攻撃中）。
mod StairsExitDriver {

    /// 退場進行の状態。`queue`=これから階段へ向かう (id, 残り移動歩数) 列（階段に近い順）、
    /// `idleRounds`=連続で誰も前進できなかった回数（1 巡で誰も進めなければ finalize＝無限ループ防止）。
    pub type alias Data = { queue = List[(Int32, Int32)], idleRounds = Int32 }

    /// 退場進行の resource。`begin` が積み、`step` が読み、`stepOnce` 系が書き戻す。
    pub eff State {
        def get(): Data
        def put(target: Data): Unit
    }

    /// 内部 Ref は closure に閉じ込め、読み書きを `State.get` / `State.put` 経由に強制する
    /// （ArrowCursorState と同じ Ref-based handler 注入パターン）。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let stateRef: Ref[Data, r] = Ref.fresh(rc, initialData());
            run {
                thunk()
            } with handler State {
                def get(k) = k(Ref.get(stateRef))
                def put(target, k) = {
                    Ref.put(target, stateRef);
                    k()
                }
            }
        }

    /// World の `stairsExit` field（単一権威）へ委譲する facade handler。`worldRef` を共有窓口として
    /// 受け取り、get/put とも World 経由で読み書きする（本番 `Game.start` 用。test は `withState`）。
    pub def withWorld(worldRef: Ref[World, r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            run {
                thunk()
            } with handler State {
                def get(k)         = k(World.stairsExitOf(Ref.get(worldRef)))
                def put(target, k) = { Ref.put(World.applyCmd(World.Cmd.SetStairsExit(target), Ref.get(worldRef)), worldRef); k() }
            }
        }

    /// 先頭 1 体の次手（純粋判定・テスト対象）。座標は Eq 導出のため Int32 ペアで持つ。
    pub enum StepDecision with Eq, ToString {
        case Finalize              // キュー空 → 後始末へ
        case Exit(Int32)           // 先頭 id は階段上 → 退場
        case StepTo(Int32, Int32, Int32)  // 先頭 id を (x,y) へ 1 歩（残り移動 -1）
        case Stop(Int32)           // 残り移動を使い切った → その場に残す（pop）
        case Skip(Int32)           // 前進不可（占有/壁）→ 末尾へ回してリトライ
    }

    /// 距離フィールドのフラッド上限（マップ全域を覆う。EnemyAI/Board と同値）。
    def floodSteps(): Int32 = 4096

    def initialData(): Data = {queue = Nil, idleRounds = 0}

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
    def livingUnits(): List[(Int32, {x = Int32, y = Int32}, Int32)] \ World.WorldQuery =
        PlayerDriver.getAll()
            |> List.filter(d -> d#hp > 0 and not d#hidden)
            |> List.map(d -> (d#id, d#gridPos,
                              PlayerDriver.effectiveMoveTilesOf(d) - d#moveStepsTaken))

    /// 「階段」確定。降りられる味方が 1 人以上居れば、全味方を退場キューに積み StairsExit フェーズへ。
    /// 届かない味方も含めてキューに入れる（近づけるところまで近づいて止まる）。
    pub def begin(): Unit \ {GameLogger.GameLogger, GameEngine.Audio,
                              TurnPhase.State, SelectedPlayer.State, BoardQuery, World.WorldQuery,
                              RangeOverlayState.State, CursorState.State, State} =
        // 階段位置は World 権威（stairsPosOf）を読む。
        match World.stairsPosOf(World.WorldQuery.get()) {
            case None         => ()
            case Some(stairs) =>
                let board = BoardQuery.board();
                let units = livingUnits();
                // 誰も階段に届かないなら何もしない（メニューは主人公が階段の上に居るときだけ出すので通常来ない）。
                if (List.isEmpty(eligibleExiters(board, stairs, units))) ()
                else {
                    AudioStreamPlayer.play("change_floor");
                    GameLogger.playerLog("階段へ向かう");
                    SelectedPlayer.State.put(SelectedPlayer.cleared());
                    State.put({queue = exitQueue(board, stairs, units), idleRounds = 0});
                    PhaseTransitions.enterStairsExit()
                }
        }

    // ────────────────────────────────────────────────────────
    // 毎フレーム進行
    // ────────────────────────────────────────────────────────

    /// 階段退場 System。EnemyTurnDriver と同様、OOP node callback でなく
    /// gameLoop パイプラインが明示的に呼ぶ frame-paced System。driver の `Data`（queue/idleRounds）は
    /// `State` resource から取り出し、`stepOnce` が `State.put` で書き戻す。
    /// phase==StairsExit のとき 1 step 進める。
    pub def step(): Unit
                    \ {GameEngine.Game, Pacing.State, GameLogger.GameLogger,
                       EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                       GatherResume.State, CustomEffects.FloorAdvanceRequest, World.Command, BoardQuery,
                       World.WorldQuery, RangeOverlayState.State, CameraState.State, State} =
        match TurnPhase.State.get() {
            case TurnPhase.Phase.StairsExit => stepOnce(State.get())
            case _                          => ()
        }

    /// 先頭 1 体を 1 マス進める / 退場させる / その場に残す。敵ターンと同じ 4 段 gating。
    def stepOnce(data: Data): Unit
            \ {GameEngine.Game, Pacing.State, GameLogger.GameLogger,
               EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
               GatherResume.State, CustomEffects.FloorAdvanceRequest, World.Command, BoardQuery,
               World.WorldQuery, RangeOverlayState.State, CameraState.State, State} =
        if (Pacing.State.isHolding()) ()
        else if (not CameraDriver.isSettled()) ()
        else if (World.anyEnemyAttacking(World.WorldQuery.get())) ()
        else if (World.anyPlayerAttacking(World.WorldQuery.get())) ()
        else match data#queue {
            case Nil         => finalize()
            case (u, _) :: _ =>
                if (PlayerDriver.isMoving(u)) ()
                else match World.stairsPosOf(World.WorldQuery.get()) {   // World 権威
                    case None         => finalize()   // 階段消失(通常来ない)→後始末
                    case Some(stairs) => advanceFront(data, stairs)
                }
        }

    /// 先頭の (id, 残り移動) について次手を決めて適用する。
    def advanceFront(data: Data, stairs: {x = Int32, y = Int32}): Unit
            \ {Pacing.State, GameLogger.GameLogger,
               EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
               GatherResume.State, CustomEffects.FloorAdvanceRequest,
               World.Command, World.WorldQuery, BoardQuery, RangeOverlayState.State, State} =
        match data#queue {
            case Nil              => finalize()
            case (u, rem) :: rest =>
                // frame-head の board 読みは World 由来（この frame の move 前の値）。
                let board    = BoardQuery.board();
                // 現在位置は World.posOf。
                let frontPos = World.posOf(World.EntityRef.Player(u), World.WorldQuery.get())
                                   |> Option.getWithDefault({x = 0, y = 0});
                let field    = stairsField(board, stairs);
                // 階段へ近づく「空きマス」へ 1 歩（占有/壁は ok で除外＝停止できないマスを避ける）。
                let nextCell = Board.stepDownhill(field, frontPos, c -> not Board.isOccupied(c, board));
                match decideStep(data#queue, frontPos, stairs, nextCell) {
                    case StepDecision.Finalize         => finalize()
                    case StepDecision.Exit(id)         =>
                        // 階段に到着 → 退場。先頭を外し idleRounds リセット。
                        PlayerDriver.useStairs(id);
                        State.put({queue = rest, idleRounds = 0})
                    case StepDecision.Stop(_)          =>
                        // 移動力を使い切った → その場に残す（先頭を外す）。
                        State.put({queue = rest, idleRounds = 0})
                    case StepDecision.StepTo(id, x, y) =>
                        PlayerDriver.moveToById(id, {x = x, y = y}, board#map,
                                               PlayerDriver.selectedSlideDuration());
                        Pacing.State.hold(180 |> Duration.millis);
                        // 残り移動を 1 減らして先頭継続。
                        State.put({queue = (id, rem - 1) :: rest, idleRounds = 0})
                    case StepDecision.Skip(_)          =>
                        // 前進不可 → 末尾へ回してリトライ。1 巡して誰も進めなければ finalize。
                        let rotated = List.append(rest, (u, rem) :: Nil);
                        let nd: Data = {queue = rotated, idleRounds = data#idleRounds + 1};
                        if (nd#idleRounds >= List.length(rotated)) finalize()
                        else State.put(nd)
                }
        }

    /// 全員退場できたら次フロア、残れば敵ターンへ。driver の queue は空に戻す。
    def finalize(): Unit
            \ {GameLogger.GameLogger, EnemyTurn.Queue, TurnPhase.State,
               SelectedPlayer.State, GatherResume.State, CustomEffects.FloorAdvanceRequest,
               World.Command, World.WorldQuery, RangeOverlayState.State, State} =
        State.put(initialData());
        if (PlayerDriver.allLivingUsedStairs())
            CustomEffects.FloorAdvanceRequest.advance()
        else
            ActionMenuUi.turnEndShortcut()
}
