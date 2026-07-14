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
            { at = { x = 1.0, y = 2.0 }, item = Render.box({ x = 10.0, y = 5.0 }, red(), 3) } ::
            { at = { x = 100.0, y = 200.0 },
              item = Render.polygon({ x = 0.0, y = 0.0 } :: { x = 4.0, y = 0.0 } :: { x = 0.0, y = 3.0 } :: Nil, red(), 7) } :: Nil;
        let (drawables, polygons) = Render.draw(items);
        let firstVertex = polygons |> List.head |> Option.flatMap(p -> List.head(p#vertices)) |> Option.map(v -> (v#x, v#y));
        Assert.assertEq(expected = (1, 1, Some((100.0, 200.0)), Some(7)),
            (List.length(drawables), List.length(polygons), firstVertex,
             polygons |> List.head |> Option.map(p -> p#zIndex)))

    // circle は直径サイズの全角丸 Box（Drawable の scale = 直径、cornerRadius = 半径）。
    @Test
    def testCircleIsFullyRoundedBox(): Unit \ Assert =
        let (drawables, _polys) = Render.draw({ at = { x = 0.0, y = 0.0 }, item = Render.circle(3.0, red(), 5) } :: Nil);
        let d = List.head(drawables);
        Assert.assertEq(expected = (Some((6.0, 6.0)), Some(Some(3.0))),
            (d |> Option.map(x -> (x#scale#x, x#scale#y)),
             d |> Option.map(x -> Option.map(s -> s#cornerRadius, x#style))))

    // circleAt: 中心 (10,10)・半径 3 の円は、外接正方形の左上 (7,7) に置かれる。
    @Test
    def testCircleAtPlacesByCenter(): Unit \ Assert =
        let placed = Render.circleAt({ x = 10.0, y = 10.0 }, 3.0, red(), 5);
        Assert.assertEq(expected = (7.0, 7.0), (placed#at#x, placed#at#y))

    // boxAt: 中心 (10,10)・サイズ 4×6 の矩形は、左上 (8,7) に置かれる。
    @Test
    def testBoxAtPlacesByCenter(): Unit \ Assert =
        let placed = Render.boxAt({ x = 10.0, y = 10.0 }, { x = 4.0, y = 6.0 }, red(), 5);
        Assert.assertEq(expected = (8.0, 7.0), (placed#at#x, placed#at#y))

    // flipH: 頂点の x が符号反転し（y 不変）、2 回で元に戻る。
    @Test
    def testFlipHMirrorsVerticesAndIsInvolutive(): Unit \ Assert =
        let verts = { x = 4.0, y = 0.0 } :: { x = 0.0, y = 3.0 } :: Nil;
        let once = Render.flipH(verts);
        let twice = Render.flipH(once);
        let headOf = vs -> List.head(vs) |> Option.map(v -> (v#x, v#y));
        Assert.assertEq(expected = (Some((-4.0, 0.0)), Some((4.0, 0.0))), (headOf(once), headOf(twice)))

    // flipV: 頂点の y が符号反転する（x 不変）。
    @Test
    def testFlipVMirrorsVerticesVertically(): Unit \ Assert =
        let verts = { x = 4.0, y = 3.0 } :: Nil;
        Assert.assertEq(expected = Some((4.0, -3.0)),
            List.head(Render.flipV(verts)) |> Option.map(v -> (v#x, v#y)))

    // spriteFlipped: 名前渡しの flip がそのまま Sprite のフィールドに立つ。
    @Test
    def testSpriteFlippedSetsFlags(): Unit \ Assert =
        let flags = match Render.spriteFlipped("hero", 5, { flipH = true, flipV = false }) {
            case Render.Item.Sprite(s) => Some((s#flipH, s#flipV, s#centered))
            case _                           => None
        };
        Assert.assertEq(expected = Some((true, false, true)), flags)

    // 修飾: fade は Box の α を差し替え、rounded は Poly には効かず素通し（Poly は Poly のまま出る）。
    @Test
    def testModifiersApplyAndPassThrough(): Unit \ Assert =
        let faded = Render.box({ x = 1.0, y = 1.0 }, red(), 0) |> Render.fade(0.5f32);
        let (ds, _) = Render.draw({ at = { x = 0.0, y = 0.0 }, item = faded } :: Nil);
        let untouched = Render.polygon({ x = 0.0, y = 0.0 } :: Nil, red(), 0) |> Render.rounded(4.0);
        let (_, ps) = Render.draw({ at = { x = 9.0, y = 9.0 }, item = untouched } :: Nil);
        Assert.assertEq(expected = (Some(0.5f32), 1),
            (ds |> List.head |> Option.map(d -> d#alpha), List.length(ps)))

    // outline と striped は同じ Box の style に重なる（枠幅・縞の濃度と周期を同時に pin）。
    @Test
    def testOutlineAndStripedStack(): Unit \ Assert =
        let item = Render.box({ x = 2.0, y = 2.0 }, red(), 0)
            |> Render.outline(red(), 1.5)
            |> Render.striped({ color = red(), alpha = 0.25f32, width = 2.0, period = 6.0 });
        let (ds, _) = Render.draw({ at = { x = 0.0, y = 0.0 }, item = item } :: Nil);
        let style = ds |> List.head |> Option.flatMap(d -> d#style);
        Assert.assertEq(expected = (Some(1.5), Some(0.25f32), Some(6.0)),
            (style |> Option.map(s -> s#borderWidth),
             style |> Option.map(s -> s#stripeAlpha),
             style |> Option.map(s -> s#stripePeriod)))
}
