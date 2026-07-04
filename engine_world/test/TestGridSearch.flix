// GridSearch のテスト。玩具盤で reachable / distances / manhattanRing の具体値を pin し、
// canEnter 述語で政策（壁・盤外）を注入すると探索が避けることを確認する。
// セルは (Int32, Int32) タプルなので Eq/ToString が付き、リストや Option をそのまま比較できる。

mod TestGridSearch {

    /// maxSteps=0 なら start 自身だけが返る（0 歩）。
    @Test
    def testReachableZeroSteps(): Unit \ Assert =
        Assert.assertEq(expected = (0, 0) :: Nil,
            GridSearch.reachable(_ -> true, (0, 0), 0))

    /// distances の maxSteps=0 は「canEnter を満たす sources だけが 0 歩で載る」
    /// （reachable と同じ端）。進入不可の source は 0 歩でも載らない。
    @Test
    def testDistancesZeroStepsSeedsOnly(): Unit \ Assert =
        let field = GridSearch.distances(c -> c != (5, 5), (0, 0) :: (5, 5) :: Nil, 0);
        Assert.assertEq(expected = Map#{(0, 0) => 0}, field)

    /// 訪問順は start → 近傍（上→下→左→右）の決定的順。開けた盤で maxSteps=1 を丸ごと pin。
    @Test
    def testReachableOrderOneStep(): Unit \ Assert =
        Assert.assertEq(
            expected = (0, 0) :: (0, -1) :: (0, 1) :: (-1, 0) :: (1, 0) :: Nil,
            GridSearch.reachable(_ -> true, (0, 0), 1))

    /// 開けた盤で maxSteps=2 の到達数はマンハッタン距離 ≤ 2 の 13 マス（1+4+8）。
    @Test
    def testReachableOpenTwoSteps(): Unit \ Assert =
        Assert.assertEq(expected = 13,
            List.length(GridSearch.reachable(_ -> true, (0, 0), 2)))

    /// canEnter で壁 (1,0) を塞ぐと、直進 2 歩の (2,0) は迂回（4 歩）が要るので 2 歩では届かない。
    /// start 自身は canEnter に関わらず含まれる（出発点はいつでも居られる）。
    @Test
    def testReachableWallBlocksWithinBudget(): Unit \ Assert =
        let canEnter = c -> c != (1, 0);
        let cells = GridSearch.reachable(canEnter, (0, 0), 2);
        Assert.assertEq(expected = (true, false),
            (List.memberOf((0, 0), cells), List.memberOf((2, 0), cells)))

    /// 壁で迂回が強制されると距離場の値はマンハッタンより大きい（真の経路歩数）。
    /// (1,1) だけ壁。源 (0,1) から (2,1) は直線 2 だが壁を回って 4 歩。源自身は 0。
    @Test
    def testDistancesDetourGreaterThanManhattan(): Unit \ Assert =
        let field = GridSearch.distances(c -> c != (1, 1), (0, 1) :: Nil, 64);
        Assert.assertEq(expected = (Some(0), Some(4)),
            (Map.get((0, 1), field), Map.get((2, 1), field)))

    /// 政策注入で分断されたマスは距離場に載らない（= ∞）。3×1 盤・(1,0) が壁で (2,0) は到達不能。
    /// canEnter が「盤内かつ非壁」の両方を担い、探索がそれを尊重することを確認する。
    @Test
    def testDistancesDisconnectedIsAbsent(): Unit \ Assert =
        let canEnter = c -> Grid.inRect(c, 3, 1) and c != (1, 0);
        let field = GridSearch.distances(canEnter, (0, 0) :: Nil, 64);
        Assert.assertEq(expected = (Some(0), None),
            (Map.get((0, 0), field), Map.get((2, 0), field)))

    /// 多始点: 2 つの源から塗ると各マスは近い方の源までの歩数になる（1 直線 5 マス）。
    @Test
    def testDistancesMultiSource(): Unit \ Assert =
        let field = GridSearch.distances(_ -> true, (0, 0) :: (4, 0) :: Nil, 64);
        Assert.assertEq(expected = (Some(0), Some(2), Some(0)),
            (Map.get((0, 0), field), Map.get((2, 0), field), Map.get((4, 0), field)))

    /// manhattanDistance は |dx|+|dy|。
    @Test
    def testManhattanDistance(): Unit \ Assert =
        Assert.assertEq(expected = 5, GridSearch.manhattanDistance((1, 2), (3, -1)))

    /// 距離ちょうど 1 の環は上下左右の 4 マスで、中心は含まない。
    @Test
    def testManhattanRingOne(): Unit \ Assert =
        let ring = GridSearch.manhattanRing((0, 0), 1, 1);
        Assert.assertEq(expected = (4, true, false),
            (List.length(ring), List.memberOf((1, 0), ring), List.memberOf((0, 0), ring)))

    /// 距離ちょうど 2 の環は 8 マスで斜め (1,1) を含む。中心をずらすと全マスが平行移動する。
    @Test
    def testManhattanRingTwoOffset(): Unit \ Assert =
        let ring = GridSearch.manhattanRing((5, 5), 2, 2);
        Assert.assertEq(expected = (8, true, true),
            (List.length(ring), List.memberOf((6, 6), ring), List.memberOf((5, 3), ring)))

    /// minR > maxR は空の環。
    @Test
    def testManhattanRingEmpty(): Unit \ Assert =
        Assert.assertEq(expected = true, List.isEmpty(GridSearch.manhattanRing((0, 0), 3, 1)))
}
