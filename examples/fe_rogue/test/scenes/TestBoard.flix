// Board のテスト — 動きルール (tryMove / tryMoveWithRange) と 経路探索 (reachableCells)
//
// 盤面（マップ + 駒の位置）から「次の手」を計算するロジックを公開 API
// `Board.tryMove` 経由で検証する。Board を直接合成して任意の盤面を作る。
//
// `Board.isWalkable` / `Board.stepTarget` は委譲だけの 1 行関数なので
// ここではテストしない（`tryMove` 経由で間接的にカバーされる）。

mod TestBoard {

    // ========================================================================
    // ヘルパー — 盤面 fixture と Option アダプタ
    // ========================================================================

    /// テスト用 tileSize（実機と同じ 16px 正方形）
    def testTileSize(): Float64 = 16.0

    /// グリッド座標 → タイル中心ピクセル座標
    def testGridToWorld(c: {x = Int32, y = Int32}): Vec2.Vec2 =
        let s = testTileSize();
        let v = Vec2i.toVec2(c);
        {x = v#x * s + s / 2.0, y = v#y * s + s / 2.0}

    /// w×h サイズの盤面で、全マス床。範囲外は壁扱い。
    def emptySnapshot(w: Int32, h: Int32): MapSnapshot =
        let inB = c -> c#x >= 0 and c#x < w and c#y >= 0 and c#y < h;
        {
            tileSize     = testTileSize(),
            usedRect     = {position = Vec2i.zero(), size = ({x = w, y = h}: {x = Int32, y = Int32})},
            isWall       = c -> not inB(c),
            isFloor      = c -> inB(c),
            mapToLocal   = c -> testGridToWorld(c),
            gridToWorld  = c -> testGridToWorld(c),
            moduleOfCell = _ -> None
        }

    /// w×h サイズの盤面で、wall の 1 マスだけ壁、ほかは床。範囲外も壁扱い。
    def floorSnapshotWithWall(w: Int32, h: Int32, wall: {x = Int32, y = Int32}): MapSnapshot =
        let inB = c -> c#x >= 0 and c#x < w and c#y >= 0 and c#y < h;
        let isW = c -> c#x == wall#x and c#y == wall#y;
        {
            tileSize     = testTileSize(),
            usedRect     = {position = Vec2i.zero(), size = ({x = w, y = h}: {x = Int32, y = Int32})},
            isWall       = c -> not inB(c) or isW(c),
            isFloor      = c -> inB(c) and not isW(c),
            mapToLocal   = c -> testGridToWorld(c),
            gridToWorld  = c -> testGridToWorld(c),
            moduleOfCell = _ -> None
        }

    /// snapshot と Player 位置から Board を組む（id=0 単独パーティ）
    def boardWithPlayer(snapshot: MapSnapshot, player: {x = Int32, y = Int32}): Board =
        {
            map    = snapshot,
            pieces = (Piece.Player(0), player) :: Nil
        }

    /// テスト用：Player 位置（=source）として使うのは boardWithPlayer の player と一致する想定
    def src(c: Int32, d: Int32): {x = Int32, y = Int32} = {x = c, y = d}

    /// Option[Vec2i] を assertEq 用の tuple に変換
    /// (None → (false, 0, 0)、Some → (true, x, y))
    def unpackOption(o: Option[{x = Int32, y = Int32}]): (Bool, Int32, Int32) =
        match o {
            case Some(v) => (true, v#x, v#y)
            case None    => (false, 0, 0)
        }

    // ========================================================================
    // tryMove — Player 位置を起点に、壁・範囲外で None、床なら Some(target)
    // ========================================================================

    /// 何もない 5×5 盤面で Player(2,2) は右に進める → Some(3, 2)
    @Test
    def testTryMoveAllowedOnEmptyBoard(): Unit \ Assert =
        let board = boardWithPlayer(emptySnapshot(5, 5), src(2, 2));
        let result = Board.tryMove(board, src(2, 2), Vec2i.right());
        Assert.assertEq(expected = (true, 3, 2), unpackOption(result))

    /// 進行先 (3, 2) が壁なら None
    @Test
    def testTryMoveBlockedByWall(): Unit \ Assert =
        let snapshot = floorSnapshotWithWall(5, 5, src(3, 2));
        let board = boardWithPlayer(snapshot, src(2, 2));
        let result = Board.tryMove(board, src(2, 2), Vec2i.right());
        Assert.assertEq(expected = (false, 0, 0), unpackOption(result))

    /// 盤面の端 (0, 0) から外（左）に出ようとすると None
    @Test
    def testTryMoveBlockedAtEdge(): Unit \ Assert =
        let board = boardWithPlayer(emptySnapshot(5, 5), src(0, 0));
        let result = Board.tryMove(board, src(0, 0), Vec2i.left());
        Assert.assertEq(expected = (false, 0, 0), unpackOption(result))

    /// 右が壁でも下方向は開いている → 別方向には進める
    @Test
    def testTryMovePicksOpenDirection(): Unit \ Assert =
        let snapshot = floorSnapshotWithWall(5, 5, src(3, 2));
        let board = boardWithPlayer(snapshot, src(2, 2));
        let resultRight = Board.tryMove(board, src(2, 2), Vec2i.right());
        let resultDown  = Board.tryMove(board, src(2, 2), Vec2i.down());
        Assert.assertEq(
            expected = ((false, 0, 0), (true, 2, 3)),
            (unpackOption(resultRight), unpackOption(resultDown)))

    // ========================================================================
    // tryMoveWithRange — `allowed` 述語で目標を弾けるか
    // ========================================================================

    /// `allowed` が常に true なら `tryMove` と同じく Some(target) を返す。
    @Test
    def testTryMoveWithRangeAllowed(): Unit \ Assert =
        let board = boardWithPlayer(emptySnapshot(5, 5), src(2, 2));
        let result = Board.tryMoveWithRange(board, src(2, 2), Vec2i.right(), _ -> true);
        Assert.assertEq(expected = (true, 3, 2), unpackOption(result))

    /// `allowed` が false を返すセルへは進めない（壁と同じ扱い）。
    @Test
    def testTryMoveWithRangeBlocked(): Unit \ Assert =
        let board = boardWithPlayer(emptySnapshot(5, 5), src(2, 2));
        let result = Board.tryMoveWithRange(board, src(2, 2), Vec2i.right(), _ -> false);
        Assert.assertEq(expected = (false, 0, 0), unpackOption(result))

    /// 他駒（敵）が居るマスへは入れない。pieces に Enemy(0) を進行先 (3,2) に置く。
    @Test
    def testTryMoveBlockedByEnemy(): Unit \ Assert =
        let board: Board = {
            map    = emptySnapshot(5, 5),
            pieces = (Piece.Player(0), src(2, 2))
                  :: (Piece.Enemy(0), src(3, 2)) :: Nil
        };
        let result = Board.tryMoveWithRange(board, src(2, 2), Vec2i.right(), _ -> true);
        Assert.assertEq(expected = (false, 0, 0), unpackOption(result))

    // ========================================================================
    // reachableCells — BFS の到達範囲
    // ========================================================================

    /// origin (0,0) で maxSteps = 0 なら origin だけが返る。
    @Test
    def testReachableCellsZeroSteps(): Unit \ Assert =
        let isFloor = _ -> true;
        let cells = Board.reachableCells(isFloor, ({x = 0, y = 0}: {x = Int32, y = Int32}), 0);
        Assert.assertEq(expected = 1, List.length(cells))

    /// 全床無限平面で origin (0,0)、maxSteps = 5 → マンハッタン距離 ≤ 5 の 61 セル
    /// (1 + 4 + 8 + 12 + 16 + 20)。BFS が 4 方向 + 範囲打ち切りで動くことを確認。
    @Test
    def testReachableCellsFiveStepsOpen(): Unit \ Assert =
        let isFloor = _ -> true;
        let cells = Board.reachableCells(isFloor, ({x = 0, y = 0}: {x = Int32, y = Int32}), 5);
        Assert.assertEq(expected = 61, List.length(cells))

    /// origin が isFloor 述語を満たさない場合でも origin は visited 初期値として含まれる。
    /// （BFS 展開は `isFloor` で制限されるが、出発点は強制的に許容）
    @Test
    def testReachableCellsIncludesOrigin(): Unit \ Assert =
        let isFloor = _ -> false;
        let cells = Board.reachableCells(isFloor, ({x = 3, y = 7}: {x = Int32, y = Int32}), 5);
        Assert.assertEq(expected = (1, 3, 7),
                         (List.length(cells),
                          (List.head(cells) |> Option.map(c -> c#x) |> Option.getWithDefault(-1)),
                          (List.head(cells) |> Option.map(c -> c#y) |> Option.getWithDefault(-1))))

    /// 壁 1 マス（(1,0)) で経路が遮られる場合、(2,0) は迂回でしか届かない。
    /// origin (0,0) maxSteps=2 なら通常 (2,0) が含まれるが、壁があると到達 3 ステップ
    /// 必要なので含まれない。
    @Test
    def testReachableCellsBlockedByWall(): Unit \ Assert =
        let wall: {x = Int32, y = Int32} = {x = 1, y = 0};
        let isFloor = c -> not (c#x == wall#x and c#y == wall#y);
        let cells = Board.reachableCells(isFloor, ({x = 0, y = 0}: {x = Int32, y = Int32}), 2);
        let hasFarRight = List.exists(c -> c#x == 2 and c#y == 0, cells);
        Assert.assertEq(expected = false, hasFarRight)

    // ========================================================================
    // rayCast — 杖の直線射出
    //   origin から dir 方向に最大 range マス進み、最初に当たった対象を返す。
    // ========================================================================

    /// 任意の pieces で Board を組むヘルパー（rayCast / knockbackPath 用）
    def boardWith(snapshot: MapSnapshot,
                   pieces: List[(Piece, {x = Int32, y = Int32})]): Board =
        {map = snapshot, pieces = pieces}

    /// RayHit を assertEq 用のタプルに変換する。
    /// 形式: (タグ名, idOrZero, cellX, cellY)。タグは "player"/"enemy"/"wall"/"oor"。
    def unpackHit(hit: RayHit): (String, Int32, Int32, Int32) = match hit {
        case RayHit.HitPlayer(id, c) => ("player", id, c#x, c#y)
        case RayHit.HitEnemy(id, c)  => ("enemy", id, c#x, c#y)
        case RayHit.HitWall(c)       => ("wall", 0, c#x, c#y)
        case RayHit.OutOfRange(c)    => ("oor", 0, c#x, c#y)
    }

    /// 何もない 5×5 盤面で (1,2) から右に range=5 で射出する。
    /// 盤面の右端 (4,2) まで進んで、その先 (5,2) は範囲外（= 壁扱い）なので
    /// HitWall(4, 2) を返す。
    @Test
    def testRayCastHitsWall(): Unit \ Assert =
        let board = boardWith(emptySnapshot(5, 5), Nil);
        let hit = Board.rayCast(src(1, 2), Vec2i.right(), 5, board);
        Assert.assertEq(expected = ("wall", 0, 4, 2), unpackHit(hit))

    /// (1,2) の右隣 (2,2) にプレイヤー id=7 がいる → HitPlayer(7, (2,2))。
    /// origin にいる駒は origin から踏み出さない（origin そのものは判定対象外）。
    @Test
    def testRayCastHitsPlayer(): Unit \ Assert =
        let pieces = (Piece.Player(7), src(2, 2)) :: Nil;
        let board = boardWith(emptySnapshot(5, 5), pieces);
        let hit = Board.rayCast(src(1, 2), Vec2i.right(), 3, board);
        Assert.assertEq(expected = ("player", 7, 2, 2), unpackHit(hit))

    /// (1,2) の 2 マス先 (3,2) に敵 id=4 がいる → HitEnemy(4, (3,2))。
    /// 途中の (2,2) は空マスなので通り抜けて (3,2) で止まる。
    @Test
    def testRayCastHitsEnemy(): Unit \ Assert =
        let pieces = (Piece.Enemy(4), src(3, 2)) :: Nil;
        let board = boardWith(emptySnapshot(5, 5), pieces);
        let hit = Board.rayCast(src(1, 2), Vec2i.right(), 5, board);
        Assert.assertEq(expected = ("enemy", 4, 3, 2), unpackHit(hit))

    /// 何もない 5×5 で (0,2) から右に range=3 → 3 マス先 (3,2) で射程切れ。
    /// 何にも当たっていないので OutOfRange((3,2))。
    @Test
    def testRayCastReachesRangeLimit(): Unit \ Assert =
        let board = boardWith(emptySnapshot(5, 5), Nil);
        let hit = Board.rayCast(src(0, 2), Vec2i.right(), 3, board);
        Assert.assertEq(expected = ("oor", 0, 3, 2), unpackHit(hit))

    /// origin (1,2) に自分（Player(0)）がいて、隣 (2,2) に敵 id=4 がいる。
    /// origin の駒（自分）は origin から踏み出すので当たらず、隣の敵にヒットする。
    @Test
    def testRayCastIgnoresSelfAtOrigin(): Unit \ Assert =
        let pieces = (Piece.Player(0), src(1, 2))
                   :: (Piece.Enemy(4),  src(2, 2)) :: Nil;
        let board = boardWith(emptySnapshot(5, 5), pieces);
        let hit = Board.rayCast(src(1, 2), Vec2i.right(), 3, board);
        Assert.assertEq(expected = ("enemy", 4, 2, 2), unpackHit(hit))

    // ========================================================================
    // knockbackPath — ふきとばしで対象が押される経路
    //   hitCell から dir 方向に進めるだけ進む。hitCell に居る駒は移動中とみなして
    //   障害物判定から除外する。
    // ========================================================================

    /// `{x, y}` の List を `(x, y)` Int32 ペアの List にする。
    /// `{x, y}` に Eq/ToString が無いため、assertEq の前にこれで変換する。
    def pathToTuples(path: List[{x = Int32, y = Int32}]): List[(Int32, Int32)] =
        List.map(c -> (c#x, c#y), path)

    /// 5×5 で hitCell (1,2) から右に押す。3 マス先 (4,2) まで進めて、
    /// その先は壁（範囲外）。経路は [(2,2), (3,2), (4,2)]。
    @Test
    def testKnockbackPathUntilWall(): Unit \ Assert =
        let pieces = (Piece.Enemy(0), src(1, 2)) :: Nil;
        let board = boardWith(emptySnapshot(5, 5), pieces);
        let path = Board.knockbackPath(src(1, 2), Vec2i.right(), board);
        Assert.assertEq(
            expected = (2, 2) :: (3, 2) :: (4, 2) :: Nil,
            pathToTuples(path))

    /// hitCell (1,2)、すぐ右隣 (2,2) に別駒がいる → 押される先がないので Nil。
    @Test
    def testKnockbackPathBlockedImmediately(): Unit \ Assert =
        let pieces = (Piece.Enemy(0), src(1, 2))
                   :: (Piece.Enemy(1), src(2, 2)) :: Nil;
        let board = boardWith(emptySnapshot(5, 5), pieces);
        let path = Board.knockbackPath(src(1, 2), Vec2i.right(), board);
        Assert.assertEq(expected = (Nil: List[(Int32, Int32)]), pathToTuples(path))

    /// hitCell (1,2)、2 マス先 (3,2) に別駒がいる → 1 マスだけ動いて停止。
    /// 経路は [(2,2)]（最終着地が (2,2)、(3,2) の手前で止まる）。
    @Test
    def testKnockbackPathStopsBeforeOtherPiece(): Unit \ Assert =
        let pieces = (Piece.Enemy(0), src(1, 2))
                   :: (Piece.Player(0), src(3, 2)) :: Nil;
        let board = boardWith(emptySnapshot(5, 5), pieces);
        let path = Board.knockbackPath(src(1, 2), Vec2i.right(), board);
        Assert.assertEq(
            expected = (2, 2) :: Nil,
            pathToTuples(path))
}
