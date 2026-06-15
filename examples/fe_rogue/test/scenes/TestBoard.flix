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

    /// w×h サイズの盤面で、全マス床。範囲外は壁扱い。
    def emptySnapshot(w: Int32, h: Int32): MapSnapshot =
        {
            tileSize     = testTileSize(),
            usedRect     = {position = {x = 0, y = 0}, size = ({x = w, y = h}: {x = Int32, y = Int32})},
            wallCells    = (Set#{}: Set[(Int32, Int32)]),
            mapGlobal    = {x = 0.0, y = 0.0},
            placements   = Nil
        }

    /// w×h サイズの盤面で、wall の 1 マスだけ壁、ほかは床。範囲外も壁扱い。
    def floorSnapshotWithWall(w: Int32, h: Int32, wall: {x = Int32, y = Int32}): MapSnapshot =
        {
            tileSize     = testTileSize(),
            usedRect     = {position = {x = 0, y = 0}, size = ({x = w, y = h}: {x = Int32, y = Int32})},
            wallCells    = Set#{(wall#x, wall#y)},
            mapGlobal    = {x = 0.0, y = 0.0},
            placements   = Nil
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

    // ========================================================================
    // ダイクストラ距離フィールド: distanceField / fieldDist / stepDownhill
    // ========================================================================

    /// 壁で迂回が強制されるとき、フィールド値は manhattan より大きい（= 真の経路距離）。
    /// 3×3・(1,1) のみ壁。源 (0,1) から (2,1) は直線 manhattan 2 だが、壁を回って経路距離 4。
    ///   . . .
    ///   S # G    源=(0,1)。(2,1) へは (0,0)(1,0)(2,0) か (0,2)(1,2)(2,2) を回る = 4 歩。
    ///   . . .
    @Test
    def testDistanceFieldDetourGreaterThanManhattan(): Unit \ Assert =
        let map   = floorSnapshotWithWall(3, 3, src(1, 1));
        let field = Board.distanceField(c -> MapSnapshot.isFloor(c, map), src(0, 1) :: Nil, 64);
        Assert.assertEq(expected = (0, 4),
            (Board.fieldDist(field, src(0, 1)), Board.fieldDist(field, src(2, 1))))

    /// stepDownhill は「値がより小さい隣」へ進む。(2,1)(値4) からは値3の隣へ。
    /// タイブレークに依らず「降下したこと（値3）」を確認する。
    @Test
    def testStepDownhillDescends(): Unit \ Assert =
        let map   = floorSnapshotWithWall(3, 3, src(1, 1));
        let field = Board.distanceField(c -> MapSnapshot.isFloor(c, map), src(0, 1) :: Nil, 64);
        let next  = Board.stepDownhill(field, src(2, 1), _ -> true);
        Assert.assertEq(expected = Some(3),
            Option.map(c -> Board.fieldDist(field, c), next))

    /// 開けた 5×1。源 (0,0) から (4,0)(値4) を 1 歩降りると (3,0)。
    @Test
    def testStepDownhillTowardSource(): Unit \ Assert =
        let map   = emptySnapshot(5, 1);
        let field = Board.distanceField(c -> MapSnapshot.isFloor(c, map), src(0, 0) :: Nil, 64);
        Assert.assertEq(expected = (true, 3, 0),
            unpackOption(Board.stepDownhill(field, src(4, 0), _ -> true)))

    /// 壁で分断された領域のセルはフィールドに含まれない（= infDist）。
    /// 3×1・(1,0) が壁。源 (0,0) から (2,0) は壁越しで到達不能。
    @Test
    def testDistanceFieldDisconnectedIsInfinite(): Unit \ Assert =
        let map   = floorSnapshotWithWall(3, 1, src(1, 0));
        let field = Board.distanceField(c -> MapSnapshot.isFloor(c, map), src(0, 0) :: Nil, 64);
        Assert.assertEq(expected = (0, Board.infDist()),
            (Board.fieldDist(field, src(0, 0)), Board.fieldDist(field, src(2, 0))))

    /// 降下できる隣が無ければ None（源そのもの = 値0）。
    @Test
    def testStepDownhillNoneAtSource(): Unit \ Assert =
        let map   = emptySnapshot(3, 1);
        let field = Board.distanceField(c -> MapSnapshot.isFloor(c, map), src(0, 0) :: Nil, 64);
        Assert.assertEq(expected = true,
            Option.isEmpty(Board.stepDownhill(field, src(0, 0), _ -> true)))

    // ========================================================================
    // (F) 射程プリミティブ — manhattanOffsets / computeThreatCells（RangeScenes が委譲）
    //   {x,y} record は Eq 無しなので件数 + Board.containsCell で検証する。
    // ========================================================================

    /// 距離ちょうど 1 のオフセットは上下左右の 4 つ。原点(0,0)は含まない（剣/槍の隣接）。
    @Test
    def testManhattanRange1Is4Cells(): Unit \ Assert =
        let offs = Board.manhattanOffsets(1, 1);
        Assert.assertEq(
            expected = (4, true, false),
            (List.length(offs),
             Board.containsCell({x = 1, y = 0}, offs),
             Board.containsCell({x = 0, y = 0}, offs)))

    /// 距離ちょうど 2 は 8 オフセットで、斜め (1,1) を含む（弓 range=2 の斜め射程）。
    @Test
    def testManhattanRange2IncludesDiagonal(): Unit \ Assert =
        let offs = Board.manhattanOffsets(2, 2);
        Assert.assertEq(
            expected = (8, true),
            (List.length(offs), Board.containsCell({x = 1, y = 1}, offs)))

    /// lo > hi（射程下限が上限を超える）なら空（境界）。
    @Test
    def testManhattanLoGtHiIsEmpty(): Unit \ Assert =
        Assert.assertEq(expected = true, List.isEmpty(Board.manhattanOffsets(3, 1)))

    /// 脅威セルは reachable 自身を除外する（青マスに赤を二重表示しない不変条件）。
    /// reachable=(5,5) のみ・射程1 → 上下左右の 4 セルだけで (5,5) は入らない。
    @Test
    def testThreatExcludesReachable(): Unit \ Assert =
        let threat = Board.computeThreatCells({x = 5, y = 5} :: Nil, 1, 1);
        Assert.assertEq(
            expected = (4, false),
            (List.length(threat), Board.containsCell({x = 5, y = 5}, threat)))

    /// 隣接する 2 起点 (0,0)/(2,0) の射程1脅威は重複 (1,0) を 1 つにまとめる。
    /// 生セル 8 個から重複 (1,0) を 1 つ落として 7 セル（先勝ち dedup）。
    @Test
    def testThreatDedupsOverlap(): Unit \ Assert =
        let reachable = {x = 0, y = 0} :: {x = 2, y = 0} :: Nil;
        let threat = Board.computeThreatCells(reachable, 1, 1);
        Assert.assertEq(
            expected = (7, true),
            (List.length(threat), Board.containsCell({x = 1, y = 0}, threat)))

    // ========================================================================
    // (E) 駒視点の移動範囲 — reachableForUnit / stoppableForUnit（MoveRange の青マス）
    //   敵=障害物・味方=貫通可、停止は味方マス除外（FE ルール）。
    // ========================================================================

    /// 隣の敵駒は障害物。すり抜けられず、その先 (2,0) には到達しない。
    @Test
    def testReachableBlockedByEnemy(): Unit \ Assert =
        let board = boardWith(emptySnapshot(5, 1),
            (Piece.Player(0), {x = 0, y = 0}) :: (Piece.Enemy(1), {x = 1, y = 0}) :: Nil);
        let reach = Board.reachableForUnit(board, {x = 0, y = 0}, 3);
        Assert.assertEq(
            expected = (true, false),
            (Board.containsCell({x = 0, y = 0}, reach),
             Board.containsCell({x = 2, y = 0}, reach)))

    /// 味方駒は通過可能。隣の味方を貫通してその先 (3,0) まで到達する。
    @Test
    def testReachablePassesThroughAlly(): Unit \ Assert =
        let board = boardWith(emptySnapshot(5, 1),
            (Piece.Player(0), {x = 0, y = 0}) :: (Piece.Player(1), {x = 1, y = 0}) :: Nil);
        let reach = Board.reachableForUnit(board, {x = 0, y = 0}, 3);
        Assert.assertEq(
            expected = (true, true),
            (Board.containsCell({x = 1, y = 0}, reach),
             Board.containsCell({x = 3, y = 0}, reach)))

    /// 味方マスは「到達はするが停止できない」。reachable には在り stoppable から除外。
    @Test
    def testStoppableExcludesAllyCells(): Unit \ Assert =
        let board = boardWith(emptySnapshot(5, 1),
            (Piece.Player(0), {x = 0, y = 0}) :: (Piece.Player(1), {x = 1, y = 0}) :: Nil);
        let reach = Board.reachableForUnit(board, {x = 0, y = 0}, 3);
        let stop  = Board.stoppableForUnit(board, {x = 0, y = 0}, 3);
        Assert.assertEq(
            expected = (true, false),
            (Board.containsCell({x = 1, y = 0}, reach),
             Board.containsCell({x = 1, y = 0}, stop)))

    /// stoppable ⊆ reachable（停止可能マスは必ず到達可能。不変条件）。
    @Test
    def testStoppableSubsetOfReachable(): Unit \ Assert =
        let board = boardWith(emptySnapshot(5, 1),
            (Piece.Player(0), {x = 0, y = 0}) :: (Piece.Player(1), {x = 1, y = 0}) :: Nil);
        let reach = Board.reachableForUnit(board, {x = 0, y = 0}, 3);
        let stop  = Board.stoppableForUnit(board, {x = 0, y = 0}, 3);
        Assert.assertEq(
            expected = true,
            List.forAll(c -> Board.containsCell(c, reach), stop))

    // ========================================================================
    // (D) bfsPathSkipAllies — 味方貫通・敵/壁不可の経路探索（AutoMove のロード合流）
    // ========================================================================

    /// 間に居る味方マスを通過して goal までの経路を返す（味方は障害にしない）。
    @Test
    def testBfsPassesAllyToReachGoal(): Unit \ Assert =
        let board = boardWith(emptySnapshot(5, 1),
            (Piece.Player(0), {x = 0, y = 0}) :: (Piece.Player(1), {x = 1, y = 0}) :: Nil);
        let path = Board.bfsPathSkipAllies(board, {x = 1, y = 0} :: Nil,
                                            {x = 0, y = 0}, {x = 2, y = 0});
        Assert.assertEq(
            expected = (true, true),
            (Option.nonEmpty(path),
             path |> Option.map(p -> Board.containsCell({x = 2, y = 0}, p))
                  |> Option.getWithDefault(false)))

    /// 壁で分断され goal に到達不能なら None（1 マス幅通路の (2,0) が壁）。
    @Test
    def testBfsBlockedByWallIsNone(): Unit \ Assert =
        let board = boardWith(floorSnapshotWithWall(5, 1, {x = 2, y = 0}),
            (Piece.Player(0), {x = 0, y = 0}) :: Nil);
        let path = Board.bfsPathSkipAllies(board, Nil, {x = 0, y = 0}, {x = 4, y = 0});
        Assert.assertEq(expected = true, Option.isEmpty(path))

    // ========================================================================
    // followStepsToward — 集合（行軍）の味方 1 歩追従
    //   各味方を「主人公の移動前マス」へ味方すり抜け最短で 1 歩寄せる。
    //   {x,y} は Eq 無しなので Option を (x,y) tuple 化し、Some/None のまま比較する。
    // ========================================================================

    /// 結果の各味方の次マスを比較用に変換する（None はそのまま、Some は (x,y) tuple へ）。
    /// consumesStep は捨てて (id, 次マス) で比較する（消費判定は別テストで確認）。
    def followToTuples(result: List[(Int32, Option[{x = Int32, y = Int32}], Bool)]):
            List[(Int32, Option[(Int32, Int32)])] =
        List.map(e -> { let (id, o, _) = e; (id, Option.map(c -> (c#x, c#y), o)) }, result)

    /// 結果の各味方の「移動距離を消費するか(consumesStep)」だけを (id, Bool) で取り出す。
    def followConsumes(result: List[(Int32, Option[{x = Int32, y = Int32}], Bool)]):
            List[(Int32, Bool)] =
        List.map(e -> { let (id, _, consumes) = e; (id, consumes) }, result)

    /// 主人公が (1,0)→(2,0) と動いた後、真後ろの味方(1)は移動前マス (1,0) へ 1 歩進む。
    @Test
    def testFollowStepsBehindLord(): Unit \ Assert =
        let board = boardWith(emptySnapshot(5, 1),
            (Piece.Player(0), {x = 2, y = 0}) :: (Piece.Player(1), {x = 0, y = 0}) :: Nil);
        let result = Board.followStepsToward(board,
            {x = 2, y = 0} :: {x = 0, y = 0} :: Nil,
            {x = 2, y = 0},
            {x = 1, y = 0},
            (1, {x = 0, y = 0}, true) :: Nil);
        Assert.assertEq(expected = (1, Some((1, 0))) :: Nil, followToTuples(result))

    /// 前の味方(2)が空けたマスを後続(1)がすり抜けて詰める。主人公は (3,0) に居る。
    /// 味方2 は (1,0)→(2,0)、味方1 は (0,0)→(1,0)（(1,0) は味方2が抜けたマス）。
    @Test
    def testFollowStepsPassThroughAlly(): Unit \ Assert =
        let board = boardWith(emptySnapshot(5, 1),
            (Piece.Player(0), {x = 3, y = 0}) ::
            (Piece.Player(1), {x = 0, y = 0}) :: (Piece.Player(2), {x = 1, y = 0}) :: Nil);
        let result = Board.followStepsToward(board,
            {x = 3, y = 0} :: {x = 0, y = 0} :: {x = 1, y = 0} :: Nil,
            {x = 3, y = 0},
            {x = 2, y = 0},
            (1, {x = 0, y = 0}, true) :: (2, {x = 1, y = 0}, true) :: Nil);
        Assert.assertEq(
            expected = (1, Some((1, 0))) :: (2, Some((2, 0))) :: Nil,
            followToTuples(result))

    /// 主人公が味方(2)のマス (2,0) に踏み込むと、味方2 は主人公の元マス (1,0) へ抜ける（入れ替え）。
    @Test
    def testFollowStepsSwapWhenLordEntersAllyCell(): Unit \ Assert =
        let board = boardWith(emptySnapshot(5, 1),
            (Piece.Player(0), {x = 1, y = 0}) :: (Piece.Player(2), {x = 2, y = 0}) :: Nil);
        let result = Board.followStepsToward(board,
            {x = 1, y = 0} :: {x = 2, y = 0} :: Nil,
            {x = 2, y = 0},
            {x = 1, y = 0},
            (2, {x = 2, y = 0}, true) :: Nil);
        Assert.assertEq(expected = (2, Some((1, 0))) :: Nil, followToTuples(result))

    /// 同じ goal を狙う 2 人は同じマスに重ならない: 先勝ちの(1)が (1,0) を取り、(2) は留まる。
    @Test
    def testFollowStepsNeverStackOnSameCell(): Unit \ Assert =
        let board = boardWith(emptySnapshot(3, 3),
            (Piece.Player(0), {x = 2, y = 0}) ::
            (Piece.Player(1), {x = 0, y = 0}) :: (Piece.Player(2), {x = 1, y = 1}) :: Nil);
        let result = Board.followStepsToward(board,
            {x = 0, y = 0} :: {x = 1, y = 1} :: Nil,
            {x = 2, y = 0},
            {x = 1, y = 0},
            (1, {x = 0, y = 0}, true) :: (2, {x = 1, y = 1}, true) :: Nil);
        Assert.assertEq(
            expected = (1, Some((1, 0))) :: (2, None) :: Nil,
            followToTuples(result))

    /// 壁で分断され goal に到達できない味方は None（動かない）。(2,0) が壁。
    @Test
    def testFollowStepsNoPathIsNone(): Unit \ Assert =
        let board = boardWith(floorSnapshotWithWall(5, 1, {x = 2, y = 0}),
            (Piece.Player(0), {x = 3, y = 0}) :: (Piece.Player(1), {x = 0, y = 0}) :: Nil);
        let result = Board.followStepsToward(board,
            {x = 3, y = 0} :: {x = 0, y = 0} :: Nil,
            {x = 3, y = 0},
            {x = 4, y = 0},
            (1, {x = 0, y = 0}, true) :: Nil);
        Assert.assertEq(expected = (1, None) :: Nil, followToTuples(result))

    /// 既に goal に居る味方は None（重ねて進ませない）。
    @Test
    def testFollowStepsAlreadyAtGoalIsNone(): Unit \ Assert =
        let board = boardWith(emptySnapshot(5, 1),
            (Piece.Player(0), {x = 2, y = 0}) :: (Piece.Player(1), {x = 1, y = 0}) :: Nil);
        let result = Board.followStepsToward(board,
            {x = 2, y = 0} :: {x = 1, y = 0} :: Nil,
            {x = 2, y = 0},
            {x = 1, y = 0},
            (1, {x = 1, y = 0}, true) :: Nil);
        Assert.assertEq(expected = (1, None) :: Nil, followToTuples(result))

    /// 非アクティブ(active=false)な味方は動かず、その停止マスは予約される:
    /// 移動済みの(2)@(1,0) は留まり、(1) は (2) のマスへ停止できないので手前 (0,0) に留まる。
    @Test
    def testFollowStepsInactiveAllyStaysAndReserves(): Unit \ Assert =
        let board = boardWith(emptySnapshot(5, 1),
            (Piece.Player(0), {x = 3, y = 0}) ::
            (Piece.Player(1), {x = 0, y = 0}) :: (Piece.Player(2), {x = 1, y = 0}) :: Nil);
        let result = Board.followStepsToward(board,
            {x = 3, y = 0} :: {x = 0, y = 0} :: {x = 1, y = 0} :: Nil,
            {x = 3, y = 0},
            {x = 2, y = 0},
            (1, {x = 0, y = 0}, true) :: (2, {x = 1, y = 0}, false) :: Nil);
        Assert.assertEq(
            expected = (1, None) :: (2, None) :: Nil,
            followToTuples(result))

    /// allyCells に含まれない味方（＝集合で待機中になった味方の想定）は通り抜けられない固体障害物。
    /// (2,0) を allyCells から外すと、後続(1)は (2,0) を越えて goal(4,0) へ追従できず留まる。
    @Test
    def testFollowStepsBlockedByOpaqueAlly(): Unit \ Assert =
        let board = boardWith(emptySnapshot(6, 1),
            (Piece.Player(0), {x = 5, y = 0}) ::
            (Piece.Player(1), {x = 0, y = 0}) :: (Piece.Player(2), {x = 2, y = 0}) :: Nil);
        let result = Board.followStepsToward(board,
            {x = 5, y = 0} :: {x = 0, y = 0} :: Nil,   // allyCells: 主人公+味方1 のみ（味方2 を除外＝障害物）
            {x = 5, y = 0},
            {x = 4, y = 0},
            (1, {x = 0, y = 0}, true) :: (2, {x = 2, y = 0}, false) :: Nil);
        Assert.assertEq(
            expected = (1, None) :: (2, None) :: Nil,
            followToTuples(result))

    /// 障害物(待機味方)を大回りしないと goal に近づけない味方は、移動力を浪費せずその場に留まる。
    /// (0,1) の待機味方を避けて x=1 列へ迂回する一歩は主人公(0,3)から遠ざかるので踏まない。
    @Test
    def testFollowStepsStaysWhenDetourGoesAway(): Unit \ Assert =
        let board = boardWith(emptySnapshot(2, 4),
            (Piece.Player(0), {x = 0, y = 3}) ::
            (Piece.Player(1), {x = 0, y = 0}) :: (Piece.Player(2), {x = 0, y = 1}) :: Nil);
        let result = Board.followStepsToward(board,
            {x = 0, y = 3} :: {x = 0, y = 0} :: Nil,   // allyCells: 主人公+味方1（待機の味方2 を除外＝障害物）
            {x = 0, y = 3},
            {x = 0, y = 2},
            (1, {x = 0, y = 0}, true) :: (2, {x = 0, y = 1}, false) :: Nil);
        Assert.assertEq(
            expected = (1, None) :: (2, None) :: Nil,
            followToTuples(result))

    /// 未行動の味方は、間に居る敵を迂回しないと goal に届かない配置でも追従する（回帰）。
    /// 幅 2 の縦通路: 主人公は (0,1)→(0,0) と上に動き、goal=(0,1)。敵が (0,2) で直進を塞ぐ。
    /// 味方(1)@(0,3) は唯一の迂回路 x=1 側へ 1 歩 (1,3) 進む。
    /// 旧マンハッタンゲートはこの一歩が主人公の新位置 (0,0) から遠ざかるため None としていた（バグ）。
    /// 敵・壁を障害物・味方を素通しで測る理想距離フィールドでは迂回が前進になるので追従する。
    @Test
    def testFollowStepsDetoursAroundEnemy(): Unit \ Assert =
        let board = boardWith(emptySnapshot(2, 4),
            (Piece.Player(0), {x = 0, y = 0}) :: (Piece.Player(1), {x = 0, y = 3}) ::
            (Piece.Enemy(9),  {x = 0, y = 2}) :: Nil);
        let result = Board.followStepsToward(board,
            {x = 0, y = 0} :: {x = 0, y = 3} :: Nil,   // allyCells: 主人公+味方1（敵は含めない）
            {x = 0, y = 0},
            {x = 0, y = 1},
            (1, {x = 0, y = 3}, true) :: Nil);
        Assert.assertEq(expected = (1, Some((1, 3))) :: Nil, followToTuples(result))

    /// 自発的に追従した味方は移動距離を消費する(consumesStep=true)。
    /// (1) は (0,0)→(1,0) と自発的に 1 歩進むので true。
    @Test
    def testFollowConsumesStepOnVoluntaryMove(): Unit \ Assert =
        let board = boardWith(emptySnapshot(5, 1),
            (Piece.Player(0), {x = 2, y = 0}) :: (Piece.Player(1), {x = 0, y = 0}) :: Nil);
        let result = Board.followStepsToward(board,
            {x = 2, y = 0} :: {x = 0, y = 0} :: Nil,
            {x = 2, y = 0},
            {x = 1, y = 0},
            (1, {x = 0, y = 0}, true) :: Nil);
        Assert.assertEq(expected = (1, true) :: Nil, followConsumes(result))

    /// 主人公に押し出された味方の入れ替えは強制退避なので移動距離を消費しない(consumesStep=false)。
    @Test
    def testFollowDoesNotConsumeOnPush(): Unit \ Assert =
        let board = boardWith(emptySnapshot(5, 1),
            (Piece.Player(0), {x = 1, y = 0}) :: (Piece.Player(2), {x = 2, y = 0}) :: Nil);
        let result = Board.followStepsToward(board,
            {x = 1, y = 0} :: {x = 2, y = 0} :: Nil,
            {x = 2, y = 0},
            {x = 1, y = 0},
            (2, {x = 2, y = 0}, true) :: Nil);
        Assert.assertEq(expected = (2, false) :: Nil, followConsumes(result))

    // ========================================================================
    // dedupCells / padCells — 座標集合の整形（spawn 配置・危険域表示が共有）
    //   {x,y} は Eq 無しなので tuple 化して順序ごと比較する。
    // ========================================================================

    /// 重複セルは先に出たものを残して 1 つに（順序保持・先勝ち）。
    @Test
    def testDedupCellsFirstWins(): Unit \ Assert =
        let out = Board.dedupCells({x = 1, y = 1} :: {x = 2, y = 2} :: {x = 1, y = 1} :: Nil)
                    |> List.map(c -> (c#x, c#y));
        Assert.assertEq(expected = (1, 1) :: (2, 2) :: Nil, out)

    /// 不足分は fallback で埋めて長さ n に揃える（狭所スポーンの保険）。
    @Test
    def testPadCellsFillsShortfall(): Unit \ Assert =
        let out = Board.padCells({x = 0, y = 0} :: Nil, {x = 9, y = 9}, 3)
                    |> List.map(c -> (c#x, c#y));
        Assert.assertEq(expected = (0, 0) :: (9, 9) :: (9, 9) :: Nil, out)

    /// 余っていれば先頭 n 個に切り詰める（境界）。
    @Test
    def testPadCellsTruncatesExcess(): Unit \ Assert =
        let out = Board.padCells({x = 0, y = 0} :: {x = 1, y = 1} :: {x = 2, y = 2} :: Nil,
                                  {x = 9, y = 9}, 2)
                    |> List.map(c -> (c#x, c#y));
        Assert.assertEq(expected = (0, 0) :: (1, 1) :: Nil, out)

    // ========================================================================
    // knockbackPathCapped — ふきとばし経路の距離上限（如意棒2マス / 突風=無制限）
    //   {x,y} は Eq 無しなので tuple 化して比較する。
    // ========================================================================

    /// 10×1 の床で (1,0) の駒を右へ押すと、範囲端まで 8 マス分の経路が出る（無制限の基準）。
    @Test
    def testKnockbackPathUncapped(): Unit \ Assert =
        let board = boardWithPlayer(emptySnapshot(10, 1), {x = 1, y = 0});
        let out = Board.knockbackPathCapped({x = 1, y = 0}, {x = 1, y = 0}, board, None)
                    |> List.map(c -> (c#x, c#y));
        Assert.assertEq(expected = (2,0)::(3,0)::(4,0)::(5,0)::(6,0)::(7,0)::(8,0)::(9,0)::Nil, out)

    /// Some(2)（如意棒）→ 同じ経路の先頭 2 マスだけに切り詰める。
    @Test
    def testKnockbackPathCappedToTwo(): Unit \ Assert =
        let board = boardWithPlayer(emptySnapshot(10, 1), {x = 1, y = 0});
        let out = Board.knockbackPathCapped({x = 1, y = 0}, {x = 1, y = 0}, board, Some(2))
                    |> List.map(c -> (c#x, c#y));
        Assert.assertEq(expected = (2, 0) :: (3, 0) :: Nil, out)

    /// 壁での停止は上限より先に効く：(4,0) が壁なら cap=5 でも (2,0),(3,0) で止まる。
    @Test
    def testKnockbackPathStopsAtWallBeforeCap(): Unit \ Assert =
        let board = boardWithPlayer(floorSnapshotWithWall(10, 1, {x = 4, y = 0}), {x = 1, y = 0});
        let out = Board.knockbackPathCapped({x = 1, y = 0}, {x = 1, y = 0}, board, Some(5))
                    |> List.map(c -> (c#x, c#y));
        Assert.assertEq(expected = (2, 0) :: (3, 0) :: Nil, out)
}
