// 共有 lib の Viewport（画面外クエリ）/ Motion（速度積分）の直接テスト。

mod TestViewport {

    def b(): Viewport.Bounds = Viewport.bounds(480.0, 720.0)   // margin は呼び出し側で 64

    /// 画面内は outside でない、各辺の外は outside。
    @Test
    def testIsOutside(): Unit \ Assert =
        Assert.assertEq(expected = (false, true, true, true, true),
            ( Viewport.isOutside({x = 240.0, y = 360.0}, b(), 64.0),   // 中央 → 内
              Viewport.isOutside({x = 545.0, y = 360.0}, b(), 64.0),   // 右外 (>480+64)
              Viewport.isOutside({x = -65.0, y = 360.0}, b(), 64.0),   // 左外
              Viewport.isOutside({x = 240.0, y = 785.0}, b(), 64.0),   // 下外 (>720+64)
              Viewport.isOutside({x = 240.0, y = -65.0}, b(), 64.0)))  // 上外

    /// 各辺の exact boundary（maxX+margin ちょうど=内、+1=外）を lib テストで固定する。
    @Test
    def testIsOutsideBoundary(): Unit \ Assert =
        Assert.assertEq(
            expected = (false, true, false, true, false, true, false, true),
            ( Viewport.isOutside({x = 544.0, y = 360.0}, b(), 64.0),    // 右 480+64 ちょうど → 内
              Viewport.isOutside({x = 545.0, y = 360.0}, b(), 64.0),    // 右 +1 → 外
              Viewport.isOutside({x = -64.0, y = 360.0}, b(), 64.0),    // 左 0-64 ちょうど → 内
              Viewport.isOutside({x = -65.0, y = 360.0}, b(), 64.0),    // 左 -1 → 外
              Viewport.isOutside({x = 240.0, y = 784.0}, b(), 64.0),    // 下 720+64 ちょうど → 内
              Viewport.isOutside({x = 240.0, y = 785.0}, b(), 64.0),    // 下 +1 → 外
              Viewport.isOutside({x = 240.0, y = -64.0}, b(), 64.0),    // 上 0-64 ちょうど → 内
              Viewport.isOutside({x = 240.0, y = -65.0}, b(), 64.0)))   // 上 -1 → 外

    /// offscreenEntities は画面外の id だけを返す。
    @Test
    def testOffscreenEntities(): Unit \ Assert =
        let positions = Map#{ 0 => {x = 240.0, y = 360.0},   // 内
                              1 => {x = 600.0, y = 360.0},   // 右外
                              2 => {x = -100.0, y = 100.0} }; // 左外
        let off = Viewport.offscreenEntities(positions, b(), 64.0);
        Assert.assertEq(expected = true,
            List.memberOf(1, off) and List.memberOf(2, off) and
            not List.memberOf(0, off) and List.length(off) == 2)

    /// Motion.integrate: velocity を持つものだけ p += v*dt で進む。
    @Test
    def testMotionIntegrate(): Unit \ Assert =
        let positions  = Map#{ 0 => {x = 10.0, y = 10.0}, 1 => {x = 5.0, y = 5.0} };
        let velocities = Map#{ 0 => {x = 2.0, y = 3.0} };   // 1 は velocity 無し → 動かない
        let moved = Motion.integrate(positions, velocities, 1.0);
        let p0 = Map.get(0, moved) |> Option.getWithDefault({x = -1.0, y = -1.0});
        let p1 = Map.get(1, moved) |> Option.getWithDefault({x = -1.0, y = -1.0});
        Assert.assertEq(expected = true,
            p0#x == 12.0 and p0#y == 13.0 and p1#x == 5.0 and p1#y == 5.0)
}
