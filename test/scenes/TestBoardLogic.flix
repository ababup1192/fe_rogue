// BoardLogic のテスト
//
// 盤面（マップ + 駒の位置）から「次の手」を計算するロジックを公開 API
// `BoardLogic.tryMove` 経由で検証する。Board を直接合成して任意の盤面を作る。
//
// `BoardLogic.isWalkable` / `BoardLogic.stepTarget` は委譲だけの 1 行関数なので
// ここではテストしない（`tryMove` 経由で間接的にカバーされる）。

mod TestBoardLogic {

    // ========================================================================
    // ヘルパー — 盤面 fixture と Option アダプタ
    // ========================================================================

    /// テスト用 tileSize（実機と同じ 16px 正方形）
    def testTileSize(): Float64 = 16.0

    /// グリッド座標 → タイル中心ピクセル座標
    def testGridToWorld(c: Vec2.Vec2i): Vec2.Vec2 =
        let s = testTileSize();
        let v = Vec2.fromI(c);
        {x = v#x * s + s / 2.0, y = v#y * s + s / 2.0}

    /// w×h サイズの盤面で、全マス床。範囲外は壁扱い。
    def emptySnapshot(w: Int32, h: Int32): MapSnapshot =
        let inB = c -> c#x >= 0 and c#x < w and c#y >= 0 and c#y < h;
        {
            tileSize    = testTileSize(),
            usedRect    = {position = Vec2.zeroI(), size = ({x = w, y = h}: Vec2.Vec2i)},
            isWall      = c -> not inB(c),
            isFloor     = c -> inB(c),
            mapToLocal  = c -> testGridToWorld(c),
            gridToWorld = c -> testGridToWorld(c)
        }

    /// w×h サイズの盤面で、wall の 1 マスだけ壁、ほかは床。範囲外も壁扱い。
    def floorSnapshotWithWall(w: Int32, h: Int32, wall: Vec2.Vec2i): MapSnapshot =
        let inB = c -> c#x >= 0 and c#x < w and c#y >= 0 and c#y < h;
        let isW = c -> c#x == wall#x and c#y == wall#y;
        {
            tileSize    = testTileSize(),
            usedRect    = {position = Vec2.zeroI(), size = ({x = w, y = h}: Vec2.Vec2i)},
            isWall      = c -> not inB(c) or isW(c),
            isFloor     = c -> inB(c) and not isW(c),
            mapToLocal  = c -> testGridToWorld(c),
            gridToWorld = c -> testGridToWorld(c)
        }

    /// snapshot と Player 位置から Board を組む
    def boardWithPlayer(snapshot: MapSnapshot, player: Vec2.Vec2i): Board =
        {
            map    = snapshot,
            pieces = (Piece.Player, player) :: Nil
        }

    /// Option[Vec2i] を assertEq 用の tuple に変換
    /// (None → (false, 0, 0)、Some → (true, x, y))
    def unpackOption(o: Option[Vec2.Vec2i]): (Bool, Int32, Int32) =
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
        let board = boardWithPlayer(emptySnapshot(5, 5), ({x = 2, y = 2}: Vec2.Vec2i));
        let result = BoardLogic.tryMove(board, Vec2.rightI());
        Assert.assertEq(expected = (true, 3, 2), unpackOption(result))

    /// 進行先 (3, 2) が壁なら None
    @Test
    def testTryMoveBlockedByWall(): Unit \ Assert =
        let snapshot = floorSnapshotWithWall(5, 5, ({x = 3, y = 2}: Vec2.Vec2i));
        let board = boardWithPlayer(snapshot, ({x = 2, y = 2}: Vec2.Vec2i));
        let result = BoardLogic.tryMove(board, Vec2.rightI());
        Assert.assertEq(expected = (false, 0, 0), unpackOption(result))

    /// 盤面の端 (0, 0) から外（左）に出ようとすると None
    @Test
    def testTryMoveBlockedAtEdge(): Unit \ Assert =
        let board = boardWithPlayer(emptySnapshot(5, 5), ({x = 0, y = 0}: Vec2.Vec2i));
        let result = BoardLogic.tryMove(board, Vec2.leftI());
        Assert.assertEq(expected = (false, 0, 0), unpackOption(result))

    /// 右が壁でも下方向は開いている → 別方向には進める
    @Test
    def testTryMovePicksOpenDirection(): Unit \ Assert =
        let snapshot = floorSnapshotWithWall(5, 5, ({x = 3, y = 2}: Vec2.Vec2i));
        let board = boardWithPlayer(snapshot, ({x = 2, y = 2}: Vec2.Vec2i));
        let resultRight = BoardLogic.tryMove(board, Vec2.rightI());
        let resultDown  = BoardLogic.tryMove(board, Vec2.downI());
        Assert.assertEq(
            expected = ((false, 0, 0), (true, 2, 3)),
            (unpackOption(resultRight), unpackOption(resultDown)))

    /// pieces に Player がいない Board では tryMove が None を返す
    @Test
    def testTryMoveWithoutPlayer(): Unit \ Assert =
        let board: Board = {
            map    = emptySnapshot(5, 5),
            pieces = Nil
        };
        let result = BoardLogic.tryMove(board, Vec2.rightI());
        Assert.assertEq(expected = (false, 0, 0), unpackOption(result))
}
