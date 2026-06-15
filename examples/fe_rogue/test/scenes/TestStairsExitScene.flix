/// StairsExitScene の純粋ロジック（`decideStep` / `eligibleExiters`）のテスト
///
/// 「階段で離脱」の判定を Scene / effect を使わず値だけで検証する。
///   - decideStep: 先頭1体の次手（Finalize / Exit / StepTo / Skip）。
///   - eligibleExiters: 残り移動で階段に届く id を「階段に近い順・同距離 id 昇順」で返す。
///     味方は透過、敵・壁は障害物。
mod TestStairsExitScene {

    use StairsExitScene.StepDecision

    /// 全マス床の w×h 盤面。範囲外は壁扱い。
    def emptySnapshot(w: Int32, h: Int32): MapSnapshot =
        {
            tileSize   = 16.0,
            usedRect   = {position = {x = 0, y = 0}, size = ({x = w, y = h}: {x = Int32, y = Int32})},
            wallCells  = (Set#{}: Set[(Int32, Int32)]),
            mapGlobal  = {x = 0.0, y = 0.0},
            placements = Nil
        }

    def boardWith(snapshot: MapSnapshot,
                   pieces: List[(Piece, {x = Int32, y = Int32})]): Board =
        {map = snapshot, pieces = pieces}

    // ========================================================================
    // decideStep — 先頭1体の次手
    // ========================================================================

    /// 空キュー→Finalize、階段上→Exit、移動力切れ→Stop、空きマスへ→StepTo、前進不可→Skip。
    /// キューは (id, 残り移動) のペア列。5 ケースをまとめて確認。
    @Test
    def testDecideStepCases(): Unit \ Assert =
        Assert.assertEq(
            expected = (StepDecision.Finalize, StepDecision.Exit(1), StepDecision.Stop(1),
                        StepDecision.StepTo(1, 1, 0), StepDecision.Skip(1)),
            (StairsExitScene.decideStep(Nil, {x = 0, y = 0}, {x = 0, y = 0}, None),
             StairsExitScene.decideStep((1, 5) :: Nil, {x = 2, y = 3}, {x = 2, y = 3}, None),
             StairsExitScene.decideStep((1, 0) :: Nil, {x = 0, y = 0}, {x = 3, y = 0}, Some({x = 1, y = 0})),
             StairsExitScene.decideStep((1, 5) :: Nil, {x = 0, y = 0}, {x = 3, y = 0}, Some({x = 1, y = 0})),
             StairsExitScene.decideStep((1, 5) :: (2, 5) :: Nil, {x = 0, y = 0}, {x = 3, y = 0}, None)))

    // ========================================================================
    // eligibleExiters — 到達可能 id を階段に近い順で
    // ========================================================================

    /// 全員が残り移動内で階段(4,0)に届く → 近い順 [3,2,1]（距離 1,2,4）。
    @Test
    def testEligibleAllReachableNearestFirst(): Unit \ Assert =
        let board = boardWith(emptySnapshot(5, 1), Nil);
        let units = (1, {x = 0, y = 0}, 5) :: (2, {x = 2, y = 0}, 5) :: (3, {x = 3, y = 0}, 5) :: Nil;
        Assert.assertEq(
            expected = 3 :: 2 :: 1 :: Nil,
            StairsExitScene.eligibleExiters(board, {x = 4, y = 0}, units))

    /// 残り移動が足りない味方は除外。階段(5,0): id1 は距離5>3で除外、id2 は距離2<=3で採用。
    @Test
    def testEligibleExcludesOutOfRange(): Unit \ Assert =
        let board = boardWith(emptySnapshot(6, 1), Nil);
        let units = (1, {x = 0, y = 0}, 3) :: (2, {x = 3, y = 0}, 3) :: Nil;
        Assert.assertEq(
            expected = 2 :: Nil,
            StairsExitScene.eligibleExiters(board, {x = 5, y = 0}, units))

    /// 1 マス幅で敵(2,0)が経路を塞ぐと、後ろの味方(0,0)は階段(4,0)に到達できず除外。
    @Test
    def testEligibleBlockedByEnemy(): Unit \ Assert =
        let board = boardWith(emptySnapshot(5, 1),
            (Piece.Enemy(9), {x = 2, y = 0}) :: Nil);
        let units = (1, {x = 0, y = 0}, 10) :: Nil;
        Assert.assertEq(
            expected = (Nil: List[Int32]),
            StairsExitScene.eligibleExiters(board, {x = 4, y = 0}, units))

    // ========================================================================
    // exitQueue — 届かない味方も含めて (id, 残り移動) を階段に近い順で
    // ========================================================================

    /// 階段(4,0): id2(距離1)・id1(距離4)。届かない id1(残り2<4) も含め、近い順で残り移動付きで返す。
    @Test
    def testExitQueueIncludesUnreachableNearestFirst(): Unit \ Assert =
        let board = boardWith(emptySnapshot(5, 1), Nil);
        let units = (1, {x = 0, y = 0}, 2) :: (2, {x = 3, y = 0}, 5) :: Nil;
        Assert.assertEq(
            expected = (2, 5) :: (1, 2) :: Nil,
            StairsExitScene.exitQueue(board, {x = 4, y = 0}, units))
}
