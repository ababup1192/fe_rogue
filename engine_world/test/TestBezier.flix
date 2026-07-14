// TestBezier — 曲線の平坦化と帯・塗りの部品数を具体値で固定する。
mod TestBezier {

    @Test
    def testQuadraticHitsEndpointsAndMidpoint(): Unit \ Assert =
        // (0,0)→制御(10,0)→(10,10) の 2 分割: 始点・中点(7.5,2.5)・終点。
        let pts = Bezier.quadratic({x = 0.0, y = 0.0}, {x = 10.0, y = 0.0}, {x = 10.0, y = 10.0}, 2)
            |> List.map(p -> (p#x, p#y));
        Assert.assertEq(expected = (0.0, 0.0) :: (7.5, 2.5) :: (10.0, 10.0) :: Nil, pts)

    @Test
    def testStrokeAndPolylinePieceCounts(): Unit \ Assert =
        // n+1 点の背骨 → n 枚のクアッド + n-1 個の継ぎ目円盤。2 点の polyline は 1 枚だけ。
        let spine = Bezier.quadratic({x = 0.0, y = 0.0}, {x = 5.0, y = 0.0}, {x = 10.0, y = 0.0}, 8);
        let band = Bezier.stroke({ spine = spine, color = white(), z = 1 }, _ -> 4.0);
        let one = Bezier.polyline({x = 0.0, y = 0.0} :: {x = 10.0, y = 0.0} :: Nil, width = 2.0, white(), 1);
        Assert.assertEq(expected = (15, 1), (List.length(band), List.length(one)))

    @Test
    def testFillIsOnePieceEvenWhenConcave(): Unit \ Assert =
        // fill は形によらず 1 枚の多角形（三角形化は描画側の耳切りの仕事）。
        // 凸の楕円でも深くえぐれた星でも、描画コマンド数が形に比例して増えない。
        let ellipseFill = Bezier.fill(Bezier.ellipse({x = 0.0, y = 0.0}, 10.0, 6.0, 16), white(), 1);
        let starFill = Bezier.fill(Bezier.star({x = 0.0, y = 0.0}, rOut = 21.0, rIn = 9.0), white(), 1);
        Assert.assertEq(expected = (1, 1), (List.length(ellipseFill), List.length(starFill)))

    def white(): Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}
}
