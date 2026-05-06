/// BoardLogic — グリッド盤面上の純粋ロジック
///
/// チェスの盤面の駒の動きを計算するイメージで、
/// 「ここから右に1マス進めるか？」「攻撃範囲内のセルはどれか？」など、
/// マップの形状や駒の位置に基づくルール判定を集約する。
///
/// 引数で受ける `Board` には地形（map）と駒の位置（pieces）が同梱されているので、
/// 「コマの位置を毎回外から教えてもらう」必要がなくなり、責務が「盤面 → 手」に閉じる。
/// Scene の構造や PlayerScene の Data には依存しない（テストは Board を直接合成可能）。
mod BoardLogic {

    /// 指定セルが歩行可能か（マップ範囲内 かつ 壁ではない）。
    /// 駒の占有は別途 `Board.isOccupied` でチェックする（自分自身が source にいる
    /// ケースを呼び出し側が制御できるよう、ここでは地形のみ見る）。
    pub def isWalkable(board: Board, coord: Vec2.Vec2i): Bool =
        board#map#isFloor(coord)

    /// origin から dir 方向に 1 マス進む候補座標
    pub def stepTarget(origin: Vec2.Vec2i, dir: Vec2.Vec2i): Vec2.Vec2i =
        Vec2.addI(origin, dir)

    /// Player を dir 方向に 1 マス進めるか試みる。
    /// 進めるなら Some(目標座標)、壁・範囲外、または盤上に Player がいなければ None。
    pub def tryMove(board: Board, dir: Vec2.Vec2i): Option[Vec2.Vec2i] =
        tryMoveWithRange(board, dir, _ -> true)

    /// `tryMove` に「移動可能セル」述語による追加制約を加える版。
    /// 範囲表示（move_tile）の外には踏み込めないようにする用途で `MoveRangeScene.isInRange`
    /// 等を渡す。`allowed` が常に true なら `tryMove` と同じ挙動。
    pub def tryMoveWithRange(board: Board, dir: Vec2.Vec2i,
                              allowed: Vec2.Vec2i -> Bool): Option[Vec2.Vec2i] =
        Board.playerPos(board) |> Option.flatMap(player ->
            let target = stepTarget(player, dir);
            // 床 + 範囲内 + 他駒に占有されていない（敵駒に重ねない）
            if (isWalkable(board, target)
                and allowed(target)
                and not Board.isOccupied(target, board)) Some(target) else None)

    /// 4 方向 BFS で `origin` から最大 `maxSteps` ステップ以内に到達できる床セルの一覧を返す。
    /// `origin` 自身も結果に含む（距離 0）。
    /// `isFloor` は「そのセルが歩行可能か（床か）」を判定する述語。
    /// `MapSnapshot` を直接受け取らないことで、テストや別経路でも合成しやすくする。
    pub def reachableCells(isFloor: Vec2.Vec2i -> Bool,
                            origin: Vec2.Vec2i,
                            maxSteps: Int32): List[Vec2.Vec2i] =
        let initVisited = origin :: Nil;
        let initQueue   = (origin, 0i32) :: Nil;
        bfs(isFloor, maxSteps, initVisited, initQueue)

    /// BFS のキューを 1 セルずつ消化する。`visited` は到達済みセル（順序保持）。
    /// 深さ `maxSteps` に達した節点はそれ以上展開しない。
    def bfs(isFloor: Vec2.Vec2i -> Bool,
             maxSteps: Int32,
             visited: List[Vec2.Vec2i],
             queue: List[(Vec2.Vec2i, Int32)]): List[Vec2.Vec2i] =
        match queue {
            case Nil => visited
            case (cur, depth) :: rest =>
                if (depth >= maxSteps) bfs(isFloor, maxSteps, visited, rest)
                else
                    let dirs = Vec2.upI() :: Vec2.downI()
                                :: Vec2.leftI() :: Vec2.rightI() :: Nil;
                    let candidates = List.map(d -> Vec2.addI(cur, d), dirs);
                    let fresh = List.filter(c ->
                        isFloor(c) and
                        not List.exists(v -> v#x == c#x and v#y == c#y, visited),
                        candidates);
                    let newVisited = List.append(visited, fresh);
                    let newQueue   = List.append(rest,
                        List.map(c -> (c, depth + 1), fresh));
                    bfs(isFloor, maxSteps, newVisited, newQueue)
        }
}
