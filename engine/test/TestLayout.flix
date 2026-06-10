// Tests for Layout module

mod TestLayout {

    def approx(a: Float64, b: Float64): Bool =
        Float64.abs(a - b) < 0.001

    def rectApprox(r: Rect2.Rect2, x: Float64, y: Float64, w: Float64, h: Float64): Bool =
        approx(r#position#x, x) and approx(r#position#y, y)
        and approx(r#size#x, w) and approx(r#size#y, h)

    /// 空の JSON definition (resolve / measure テストでは Node の definition は使われない)
    def stubJson(): Util.Json.Json =
        Util.Json.Json.JObject(Map.empty())

    /// 指定 name の Layout.Node を作る (definition は stub)
    def nodeRef(name: String): Layout =
        Layout.Node({name = name, definition = stubJson()})

    /// anchor preset を JSON definition に含む Layout.Node を作る (Panel テスト用)
    def nodeRefWithAnchor(name: String, anchorStr: String): Layout =
        let json = parseJson("{\"type\": \"ColorRect\", \"name\": \"${name}\", \"anchor\": \"${anchorStr}\"}");
        Layout.Node({name = name, definition = json})

    /// anchor + margin の JSON definition を持つ Layout.Node (Panel テスト用)
    def nodeRefWithAnchorMargin(name: String, anchorStr: String, margin: Float64): Layout =
        let json = parseJson("{\"type\": \"ColorRect\", \"name\": \"${name}\", \"anchor\": \"${anchorStr}\", \"margin\": ${margin}}");
        Layout.Node({name = name, definition = json})

    /// rect サイズを持つ ColorRect を含む 1 ノードの Scene を作る
    def sceneWithColorRect(name: NodeName, size: Vec2.Vec2): Scene[Unit] =
        let rect = ColorRect.make(size, {r = 1.0f32, g = 1.0f32, b = 1.0f32});
        Scene.empty()
            |> Scene.addNode(name, EngineNode.ColorRectWithState(rect, ()))

    def origin100x100(): Rect2.Rect2 =
        {position = {x = 0.0, y = 0.0}, size = {x = 100.0, y = 100.0}}

    /// resolve 用の便利関数: parentPath = Nil で呼ぶ (テストの node は scene tree root にある)
    def resolveRoot(layout: Layout, scene: Scene[Unit]): Map[NodePath, Rect2.Rect2] =
        Layout.resolve((Nil: NodePath), origin100x100(), layout, scene)

    // ========================================================================
    // Node — 単一ノードを origin に配置
    // ========================================================================

    @Test
    def testNodeFillsOrigin(): Unit \ Assert =
        let scene = sceneWithColorRect("bg", {x = 40.0, y = 30.0});
        let rects = resolveRoot(nodeRef("bg"), scene);
        match Map.get("bg" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 0.0, 0.0, 100.0, 100.0))
            case None    => Assert.assertTrue(false)
        }

    // ========================================================================
    // MarginContainer — 全方向に縮小
    // ========================================================================

