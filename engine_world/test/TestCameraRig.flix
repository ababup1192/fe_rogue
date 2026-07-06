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
}
