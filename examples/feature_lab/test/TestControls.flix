// TestControls — カンテラの壁すり抜け防止（moveLantern）を pin する。
// 壁形状は View.wallHitShapes（見た目と同じソース）をそのまま使うので、ここでは
// 「壁に向かって進んでも止まる」「平行方向へはスライドできる」の2点だけを見る。

mod TestControls {

    def at(x: Float64, y: Float64): Vec2.Vec2 = { x = x, y = y }

    def near(a: Float64, b: Float64): Bool = Float64.abs(a - b) < 0.000001

    def vecNear(a: Vec2.Vec2, b: Vec2.Vec2): Bool = near(a#x, b#x) and near(a#y, b#y)

    /// walls=off なら壁形状を無視して delta をそのまま足す（既存の自由移動と同じ挙動）。
    @Test
    def testWallsOffMovesFreelyThroughWallArea(): Unit \ Assert =
        // wallPillarCenter=(110,90) の真上から柱へ向かって進む delta。walls=off なので何もせず通す。
        let moved = Controls.moveLantern(at(110.0, 70.0), at(0.0, 20.0), false);
        Assert.assertEq(expected = true, vecNear(at(110.0, 90.0), moved))

    /// walls=on で柱（wallPillarCenter=(110,90), r=10）へ向かって進むと、当たり判定円が
    /// 重なる直前で止まる＝位置が変わらない（元の位置のまま）。
    @Test
    def testWallsOnStopsBeforeEnteringPillar(): Unit \ Assert =
        // 柱の真上、当たり判定込みで重ならない位置(110, 70)から柱中心へ向けて大きく進もうとする。
        let start = at(110.0, 70.0);
        let moved = Controls.moveLantern(start, at(0.0, 20.0), true);
        Assert.assertEq(expected = true, vecNear(start, moved))

    /// walls=on で壁に向かって斜め移動しても、壁と平行な軸方向へはスライドできる
    /// （X軸は柱に阻まれて止まるが、Y軸だけの移動は通る＝定番の軸別スライド）。
    @Test
    def testWallsOnSlidesAlongParallelAxis(): Unit \ Assert =
        // 柱と同じ高さ(y=90)、柱の左20pxから、右(+x, 柱の中心を直撃=阻まれる)+下(+y, 通る)の斜め移動。
        let start = at(90.0, 90.0);
        let delta = at(20.0, 5.0);
        let moved = Controls.moveLantern(start, delta, true);
        // X: 90+20=110 は柱の中心そのもの＝阻まれ x は 90 のまま。Y: 90+5=95 は柱から離れるので通る。
        Assert.assertEq(expected = (true, true), (near(moved#x, start#x), near(moved#y, start#y + delta#y)))
}
