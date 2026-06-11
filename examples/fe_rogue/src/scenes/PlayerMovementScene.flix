/// PlayerMovementScene — 手動プレイヤー移動の「打ち手(Mover)」
///
/// 将棋でいう打ち手。盤面(Board)を読み、入力で次の手(1 マス移動)を決め、駒(PlayerScene)へ
/// `moveToById`（座標＋見た目の適用）で反映する。**駒は Board を読まない**という分離を保つための層で、
/// 敵の `EnemyAI`/`EnemyTurnDriverScene`、ローグ合流の `AutoMoveScene` と対称。
///
/// dispatch は Game.flix の `Node[NodeTag]` redef の **physicsProcess**（入力ポーリングパス）の
/// Player arm から呼ばれる（PlayerMoving=選択中プレイヤー / RogueMove=ロード id 0）。
/// 常駐ノードは持たず、既存の Player ノードに対して関数として作用する（CursorScene.physicsProcess と同様）。
/// これにより移動のフレームタイミングは従来（駒内 physicsProcess）と完全に一致する。
mod PlayerMovementScene {

    /// PlayerMoving: 選択中プレイヤーを **移動力(MoveRange)範囲内・低速** で 1 歩動かす。
    pub def physicsStep(_delta: Duration.Duration, node: EngineNode[NodeTag],
                         path: NodePath, scene: Scene[NodeTag]):
                        (EngineNode[NodeTag], Scene[NodeTag])
                        \ {GameEngine.Game, BoardQuery, Tween.Scheduler} =
        stepFor(selectAllowedPred(TurnPhase.Phase.PlayerMoving, scene),
                PlayerScene.selectedSlideDuration(), node, path, scene)

    /// RogueMove: ロード(id 0)を **制限なし・通常速** で自由歩行させる。
    /// 敵検知での自動解散判定は driver(`AutoMoveScene.roamJudge`)が別途行う（従来どおりの共存）。
    pub def roamStep(_delta: Duration.Duration, node: EngineNode[NodeTag],
                      path: NodePath, scene: Scene[NodeTag]):
                     (EngineNode[NodeTag], Scene[NodeTag])
                     \ {GameEngine.Game, BoardQuery, Tween.Scheduler} =
        stepFor(selectAllowedPred(TurnPhase.Phase.RogueMove, scene),
                PlayerScene.slideDuration(), node, path, scene)

    /// フェーズ別の「進入可否」述語。将来の移動制限（床限定・特定敵回避 等）はここに足す。
    /// driver にハードコードせず関数化しておくことで拡張に開く。
    def selectAllowedPred(phase: TurnPhase.Phase,
                           scene: Scene[NodeTag]): {x = Int32, y = Int32} -> Bool =
        match phase {
            case TurnPhase.Phase.PlayerMoving => c -> MoveRangeScene.isInRange(c, scene)
            case _                            => _ -> true
        }

    /// 手動移動の共通本体。`isMoving` ガード → 入力 → Board 判定 → 駒へ `moveToById` で適用。
    /// 移動後のノードは scene から取り直して返す（engine の physicsProcess 契約: 返した node が
    /// path へ書き戻される。`moveToById` が既に scene を更新しているので最新ノードを返す）。
    def stepFor(allowedPred: {x = Int32, y = Int32} -> Bool,
                 slide: Duration.Duration, node: EngineNode[NodeTag],
                 path: NodePath, scene: Scene[NodeTag]):
                (EngineNode[NodeTag], Scene[NodeTag])
                \ {GameEngine.Game, BoardQuery, Tween.Scheduler} =
        match node {
            case EngineNode.Marker2DWithState(_, NodeTag.Player(data)) =>
                // Tween 中（前の 1 マスがまだ滑走中）は入力を捨てる。1 回だけ評価する。
                if (PlayerScene.isMoving(data#id)) (node, scene)
                else
                    let board = BoardQuery.board();
                    // 方向キー押下で 1 セルだけ進む。味方セルへ進入可能（重なる）、敵セルはブロック。
                    let moved = forM (
                        dir    <- readHeldDirection();
                        target <- Board.tryMoveWithRange(board, data#gridPos, dir, allowedPred)
                    ) yield PlayerScene.moveToById(data#id, target, board#map, slide, scene);
                    match moved {
                        case None       => (node, scene)
                        case Some(next) => match Scene.getEngineNode(path, next) {
                            case Some(latest) => (latest, next)
                            case None         => (node, next)
                        }
                    }
            case _ => (node, scene)
        }

    /// 押されている方向キーを Option で返す（複数同時押しは上 > 下 > 左 > 右）。
    /// 入力ポーリングは打ち手の責務。ここ 1 箇所に集約し PlayerScene からは削除した。
    def readHeldDirection(): Option[{x = Int32, y = Int32}] \ GameEngine.Game =
        let isDown = key -> GameEngine.Game.isKeyPressed(key);
        if      (isDown(GameEngine.Key.W) or isDown(GameEngine.Key.Up))    Some(Vec2i.up())
        else if (isDown(GameEngine.Key.S) or isDown(GameEngine.Key.Down))  Some(Vec2i.down())
        else if (isDown(GameEngine.Key.A) or isDown(GameEngine.Key.Left))  Some(Vec2i.left())
        else if (isDown(GameEngine.Key.D) or isDown(GameEngine.Key.Right)) Some(Vec2i.right())
        else None
}
