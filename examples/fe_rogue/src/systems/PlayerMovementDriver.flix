/// PlayerMovementDriver — 手動プレイヤー移動の「打ち手(Mover)」
///
/// 将棋でいう打ち手。盤面(Board)を読み、入力で次の手(1 マス移動)を決め、駒(PlayerScene)へ
/// `moveToById`（座標＋見た目の適用）で反映する。**駒は Board を読まない**という分離を保つための層で、
/// 敵の `EnemyAI`/`EnemyTurnDriver` と対称。
/// 駒(PlayerScene)が Board を直接読むと、盤面の内部表現が変わるたびに駒側の修正が波及し、
/// テストや再利用も困難になる。打ち手を挟むことで Board 変更の影響範囲をこの層に限定する。
///
/// dispatch は Game.flix の `Node[NodeTag]` redef の **physicsProcess**（入力ポーリングパス）の
/// Player arm から呼ばれる（PlayerMoving=選択中プレイヤー / GatherMove=主人公 id 0 + 味方追従）。
/// 常駐ノードは持たず、既存の Player ノードに対して関数として作用する（CursorScene.physicsProcess と同様）。
/// これにより移動のフレームタイミングは従来（駒内 physicsProcess）と完全に一致する。
mod PlayerMovementDriver {

    /// PlayerMoving: 選択中プレイヤーを **移動力(MoveRange)範囲内・低速** で 1 歩動かす。
    /// 着地マスの床アイテムは重量が許す限り自動取得する（`stepFor` の着地フックが担う）ため
    /// `SelectedPlayer.State`（取得の巻き戻しドラフト）も要求する。
    pub def physicsStep(_delta: Duration.Duration, node: EngineNode[NodeTag],
                         path: NodePath, scene: Scene[NodeTag]):
                        (EngineNode[NodeTag], Scene[NodeTag])
                        \ {GameEngine.Game, BoardQuery, GameLogger.GameLogger,
                           SelectedPlayer.State, World.Command, World.WorldQuery,
                           ItemPickupPopupState.State, RangeOverlayState.State} =
        stepFor(selectAllowedPred(TurnPhase.Phase.PlayerMoving, scene),
                PlayerScene.selectedSlideDuration(), node, path, scene)

