// RawDraw の単体テスト: 図形そのものの幾何（circle は全角丸 Box・boxAt/circleAt/ngonAt の
// 中心置き換算・ellipseAt の半径・sector と circleSegment の頂点構成・starAt の交互半径・
// lineQuad の幅・半周超の扇形の耳切り面積保存）を具体値で固定する。
// lint-view: 対象外 — 図形プリミティブ 1 つずつの幾何を数字で固定するための呼び出し。画面に出す絵ではない。
mod TestRawDraw {

    def red(): Color = { r = 1.0, g = 0.0, b = 0.0 }

    /// PlacedItem から Poly の頂点列を取り出す（図形テストの共通口）。
    def vertsOf(placed: Render.PlacedItem): List[Vec2.Vec2] =
        match placed#item {
            case Render.Item.Poly(p) => p#vertices
            case _                   => Nil
        }

    /// 小数4桁へ丸める（円周上の点の浮動小数比較用）。
    def round4(x: Float64): Float64 = Float64.floor(x * 10000.0 + 0.5) / 10000.0

    // circle は直径サイズの全角丸 Box（Drawable の scale = 直径、cornerRadius = 半径）。
    @Test
    def testCircleIsFullyRoundedBox(): Unit \ Assert =
        let (drawables, _polys) = Render.draw({ at = { x = 0.0, y = 0.0 }, item = RawDraw.circle(3.0, red(), 5) } :: Nil);
        let d = List.head(drawables);
        Assert.assertEq(expected = (Some((6.0, 6.0)), Some(Some(3.0))),
            (d |> Option.map(x -> (x#scale#x, x#scale#y)),
             d |> Option.map(x -> Option.map(s -> s#cornerRadius, x#style))))

    // circleAt: 中心 (10,10)・半径 3 の円は、外接正方形の左上 (7,7) に置かれる。
    @Test
    def testCircleAtPlacesByCenter(): Unit \ Assert =
        let placed = RawDraw.circleAt({ x = 10.0, y = 10.0 }, 3.0, red(), 5);
        Assert.assertEq(expected = (7.0, 7.0), (placed#at#x, placed#at#y))

    // boxAt: 中心 (10,10)・サイズ 4×6 の矩形は、左上 (8,7) に置かれる。
    @Test
    def testBoxAtPlacesByCenter(): Unit \ Assert =
        let placed = RawDraw.boxAt({ x = 10.0, y = 10.0 }, { x = 4.0, y = 6.0 }, red(), 5);
        Assert.assertEq(expected = (8.0, 7.0), (placed#at#x, placed#at#y))

    // ngonAt: 頂点数 = n・最初の頂点は真上（y = −radius）・置き場所は中心そのもの。
    @Test
    def testNgonAtPointsUpWithNVertices(): Unit \ Assert =
        let hex = RawDraw.ngonAt({ x = 7.0, y = 9.0 }, 6, 10.0, red(), 0);
        let first = List.head(vertsOf(hex)) |> Option.map(v -> (round4(v#x), round4(v#y)));
        Assert.assertEq(expected = (6, Some((0.0, -10.0)), (7.0, 9.0)),
            (List.length(vertsOf(hex)), first, (hex#at#x, hex#at#y)))

    // ellipseAt: 32 頂点で、x 半径・y 半径がそれぞれ radii どおりに届く。
    @Test
    def testEllipseAtSpansRadii(): Unit \ Assert =
        let e = RawDraw.ellipseAt(Vec2.zero(), { x = 26.0, y = 16.0 }, red(), 0);
        let vs = vertsOf(e);
        let maxX = List.foldLeft((m, v) -> Float64.max(m, v#x), 0.0, vs);
        let maxY = List.foldLeft((m, v) -> Float64.max(m, v#y), 0.0, vs);
        Assert.assertEq(expected = (32, 26.0, 16.0), (List.length(vs), round4(maxX), round4(maxY)))

    // sectorAt は中心点から始まり（パイの要）、circleSegmentAt は弧だけ（弦は自動で閉じる）。
    @Test
    def testSectorHasApexAndSegmentDoesNot(): Unit \ Assert =
        let sec = RawDraw.sectorAt(Vec2.zero(), 22.0, { fromT = 0.05, toT = 0.45 }, red(), 0);
        let seg = RawDraw.circleSegmentAt(Vec2.zero(), 22.0, { fromT = 0.05, toT = 0.45 }, red(), 0);
        let apex = List.head(vertsOf(sec)) |> Option.map(v -> (v#x, v#y));
        Assert.assertEq(expected = (Some((0.0, 0.0)), 26, 25),
            (apex, List.length(vertsOf(sec)), List.length(vertsOf(seg))))

    // starAt: 頂点数 = 尖り × 2（外径と内径の交互）。
    @Test
    def testStarAtAlternatesRadii(): Unit \ Assert =
        let s = RawDraw.starAt(Vec2.zero(), 5, { outer = 21.0, inner = 9.0 }, red(), 0);
        Assert.assertEq(expected = 10, List.length(vertsOf(s)))

    // lineQuad: 4 頂点で、両端の幅辺（始点側 v0-v3・終点側 v1-v2）がどちらも width
    // （斜めの線でも太さが崩れない）。
    @Test
    def testLineQuadWidthIsPerpendicular(): Unit \ Assert =
        let quad = RawDraw.lineQuad({ x = 0.0, y = 0.0 }, { x = 10.0, y = 10.0 }, 4.0);
        let widths = List.zip(quad, List.reverse(quad))
            |> List.take(2)
            |> List.map(pair -> { let (p, q) = pair; round4(Vec2.length(Vec2.sub(p, q))) });
        Assert.assertEq(expected = (4, 4.0 :: 4.0 :: Nil), (List.length(quad), widths))

    // 半周を超える扇形（パックマン）でも耳切りで面積が保存される（凹の実戦形の回帰）。
    // 期待値は頂点列そのものの靴ひも面積 — 分割で欠けても余っても一致しない。
    @Test
    def testReflexSectorPreservesAreaUnderTriangulation(): Unit \ Assert =
        let vs = vertsOf(RawDraw.sectorAt(Vec2.zero(), 20.0, { fromT = 0.10, toT = 0.90 }, red(), 0));
        let area = List.foldLeft((s, t) -> {
            let (a, b, c) = t;
            s + Float64.abs((b#x - a#x) * (c#y - a#y) - (b#y - a#y) * (c#x - a#x)) / 2.0
        }, 0.0, Triangulate.triangles(vs));
        Assert.assertEq(expected = round4(Float64.abs(Triangulate.signedArea(vs))), round4(area))

    // orBoxAt: items が空なら仮板（fallback）が 1 枚返る。
    @Test
    def testOrBoxAtFallsBackToPlaceholderWhenEmpty(): Unit \ Assert =
        let placed = RawDraw.orBoxAt({ x = 10.0, y = 10.0 }, { x = 4.0, y = 6.0 }, red(), 5, Nil);
        Assert.assertEq(expected = 1, List.length(placed))

    // orBoxAt: items が非空ならそのまま返す（仮板に差し替えない）。
    @Test
    def testOrBoxAtReturnsItemsUnchangedWhenNonEmpty(): Unit \ Assert =
        let items = { at = { x = 1.0, y = 2.0 }, item = RawDraw.box({ x = 3.0, y = 3.0 }, red(), 0) } :: Nil;
        let placed = RawDraw.orBoxAt({ x = 10.0, y = 10.0 }, { x = 4.0, y = 6.0 }, red(), 5, items);
        Assert.assertEq(expected = (1, Some((1.0, 2.0))),
            (List.length(placed), List.head(placed) |> Option.map(p -> (p#at#x, p#at#y))))

}
