// CameraRig の単体テスト: 揺れ幅の二乗則・滑らかノイズの格子点一致・恒等カメラを具体値で固定する。
mod TestCameraRig {

    // trauma は二乗で効く: 満タン 1.0 で maxOffset、半分 0.5 で 1/4、ゼロは揺れない。
    @Test
    def testShakeStrengthIsQuadratic(): Unit \ Assert =
        Assert.assertEq(expected = (8.0, 2.0, 0.0),
            (CameraRig.shakeStrength(1.0, maxOffset = 8.0),
             CameraRig.shakeStrength(0.5, maxOffset = 8.0),
             CameraRig.shakeStrength(0.0, maxOffset = 8.0)))

    // 滑らかノイズは格子点（整数 t）でちょうど Hash01 の値に一致し（フェード 0）、
    // 格子点の中間でも [-1, 1] に収まる。oracle は Hash01（別関数）。
    @Test
    def testSmoothNoiseAnchorsAtLattice(): Unit \ Assert =
        let anchor3 = CameraRig.smoothNoise(3.0, 0) == 2.0 * Hash01.at(3, 0) - 1.0;
        let anchor7 = CameraRig.smoothNoise(7.0, 1) == 2.0 * Hash01.at(7, 1) - 1.0;
        let mid = CameraRig.smoothNoise(3.5, 0);
        let midBounded = mid >= -1.0 and mid <= 1.0;
        Assert.assertEq(expected = (true, true, true), (anchor3, anchor7, midBounded))

    /// テスト用の調整値。
    def spec(): CameraRig.ShakeSpec = { maxOffset = 8.0, freq = 25.0, decayPerSecond = 1.5 }

    /// 小数 4 桁に丸める（2 進で表せない加算の比較用）。
    def round4(x: Float64): Float64 = Float64.floor(x * 10000.0 + 0.5) / 10000.0

