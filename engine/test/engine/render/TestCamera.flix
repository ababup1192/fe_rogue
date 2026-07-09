/// Camera の追従処理 (`process`) のテスト
///
/// 検証する観点:
///   - smoothing 単純 lerp が `speed * delta` を t として position へ補間する
///   - smoothing 無効時は logical（drag margin 適用後）に即追従する
///   - drag margin 内に target が居るあいだは smoothPosition が動かない
///   - drag margin を target が超えたら margin 境界まで追従する
///   - limit clamp が smoothPosition を矩形にハードクランプする
///   - smoothing/drag 全無効時は `getViewTransform` が `globalPos`（= position）を使う
///
/// 数式の仕様:
///   - smoothing: `next = curr + (target - curr) * min(1, speed * delta)` （単純 lerp + 夾着クランプ）
///   - drag margin: 0.0..1.0 を viewport 半幅×倍率として world 単位で適用
///   - limit: hard clamp（`limitSmoothed = false` 相当）

mod TestCamera {

    // ════════════════════════════════════════════════════════
    // ヘルパー
    // ════════════════════════════════════════════════════════

    /// Float64 の許容誤差比較（smoothing は浮動小数の lerp なので厳密一致不可）
    def approx(a: Float64, b: Float64): Bool =
        let diff = a - b;
        let d = if (diff < 0.0) -1.0 * diff else diff;
        d < 0.0001

    def vp200x100(): {viewportWidth = Float64, viewportHeight = Float64} =
        {viewportWidth = 200.0, viewportHeight = 100.0}

    /// position をターゲットにセットしたカメラを作る（zoom=1, 各種フラグはテスト側で個別設定）
    def cameraAt(target: Vec2.Vec2): Camera =
        Camera.make({x = 0.0, y = 0.0})
            |> Camera.mapTransform(Transform.setPosition(target))

    // ════════════════════════════════════════════════════════
    // smoothing: speed × delta が dt 0.05・speed 10 で 0.5 lerp になる
    // ════════════════════════════════════════════════════════

