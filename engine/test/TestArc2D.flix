/// Arc2D ノード（円弧/リング、Godot draw_arc 相当）の挙動テスト。
/// toRenderCmds のセグメント数・非描画条件・頂点座標、setter/getter のラウンドトリップ、
/// CanvasItem / Node2D instance を検証する。
mod TestArc2D {

    def cyan(): Color = {r = 0.2f32, g = 0.8f32, b = 1.0f32}
    def white(): Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}

    def origin(): Vec2.Vec2 = {x = 0.0, y = 0.0}
    def unitScale(): Vec2.Vec2 = {x = 1.0, y = 1.0}

    /// 全周リングは segments 個の塗りコマンド（クアッド）を返す
    @Test
    def testRingReturnsSegmentCmds(): Unit \ Assert =
        let arc = Arc2D.ring(10.0, 2.0, cyan())
            |> Arc2D.setSegments(24);
        let cmds = Arc2D.toRenderCmds(origin(), unitScale(), arc);
        Assert.assertEq(expected = 24, List.length(cmds))

    /// 各セグメントはアヌラスの台形 = 4 頂点を持つ
    @Test
    def testSegmentHasFourVertices(): Unit \ Assert =
        let arc = Arc2D.ring(10.0, 2.0, cyan()) |> Arc2D.setSegments(8);
        let firstLen = Arc2D.toRenderCmds(origin(), unitScale(), arc)
            |> List.head
            |> Option.map(c -> List.length(c#vertices));
        Assert.assertEq(expected = Some(4), firstLen)

    /// endAngle <= startAngle のときは非描画（空リスト）
    @Test
    def testEmptyWhenNoSweep(): Unit \ Assert =
        let arc = Arc2D.make(10.0, 2.0, 1.0, 1.0, cyan());
        Assert.assertEq(expected = 0, List.length(Arc2D.toRenderCmds(origin(), unitScale(), arc)))

    /// 太さ 0 以下のときは非描画（空リスト）
    @Test
    def testEmptyWhenNoWidth(): Unit \ Assert =
        let arc = Arc2D.ring(10.0, 0.0, cyan());
        Assert.assertEq(expected = 0, List.length(Arc2D.toRenderCmds(origin(), unitScale(), arc)))

    /// startAngle=0 の外周始点は screenPos + (radius, 0) に来る（cos0=1, sin0=0）
    @Test
    def testFirstOuterVertexAtStartAngle(): Unit \ Assert =
        let arc = Arc2D.make(10.0, 2.0, 0.0, 3.141592653589793, cyan());
        let firstOuter = Arc2D.toRenderCmds(origin(), unitScale(), arc)
            |> List.head
            |> Option.map(c -> c#vertices)
            |> Option.flatMap(List.head);
        Assert.assertEq(expected = Some(10.0), Option.map(v -> v#x, firstOuter));
        Assert.assertEq(expected = Some(0.0), Option.map(v -> v#y, firstOuter))

    /// 比率→角度換算（startAngle + tau*ratio）で endAngle を駆動できる
    @Test
    def testEndAngleFromRatio(): Unit \ Assert =
        let half = Arc2D.ring(10.0, 2.0, cyan())
            |> Arc2D.setEndAngle(0.0 + Arc2D.tau() * 0.5);
        Assert.assertEq(expected = 3.141592653589793, Arc2D.getEndAngle(half))

    /// segments は 1 未満を 1 にクランプする
    @Test
    def testSegmentsClampedToOne(): Unit \ Assert =
        let arc = Arc2D.ring(10.0, 2.0, cyan()) |> Arc2D.setSegments(0);
        Assert.assertEq(expected = 1, Arc2D.getSegments(arc));
        Assert.assertEq(expected = 1, List.length(Arc2D.toRenderCmds(origin(), unitScale(), arc)))

    /// alpha round-trip
    @Test
    def testAlphaRoundtrip(): Unit \ Assert =
        let arc = Arc2D.ring(10.0, 2.0, cyan()) |> Arc2D.setAlpha(0.5f32);
        Assert.assertEq(expected = 0.5f32, Arc2D.getAlpha(arc))

    /// endAngle round-trip
    @Test
    def testEndAngleRoundtrip(): Unit \ Assert =
        let arc = Arc2D.ring(10.0, 2.0, cyan()) |> Arc2D.setEndAngle(1.25);
        Assert.assertEq(expected = 1.25, Arc2D.getEndAngle(arc))

    /// radius / width round-trip
    @Test
    def testRadiusWidthRoundtrip(): Unit \ Assert =
        let arc = Arc2D.ring(10.0, 2.0, cyan())
            |> Arc2D.setRadius(16.0)
            |> Arc2D.setWidth(3.0);
        Assert.assertEq(expected = 16.0, Arc2D.getRadius(arc));
        Assert.assertEq(expected = 3.0, Arc2D.getWidth(arc))

    /// CanvasItem: modulate round-trip
    @Test
    def testModulateRoundtrip(): Unit \ Assert =
        let arc = Arc2D.ring(10.0, 2.0, cyan())
            |> CanvasItem.setModulate(white());
        Assert.assertEq(expected = 1.0f32, CanvasItem.getModulate(arc)#r)

    /// CanvasItem: visible round-trip
    @Test
    def testVisibleRoundtrip(): Unit \ Assert =
        let arc = Arc2D.ring(10.0, 2.0, cyan()) |> CanvasItem.setVisible(false);
        Assert.assertEq(expected = false, CanvasItem.isVisible(arc))

    /// Node2D: position round-trip（描画原点ずらしに使う）
    @Test
    def testPositionRoundtrip(): Unit \ Assert =
        let arc = Arc2D.ring(10.0, 2.0, cyan())
            |> Node2D.setPosition({x = 85.0, y = 64.0});
        Assert.assertEq(expected = 85.0, Node2D.getPosition(arc)#x);
        Assert.assertEq(expected = 64.0, Node2D.getPosition(arc)#y)
}