    // 恒等カメラは動かず、trauma 0 のシェイクは揺れない。
    @Test
    def testFixedCameraAndZeroTraumaAreStill(): Unit \ Assert =
        let fixedCam = CameraRig.fixed();
        let still = CameraRig.shakeOffset(spec(), { trauma = 0.0, fxClock = 5.0 });
        Assert.assertEq(expected = (0.0, 0.0, 0.0, 0.0),
            (fixedCam#offset#x, fixedCam#offset#y, still#x, still#y))

    // trauma 満タンのオフセットは揺れ幅（maxOffset）の中に収まる。
    @Test
    def testShakeOffsetIsBounded(): Unit \ Assert =
        let offset = CameraRig.shakeOffset(spec(), { trauma = 1.0, fxClock = 1.25 });
        Assert.assertEq(expected = (true, true),
            (Float64.abs(offset#x) <= 8.0, Float64.abs(offset#y) <= 8.0))

    // 積むと蓄積し（0.3 + 0.45 = 0.75）、上限 1.0 でクランプされる（0.7 + 0.7 → 1.0）。
    // record は丸ごと渡せて、揺れ以外のフィールド（score）は素通しされる。
    @Test
    def testAddTraumaAccumulatesAndClamps(): Unit \ Assert =
        let base = { trauma = 0.0, score = 42 };
        let stacked = base |> CameraRig.addTrauma(0.3) |> CameraRig.addTrauma(0.45);
        let capped = base |> CameraRig.addTrauma(0.7) |> CameraRig.addTrauma(0.7);
        Assert.assertEq(expected = (0.75, 1.0, 42),
            (round4(stacked#trauma), capped#trauma, stacked#score))

    // tick は trauma を decay×dt だけ減らし（下限 0.0）、fxClock を dt だけ進める。
    @Test
    def testTickDecaysAndAdvancesClock(): Unit \ Assert =
        let ticked = CameraRig.tick(0.5, spec(), { trauma = 1.0, fxClock = 2.0 });
        let floored = CameraRig.tick(0.5, spec(), { trauma = 0.1, fxClock = 0.0 });
        Assert.assertEq(expected = (0.25, 2.5, 0.0, 0.5),
            (ticked#trauma, ticked#fxClock, floored#trauma, floored#fxClock))

    /// 追従テスト用の仕様: 不感帯 40px・寄せ率 8/s。
    def follow(): CameraRig.Follow = { deadzone = 40.0, k = 8.0 }

    // 不感帯の中（±40px 以内）では動かない。帯の両端ぎりぎりも 0。
    @Test
    def testFollowDeltaHoldsInsideDeadzone(): Unit \ Assert =
        Assert.assertEq(expected = (0.0, 0.0, 0.0),
            (CameraRig.followDelta(follow(), 0.25, 100.0, 100.0),
             CameraRig.followDelta(follow(), 0.25, 140.0, 100.0),
             CameraRig.followDelta(follow(), 0.25, 60.0, 100.0)))

    // 帯を出たぶん × min(1, k×dt) の移動量。dt=1/8 で係数 1.0 → 出たぶん全部（±60）。
    // k×dt が 1 を超えても行き過ぎない（min で 1.0 に頭打ち）。
    @Test
    def testFollowDeltaMovesByExcess(): Unit \ Assert =
        Assert.assertEq(expected = (60.0, -60.0, 60.0),
            (CameraRig.followDelta(follow(), 0.125, 200.0, 100.0),
             CameraRig.followDelta(follow(), 0.125, 0.0, 100.0),
             CameraRig.followDelta(follow(), 5.0, 200.0, 100.0)))

    // clampAxis は lo..hi へ収め、hi < lo（レベルが 1 画面ぶんしか無い）なら lo に張り付く。
    @Test
    def testClampAxisEdges(): Unit \ Assert =
        Assert.assertEq(expected = (0.0, 960.0, 5.0, 0.0),
            (CameraRig.clampAxis(0.0, 960.0, -10.0),
             CameraRig.clampAxis(0.0, 960.0, 1000.0),
             CameraRig.clampAxis(0.0, 960.0, 5.0),
             CameraRig.clampAxis(0.0, -160.0, 100.0)))

    // ========================================================================
    // 中央映し: centerOffset / centerOn / toWorldPos / visibleRect
    // ========================================================================

    // center (100,50) を 320×240 の中央に映すずらし量は (60, 70)。
    @Test
    def testCenterOffsetMovesCenterToMiddle(): Unit \ Assert =
        let off = CameraRig.centerOffset({ x = 100.0, y = 50.0 }, design = { x = 320.0, y = 240.0 });
        Assert.assertEq(expected = (60.0, 70.0), (off#x, off#y))

    // centerOn: center に置いた item は画面中央 (design/2) に着地する。
    @Test
    def testCenterOnLandsCenterAtMiddle(): Unit \ Assert =
        let center = { x = 100.0, y = 50.0 };
        let item = { at = center, item = Render.box({ x = 1.0, y = 1.0 }, red(), 0) };
        let moved = CameraRig.centerOn(center, design = { x = 320.0, y = 240.0 }, item :: Nil);
        Assert.assertEq(expected = Some((160.0, 120.0)),
            List.head(moved) |> Option.map(p -> (p#at#x, p#at#y)))

    // toWorldPos は centerOn と互いに逆: 画面中央を world に戻すと center そのもの。
    @Test
    def testToWorldPosInvertsCenterOn(): Unit \ Assert =
        let center = { x = 100.0, y = 50.0 };
        let back = CameraRig.toWorldPos(center, design = { x = 320.0, y = 240.0 },
                                        screen = { x = 160.0, y = 120.0 });
        Assert.assertEq(expected = (100.0, 50.0), (back#x, back#y))

    // visibleRect は center を中央にした design サイズの矩形（左上 = center - design/2）。
    @Test
    def testVisibleRectSurroundsCenter(): Unit \ Assert =
        let r = CameraRig.visibleRect({ x = 100.0, y = 50.0 }, design = { x = 320.0, y = 240.0 });
        Assert.assertEq(expected = (-60.0, -70.0, 320.0, 240.0),
            (r#position#x, r#position#y, r#size#x, r#size#y))

    def red(): Color = { r = 1.0f32, g = 0.0f32, b = 0.0f32 }
}