    /// smoothing 有効、speed = 10, dt = 0.05 → t = 0.5。
    /// smoothPosition (0,0) から target (10,0) へ 0.5 lerp で (5,0) に到達する
    @Test
    def testSmoothingHalfwayWithSpeedTimesDelta(): Unit \ Assert =
        let cam = cameraAt({x = 10.0, y = 0.0})
            |> Camera.setPositionSmoothingEnabled(true)
            |> Camera.setPositionSmoothingSpeed(10.0);
        let processed = Camera.process(0.05 |> Duration.seconds, vp200x100(), cam);
        let s = Camera.getSmoothPosition(processed);
        Assert.assertEq(expected = true, approx(s#x, 5.0) and approx(s#y, 0.0))

    /// dt が大きすぎても overshoot しない（夾着クランプ）。speed=100, dt=1.0 で t は 1.0 にクランプ
    @Test
    def testSmoothingClampsAtOne(): Unit \ Assert =
        let cam = cameraAt({x = 10.0, y = 0.0})
            |> Camera.setPositionSmoothingEnabled(true)
            |> Camera.setPositionSmoothingSpeed(100.0);
        let processed = Camera.process(1.0 |> Duration.seconds, vp200x100(), cam);
        let s = Camera.getSmoothPosition(processed);
        // t=1 で完全追従 → smoothPosition = target
        Assert.assertEq(expected = true, approx(s#x, 10.0) and approx(s#y, 0.0))

    /// smoothing 無効時は drag/limit 適用後の値に即追従（lerp なし）
    @Test
    def testSmoothingDisabledSnaps(): Unit \ Assert =
        let cam = cameraAt({x = 42.0, y = 7.0});
        // 全フラグ無効。smoothPosition は target 即一致になる
        let processed = Camera.process(0.016 |> Duration.seconds, vp200x100(), cam);
        let s = Camera.getSmoothPosition(processed);
        Assert.assertEq(expected = true, approx(s#x, 42.0) and approx(s#y, 7.0))

    // ════════════════════════════════════════════════════════
    // drag margin: 内側で停止、外側で追従
    // ════════════════════════════════════════════════════════

    /// drag horizontal 有効、target が margin 内に居る → smoothPosition 不変。
    /// viewport 200, zoom 1, dragRightMargin 0.5 → 右マージン = 200/2*0.5 = 50。
    /// smoothPosition = (0,0)、target = (40, 0) なら 50 以内なので追従しない。
    @Test
    def testDragMarginInsideKeepsCamera(): Unit \ Assert =
        let cam = cameraAt({x = 40.0, y = 0.0})
            |> Camera.setDragHorizontalEnabled(true)
            |> Camera.setDragLeftMargin(0.5)
            |> Camera.setDragRightMargin(0.5);
        let processed = Camera.process(1.0 |> Duration.seconds, vp200x100(), cam);
        let s = Camera.getSmoothPosition(processed);
        Assert.assertEq(expected = true, approx(s#x, 0.0))

    /// drag horizontal、target が margin を超える → margin 境界まで追従。
    /// dragRightMargin 0.5、viewport 200 → margin 50。target=(80,0) は smooth(0,0) から 80 離れている。
    /// margin 境界に target を保つよう smoothPosition.x = 80 - 50 = 30 にシフト
    @Test
    def testDragMarginOutsideFollowsToBoundary(): Unit \ Assert =
        let cam = cameraAt({x = 80.0, y = 0.0})
            |> Camera.setDragHorizontalEnabled(true)
            |> Camera.setDragLeftMargin(0.5)
            |> Camera.setDragRightMargin(0.5);
        let processed = Camera.process(1.0 |> Duration.seconds, vp200x100(), cam);
        let s = Camera.getSmoothPosition(processed);
        // smoothing 無効なので drag margin 適用後の logical = 30 がそのまま smoothPosition に
        Assert.assertEq(expected = true, approx(s#x, 30.0))

    /// vertical 軸も同様。dragBottomMargin 0.4、viewport 100 → margin 20。
    /// target=(0, 50) は smooth(0,0) から 50 離れて margin 超え → smoothPosition.y = 50 - 20 = 30
    @Test
    def testDragMarginVerticalAxis(): Unit \ Assert =
        let cam = cameraAt({x = 0.0, y = 50.0})
            |> Camera.setDragVerticalEnabled(true)
            |> Camera.setDragTopMargin(0.4)
            |> Camera.setDragBottomMargin(0.4);
        let processed = Camera.process(1.0 |> Duration.seconds, vp200x100(), cam);
        let s = Camera.getSmoothPosition(processed);
        Assert.assertEq(expected = true, approx(s#y, 30.0))

    // ════════════════════════════════════════════════════════
    // limit clamp: smoothPosition を矩形外に出さない
    // ════════════════════════════════════════════════════════

    /// limitRight=100、target=(200,0) でも smoothPosition.x は 100 を超えない
    @Test
    def testLimitClampsRight(): Unit \ Assert =
        let cam = cameraAt({x = 200.0, y = 0.0})
            |> Camera.setLimitRight(100);
        let processed = Camera.process(0.016 |> Duration.seconds, vp200x100(), cam);
        let s = Camera.getSmoothPosition(processed);
        Assert.assertEq(expected = true, approx(s#x, 100.0))

    /// limitLeft=-50、target=(-200,0) でも smoothPosition.x は -50 を下回らない
    @Test
    def testLimitClampsLeft(): Unit \ Assert =
        let cam = cameraAt({x = -200.0, y = 0.0})
            |> Camera.setLimitLeft(-50);
        let processed = Camera.process(0.016 |> Duration.seconds, vp200x100(), cam);
        let s = Camera.getSmoothPosition(processed);
        Assert.assertEq(expected = true, approx(s#x, -50.0))

    // ════════════════════════════════════════════════════════
    // smoothing/drag 全無効時は getViewTransform が globalPos を使う
    // ════════════════════════════════════════════════════════

    /// 全フラグ無効のカメラ。getViewTransform は smoothPosition ではなく
    /// 引数の globalPos に基づいて計算する（process が走っていない or 走った後でも）
    @Test
    def testGetViewTransformUsesGlobalPosWhenAllFlagsOff(): Unit \ Assert =
        let cam = Camera.make({x = 99.0, y = 99.0});  // smoothPos = (99,99)
        // globalPos は (0,0) として渡す（呼び出し側 = render が渡すワールド座標）
        let t = Camera.getViewTransform(cam, {x = 0.0, y = 0.0}, vp200x100());
        // DragCenter で globalPos=(0,0), zoom=(1,1) → screenCenter=(0,0), offset=(0-100, 0-50)
        Assert.assertEq(expected = true, approx(t#offset#x, -100.0) and approx(t#offset#y, -50.0))

    /// smoothing 有効時は smoothPosition を起点にする（globalPos は無視）
    @Test
    def testGetViewTransformUsesSmoothPosWhenFollowingActive(): Unit \ Assert =
        let cam = Camera.make({x = 0.0, y = 0.0})
            |> Camera.setSmoothPosition({x = 50.0, y = 25.0})
            |> Camera.setPositionSmoothingEnabled(true);
        // globalPos=(0,0) を渡しても smoothPosition (50,25) で計算される
        let t = Camera.getViewTransform(cam, {x = 0.0, y = 0.0}, vp200x100());
        // screenCenter=(50,25), offset=(50-100, 25-50) = (-50, -25)
        Assert.assertEq(expected = true, approx(t#offset#x, -50.0) and approx(t#offset#y, -25.0))

    // ════════════════════════════════════════════════════════
    // isWithinDragDeadZone: drag margin の幾何から settle を判定
    // ════════════════════════════════════════════════════════

    /// drag 無効時は 4 px 以内が settled。target=smooth=(0,0) → 0 px 差で true
    @Test
    def testDeadZoneWithoutDragIsTinyEpsilon(): Unit \ Assert =
        let cam = Camera.make({x = 0.0, y = 0.0});
        // smoothPosition も初期化で position と同値 → 距離 0
        Assert.assertEq(expected = true,
            Camera.isWithinDragDeadZone(cam, vp200x100()))

    /// drag 無効、target が smooth から 5 px 離れている → 4 px 超えで false
    @Test
    def testDeadZoneWithoutDragRejectsBeyondEpsilon(): Unit \ Assert =
        let cam = Camera.make({x = 5.0, y = 0.0})
            |> Camera.setSmoothPosition({x = 0.0, y = 0.0});
        Assert.assertEq(expected = false,
            Camera.isWithinDragDeadZone(cam, vp200x100()))

    /// drag horizontal 有効。viewport 200, zoom 1, dragRightMargin 0.3 → world dead zone half
    /// = 200/2 * 0.3 = 30. target が smooth から 28 px 離れていても dead zone 内 → true
    @Test
    def testDeadZoneWithDragMarginAcceptsWithinMargin(): Unit \ Assert =
        let cam = Camera.make({x = 28.0, y = 0.0})
            |> Camera.setSmoothPosition({x = 0.0, y = 0.0})
            |> Camera.setDragHorizontalEnabled(true)
            |> Camera.setDragLeftMargin(0.3)
            |> Camera.setDragRightMargin(0.3);
        Assert.assertEq(expected = true,
            Camera.isWithinDragDeadZone(cam, vp200x100()))

    /// drag margin 30、target が smooth から 50 px 離れている → dead zone (30+2=32) 超え → false
    @Test
    def testDeadZoneWithDragMarginRejectsBeyondMargin(): Unit \ Assert =
        let cam = Camera.make({x = 50.0, y = 0.0})
            |> Camera.setSmoothPosition({x = 0.0, y = 0.0})
            |> Camera.setDragHorizontalEnabled(true)
            |> Camera.setDragLeftMargin(0.3)
            |> Camera.setDragRightMargin(0.3);
        Assert.assertEq(expected = false,
            Camera.isWithinDragDeadZone(cam, vp200x100()))

    /// drag margin で大移動 → process を回せば smooth が dead zone 内に収束する
    /// （フリーズ修正の核となる挙動の pin）
    @Test
    def testDeadZoneReachedAfterProcessConvergence(): Unit \ Assert =
        let cam = Camera.make({x = 100.0, y = 0.0})    // target は遠く
            |> Camera.setSmoothPosition({x = 0.0, y = 0.0})
            |> Camera.setPositionSmoothingEnabled(true)
            |> Camera.setPositionSmoothingSpeed(5.0)
            |> Camera.setDragHorizontalEnabled(true)
            |> Camera.setDragLeftMargin(0.3)
            |> Camera.setDragRightMargin(0.3);
        // 1.0 秒進めて収束させる
        let processed = Camera.process(1.0 |> Duration.seconds, vp200x100(), cam);
        // 収束後、target が dead zone 内に居る
        Assert.assertEq(expected = true,
            Camera.isWithinDragDeadZone(processed, vp200x100()))
}