    /// GatherMove: 主人公(id 0)を移動範囲内・低速で 1 歩動かし、**主人公が動いたフレームだけ**
    /// 各味方を主人公の「移動前マス」へ最短 1 歩で追従させる（行軍）。
    /// `stepFor` は無改修で再利用し、移動成立は「移動前後の主人公グリッド座標が変わったか」で判定する
    /// （`stepFor` が着地マスを返さなくても、scene を読み直せば差分で分かる）。
    /// 主人公の Tween 完了待ち (`stepFor` 内の isMoving ガード) が 1 フレーム 1 歩のリズムを保つ。
    pub def gatherStep(_delta: Duration.Duration, node: EngineNode[NodeTag],
                        path: NodePath, scene: Scene[NodeTag]):
                       (EngineNode[NodeTag], Scene[NodeTag])
                       \ {GameEngine.Game, BoardQuery, GameLogger.GameLogger,
                          SelectedPlayer.State, World.Command, World.WorldQuery,
                          ItemPickupPopupState.State, RangeOverlayState.State} =
        let lord = PlayerScene.lordId();
        // 移動前位置は World.posOf（stepFor が emit する **前**の読み＝pre-move。scene twin は持たない）。
        let prev = World.posOf(World.EntityRef.Player(lord), World.WorldQuery.get())
                       |> Option.getWithDefault(PlayerScene.getGridPos(lord, scene));
        let (movedNode, movedScene) =
            stepFor(selectAllowedPred(TurnPhase.Phase.GatherMove, scene),
                    PlayerScene.selectedSlideDuration(), node, path, scene);
        // move 関数は scene gridPos を書かない（位置は World 権威）。
        // よって移動後の主人公位置は scene でなく **World 由来の board**（`Cmd.Move` 反映済み）から読む。
        let now = Board.playerPositions(BoardQuery.board())
            |> List.find(p -> { let (pid, _) = p; pid == lord })
            |> Option.map(p -> { let (_, pos) = p; pos })
            |> Option.getWithDefault(prev);
        if (now#x == prev#x and now#y == prev#y) (movedNode, movedScene)
        else (movedNode, followAllies(now, prev, movedScene))

    /// 主人公の移動後マス `lordNewPos` と移動前マス `goal` を使い、主人公以外の生存味方を
    /// 重なりなく最短 1 歩ずつ追従させる。次マスの決定は純粋関数 `Board.followStepsToward` に委ねる。
    ///   - 自分の移動距離(`moveTiles`)を使い切った / 集合前から待機の味方は追従しない（active=false）。
    ///   - 自発的に 1 歩追従した味方は `moveStepsTaken` を 1 消費し、上限到達で `setWaited`（非アクティブ化）。
    ///     その非アクティブ化は `GatherWaited` ドラフトに積み、集合キャンセルで再アクティブに戻せるようにする。
    ///   - 主人公に押し出された味方（着地マスに居た）はその場の入れ替えなので歩数を消費しない。
    def followAllies(lordNewPos: {x = Int32, y = Int32}, goal: {x = Int32, y = Int32},
                      scene: Scene[NodeTag]):
            Scene[NodeTag] \ {BoardQuery, SelectedPlayer.State, World.Command,
                              World.WorldQuery} =
        let board     = BoardQuery.board();
        let world     = World.WorldQuery.get();
        // 待機中(行動済み)の味方は「すれ違えない」固体障害物。すり抜け対象(allyCells)から除く。
        let waited    = waitedAllyCells(scene);
        let allyCells = Board.allPlayerCells(board)
            |> List.filter(c -> not Board.containsCell(c, waited));
        // 「このフレーム追従で動けるか」(= 非 waited & 残移動あり) は当フレームの waited を
        // 正しく見る必要がある sim 判定＝World 権威で読む。
        // 階段離脱済み(hidden)の駒は盤面から退場済み。占有・追従対象から除く
        // （board は hidden を除外済み・ここだけ含めるとゴースト駒が階段マスを塞ぐ）。
        let movers    = PlayerScene.getAllWithWorldPos(scene)
            |> List.filter(d -> d#id != PlayerScene.lordId() and d#hp > 0 and not d#hidden)
            |> List.map(d -> (d#id, d#gridPos,
                              not waitedW(d#id, d#waited, world)
                                  and d#moveStepsTaken < PlayerScene.effectiveMoveTilesOf(d)));
        Board.followStepsToward(board, allyCells, lordNewPos, goal, movers)
            |> List.foldLeft((acc, step) -> match step {
                case (_id, None, _)                => acc
                case (id, Some(target), consumes)  =>
                    let moved = PlayerScene.moveToById(id, target, board#map,
                                                       PlayerScene.selectedSlideDuration(), acc);
                    // consumes=true（自発的な追従1歩）のときだけ移動距離を消費し、上限で非アクティブ化。
                    if (consumes) consumeFollowStep(id, moved) else moved
            }, scene)

    /// 自発的追従 1 歩ぶんの後始末: `moveStepsTaken` を 1 増やし、自分の `moveTiles` に達したら
    /// 非アクティブ化（`setWaited`）して、巻き戻し用の `GatherWaited` ドラフトを積む。
    def consumeFollowStep(id: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {SelectedPlayer.State, World.Command} =
        match PlayerScene.get(id, scene) {
            case None    => scene
            case Some(d) =>
                let used      = d#moveStepsTaken + 1;
                let withSteps = PlayerScene.setMoveStepsTaken(id, used, scene);
                if (used >= PlayerScene.effectiveMoveTilesOf(d)) {
                    SelectedPlayer.pushDraft(MoveDraft.DraftAction.GatherWaited(id));
                    PlayerScene.setWaited(id, withSteps)
                } else withSteps
        }

    /// フェーズ別の「進入可否」述語。将来の移動制限（床限定・特定敵回避 等）はここに足す。
    /// physicsStep/gatherStep は共通 stepFor に述語を渡す構造のため、フェーズ固有の制限を
    /// 呼び出し元ごとに重複して書かずに済む。driver にハードコードせず関数化することで拡張にも開く。
    def selectAllowedPred(phase: TurnPhase.Phase,
                           scene: Scene[NodeTag]): ({x = Int32, y = Int32} -> Bool) \ {World.WorldQuery, RangeOverlayState.State} =
        // 移動範囲のメンバーシップは範囲 resource から 1 度だけ読んで、純粋な述語に閉じ込める
        // （`stepFor` は純粋述語 `{x,y} -> Bool` を取る＝毎セル resource を触らせない）。
        let reach = MoveRangeScene.reachable(scene);
        let inReach = cell -> List.exists(c -> c#x == cell#x and c#y == cell#y, reach);
        match phase {
            case TurnPhase.Phase.PlayerMoving => inReach
            // 集合: 主人公は集合開始位置を原点に固定した移動範囲(青マス)内だけ動ける。
            // 待機中(行動済み)の味方マスへは進めない（すれ違い不可。＝押し出しも起きない）。
            case TurnPhase.Phase.GatherMove   =>
                let waited = waitedAllyCells(scene);
                cell -> inReach(cell) and not Board.containsCell(cell, waited)
            case _                            => _ -> true
        }

    /// 味方の waited を **World 権威**で読む sim seam。当フレームの
    /// waited は World（Cmd.SetWaited 反映済み）から読む。未登録は scene 値へ fallback。
    def waitedW(id: Int32, fallback: Bool, world: World): Bool =
        World.waitedOf(World.EntityRef.Player(id), world) |> Option.getWithDefault(fallback)

    /// 待機中(行動済み)かつ生存している味方のグリッドマス一覧。集合の「すれ違えない障害物」。
    /// waited は World 権威で読む（this-frame の集合移動判定＝sim）。
    def waitedAllyCells(scene: Scene[NodeTag]): List[{x = Int32, y = Int32}] \ World.WorldQuery =
        let world = World.WorldQuery.get();
        // 階段離脱済み(hidden)の駒は盤面から退場済みなので障害物に数えない
        // （board は hidden を除外済み・含めると離脱者の階段マスに集合で重なれなくなる）。
        PlayerScene.getAllWithWorldPos(scene)
            |> List.filter(d -> waitedW(d#id, d#waited, world) and d#hp > 0 and not d#hidden)
            |> List.map(d -> d#gridPos)

    /// 手動移動の共通本体。`isMoving` ガード → 入力 → Board 判定 → 駒へ `moveToById` で適用。
    /// 移動後のノードは scene から取り直して返す（engine の physicsProcess 契約: 返した node が
    /// path へ書き戻される。`moveToById` が既に scene を更新しているので最新ノードを返す）。
    def stepFor(allowedPred: {x = Int32, y = Int32} -> Bool,
                 slide: Duration.Duration, node: EngineNode[NodeTag],
                 path: NodePath, scene: Scene[NodeTag]):
                (EngineNode[NodeTag], Scene[NodeTag])
                \ {GameEngine.Game, BoardQuery, World.WorldQuery, GameLogger.GameLogger,
                   SelectedPlayer.State, World.Command, ItemPickupPopupState.State} =
        match node {
            case EngineNode.Marker2DWithState(_, NodeTag.Player(data)) =>
                // かなしばり（完全停止）中は移動入力を捨てる。攻撃も ActionMenu 側で封じる。
                if (StatusSystem.isImmobilized(data#statuses)) (node, scene)
                // Tween 中（前の 1 マスがまだ滑走中）は入力を捨てる。1 回だけ評価する。
                else if (PlayerScene.isMoving(data#id)) (node, scene)
                else
                    let board = BoardQuery.board();
                    // 入力(view)→System(sim)→event→replay(view) の seam。
                    //   VIEW: 押下方向を MoveIntent(dir) に写す（readHeldDirection）。
                    //   SYSTEM: stepPlayerMove が合法判定（壁/範囲/敵占有）→World に Cmd.Move→Moved を返す。
                    //   VIEW: replayMovedEvent が Moved を Tween/anim 再生し、着地マスを自動取得。
                    // 同 dispatch 内で emit→replay ゆえ timing は 1 フレームに収まる。
                    // 移動の起点は World.posOf（Cmd.Move の emit **前**＝pre-move）。
                    // ノード Data の gridPos は twin を持たず（位置は World 権威）更新されないため、
                    // これを起点に使うと「古い位置＋方向」へ Move が飛び斜め移動に見えるバグになる。
                    let origin = World.posOf(World.EntityRef.Player(data#id), World.WorldQuery.get())
                                     |> Option.getWithDefault(data#gridPos);
                    let outcome = forM (
                        dir   <- readHeldDirection();
                        event <- stepPlayerMove(data#id, origin, dir, board, allowedPred)
                    ) yield event;
                    match outcome {
                        case None        => (node, scene)
                        case Some(event) =>
                            // INVARIANT: movedTarget / replayMovedEvent は move-seam 専用＝Moved 以外を渡すと
                            // bug! で落ちる（no-op ではない）。ここは stepPlayerMove が常に Moved を返すので安全。
                            // combat SimEvent をここへ配線するなら、その event は必ず Moved に pre-filter してから渡すこと。
                            let target   = PlayerScene.movedTarget(event);
                            let replayed = PlayerScene.replayMovedEvent(event, board#map, slide, scene);
                            returnNode(node, path, autoPickupOrLog(data, target, replayed))
                    }
            case _ => (node, scene)
        }

    /// SYSTEM(sim): 選択中プレイヤーの 1 歩を判定し、合法なら World に位置を書いて `Moved` を返す。
    /// 合法性は board（壁/MoveRange/敵占有）の純粋判定（`Board.tryMoveWithRange`）。`allowed` は
    /// フェーズ固有の範囲制限（physicsStep は MoveRange、gatherStep は集合範囲）。
    /// gridPos は World 権威＝ここでは scene を触らない。
    /// 返り値 `Moved` を VIEW（`PlayerScene.replayMovedEvent`）が Tween/anim 再生する。
    pub def stepPlayerMove(id: Int32, fromPos: {x = Int32, y = Int32},
                            dir: {x = Int32, y = Int32}, board: Board,
                            allowed: {x = Int32, y = Int32} -> Bool):
            Option[World.SimEvent] \ World.Command =
        forM (target <- Board.tryMoveWithRange(board, fromPos, dir, allowed))
            yield {
                World.Command.emit(World.Cmd.Move(World.EntityRef.Player(id), target));
                World.SimEvent.Moved(World.EntityRef.Player(id), target)
            }

    /// 着地したマスに床アイテムがあれば、**重量が許す限り自動で拾う**（基本拾う仕様）。
    /// 取得は移動キャンセル(`cancelSelection`)で巻き戻せるよう `PickedUp` ドラフトに積む
    /// （`PlayerScene.pickupFloorItem` に集約。手動「ひろう」と同じ取得経路）。
    /// 拾うと積載過多（Immobile=移動不可）になるアイテムは拾わず、「○○の上に乗った」だけ
    /// 記録して床に残す（重さで詰むのを防ぐ。降ろすか軽くしてから手動「ひろう」で取れる）。
    /// 重量判定は移動前スナップショット `data` で行う。取得で在庫は増えるが、`stepFor` が
    /// フレーム毎に Player ノードを読み直し 1 フレーム 1 歩（isMoving/Tween ガード）なので、
    /// 取得後の積載は必ず次の歩に反映される＝同一マスでの二重取得や過多の取りこぼしは起きない。
    /// pub: 着地時の自動取得/非取得の判定を `TestActionMenuScene` から直接観測するため。
    pub def autoPickupOrLog(data: PlayerScene.Data, target: {x = Int32, y = Int32},
                             scene: Scene[NodeTag]):
            Scene[NodeTag] \ {SelectedPlayer.State, GameLogger.GameLogger, World.Command,
                              ItemPickupPopupState.State, World.WorldQuery} =
        // 床アイテムは World store から読む。
        match World.groundItemAtOf(target, World.WorldQuery.get()) |> Option.map(d -> d#item) {
            case None            => scene
            case Some(kind) =>
                if (PlayerScene.wouldOverloadByPicking(data, kind)) {
                    GameLogger.playerLog(
                        "${data#resource#description}は ${GroundItems.kindDisplayName(kind)}の上に乗った");
                    scene
                } else
                    // 取得音(get_item)を予約（process が次フレームに鳴らす。physicsProcess に
                    // GameEngine.Audio は無いため、純粋な予約で process 側へ委ねる）。
                    PlayerScene.pickupFloorItem(data#id, target, scene)
                        |> ItemPickupPopupUi.reserveGetItemSound
        }

    /// engine の physicsProcess 契約に合わせ、scene を更新したあとの最新ノードを取り直して返す。
    def returnNode(fallback: EngineNode[NodeTag], path: NodePath,
                    scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) =
        match Scene.getEngineNode(path, scene) {
            case Some(latest) => (latest, scene)
            case None         => (fallback, scene)
        }

    /// 押されている方向キーを Option で返す（複数同時押しは上 > 下 > 左 > 右）。
    /// 優先順序は特定のゲームデザイン意図によるものではなく、コード記述順による任意の一貫した順序。
    /// 入力ポーリングは打ち手の責務。ここ 1 箇所に集約し PlayerScene からは削除した。
    def readHeldDirection(): Option[{x = Int32, y = Int32}] \ GameEngine.Game =
        let isDown = key -> GameEngine.Game.isKeyPressed(key);
        if      (isDown(GameEngine.Key.W) or isDown(GameEngine.Key.Up))    Some(Vec2i.up())
        else if (isDown(GameEngine.Key.S) or isDown(GameEngine.Key.Down))  Some(Vec2i.down())
        else if (isDown(GameEngine.Key.A) or isDown(GameEngine.Key.Left))  Some(Vec2i.left())
        else if (isDown(GameEngine.Key.D) or isDown(GameEngine.Key.Right)) Some(Vec2i.right())
        else None
}
