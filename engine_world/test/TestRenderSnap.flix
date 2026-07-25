// Render の升目吸着（ドット絵の画面に、なめらかな多角形をなじませる）。
mod TestRenderSnap {

    def poly(xs: List[(Float64, Float64)]): Render.Item =
        Render.polygon(xs |> List.map(p -> { x = fst(p), y = snd(p) }),
            { r = 1.0f32, g = 1.0f32, b = 1.0f32 }, 0)

    def vertsOf(item: Render.Item): List[(Float64, Float64)] =
        match item {
            case Render.Item.Poly(p) => p#vertices |> List.map(v -> (v#x, v#y))
            case _                   => Nil
        }

    @Test
    def testVerticesLandOnWholePixels(): Unit \ Assert =
        // ちょうど半分（2.5）は偶数側へ丸まる（Float64.round の決まり）。
        let out = Render.snapped(1.0, poly((0.4, 1.6) :: (2.5, 0.4) :: (3.49, 3.51) :: Nil));
        Assert.assertEq(expected = (0.0, 2.0) :: (2.0, 0.0) :: (3.0, 4.0) :: Nil, vertsOf(out))

    @Test
    def testCoarserStepMakesChunkierEdges(): Unit \ Assert =
        let out = Render.snapped(2.0, poly((0.9, 3.1) :: (5.2, 5.2) :: (0.0, 0.0) :: Nil));
        Assert.assertEq(expected = (0.0, 4.0) :: (6.0, 6.0) :: (0.0, 0.0) :: Nil, vertsOf(out))

    @Test
    def testZeroStepLeavesTheShapeAlone(): Unit \ Assert =
        let original = poly((0.4, 1.6) :: (2.5, -0.4) :: Nil);
        Assert.assertEq(expected = vertsOf(original), vertsOf(Render.snapped(0.0, original)))

    @Test
    def testPlacementIsSnappedToo(): Unit \ Assert =
        // 頂点だけ揃えても、置き場所が半端なら画面上ではずれる。
        let items = { at = { x = 10.4, y = 7.6 }, item = poly((0.0, 0.0) :: Nil) } :: Nil;
        let out = Render.snappedAll(1.0, items) |> List.map(p -> (p#at#x, p#at#y));
        Assert.assertEq(expected = (10.0, 8.0) :: Nil, out)

    @Test
    def testNonPolygonItemsPassThrough(): Unit \ Assert =
        // 箱や絵は元から軸に平行なので、頂点をいじる必要はない（置き場所だけ揃う）。
        let box = { at = { x = 3.7, y = 3.2 },
                    item = Render.box({ x = 4.0, y = 4.0 }, { r = 1.0f32, g = 1.0f32, b = 1.0f32 }, 0) };
        let out = Render.snappedAll(1.0, box :: Nil) |> List.map(p -> (p#at#x, p#at#y));
        Assert.assertEq(expected = (4.0, 3.0) :: Nil, out)
}
