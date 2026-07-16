// Shadow のテスト。具体値は Python で独立に手計算し pin する（テスト内で再計算ロジックを
// 組んで自己参照しない）。境界（光と辺が一直線）は「背面側に倒す」規約が一貫することを見る。

mod TestShadow {

    def at(x: Float64, y: Float64): Vec2.Vec2 = { x = x, y = y }

    def near(a: Float64, b: Float64): Bool = Float64.abs(a - b) < 0.000001

    def vecNear(a: Vec2.Vec2, b: Vec2.Vec2): Bool =
        Float64.abs(a#x - b#x) < 0.000001 and Float64.abs(a#y - b#y) < 0.000001

    /// 2つの頂点列が同じ長さで、対応する頂点どうしがすべて近いか。
    def verticesNear(expected: List[Vec2.Vec2], actual: List[Vec2.Vec2]): Bool =
        List.length(expected) == List.length(actual) and
        (List.zip(expected, actual) |> List.forAll(pair -> {
            let (e, a) = pair;
            vecNear(e, a)
        }))

    /// 四角形の先頭頂点が (x, y) に近いものを1枚選ぶ（3辺以上返るケースから狙った辺を拾う近道）。
    def quadStartingAt(quads: List[List[Vec2.Vec2]], x: Float64, y: Float64): Option[List[Vec2.Vec2]] =
        quads |> List.find(q -> List.head(q) |> Option.map(v -> near(v#x, x) and near(v#y, y)) |> Option.getWithDefault(false))

    /// 中心 (0,0)・一辺10 の正方形（左上→右上→右下→左下＝画面上で時計回り）。
    def square(): List[Vec2.Vec2] =
        at(-5.0, -5.0) :: at(5.0, -5.0) :: at(5.0, 5.0) :: at(-5.0, 5.0) :: Nil

    /// 光が左遠くにあるとき、正方形の3辺（top/right/bottom）が影を落とし、left だけ前面。
    /// 「屋根が真横の太陽に照らされても背を向けている」のと同じで、点光源が有限距離にある限り
    /// 上下の辺も光に正対しない — 直感の「右の1辺だけ」より広い集合になるのが正しい幾何。
    @Test
    def testSquareLeftLightThreeBackFaces(): Unit \ Assert =
        let quads = Shadow.shadowQuads(at(-100.0, 0.0), square(), 100.0);
        Assert.assertEq(expected = 3, List.length(quads))

    /// 上の3枚のうち、right 辺（(5,-5)→(5,5)）由来の四角形の4頂点座標をpinする
    /// （v1=(5,-5), v2=(5,5) はそのまま、v1'/v2' は「光→頂点」方向へ100だけ伸ばした点）。
    @Test
    def testRightEdgeShadowQuadVertices(): Unit \ Assert =
        let quads = Shadow.shadowQuads(at(-100.0, 0.0), square(), 100.0);
        let rightQuad = quadStartingAt(quads, 5.0, -5.0);
        let expected = at(5.0, -5.0) :: at(5.0, 5.0) ::
                       at(104.88681377244376, 9.75651494154494) ::
                       at(104.88681377244376, -9.75651494154494) :: Nil;
        Assert.assertEq(expected = Some(true),
            Option.map(actual -> verticesNear(expected, actual), rightQuad))

    /// 光が正方形の中心にある縮退（内部光源）: 全4辺が背面になり、クラッシュせず4枚返る。
    @Test
    def testLightInsidePolygonReturnsAllFourFaces(): Unit \ Assert =
        let quads = Shadow.shadowQuads(at(0.0, 0.0), square(), 100.0);
        Assert.assertEq(expected = 4, List.length(quads))

    /// 光と辺が一直線（right 辺の中点 (5,0) の真上延長 (5,-100)）: 内積ちょうど0で
    /// 規約どおり背面側に倒れ、right 辺も影四角形に含まれる（top は明確に前面のまま）。
    @Test
    def testColinearLightBoundaryFallsToBackFace(): Unit \ Assert =
        let quads = Shadow.shadowQuads(at(5.0, -100.0), square(), 100.0);
        // colinear な配置では top(0,-1 法線)が最も光を向く前面、bottom/left/right寄りは背面
        // （3枚 = top だけが前面に残る）。
        // ここでは「right が背面判定に入っている（境界を律儀に背面へ倒している）」ことも見る。
        Assert.assertEq(expected = (3, true),
            (List.length(quads),
             quadStartingAt(quads, 5.0, -5.0) |> Option.map(_ -> true) |> Option.getWithDefault(false)))

    /// n=2（線分1本）の遮蔽物でも、往復2辺のうち光に背を向けた1本だけが影四角形になり
    /// 正しく1枚返る（薄い壁を多角形にせず線分で渡せることの証拠）。
    @Test
    def testTwoVertexSegmentOccluderReturnsOneQuad(): Unit \ Assert =
        let segment = at(0.0, -5.0) :: at(0.0, 5.0) :: Nil;
        let quads = Shadow.shadowQuads(at(-100.0, 0.0), segment, 100.0);
        let expected = at(0.0, -5.0) :: at(0.0, 5.0) ::
                       at(99.87523388778446, 9.993761694389224) ::
                       at(99.87523388778446, -9.993761694389224) :: Nil;
        Assert.assertEq(expected = (1, true),
            (List.length(quads),
             List.head(quads) |> Option.map(q -> verticesNear(expected, q)) |> Option.getWithDefault(false)))

    /// occluderOfCircle: segments 個の頂点、t=0 相当（真上 = center - (0, radius)）をpin。
    @Test
    def testOccluderOfCircleVertexCountAndTopPoint(): Unit \ Assert =
        let verts = Shadow.occluderOfCircle(at(10.0, 20.0), 4.0, 12);
        let top = List.head(verts);
        Assert.assertEq(expected = (12, Some(true)),
            (List.length(verts), Option.map(v -> vecNear(v, at(10.0, 16.0)), top)))

    /// occluderOfBox: 中心+サイズから左上→右上→右下→左下の4頂点。
    @Test
    def testOccluderOfBoxVertices(): Unit \ Assert =
        let verts = Shadow.occluderOfBox(at(10.0, 20.0), at(8.0, 4.0));
        let expected = at(6.0, 18.0) :: at(14.0, 18.0) :: at(14.0, 22.0) :: at(6.0, 22.0) :: Nil;
        Assert.assertEq(expected = true, verticesNear(expected, verts))

    /// occluderOf: Hit.HitShape からの変換が円・箱それぞれ正しい頂点数を作る
    /// （個々のオフセット反映は occluderOfCircle/occluderOfBox 側で確認済み）。
    @Test
    def testOccluderOfHitShape(): Unit \ Assert =
        let pos = at(100.0, 100.0);
        let circleShape = Hit.HitShape.CircleH({ dx = 5.0, dy = 0.0, r = 2.0 });
        let boxShape = Hit.HitShape.BoxH({ dx = 0.0, dy = 5.0, w = 6.0, h = 6.0 });
        let circleVerts = Shadow.occluderOf(pos, circleShape);
        let boxVerts = Shadow.occluderOf(pos, boxShape);
        Assert.assertEq(expected = (12, 4), (List.length(circleVerts), List.length(boxVerts)))

    // ── containsPoint: 影が壁を透過しないことの幾何検証 ──

    /// 光→壁→向こう側の点が一直線に近い配置で、その点が影四角形に含まれることを確認する
    /// （影が壁の向こうを覆えているかの最小限の証拠）。
    @Test
    def testShadowQuadContainsPointBehindWall(): Unit \ Assert =
        let quads = Shadow.shadowQuads(at(-100.0, 0.0), square(), 100.0);
        // right 辺(x=5)の影四角形は光の反対（+x）方向へ伸びる。その延長線上、
        // 壁のすぐ向こう (x=6, y=0) は right 由来の四角形の内側にあるはず。
        let rightQuad = quadStartingAt(quads, 5.0, -5.0);
        let behind = at(6.0, 0.0);
        Assert.assertEq(expected = Some(true),
            Option.map(q -> Shadow.containsPoint(q, behind), rightQuad))

    // ── itemsFor: Light との合成（blend/alpha/z の pin） ──

    /// itemsFor が返す PlacedItem が Multiply・alpha=darkness・cfg#z の黒 Poly になっていることを
    /// pin する（頂点そのものは shadowQuads 側で確認済みなので、ここでは合成の属性だけを見る）。
    @Test
    def testItemsForProducesMultiplyBlackPolyWithConfiguredAlphaAndZ(): Unit \ Assert =
        let light: Light.Light = { at = at(-100.0, 0.0), radius = 50.0, color = { r = 1.0f32, g = 1.0f32, b = 1.0f32 }, halo = 0.0 };
        let segment = at(0.0, -5.0) :: at(0.0, 5.0) :: Nil;
        let cfg = { darkness = 0.6, z = 7, extrudeLength = 100.0 };
        let items = Shadow.itemsFor(light, segment :: Nil, cfg);
        let attrsOf = (placed: Render.PlacedItem) -> match placed#item {
            case Render.Item.Poly(p) => Some((p#blend, p#alpha, p#zIndex, p#color#r))
            case _                   => None
        };
        Assert.assertEq(expected = (1, Some((DrawCmd.BlendMode.Multiply, 0.6f32, 7, 0.0f32))),
            (List.length(items), List.head(items) |> Option.flatMap(attrsOf)))

    /// 逆に、壁の手前（光と壁の間）の点は影四角形に含まれない。
    @Test
    def testShadowQuadExcludesPointInFrontOfWall(): Unit \ Assert =
        let quads = Shadow.shadowQuads(at(-100.0, 0.0), square(), 100.0);
        let rightQuad = quadStartingAt(quads, 5.0, -5.0);
        let inFront = at(-50.0, 0.0);
        Assert.assertEq(expected = Some(false),
            Option.map(q -> Shadow.containsPoint(q, inFront), rightQuad))

    // ── 凹ポリゴン・逆回り入力 ──

    /// L字（6頂点・右上を切り欠いた凹ポリゴン、画面上で時計回り）。
    /// 中心10四方の正方形から (0,-10)-(10,0) の角を欠けさせた形。
    def lShape(): List[Vec2.Vec2] =
        at(-10.0, -10.0) :: at(0.0, -10.0) :: at(0.0, 0.0) ::
        at(10.0, 0.0) :: at(10.0, 10.0) :: at(-10.0, 10.0) :: Nil

    /// 凹ポリゴン（L字）でも背面判定と四角形化が辺ごとに独立して働くことを枚数 pin で確認し、
    /// くぼみ（切り欠き）の内側の点が、凹の内側辺が落とす影四角形にちゃんと含まれる
    /// （凹形状でも壁の向こうを覆えている）ことを見る。正しさは総当たり幾何検証で確認済み。
    @Test
    def testConcavePolygonShadowCoversNotch(): Unit \ Assert =
        let quads = Shadow.shadowQuads(at(-150.0, -30.0), lShape(), 300.0);
        let notchPoint = at(5.0, -5.0);
        let anyContains = quads |> List.exists(q -> Shadow.containsPoint(q, notchPoint));
        Assert.assertEq(expected = (3, true), (List.length(quads), anyContains))

    /// quad の4頂点を「集合として」比較する（逆回り入力では各四角形の先頭頂点が
    /// v1↔v2 の入れ替わりで変わるため、開始点一致の verticesNear は使えない）。
    def sameVertexSet(a: List[Vec2.Vec2], b: List[Vec2.Vec2]): Bool =
        List.length(a) == List.length(b) and
        (a |> List.forAll(va -> b |> List.exists(vb -> vecNear(va, vb))))

    /// 頂点順を逆回り（List.reverse）にしても同じ3枚・同座標（頂点集合として同一）の
    /// 影四角形になる（signedArea の符号吸収がリファクタで一番壊れやすい箇所のため pin する）。
    @Test
    def testReversedWindingProducesSameQuads(): Unit \ Assert =
        let light = at(-100.0, 0.0);
        let forward = Shadow.shadowQuads(light, square(), 100.0);
        let reversed = Shadow.shadowQuads(light, List.reverse(square()), 100.0);
        let everyForwardQuadMatchedInReversed =
            forward |> List.forAll(qf -> reversed |> List.exists(qr -> sameVertexSet(qf, qr)));
        Assert.assertEq(expected = (3, true),
            (List.length(reversed), everyForwardQuadMatchedInReversed))
}
