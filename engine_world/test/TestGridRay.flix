// GridRay（見通しの遮蔽・DDA）— 間に壁があると blocked、何も無ければ通ること、
// ignore 述語に当たるマスは遮蔽と数えないこと、線分が通過するマスを DDA が
// 漏れなく拾うこと（軸平行・対角・薄いかすめ・同一マス）。
mod TestGridRay {

    // ---- 元からの意味（間に壁 / 素通し / ignore） ----

    @Test
    def testWallBetweenBlocksSight(): Unit \ Assert =
        // (0,0) → (4,0) の途中 (2,0) が壁なら遮られる。
        let solid = c -> c#x == 2 and c#y == 0;
        Assert.assertEq(expected = true,
            GridRay.blocked(solid, _ -> false, { x = 0.0, y = 0.0 }, { x = 4.0, y = 0.0 }))

    @Test
    def testEmptyCorridorIsClear(): Unit \ Assert =
        // 壁が 1 つも無ければ通る。
        Assert.assertEq(expected = false,
            GridRay.blocked(_ -> false, _ -> false, { x = 0.0, y = 0.0 }, { x = 4.0, y = 0.0 }))

    @Test
    def testIgnoredCellDoesNotBlock(): Unit \ Assert =
        // 途中の壁でも ignore 述語に当たれば遮蔽と数えない。
        let solid = c -> c#x == 2 and c#y == 0;
        Assert.assertEq(expected = false,
            GridRay.blocked(solid, c -> c#x == 2 and c#y == 0,
                { x = 0.0, y = 0.0 }, { x = 4.0, y = 0.0 }))

    @Test
    def testGoalWallCellBlocksWithoutIgnore(): Unit \ Assert =
        // goal のマス自身も数える — 壁マスに掛かる物を見たいなら ignore で除くのが決まり。
        let solid = c -> c#x == 4 and c#y == 0;
        Assert.assertEq(expected = true,
            GridRay.blocked(solid, _ -> false, { x = 0.0, y = 0.0 }, { x = 4.0, y = 0.0 }))

    @Test
    def testGoalWallCellClearsWithIgnore(): Unit \ Assert =
        // goal が壁掛け（松明など）のとき、その壁マスを ignore で除けば見通せる。
        let solid = c -> c#x == 4 and c#y == 0;
        Assert.assertEq(expected = false,
            GridRay.blocked(solid, c -> c#x == 4 and c#y == 0,
                { x = 0.0, y = 0.0 }, { x = 4.0, y = 0.0 }))

    // ---- DDA が正確になるケース ----

    @Test
    def testAxisParallelVerticalBlocked(): Unit \ Assert =
        // 縦一直線 (1,0) → (1,4) の途中 (1,2) が壁なら遮られる。
        let solid = c -> c#x == 1 and c#y == 2;
        Assert.assertEq(expected = true,
            GridRay.blocked(solid, _ -> false, { x = 1.0, y = 0.0 }, { x = 1.0, y = 4.0 }))

    @Test
    def testDiagonalCornerStepsXFirst(): Unit \ Assert =
        // 真対角 (0,0) → (2,2) はマスの角をちょうど通る。タイブレークは x 側が先
        // なので、通り道は (0,0)→(1,0)→(1,1)→(2,1)→(2,2)。(1,0) の壁は遮る。
        let solid = c -> c#x == 1 and c#y == 0;
        Assert.assertEq(expected = true,
            GridRay.blocked(solid, _ -> false, { x = 0.0, y = 0.0 }, { x = 2.0, y = 2.0 }))

    @Test
    def testDiagonalCornerSkipsYSide(): Unit \ Assert =
        // 同じ真対角でも y 側の (0,1) は通り道に入らない（タイブレークの決定性）。
        let solid = c -> c#x == 0 and c#y == 1;
        Assert.assertEq(expected = false,
            GridRay.blocked(solid, _ -> false, { x = 0.0, y = 0.0 }, { x = 2.0, y = 2.0 }))

    @Test
    def testThinGrazeIsCaught(): Unit \ Assert =
        // (0,0) → (2,1.9) は (1,0) のマスの角をごく薄くかすめる
        // （線分の 1.3% ほどしか通らない — 0.1 刻みの標本では拾い損ねうる幅）。
        let solid = c -> c#x == 1 and c#y == 0;
        Assert.assertEq(expected = true,
            GridRay.blocked(solid, _ -> false, { x = 0.0, y = 0.0 }, { x = 2.0, y = 1.9 }))

    @Test
    def testNegativeDirectionBlocked(): Unit \ Assert =
        // 逆向き (4,0) → (0,0) でも途中 (2,0) の壁は遮る（横断は向きに依らない）。
        let solid = c -> c#x == 2 and c#y == 0;
        Assert.assertEq(expected = true,
            GridRay.blocked(solid, _ -> false, { x = 4.0, y = 0.0 }, { x = 0.0, y = 0.0 }))

    @Test
    def testStartWallCellBlocks(): Unit \ Assert =
        // start のマス自身も数える — 壁の中から歩き出す線分は最初から遮られている。
        let solid = c -> c#x == 0 and c#y == 0;
        Assert.assertEq(expected = true,
            GridRay.blocked(solid, _ -> false, { x = 0.0, y = 0.0 }, { x = 3.0, y = 0.0 }))

    @Test
    def testBoundaryStartBelongsToPlusSide(): Unit \ Assert =
        // 境界 ±0.5 ちょうどの start は + 側のマスから歩き出す：x = 1.5 はセル 1 と 2 の
        // 境界だがセル (2,0) に属するので、(1,0) の壁は通り道に入らず見通せる
        // （− 側に属するなら start マスの壁として即遮られるはず）。
        let solid = c -> c#x == 1 and c#y == 0;
        Assert.assertEq(expected = false,
            GridRay.blocked(solid, _ -> false, { x = 1.5, y = 0.0 }, { x = 4.0, y = 0.0 }))

    @Test
    def testSameCellIsClear(): Unit \ Assert =
        // start と goal が同じマスなら、よそに壁があっても遮られない。
        let solid = c -> c#x == 1 and c#y == 0;
        Assert.assertEq(expected = false,
            GridRay.blocked(solid, _ -> false, { x = 0.2, y = 0.1 }, { x = -0.2, y = 0.3 }))
}
