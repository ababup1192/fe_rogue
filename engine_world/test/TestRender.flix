// Render の単体テスト: draw の 2 系統振り分け（Box→Drawable / Poly→PolygonRenderCmd と
// 置き場所の頂点織り込み）、circle の正体（全角丸 Box）、修飾（半透明・角丸素通し・枠・縞）を
// 具体値で固定する。
mod TestRender {

    def red(): Color = { r = 1.0f32, g = 0.0f32, b = 0.0f32 }

    // draw の振り分け: Box は Drawable に、Poly は PolygonRenderCmd に出る。
    // Poly の頂点は置き場所相対 → 出力では加算済み（(0,0) が (100,200) になる）。
    @Test
    def testDrawSplitsAndOffsetsPoly(): Unit \ Assert =
        let items =
            ({ x = 1.0, y = 2.0 }, Render.box({ x = 10.0, y = 5.0 }, red(), 3)) ::
            ({ x = 100.0, y = 200.0 },
             Render.polygon({ x = 0.0, y = 0.0 } :: { x = 4.0, y = 0.0 } :: { x = 0.0, y = 3.0 } :: Nil, red(), 7)) :: Nil;
        let (drawables, polygons) = Render.draw(items);
        let firstVertex = polygons |> List.head |> Option.flatMap(p -> List.head(p#vertices)) |> Option.map(v -> (v#x, v#y));
        Assert.assertEq(expected = (1, 1, Some((100.0, 200.0)), Some(7)),
            (List.length(drawables), List.length(polygons), firstVertex,
             polygons |> List.head |> Option.map(p -> p#zIndex)))

    // circle は直径サイズの全角丸 Box（Drawable の scale = 直径、cornerRadius = 半径）。
    @Test
    def testCircleIsFullyRoundedBox(): Unit \ Assert =
        let (drawables, _polys) = Render.draw(({ x = 0.0, y = 0.0 }, Render.circle(3.0, red(), 5)) :: Nil);
        let d = List.head(drawables);
        Assert.assertEq(expected = (Some((6.0, 6.0)), Some(Some(3.0))),
            (d |> Option.map(x -> (x#scale#x, x#scale#y)),
             d |> Option.map(x -> Option.map(s -> s#cornerRadius, x#style))))

    // 修飾: fade は Box の α を差し替え、rounded は Poly には効かず素通し（Poly は Poly のまま出る）。
    @Test
    def testModifiersApplyAndPassThrough(): Unit \ Assert =
        let faded = Render.box({ x = 1.0, y = 1.0 }, red(), 0) |> Render.fade(0.5f32);
        let (ds, _) = Render.draw(({ x = 0.0, y = 0.0 }, faded) :: Nil);
        let untouched = Render.polygon({ x = 0.0, y = 0.0 } :: Nil, red(), 0) |> Render.rounded(4.0);
        let (_, ps) = Render.draw(({ x = 9.0, y = 9.0 }, untouched) :: Nil);
        Assert.assertEq(expected = (Some(0.5f32), 1),
            (ds |> List.head |> Option.map(d -> d#alpha), List.length(ps)))

    // outline と striped は同じ Box の style に重なる（枠幅・縞の濃度と周期を同時に pin）。
    @Test
    def testOutlineAndStripedStack(): Unit \ Assert =
        let item = Render.box({ x = 2.0, y = 2.0 }, red(), 0)
            |> Render.outline(red(), 1.5)
            |> Render.striped({ color = red(), alpha = 0.25f32, width = 2.0, period = 6.0 });
        let (ds, _) = Render.draw(({ x = 0.0, y = 0.0 }, item) :: Nil);
        let style = ds |> List.head |> Option.flatMap(d -> d#style);
        Assert.assertEq(expected = (Some(1.5), Some(0.25f32), Some(6.0)),
            (style |> Option.map(s -> s#borderWidth),
             style |> Option.map(s -> s#stripeAlpha),
             style |> Option.map(s -> s#stripePeriod)))
}