    @Test
    def testMarginShrinksOrigin(): Unit \ Assert =
        let scene = sceneWithColorRect("bg", {x = 40.0, y = 30.0});
        let layout = Layout.MarginContainer({margin = 10.0, child = nodeRef("bg")});
        let rects = resolveRoot(layout, scene);
        match Map.get("bg" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 10.0, 10.0, 80.0, 80.0))
            case None    => Assert.assertTrue(false)
        }

    // ========================================================================
    // VBoxContainer — Begin 主軸 + Stretch 交差軸
    // ========================================================================

    @Test
    def testVBoxContainerBeginStretch(): Unit \ Assert =
        let mk = sz -> ColorRect.make(sz, {r = 1.0f32, g = 1.0f32, b = 1.0f32});
        let scene = Scene.empty()
            |> Scene.addNode("a", EngineNode.ColorRectWithState(mk({x = 20.0, y = 30.0}), ()))
            |> Scene.addNode("b", EngineNode.ColorRectWithState(mk({x = 20.0, y = 40.0}), ()));
        let layout = Layout.VBoxContainer({
            separation = 10.0,
            alignment  = MainAxisAlign.Begin,
            crossAxis  = CrossAxisAlign.Stretch,
            children   = nodeRef("a") :: nodeRef("b") :: Nil
        });
        let rects = resolveRoot(layout, scene);
        match Map.get("a" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 0.0, 0.0, 100.0, 30.0))
            case None    => Assert.assertTrue(false)
        };
        match Map.get("b" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 0.0, 40.0, 100.0, 40.0))
            case None    => Assert.assertTrue(false)
        }

    // ========================================================================
    // HBoxContainer — Begin 主軸 + Stretch 交差軸
    // ========================================================================

    @Test
    def testHBoxContainerBeginStretch(): Unit \ Assert =
        let mk = sz -> ColorRect.make(sz, {r = 1.0f32, g = 1.0f32, b = 1.0f32});
        let scene = Scene.empty()
            |> Scene.addNode("s0", EngineNode.ColorRectWithState(mk({x = 32.0, y = 32.0}), ()))
            |> Scene.addNode("s1", EngineNode.ColorRectWithState(mk({x = 32.0, y = 32.0}), ()));
        let layout = Layout.HBoxContainer({
            separation = 4.0,
            alignment  = MainAxisAlign.Begin,
            crossAxis  = CrossAxisAlign.Stretch,
            children   = nodeRef("s0") :: nodeRef("s1") :: Nil
        });
        let rects = resolveRoot(layout, scene);
        match Map.get("s0" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 0.0, 0.0, 32.0, 100.0))
            case None    => Assert.assertTrue(false)
        };
        match Map.get("s1" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 36.0, 0.0, 32.0, 100.0))
            case None    => Assert.assertTrue(false)
        }

    // ========================================================================
    // VBoxContainer — Center 主軸（中央寄せ）
    // ========================================================================

    @Test
    def testVBoxContainerCenterMainAxis(): Unit \ Assert =
        let mk = sz -> ColorRect.make(sz, {r = 1.0f32, g = 1.0f32, b = 1.0f32});
        let scene = Scene.empty()
            |> Scene.addNode("a", EngineNode.ColorRectWithState(mk({x = 20.0, y = 30.0}), ()))
            |> Scene.addNode("b", EngineNode.ColorRectWithState(mk({x = 20.0, y = 30.0}), ()));
        let layout = Layout.VBoxContainer({
            separation = 0.0,
            alignment  = MainAxisAlign.Center,
            crossAxis  = CrossAxisAlign.Begin,
            children   = nodeRef("a") :: nodeRef("b") :: Nil
        });
        let rects = resolveRoot(layout, scene);
        match Map.get("a" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 0.0, 20.0, 20.0, 30.0))
            case None    => Assert.assertTrue(false)
        };
        match Map.get("b" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 0.0, 50.0, 20.0, 30.0))
            case None    => Assert.assertTrue(false)
        }

    // ========================================================================
    // CenterContainer — 子レイアウトを矩形中央に
    // ========================================================================

    @Test
    def testCenterPlacesChild(): Unit \ Assert =
        let scene = sceneWithColorRect("bg", {x = 40.0, y = 20.0});
        let layout = Layout.CenterContainer(nodeRef("bg"));
        let rects = resolveRoot(layout, scene);
        match Map.get("bg" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 30.0, 40.0, 40.0, 20.0))
            case None    => Assert.assertTrue(false)
        }

    // ========================================================================
    // Panel — 各子を独自 anchor で配置 (Overlay 代替)
    // ========================================================================

    /// FullRect 子は親 rect 全面に sizing される
    @Test
    def testPanelFullRectFillsParent(): Unit \ Assert =
        let mk = sz -> ColorRect.make(sz, {r = 1.0f32, g = 1.0f32, b = 1.0f32});
        let scene = Scene.empty()
            |> Scene.addNode("bg", EngineNode.ColorRectWithState(mk({x = 10.0, y = 10.0}), ()));
        let layout = Layout.Panel(nodeRefWithAnchor("bg", "FullRect") :: Nil);
        let rects = resolveRoot(layout, scene);
        match Map.get("bg" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 0.0, 0.0, 100.0, 100.0))
            case None    => Assert.assertTrue(false)
        }

    /// FullRect + margin は親 rect から margin 分 inset される
    @Test
    def testPanelFullRectWithMargin(): Unit \ Assert =
        let mk = sz -> ColorRect.make(sz, {r = 1.0f32, g = 1.0f32, b = 1.0f32});
        let scene = Scene.empty()
            |> Scene.addNode("text", EngineNode.ColorRectWithState(mk({x = 10.0, y = 10.0}), ()));
        let layout = Layout.Panel(nodeRefWithAnchorMargin("text", "FullRect", 2.0) :: Nil);
        let rects = resolveRoot(layout, scene);
        match Map.get("text" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 2.0, 2.0, 96.0, 96.0))
            case None    => Assert.assertTrue(false)
        }

    /// Center 子は自然 size を保持して親矩形の中央に配置
    @Test
    def testPanelCenterPlacesChild(): Unit \ Assert =
        let mk = sz -> ColorRect.make(sz, {r = 1.0f32, g = 1.0f32, b = 1.0f32});
        let scene = Scene.empty()
            |> Scene.addNode("icon", EngineNode.ColorRectWithState(mk({x = 24.0, y = 24.0}), ()));
        let layout = Layout.Panel(nodeRefWithAnchor("icon", "Center") :: Nil);
        let rects = resolveRoot(layout, scene);
        match Map.get("icon" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 38.0, 38.0, 24.0, 24.0))
            case None    => Assert.assertTrue(false)
        }

    /// anchor 未指定の Panel 子は TopLeft 扱い
    @Test
    def testPanelDefaultsToTopLeft(): Unit \ Assert =
        let mk = sz -> ColorRect.make(sz, {r = 1.0f32, g = 1.0f32, b = 1.0f32});
        let scene = Scene.empty()
            |> Scene.addNode("a", EngineNode.ColorRectWithState(mk({x = 30.0, y = 20.0}), ()));
        // nodeRef は anchor field なし → TopLeft
        let layout = Layout.Panel(nodeRef("a") :: Nil);
        let rects = resolveRoot(layout, scene);
        match Map.get("a" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 0.0, 0.0, 30.0, 20.0))
            case None    => Assert.assertTrue(false)
        }

    /// Panel は Bg (FullRect) と Icon (Center) を同じ親矩形上に重ねられる
    @Test
    def testPanelBgPlusCenterIcon(): Unit \ Assert =
        let mk = sz -> ColorRect.make(sz, {r = 1.0f32, g = 1.0f32, b = 1.0f32});
        let scene = Scene.empty()
            |> Scene.addNode("bg", EngineNode.ColorRectWithState(mk({x = 10.0, y = 10.0}), ()))
            |> Scene.addNode("icon", EngineNode.ColorRectWithState(mk({x = 24.0, y = 24.0}), ()));
        let layout = Layout.Panel(
            nodeRefWithAnchor("bg", "FullRect") ::
            nodeRefWithAnchor("icon", "Center") :: Nil);
        let rects = resolveRoot(layout, scene);
        match Map.get("bg" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 0.0, 0.0, 100.0, 100.0))
            case None    => Assert.assertTrue(false)
        };
        match Map.get("icon" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 38.0, 38.0, 24.0, 24.0))
            case None    => Assert.assertTrue(false)
        }

    // ========================================================================
    // Anchor preset — 個別位置算出
    // ========================================================================

    @Test
    def testAnchorTopRight(): Unit \ Assert =
        let mk = sz -> ColorRect.make(sz, {r = 1.0f32, g = 1.0f32, b = 1.0f32});
        let scene = Scene.empty()
            |> Scene.addNode("a", EngineNode.ColorRectWithState(mk({x = 20.0, y = 10.0}), ()));
        let layout = Layout.Panel(nodeRefWithAnchor("a", "TopRight") :: Nil);
        let rects = resolveRoot(layout, scene);
        match Map.get("a" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 80.0, 0.0, 20.0, 10.0))
            case None    => Assert.assertTrue(false)
        }

    @Test
    def testAnchorBottomLeft(): Unit \ Assert =
        let mk = sz -> ColorRect.make(sz, {r = 1.0f32, g = 1.0f32, b = 1.0f32});
        let scene = Scene.empty()
            |> Scene.addNode("a", EngineNode.ColorRectWithState(mk({x = 20.0, y = 10.0}), ()));
        let layout = Layout.Panel(nodeRefWithAnchor("a", "BottomLeft") :: Nil);
        let rects = resolveRoot(layout, scene);
        match Map.get("a" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 0.0, 90.0, 20.0, 10.0))
            case None    => Assert.assertTrue(false)
        }

    @Test
    def testAnchorBottomRight(): Unit \ Assert =
        let mk = sz -> ColorRect.make(sz, {r = 1.0f32, g = 1.0f32, b = 1.0f32});
        let scene = Scene.empty()
            |> Scene.addNode("a", EngineNode.ColorRectWithState(mk({x = 20.0, y = 10.0}), ()));
        let layout = Layout.Panel(nodeRefWithAnchor("a", "BottomRight") :: Nil);
        let rects = resolveRoot(layout, scene);
        match Map.get("a" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 80.0, 90.0, 20.0, 10.0))
            case None    => Assert.assertTrue(false)
        }

    // ========================================================================
    // parentPath が node 名に prepend される
    // ========================================================================

    @Test
    def testParentPathPrependsToNodeName(): Unit \ Assert =
        // node "Bg" を ["Inventory", "Bg"] というパスで scene に追加し、
        // parentPath = ["Inventory"] で resolve すると path が ["Inventory", "Bg"] になる
        let bg = ColorRect.make({x = 32.0, y = 32.0}, {r = 1.0f32, g = 1.0f32, b = 1.0f32});
        let layer = CanvasLayer.make(1);
        let scene = Scene.empty()
            |> Scene.addNode("Inventory", EngineNode.CanvasLayerWithState(layer, ()))
            |> Scene.addChild("Inventory", "Bg",
                EngineNode.ColorRectWithState(bg, ()));
        let layout = nodeRef("Bg");
        let rects = Layout.resolve("Inventory" :: Nil, origin100x100(), layout, scene);
        match Map.get("Inventory" :: "Bg" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 0.0, 0.0, 100.0, 100.0))
            case None    => Assert.assertTrue(false)
        }

    // ========================================================================
    // fromJson — JSON デシリアライズ
    // ========================================================================

    def parseJson(text: String): Util.Json.Json =
        match JsonCompat.parse(text) {
            case Some(j) => j
            case None    => bug!("JSON parse failed for test input: ${text}")
        }

    /// "type" を持つ object は Layout.Node として parse される
    @Test
    def testFromJsonNodeDefinition(): Unit \ Assert =
        let j = parseJson("{\"type\": \"ColorRect\", \"name\": \"Slot0Bg\", \"size\": [32, 32]}");
        match Layout.fromJson(j) {
            case Ok(Layout.Node({name, definition = _})) =>
                Assert.assertTrue(name == "Slot0Bg")
            case _ => Assert.assertTrue(false)
        }

    @Test
    def testFromJsonMarginContainer(): Unit \ Assert =
        let j = parseJson("{\"kind\": \"MarginContainer\", \"margin\": 8.0, \"child\": {\"kind\": \"Panel\", \"children\": []}}");
        match Layout.fromJson(j) {
            case Ok(Layout.MarginContainer({margin, child = Layout.Panel(Nil)})) =>
                Assert.assertTrue(approx(margin, 8.0))
            case _ => Assert.assertTrue(false)
        }

    @Test
    def testFromJsonHBoxContainer(): Unit \ Assert =
        let j = parseJson("{\"kind\": \"HBoxContainer\", \"separation\": 4.0, \"alignment\": \"Begin\", \"crossAxis\": \"Stretch\", \"children\": [{\"kind\": \"Panel\", \"children\": []}, {\"kind\": \"Panel\", \"children\": []}]}");
        match Layout.fromJson(j) {
            case Ok(Layout.HBoxContainer({separation, alignment, crossAxis, children})) =>
                Assert.assertTrue(approx(separation, 4.0));
                Assert.assertTrue(alignment == MainAxisAlign.Begin);
                Assert.assertTrue(crossAxis == CrossAxisAlign.Stretch);
                Assert.assertTrue(List.length(children) == 2)
            case _ => Assert.assertTrue(false)
        }

    @Test
    def testFromJsonVBoxContainer(): Unit \ Assert =
        let j = parseJson("{\"kind\": \"VBoxContainer\", \"separation\": 8.0, \"alignment\": \"Center\", \"crossAxis\": \"End\", \"children\": [{\"kind\": \"Panel\", \"children\": []}]}");
        match Layout.fromJson(j) {
            case Ok(Layout.VBoxContainer({separation, alignment, crossAxis, children})) =>
                Assert.assertTrue(approx(separation, 8.0));
                Assert.assertTrue(alignment == MainAxisAlign.Center);
                Assert.assertTrue(crossAxis == CrossAxisAlign.End);
                Assert.assertTrue(List.length(children) == 1)
            case _ => Assert.assertTrue(false)
        }

    @Test
    def testFromJsonCenterContainer(): Unit \ Assert =
        let j = parseJson("{\"kind\": \"CenterContainer\", \"child\": {\"kind\": \"Panel\", \"children\": []}}");
        match Layout.fromJson(j) {
            case Ok(Layout.CenterContainer(Layout.Panel(Nil))) => Assert.assertTrue(true)
            case _ => Assert.assertTrue(false)
        }

    @Test
    def testFromJsonPanel(): Unit \ Assert =
        let j = parseJson("{\"kind\": \"Panel\", \"children\": [{\"type\": \"ColorRect\", \"name\": \"a\", \"anchor\": \"FullRect\"}, {\"type\": \"ColorRect\", \"name\": \"b\", \"anchor\": \"Center\", \"size\": [10, 10]}]}");
        match Layout.fromJson(j) {
            case Ok(Layout.Panel(children)) =>
                Assert.assertTrue(List.length(children) == 2)
            case _ => Assert.assertTrue(false)
        }

    @Test
    def testFromJsonUnknownKindFails(): Unit \ Assert =
        let j = parseJson("{\"kind\": \"NotARealKind\"}");
        match Layout.fromJson(j) {
            case Err(_) => Assert.assertTrue(true)
            case Ok(_)  => Assert.assertTrue(false)
        }

    @Test
    def testFromJsonMissingFieldFails(): Unit \ Assert =
        let j = parseJson("{\"kind\": \"MarginContainer\"}");  // child フィールド欠落
        match Layout.fromJson(j) {
            case Err(_) => Assert.assertTrue(true)
            case Ok(_)  => Assert.assertTrue(false)
        }

    @Test
    def testFromJsonUnknownAlignmentFails(): Unit \ Assert =
        let j = parseJson("{\"kind\": \"HBoxContainer\", \"separation\": 0.0, \"alignment\": \"SpaceAround\", \"crossAxis\": \"Begin\", \"children\": []}");
        match Layout.fromJson(j) {
            case Err(_) => Assert.assertTrue(true)
            case Ok(_)  => Assert.assertTrue(false)
        }

    // ========================================================================
    // ネスト: MarginContainer > VBoxContainer > Node × 2
    // ========================================================================

    @Test
    def testNestedMarginVBoxContainer(): Unit \ Assert =
        let mk = sz -> ColorRect.make(sz, {r = 1.0f32, g = 1.0f32, b = 1.0f32});
        let scene = Scene.empty()
            |> Scene.addNode("a", EngineNode.ColorRectWithState(mk({x = 20.0, y = 30.0}), ()))
            |> Scene.addNode("b", EngineNode.ColorRectWithState(mk({x = 20.0, y = 30.0}), ()));
        let layout = Layout.MarginContainer({margin = 10.0, child = Layout.VBoxContainer({
            separation = 10.0,
            alignment  = MainAxisAlign.Begin,
            crossAxis  = CrossAxisAlign.Stretch,
            children   = nodeRef("a") :: nodeRef("b") :: Nil
        })});
        let rects = resolveRoot(layout, scene);
        match Map.get("a" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 10.0, 10.0, 80.0, 30.0))
            case None    => Assert.assertTrue(false)
        };
        match Map.get("b" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 10.0, 50.0, 80.0, 30.0))
            case None    => Assert.assertTrue(false)
        }

}
