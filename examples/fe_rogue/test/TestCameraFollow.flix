/// CameraState の追従数式（`step` / `reachedTarget`）のテスト。
///
/// 検証する観点:
///   - スムージング lerp が `speed × delta` を t として現在位置を logical へ寄せる
///   - `speed × delta > 1` で t が 1 に夾着し overshoot しない
///   - ドラッグ余白の内側では位置が動かず、外側では余白境界まで追従する
///   - スクロール制限が位置を矩形にハードクランプする
///   - reachedTarget がドラッグ余白の幾何から「追いついた」を判定する
///
/// 追従パラメータは CameraState の実値（speed 5 / margin 0.3 / limit ±999999）を使う。
/// zoom は計算を素直にするため 1 とする（step は zoom 一般で動く）。
mod TestCameraFollow {

    /// Float64 の許容誤差比較（lerp は浮動小数なので厳密一致不可）
    def approx(a: Float64, b: Float64): Bool =
        let diff = a - b;
        let d = if (diff < 0.0) -1.0 * diff else diff;
        d < 0.0001

    def vp200x100(): CameraState.Viewport =
        {viewportWidth = 200.0, viewportHeight = 100.0}

    /// 現在位置 pos・zoom 1 のカメラ
    def camAt(pos: Vec2.Vec2): Camera =
        Camera.make(pos) |> Camera.setZoom({x = 1.0, y = 1.0})

    def posOf(camera: Camera): Vec2.Vec2 =
        Camera.transform(camera)#position

    // ── スムージング ──

    /// speed 5, dt 0.05 → t = 0.25。current 0 から target 10（ドラッグ切）へ 0.25 lerp で 2.5
    @Test
    def testSmoothingPartialLerp(): Unit \ Assert =
        let result = CameraState.step(camAt({x = 0.0, y = 0.0}), {x = 10.0, y = 0.0},
                                      false, 0.05 |> Duration.seconds, vp200x100());
        Assert.assertEq(expected = true, approx(posOf(result)#x, 2.5))

    /// dt 1.0 で t = 5 → 1 に夾着 → 完全追従で target に一致（overshoot しない）
    @Test
    def testSmoothingClampsAtOne(): Unit \ Assert =
        let result = CameraState.step(camAt({x = 0.0, y = 0.0}), {x = 10.0, y = 0.0},
                                      false, 1.0 |> Duration.seconds, vp200x100());
        Assert.assertEq(expected = true, approx(posOf(result)#x, 10.0))

    // ── ドラッグ余白 ──

    /// ドラッグ有効、target が余白内 → 位置不変。
    /// viewport 200, zoom 1, margin 0.3 → 右余白 = 100 × 0.3 = 30。target 28 は 30 以内。
    @Test
    def testDragMarginInsideKeepsCamera(): Unit \ Assert =
        let result = CameraState.step(camAt({x = 0.0, y = 0.0}), {x = 28.0, y = 0.0},
                                      true, 1.0 |> Duration.seconds, vp200x100());
        Assert.assertEq(expected = true, approx(posOf(result)#x, 0.0))

    /// ドラッグ有効、target が余白を超える → 余白境界まで追従。
    /// margin 30、target 50 → logical = 50 - 30 = 20。dt 1.0 で t=1 なので位置 = 20。
    @Test
    def testDragMarginOutsideFollowsToBoundary(): Unit \ Assert =
        let result = CameraState.step(camAt({x = 0.0, y = 0.0}), {x = 50.0, y = 0.0},
                                      true, 1.0 |> Duration.seconds, vp200x100());
        Assert.assertEq(expected = true, approx(posOf(result)#x, 20.0))

    /// 縦軸も同様。viewport 100 → 半高 50、margin 0.3 → 15。target 40 → logical = 40 - 15 = 25。
    @Test
    def testDragMarginVerticalAxis(): Unit \ Assert =
        let result = CameraState.step(camAt({x = 0.0, y = 0.0}), {x = 0.0, y = 40.0},
                                      true, 1.0 |> Duration.seconds, vp200x100());
        Assert.assertEq(expected = true, approx(posOf(result)#y, 25.0))

    // ── スクロール制限 ──

    /// target が limitMax(999999) を超えても位置はそこで止まる
    @Test
    def testLimitClampsRight(): Unit \ Assert =
        let result = CameraState.step(camAt({x = 0.0, y = 0.0}), {x = 2000000.0, y = 0.0},
                                      false, 1.0 |> Duration.seconds, vp200x100());
        Assert.assertEq(expected = true, approx(posOf(result)#x, 999999.0))

    /// target が limitMin(-999999) を下回っても位置はそこで止まる
    @Test
    def testLimitClampsLeft(): Unit \ Assert =
        let result = CameraState.step(camAt({x = 0.0, y = 0.0}), {x = -2000000.0, y = 0.0},
                                      false, 1.0 |> Duration.seconds, vp200x100());
        Assert.assertEq(expected = true, approx(posOf(result)#x, -999999.0))

    // ── reachedTarget（追従完了判定）──

    /// ドラッグ無効、target = current → 0 px 差で true（threshold 4px 以内）
    @Test
    def testReachedWithoutDragAtSamePos(): Unit \ Assert =
        Assert.assertEq(expected = true,
            CameraState.reachedTarget(camAt({x = 0.0, y = 0.0}), {x = 0.0, y = 0.0},
                                      false, vp200x100()))

    /// ドラッグ無効、target が 5 px 離れる → 4 px 超えで false
    @Test
    def testReachedWithoutDragRejectsBeyondEpsilon(): Unit \ Assert =
        Assert.assertEq(expected = false,
            CameraState.reachedTarget(camAt({x = 0.0, y = 0.0}), {x = 5.0, y = 0.0},
                                      false, vp200x100()))

    /// ドラッグ有効、余白 30 + buffer 2 = 32。target 28 は dead zone 内 → true
    @Test
    def testReachedWithDragWithinMargin(): Unit \ Assert =
        Assert.assertEq(expected = true,
            CameraState.reachedTarget(camAt({x = 0.0, y = 0.0}), {x = 28.0, y = 0.0},
                                      true, vp200x100()))

    /// ドラッグ有効、dead zone 32。target 50 は超え → false
    @Test
    def testReachedWithDragRejectsBeyondMargin(): Unit \ Assert =
        Assert.assertEq(expected = false,
            CameraState.reachedTarget(camAt({x = 0.0, y = 0.0}), {x = 50.0, y = 0.0},
                                      true, vp200x100()))

    /// 大移動でも step を回せば dead zone 内に収束する（フリーズ修正の核挙動の pin）。
    /// target 100、margin 30 → logical 70、dt 1.0 で位置 70。reachedTarget は |100-70|=30 <= 32 で true
    @Test
    def testReachedAfterConvergence(): Unit \ Assert =
        let result = CameraState.step(camAt({x = 0.0, y = 0.0}), {x = 100.0, y = 0.0},
                                      true, 1.0 |> Duration.seconds, vp200x100());
        Assert.assertEq(expected = true,
            CameraState.reachedTarget(result, {x = 100.0, y = 0.0}, true, vp200x100()))
}
