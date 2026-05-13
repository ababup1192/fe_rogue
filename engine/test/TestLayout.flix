// Tests for Layout module

mod TestLayout {

    def approx(a: Float64, b: Float64): Bool =
        Float64.abs(a - b) < 0.001

    def rectApprox(r: Rect2.Rect2, x: Float64, y: Float64, w: Float64, h: Float64): Bool =
        approx(r#position#x, x) and approx(r#position#y, y)
        and approx(r#size#x, w) and approx(r#size#y, h)

    /// 空の JSON definition (resolve / measure テストでは Node の definition は使われない)
    def stubJson(): Json.JsonElement =
        Json.JsonElement.JsonObject(Map.empty())

    /// 指定 name の Layout.Node を作る (definition は stub)
    def nodeRef(name: String): Layout =
        Layout.Node({name = name, definition = stubJson()})

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
    // Empty — 何も配置しない
    // ========================================================================

    @Test
    def testEmpty(): Unit \ Assert =
        let scene: Scene[Unit] = Scene.empty();
        let rects = resolveRoot(Layout.Empty, scene);
        Assert.assertTrue(Map.size(rects) == 0)

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
    // Overlay — 複数の子を同じ origin に重ねる
    // ========================================================================

    @Test
    def testOverlayPlacesChildrenAtSameOrigin(): Unit \ Assert =
        let mk = sz -> ColorRect.make(sz, {r = 1.0f32, g = 1.0f32, b = 1.0f32});
        let scene = Scene.empty()
            |> Scene.addNode("bg", EngineNode.ColorRectWithState(mk({x = 100.0, y = 100.0}), ()))
            |> Scene.addNode("text", EngineNode.ColorRectWithState(mk({x = 80.0, y = 80.0}), ()));
        let layout = Layout.Overlay(
            nodeRef("bg") ::
            Layout.MarginContainer({margin = 10.0, child = nodeRef("text")}) :: Nil);
        let rects = resolveRoot(layout, scene);
        match Map.get("bg" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 0.0, 0.0, 100.0, 100.0))
            case None    => Assert.assertTrue(false)
        };
        match Map.get("text" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 10.0, 10.0, 80.0, 80.0))
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

    def parseJson(text: String): Json.JsonElement =
        match Json.Parse.parse(text) {
            case Some(j) => j
            case None    => bug!("JSON parse failed for test input: ${text}")
        }

    @Test
    def testFromJsonEmpty(): Unit \ Assert =
        let j = parseJson("{\"kind\": \"Empty\"}");
        match Layout.fromJson(j) {
            case Ok(Layout.Empty) => Assert.assertTrue(true)
            case _                 => Assert.assertTrue(false)
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
        let j = parseJson("{\"kind\": \"MarginContainer\", \"margin\": 8.0, \"child\": {\"kind\": \"Empty\"}}");
        match Layout.fromJson(j) {
            case Ok(Layout.MarginContainer({margin, child = Layout.Empty})) =>
                Assert.assertTrue(approx(margin, 8.0))
            case _ => Assert.assertTrue(false)
        }

    @Test
    def testFromJsonHBoxContainer(): Unit \ Assert =
        let j = parseJson("{\"kind\": \"HBoxContainer\", \"separation\": 4.0, \"alignment\": \"Begin\", \"crossAxis\": \"Stretch\", \"children\": [{\"kind\": \"Empty\"}, {\"kind\": \"Empty\"}]}");
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
        let j = parseJson("{\"kind\": \"VBoxContainer\", \"separation\": 8.0, \"alignment\": \"Center\", \"crossAxis\": \"End\", \"children\": [{\"kind\": \"Empty\"}]}");
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
        let j = parseJson("{\"kind\": \"CenterContainer\", \"child\": {\"kind\": \"Empty\"}}");
        match Layout.fromJson(j) {
            case Ok(Layout.CenterContainer(Layout.Empty)) => Assert.assertTrue(true)
            case _ => Assert.assertTrue(false)
        }

    @Test
    def testFromJsonOverlay(): Unit \ Assert =
        let j = parseJson("{\"kind\": \"Overlay\", \"children\": [{\"type\": \"ColorRect\", \"name\": \"a\", \"size\": [10, 10]}, {\"type\": \"ColorRect\", \"name\": \"b\", \"size\": [10, 10]}]}");
        match Layout.fromJson(j) {
            case Ok(Layout.Overlay(children)) =>
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
    // Repeat — children 内の繰り返し展開 (node も layout も同じ Repeat で展開)
    // ========================================================================

    /// HBoxContainer の children に Repeat (node template) を入れて 5 個に展開
    @Test
    def testFromJsonRepeatExpandsNodes(): Unit \ Assert =
        let j = parseJson("{\"kind\": \"HBoxContainer\", \"separation\": 4.0, \"alignment\": \"Begin\", \"crossAxis\": \"Begin\", \"children\": [{\"kind\": \"Repeat\", \"count\": 5, \"indexVar\": \"i\", \"template\": {\"type\": \"ColorRect\", \"name\": \"Slot{i}Bg\", \"size\": [32, 32]}}]}");
        match Layout.fromJson(j) {
            case Ok(Layout.HBoxContainer({separation = _, alignment = _, crossAxis = _, children})) =>
                Assert.assertTrue(List.length(children) == 5);
                match List.nth(0, children) {
                    case Some(Layout.Node({name, definition = _})) =>
                        Assert.assertTrue(name == "Slot0Bg")
                    case _ => Assert.assertTrue(false)
                };
                match List.nth(4, children) {
                    case Some(Layout.Node({name, definition = _})) =>
                        Assert.assertTrue(name == "Slot4Bg")
                    case _ => Assert.assertTrue(false)
                }
            case _ => Assert.assertTrue(false)
        }

    /// Repeat の template が複雑 (Overlay > Node + MarginContainer > Node) でも全 Node の {i} が置換される
    @Test
    def testFromJsonRepeatNestedTemplate(): Unit \ Assert =
        let j = parseJson("{\"kind\": \"HBoxContainer\", \"separation\": 4.0, \"alignment\": \"Begin\", \"crossAxis\": \"Begin\", \"children\": [{\"kind\": \"Repeat\", \"count\": 3, \"indexVar\": \"i\", \"template\": {\"kind\": \"Overlay\", \"children\": [{\"type\": \"ColorRect\", \"name\": \"Slot{i}Bg\", \"size\": [32, 32]}, {\"kind\": \"MarginContainer\", \"margin\": 4.0, \"child\": {\"type\": \"TextureRect\", \"name\": \"Slot{i}Icon\", \"size\": [24, 24]}}]}}]}");
        match Layout.fromJson(j) {
            case Ok(Layout.HBoxContainer({separation = _, alignment = _, crossAxis = _, children})) =>
                Assert.assertTrue(List.length(children) == 3);
                match List.nth(1, children) {
                    case Some(Layout.Overlay(leaves)) =>
                        match leaves {
                            case Layout.Node({name = bgName, definition = _}) ::
                                 Layout.MarginContainer({margin = _,
                                     child = Layout.Node({name = iconName, definition = _})}) :: Nil =>
                                Assert.assertTrue(bgName == "Slot1Bg");
                                Assert.assertTrue(iconName == "Slot1Icon")
                            case _ => Assert.assertTrue(false)
                        }
                    case _ => Assert.assertTrue(false)
                }
            case _ => Assert.assertTrue(false)
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
