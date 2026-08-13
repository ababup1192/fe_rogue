// Persp（2.5D の投影数学）— 分解・除算・近クリップ・逆投影が幾何として正しいこと。
mod TestPersp {

    def cam(): Persp.Camera = { pos = { x = 0.0, y = 0.0 }, yaw = 0.0 }

    def proj(): Persp.Projection = { center = { x = 240.0, y = 150.0 }, fx = 240.0, fy = 150.0 }

    def near(a: Float64, b: Float64): Bool = Float64.abs(a - b) < 0.0001

    @Test
    def testToCamAheadIsPureFwd(): Unit \ Assert =
        // yaw 0 = +x。真正面の点は fwd だけを持ち、lat は 0。
        let c = Persp.toCam(cam(), { x = 3.0, y = 0.0 });
        Assert.assertEq(expected = (true, true), (near(c#fwd, 3.0), near(c#lat, 0.0)))

    @Test
    def testToCamFollowsYaw(): Unit \ Assert =
        // カメラが +y を向けば、+y の点が真正面になる（本当に回っている）。
        let c = Persp.toCam({ pos = { x = 0.0, y = 0.0 }, yaw = 1.5707963267948966 }, { x = 0.0, y = 2.0 });
        Assert.assertEq(expected = (true, true), (near(c#fwd, 2.0), near(c#lat, 0.0)))

    @Test
    def testScreenXCentersStraightAhead(): Unit \ Assert =
        // lat 0 の点は消失点の真上の縦線（x = center.x）に落ちる。
        Assert.assertEq(expected = true,
            near(Persp.screenX(proj(), { fwd = 2.0, lat = 0.0 }), 240.0))

    @Test
    def testFartherLooksSmaller(): Unit \ Assert =
        // 同じ h でも fwd が大きいほど消失点に寄る（透視の要）。
        let nearY = Persp.screenY(proj(), 0.5, { fwd = 1.0, lat = 0.0 });
        let farY = Persp.screenY(proj(), 0.5, { fwd = 4.0, lat = 0.0 });
        Assert.assertEq(expected = true, farY < nearY)

    @Test
    def testSizeAtMatchesScreenYSpan(): Unit \ Assert =
        // 高さ 1 のストリップを screenY で上下に落とした幅と、sizeAt の換算が一致する
        // （同じ fy / fwd の式であることの裏取り）。
        let c = { fwd = 2.5, lat = 0.8 };
        let span = Persp.screenY(proj(), 0.5, c) - Persp.screenY(proj(), -0.5, c);
        Assert.assertEq(expected = true, near(Persp.sizeAt(proj(), 1.0, c), span))

    @Test
    def testSizeAtHalvesWhenTwiceAsFar(): Unit \ Assert =
        // 奥行きが 2 倍なら見た目は半分（透視除算の要）。
        let atNear = Persp.sizeAt(proj(), 1.0, { fwd = 1.5, lat = 0.0 });
        let atFar = Persp.sizeAt(proj(), 1.0, { fwd = 3.0, lat = 0.0 });
        Assert.assertEq(expected = true, near(atFar, atNear / 2.0))

    @Test
    def testClipSegmentDropsFullyBehind(): Unit \ Assert =
        Assert.assertEq(expected = true,
            Option.isEmpty(Persp.clipSegment(0.08, { fwd = -1.0, lat = 0.0 }, { fwd = 0.02, lat = 1.0 })))

    @Test
    def testClipSegmentCutsAtNearPlane(): Unit \ Assert =
        // 後方の端点は near 面ちょうどまで切り詰められ、前方の端点は残る。
        let clipped = Persp.clipSegment(0.08, { fwd = -1.0, lat = 0.0 }, { fwd = 1.0, lat = 0.0 })
            |> Option.getWithDefault({ camA = { fwd = 0.0, lat = 0.0 }, camB = { fwd = 0.0, lat = 0.0 },
                                       t0 = -1.0, t1 = -1.0, dist = -1.0 });
        Assert.assertEq(expected = (true, true, true),
            (near(clipped#camA#fwd, 0.08), near(clipped#camB#fwd, 1.0), near(clipped#t1, 1.0)))

    @Test
    def testStripCornersKeepVerticalEdges(): Unit \ Assert =
        // 同じ端点の上下は同じ x（壁の縦の辺が歪まない保証）。
        let corners = Persp.stripCorners(proj(), { hTop = -0.5, hBot = 0.5 },
            { fwd = 1.2, lat = -0.7 }, { fwd = 3.4, lat = 0.9 });
        Assert.assertEq(expected = (true, true),
            (near(corners#topA#x, corners#botA#x), near(corners#topB#x, corners#botB#x)))

    @Test
    def testDepthAtYInvertsScreenY(): Unit \ Assert =
        // screenY で落とした走査線を depthAtY で戻すと元の奥行きに帰る。
        let sy = Persp.screenY(proj(), 0.5, { fwd = 2.5, lat = 0.0 });
        Assert.assertEq(expected = true, near(Persp.depthAtY(proj(), 0.5, sy), 2.5))

    @Test
    def testFogAmountStopsAtCap(): Unit \ Assert =
        // 遠くても cap で止まる（完全には沈まない）。
        Assert.assertEq(expected = true,
            near(Persp.fogAmount({ base = 0.2, perDist = 0.2, cap = 0.9 }, 100.0), 0.9))
}
