// TestClip — clip(切り抜き窓)の勘定を具体値で固定する: Rect2.intersect の交差と空、
// clipPixels の floor 量子化(GL scissor と SoftRaster setClip が見る共通の画素集合)、
// Render.draw が Clipped を剥がして Drawable / PolygonRenderCmd に窓を刻むこと、
// 修飾(fade)が窓を素通りして中身に効くこと、Annotate の外形が窓と交差すること。
mod TestClip {

    def rect(x: Float64, y: Float64, w: Float64, h: Float64): Rect2.Rect2 =
        { position = { x = x, y = y }, size = { x = w, y = h } }

    /// 矩形をタプルへ射影(record は比較できないため)。
    def rectTuple(r: Rect2.Rect2): (Float64, Float64, Float64, Float64) =
        (r#position#x, r#position#y, r#size#x, r#size#y)

    @Test
    def testRectIntersectOverlap(): Unit \ Assert =
        // 重なりはその共通部分。
        Assert.assertEq(expected = (10.0, 20.0, 30.0, 10.0),
            rectTuple(Rect2.intersect(rect(0.0, 0.0, 40.0, 30.0), rect(10.0, 20.0, 100.0, 100.0))))

    @Test
    def testRectIntersectEmptyIsNegativeSize(): Unit \ Assert =
        // 離れた矩形の交差は size が負 — 「空」を Option でなく負サイズで返す規約。
        let empty = Rect2.intersect(rect(0.0, 0.0, 10.0, 10.0), rect(20.0, 0.0, 10.0, 10.0));
        Assert.assertEq(expected = true, empty#size#x < 0.0)

    @Test
    def testClipPixelsFloorsAtScale(): Unit \ Assert =
        // 2 倍出力では設計 px の 2 倍を floor。(x0,y0,x1,y1) の 4 点量子化。
        Assert.assertEq(expected = (24, 20, 936, 516),
            DrawCmd.clipPixels({ scaleX = 2.0, scaleY = 2.0 }, rect(12.0, 10.0, 456.0, 248.0)))

    @Test
    def testDrawStampsClipOnDrawables(): Unit \ Assert =
        // clipped で包んだ Box は Drawable の clip に窓が刻まれ、包まない物は None のまま。
        let box = Render.box({ x = 10.0, y = 10.0 }, { r = 1.0f32, g = 1.0f32, b = 1.0f32 }, 1);
        let items = ({ at = { x = 0.0, y = 0.0 }, item = Render.clipped(rect(1.0, 2.0, 3.0, 4.0), box) }: Render.PlacedItem)
                 :: ({ at = { x = 0.0, y = 0.0 }, item = box }: Render.PlacedItem)
                 :: Nil;
        let (ds, _) = Render.draw(items);
        Assert.assertEq(
            expected = Some((1.0, 2.0, 3.0, 4.0)) :: (None: Option[(Float64, Float64, Float64, Float64)]) :: Nil,
            ds |> List.map(d -> Option.map(rectTuple, d#clip)))

    @Test
    def testNestedClipIntersects(): Unit \ Assert =
        // 入れ子の Clipped は交差した窓 1 つに畳まれる。
        let box = Render.box({ x = 10.0, y = 10.0 }, { r = 1.0f32, g = 1.0f32, b = 1.0f32 }, 1);
        let nested = Render.clipped(rect(0.0, 0.0, 40.0, 30.0),
                        Render.clipped(rect(10.0, 20.0, 100.0, 100.0), box));
        let (ds, _) = Render.draw(({ at = { x = 0.0, y = 0.0 }, item = nested }: Render.PlacedItem) :: Nil);
        Assert.assertEq(expected = Some((10.0, 20.0, 30.0, 10.0)) :: Nil,
            ds |> List.map(d -> Option.map(rectTuple, d#clip)))

    @Test
    def testClippedPolyRoutesToPolygonWithClip(): Unit \ Assert =
        // Clipped に包まれた Poly も polygon 側へ届き、窓が刻まれる(Drawable 側は空)。
        let tri = Render.polygon({ x = 0.0, y = 0.0 } :: { x = 4.0, y = 0.0 } :: { x = 0.0, y = 4.0 } :: Nil,
                                 { r = 1.0f32, g = 1.0f32, b = 1.0f32 }, 1);
        let (ds, ps) = Render.draw(
            ({ at = { x = 0.0, y = 0.0 }, item = Render.clipped(rect(1.0, 1.0, 2.0, 2.0), tri) }: Render.PlacedItem) :: Nil);
        Assert.assertEq(
            expected = (0, Some((1.0, 1.0, 2.0, 2.0)) :: Nil),
            (List.length(ds), ps |> List.map(p -> Option.map(rectTuple, p#clip))))

    @Test
    def testModifierReachesLeafThroughClip(): Unit \ Assert =
        // fade は窓を素通りして中身に効く(窓は変わらない)。
        let box = Render.box({ x = 10.0, y = 10.0 }, { r = 1.0f32, g = 1.0f32, b = 1.0f32 }, 1);
        let faded = Render.clipped(rect(1.0, 2.0, 3.0, 4.0), box) |> Render.fade(0.5f32);
        let (ds, _) = Render.draw(({ at = { x = 0.0, y = 0.0 }, item = faded }: Render.PlacedItem) :: Nil);
        Assert.assertEq(
            expected = (0.5f32, Some((1.0, 2.0, 3.0, 4.0))) :: Nil,
            ds |> List.map(d -> (d#alpha, Option.map(rectTuple, d#clip))))

    @Test
    def testAnnotateAabbShrinksToWindow(): Unit \ Assert =
        // F8 の外形は窓と交差した見えている範囲になる(完全に窓の外なら負サイズ = ヒットしない)。
        let box = Render.box({ x = 100.0, y = 100.0 }, { r = 1.0f32, g = 1.0f32, b = 1.0f32 }, 1);
        let placed: Render.PlacedItem =
            { at = { x = 0.0, y = 0.0 }, item = Render.clipped(rect(10.0, 10.0, 20.0, 20.0), box) };
        let aabb = Annotate.itemAabb(_ -> None, placed);
        Assert.assertEq(expected = (10.0, 10.0, 20.0, 20.0), rectTuple(aabb))
}
