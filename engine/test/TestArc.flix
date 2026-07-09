/// Arc（円弧/リング）の挙動テスト。
/// toRenderCmds のセグメント数・非描画条件・頂点座標、setter/getter のラウンドトリップ、
/// visual / transform 部品を検証する。
mod TestArc {

    def cyan(): Color = {r = 0.2f32, g = 0.8f32, b = 1.0f32}
    def white(): Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}

    def origin(): Vec2.Vec2 = {x = 0.0, y = 0.0}
    def unitScale(): Vec2.Vec2 = {x = 1.0, y = 1.0}

    /// 全周リングは segments 個の塗りコマンド（クアッド）を返す
    @Test
    def testRingReturnsSegmentCmds(): Unit \ Assert =
        let arc = Arc.ring(10.0, 2.0, cyan())
            |> Arc.setSegments(24);
        let cmds = Arc.toRenderCmds(origin(), unitScale(), arc);
        Assert.assertEq(expected = 24, List.length(cmds))

    /// 各セグメントはアヌラスの台形 = 4 頂点を持つ
    @Test
    def testSegmentHasFourVertices(): Unit \ Assert =
        let arc = Arc.ring(10.0, 2.0, cyan()) |> Arc.setSegments(8);
        let firstLen = Arc.toRenderCmds(origin(), unitScale(), arc)
            |> List.head
            |> Option.map(c -> List.length(c#vertices));
        Assert.assertEq(expected = Some(4), firstLen)

    /// endAngle <= startAngle のときは非描画（空リスト）
    @Test
    def testEmptyWhenNoSweep(): Unit \ Assert =
        let arc = Arc.make(10.0, 2.0, 1.0, 1.0, cyan());
        Assert.assertEq(expected = 0, List.length(Arc.toRenderCmds(origin(), unitScale(), arc)))

    /// 太さ 0 以下のときは非描画（空リスト）
    @Test
    def testEmptyWhenNoWidth(): Unit \ Assert =
        let arc = Arc.ring(10.0, 0.0, cyan());
        Assert.assertEq(expected = 0, List.length(Arc.toRenderCmds(origin(), unitScale(), arc)))

    /// startAngle=0 の外周始点は screenPos + (radius, 0) に来る（cos0=1, sin0=0）
    @Test
    def testFirstOuterVertexAtStartAngle(): Unit \ Assert =
        let arc = Arc.make(10.0, 2.0, 0.0, 3.141592653589793, cyan());
        let firstOuter = Arc.toRenderCmds(origin(), unitScale(), arc)
            |> List.head
            |> Option.map(c -> c#vertices)
            |> Option.flatMap(List.head);
        Assert.assertEq(expected = Some(10.0), Option.map(v -> v#x, firstOuter));
        Assert.assertEq(expected = Some(0.0), Option.map(v -> v#y, firstOuter))

    /// 比率→角度換算（startAngle + tau*ratio）で endAngle を駆動できる
    @Test
    def testEndAngleFromRatio(): Unit \ Assert =
        let half = Arc.ring(10.0, 2.0, cyan())
            |> Arc.setEndAngle(0.0 + Arc.tau() * 0.5);
        Assert.assertEq(expected = 3.141592653589793, Arc.getEndAngle(half))

    /// segments は 1 未満を 1 にクランプする
    @Test
    def testSegmentsClampedToOne(): Unit \ Assert =
        let arc = Arc.ring(10.0, 2.0, cyan()) |> Arc.setSegments(0);
        Assert.assertEq(expected = 1, Arc.getSegments(arc));
        Assert.assertEq(expected = 1, List.length(Arc.toRenderCmds(origin(), unitScale(), arc)))

    /// alpha round-trip
    @Test
    def testAlphaRoundtrip(): Unit \ Assert =
        let arc = Arc.ring(10.0, 2.0, cyan()) |> Arc.setAlpha(0.5f32);
        Assert.assertEq(expected = 0.5f32, Arc.getAlpha(arc))

    /// endAngle round-trip
    @Test
    def testEndAngleRoundtrip(): Unit \ Assert =
        let arc = Arc.ring(10.0, 2.0, cyan()) |> Arc.setEndAngle(1.25);
        Assert.assertEq(expected = 1.25, Arc.getEndAngle(arc))

    /// radius / width round-trip
    @Test
    def testRadiusWidthRoundtrip(): Unit \ Assert =
        let arc = Arc.ring(10.0, 2.0, cyan())
            |> Arc.setRadius(16.0)
            |> Arc.setWidth(3.0);
        Assert.assertEq(expected = 16.0, Arc.getRadius(arc));
        Assert.assertEq(expected = 3.0, Arc.getWidth(arc))

    /// Visual: modulate round-trip
    @Test
    def testModulateRoundtrip(): Unit \ Assert =
        let arc = Arc.ring(10.0, 2.0, cyan())
            |> Arc.mapVisual(Visual.setModulate(white()));
        Assert.assertEq(expected = 1.0f32, Visual.getModulate(Arc.visual(arc))#r)

    /// Visual: visible round-trip
    @Test
    def testVisibleRoundtrip(): Unit \ Assert =
        let arc = Arc.ring(10.0, 2.0, cyan()) |> Arc.mapVisual(Visual.setVisible(false));
        Assert.assertEq(expected = false, Visual.getVisible(Arc.visual(arc)))

    /// Transform: position round-trip（描画原点ずらしに使う）
    @Test
    def testPositionRoundtrip(): Unit \ Assert =
        let arc = Arc.ring(10.0, 2.0, cyan())
            |> Arc.mapTransform(Transform.setPosition({x = 85.0, y = 64.0}));
        Assert.assertEq(expected = 85.0, Transform.getPosition(Arc.transform(arc))#x);
        Assert.assertEq(expected = 64.0, Transform.getPosition(Arc.transform(arc))#y)
}
