// Tests for Layout module

mod TestLayout {

    def approx(a: Float64, b: Float64): Bool =
        Float64.abs(a - b) < 0.001

    def rectApprox(r: Rect2.Rect2, x: Float64, y: Float64, w: Float64, h: Float64): Bool =
        approx(r#position#x, x) and approx(r#position#y, y)
        and approx(r#size#x, w) and approx(r#size#y, h)

    /// rect サイズを持つ ColorRect を含む 1 ノードの Scene を作る
    def sceneWithColorRect(name: NodeName, size: Vec2.Vec2): Scene[Unit] =
        let rect = ColorRect.make(size, {r = 1.0f32, g = 1.0f32, b = 1.0f32});
        Scene.empty()
            |> Scene.addNode(name, EngineNode.ColorRectWithState(rect, ()))

    def origin100x100(): Rect2.Rect2 =
        {position = {x = 0.0, y = 0.0}, size = {x = 100.0, y = 100.0}}

    // ========================================================================
    // Empty — 何も配置しない
    // ========================================================================

    @Test
    def testEmpty(): Unit \ Assert =
        let scene: Scene[Unit] = Scene.empty();
        let rects = Layout.resolve(origin100x100(), Layout.Empty, scene);
        Assert.assertTrue(Map.size(rects) == 0)

    // ========================================================================
    // Leaf — 単一ノードを origin に配置
    // ========================================================================

    @Test
    def testLeafFillsOrigin(): Unit \ Assert =
        let scene = sceneWithColorRect("bg", {x = 40.0, y = 30.0});
        let layout = Layout.Leaf({path = "bg" :: Nil});
        let rects = Layout.resolve(origin100x100(), layout, scene);
        match Map.get("bg" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 0.0, 0.0, 100.0, 100.0))
            case None    => Assert.assertTrue(false)
        }

    // ========================================================================
    // Padding — 全方向に縮小
    // ========================================================================

    @Test
    def testPaddingShrinksOrigin(): Unit \ Assert =
        let scene = sceneWithColorRect("bg", {x = 40.0, y = 30.0});
        let layout = Layout.MarginContainer({margin =10.0, child = Layout.Leaf({path = "bg" :: Nil})});
        let rects = Layout.resolve(origin100x100(), layout, scene);
        match Map.get("bg" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 10.0, 10.0, 80.0, 80.0))
            case None    => Assert.assertTrue(false)
        }

// ========================================================================
    // VStack — Start 主軸 + Stretch 交差軸
    // ========================================================================

    @Test
    def testVStackStartStretch(): Unit \ Assert =
        // 2 つの ColorRect (20×30 と 20×40) を縦に積む。spacing=10。
        let scene = Scene.empty()
            |> Scene.addNode("a", EngineNode.ColorRectWithState(
                ColorRect.make({x = 20.0, y = 30.0}, {r = 1.0f32, g = 1.0f32, b = 1.0f32}), ()))
            |> Scene.addNode("b", EngineNode.ColorRectWithState(
                ColorRect.make({x = 20.0, y = 40.0}, {r = 1.0f32, g = 1.0f32, b = 1.0f32}), ()));
        let layout = Layout.VBoxContainer({
            separation =10.0,
            alignment  =MainAxisAlign.Begin,
            crossAxis = CrossAxisAlign.Stretch,
            children  = Layout.Leaf({path = "a" :: Nil}) :: Layout.Leaf({path = "b" :: Nil}) :: Nil
        });
        let rects = Layout.resolve(origin100x100(), layout, scene);
        // a: y=0, height=30, x=0, width=100 (stretch)
        match Map.get("a" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 0.0, 0.0, 100.0, 30.0))
            case None    => Assert.assertTrue(false)
        };
        // b: y=40 (=30+10 spacing), height=40, x=0, width=100
        match Map.get("b" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 0.0, 40.0, 100.0, 40.0))
            case None    => Assert.assertTrue(false)
        }

    // ========================================================================
    // HStack — Start 主軸 + Stretch 交差軸
    // ========================================================================

    @Test
    def testHStackStartStretch(): Unit \ Assert =
        // 2 つの ColorRect (32×32) を横に並べる、spacing=4 (InventoryScene 風)。
        let mk = sz -> ColorRect.make(sz, {r = 1.0f32, g = 1.0f32, b = 1.0f32});
        let scene = Scene.empty()
            |> Scene.addNode("s0", EngineNode.ColorRectWithState(mk({x = 32.0, y = 32.0}), ()))
            |> Scene.addNode("s1", EngineNode.ColorRectWithState(mk({x = 32.0, y = 32.0}), ()));
        let layout = Layout.HBoxContainer({
            separation =4.0,
            alignment  =MainAxisAlign.Begin,
            crossAxis = CrossAxisAlign.Stretch,
            children  = Layout.Leaf({path = "s0" :: Nil}) :: Layout.Leaf({path = "s1" :: Nil}) :: Nil
        });
        let rects = Layout.resolve(origin100x100(), layout, scene);
        match Map.get("s0" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 0.0, 0.0, 32.0, 100.0))
            case None    => Assert.assertTrue(false)
        };
        match Map.get("s1" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 36.0, 0.0, 32.0, 100.0))
            case None    => Assert.assertTrue(false)
        }

    // ========================================================================
    // VStack — Center 主軸（中央寄せ）
    // ========================================================================

    @Test
    def testVStackCenterMainAxis(): Unit \ Assert =
        // 2 つの 20×30 ノードを spacing=0、合計高さ 60、中央寄せ → y 開始 = (100-60)/2 = 20
        let mk = sz -> ColorRect.make(sz, {r = 1.0f32, g = 1.0f32, b = 1.0f32});
        let scene = Scene.empty()
            |> Scene.addNode("a", EngineNode.ColorRectWithState(mk({x = 20.0, y = 30.0}), ()))
            |> Scene.addNode("b", EngineNode.ColorRectWithState(mk({x = 20.0, y = 30.0}), ()));
        let layout = Layout.VBoxContainer({
            separation =0.0,
            alignment  =MainAxisAlign.Center,
            crossAxis = CrossAxisAlign.Begin,
            children  = Layout.Leaf({path = "a" :: Nil}) :: Layout.Leaf({path = "b" :: Nil}) :: Nil
        });
        let rects = Layout.resolve(origin100x100(), layout, scene);
        match Map.get("a" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 0.0, 20.0, 20.0, 30.0))
            case None    => Assert.assertTrue(false)
        };
        match Map.get("b" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 0.0, 50.0, 20.0, 30.0))
            case None    => Assert.assertTrue(false)
        }

    // ========================================================================
    // Center — 子レイアウトを矩形中央に
    // ========================================================================

    @Test
    def testCenterPlacesChild(): Unit \ Assert =
        // 40×20 の ColorRect を 100×100 の中央に → (30, 40, 40, 20)
        let scene = sceneWithColorRect("bg", {x = 40.0, y = 20.0});
        let layout = Layout.CenterContainer(Layout.Leaf({path = "bg" :: Nil}));
        let rects = Layout.resolve(origin100x100(), layout, scene);
        match Map.get("bg" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 30.0, 40.0, 40.0, 20.0))
            case None    => Assert.assertTrue(false)
        }

    // ========================================================================
    // Overlay — 複数の子を同じ origin に重ねる（LogScene の Bg + Text 用）
    // ========================================================================

    @Test
    def testOverlayPlacesChildrenAtSameOrigin(): Unit \ Assert =
        // Bg は origin 全体を埋め、Text は Padding で内側に
        let mk = sz -> ColorRect.make(sz, {r = 1.0f32, g = 1.0f32, b = 1.0f32});
        let scene = Scene.empty()
            |> Scene.addNode("bg", EngineNode.ColorRectWithState(mk({x = 100.0, y = 100.0}), ()))
            |> Scene.addNode("text", EngineNode.ColorRectWithState(mk({x = 80.0, y = 80.0}), ()));
        let layout = Layout.Overlay(
            Layout.Leaf({path = "bg" :: Nil}) ::
            Layout.MarginContainer({margin =10.0, child = Layout.Leaf({path = "text" :: Nil})}) :: Nil);
        let rects = Layout.resolve(origin100x100(), layout, scene);
        match Map.get("bg" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 0.0, 0.0, 100.0, 100.0))
            case None    => Assert.assertTrue(false)
        };
        match Map.get("text" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 10.0, 10.0, 80.0, 80.0))
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

    @Test
    def testFromJsonLeaf(): Unit \ Assert =
        let j = parseJson("{\"kind\": \"Leaf\", \"path\": [\"Slot0Bg\"]}");
        match Layout.fromJson(j) {
            case Ok(Layout.Leaf({path})) =>
                Assert.assertTrue(path == "Slot0Bg" :: Nil)
            case _ => Assert.assertTrue(false)
        }

    @Test
    def testFromJsonMarginContainer(): Unit \ Assert =
        let j = parseJson("{\"kind\": \"MarginContainer\", \"margin\": 8.0, \"child\": {\"kind\": \"Leaf\", \"path\": [\"x\"]}}");
        match Layout.fromJson(j) {
            case Ok(Layout.MarginContainer({margin, child = Layout.Leaf({path})})) =>
                Assert.assertTrue(approx(margin, 8.0) and path == "x" :: Nil)
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
    def testFromJsonOverlay(): Unit \ Assert =
        let j = parseJson("{\"kind\": \"Overlay\", \"children\": [{\"kind\": \"Leaf\", \"path\": [\"a\"]}, {\"kind\": \"Leaf\", \"path\": [\"b\"]}]}");
        match Layout.fromJson(j) {
            case Ok(Layout.Overlay(children)) =>
                Assert.assertTrue(List.length(children) == 2)
            case _ => Assert.assertTrue(false)
        }

    /// VBoxContainer の各フィールドと alignment/crossAxis 値の往復確認
    @Test
    def testFromJsonVBoxContainer(): Unit \ Assert =
        let j = parseJson("{\"kind\": \"VBoxContainer\", \"separation\": 8.0, \"alignment\": \"Center\", \"crossAxis\": \"End\", \"children\": [{\"kind\": \"Leaf\", \"path\": [\"a\"]}]}");
        match Layout.fromJson(j) {
            case Ok(Layout.VBoxContainer({separation, alignment, crossAxis, children})) =>
                Assert.assertTrue(approx(separation, 8.0));
                Assert.assertTrue(alignment == MainAxisAlign.Center);
                Assert.assertTrue(crossAxis == CrossAxisAlign.End);
                Assert.assertTrue(List.length(children) == 1)
            case _ => Assert.assertTrue(false)
        }

    /// CenterContainer のラウンドトリップ
    @Test
    def testFromJsonCenterContainer(): Unit \ Assert =
        let j = parseJson("{\"kind\": \"CenterContainer\", \"child\": {\"kind\": \"Leaf\", \"path\": [\"x\"]}}");
        match Layout.fromJson(j) {
            case Ok(Layout.CenterContainer(Layout.Leaf({path}))) =>
                Assert.assertTrue(path == "x" :: Nil)
            case _ => Assert.assertTrue(false)
        }

    /// alignment が "End" のときも正しくパースされる
    @Test
    def testFromJsonAlignmentEnd(): Unit \ Assert =
        let j = parseJson("{\"kind\": \"HBoxContainer\", \"separation\": 0.0, \"alignment\": \"End\", \"crossAxis\": \"Begin\", \"children\": []}");
        match Layout.fromJson(j) {
            case Ok(Layout.HBoxContainer({separation = _, alignment, crossAxis = _, children = _})) =>
                Assert.assertTrue(alignment == MainAxisAlign.End)
            case _ => Assert.assertTrue(false)
        }

    /// 未知の alignment 文字列はエラー
    @Test
    def testFromJsonUnknownAlignmentFails(): Unit \ Assert =
        let j = parseJson("{\"kind\": \"HBoxContainer\", \"separation\": 0.0, \"alignment\": \"SpaceAround\", \"crossAxis\": \"Begin\", \"children\": []}");
        match Layout.fromJson(j) {
            case Err(_) => Assert.assertTrue(true)
            case Ok(_)  => Assert.assertTrue(false)
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

    // ========================================================================
    // Repeat — children 内の繰り返し展開
    // ========================================================================

    /// HBoxContainer の children に Repeat を入れて 5 個に展開
    @Test
    def testFromJsonRepeatExpandsChildren(): Unit \ Assert =
        let j = parseJson("{\"kind\": \"HBoxContainer\", \"separation\": 4.0, \"alignment\": \"Begin\", \"crossAxis\": \"Begin\", \"children\": [{\"kind\": \"Repeat\", \"count\": 5, \"indexVar\": \"i\", \"template\": {\"kind\": \"Leaf\", \"path\": [\"Slot{i}Bg\"]}}]}");
        match Layout.fromJson(j) {
            case Ok(Layout.HBoxContainer({separation = _, alignment = _, crossAxis = _, children})) =>
                // 展開後は 5 個の Leaf が並ぶ
                Assert.assertTrue(List.length(children) == 5);
                // 0 番目の path は ["Slot0Bg"]
                match List.nth(0, children) {
                    case Some(Layout.Leaf({path})) =>
                        Assert.assertTrue(path == "Slot0Bg" :: Nil)
                    case _ => Assert.assertTrue(false)
                };
                // 4 番目の path は ["Slot4Bg"]
                match List.nth(4, children) {
                    case Some(Layout.Leaf({path})) =>
                        Assert.assertTrue(path == "Slot4Bg" :: Nil)
                    case _ => Assert.assertTrue(false)
                }
            case _ => Assert.assertTrue(false)
        }

    /// Repeat の template が複雑 (MarginContainer > Overlay > Leaf × 2) でも全 Leaf の {i} が置換される
    @Test
    def testFromJsonRepeatNestedTemplate(): Unit \ Assert =
        let j = parseJson("{\"kind\": \"HBoxContainer\", \"separation\": 4.0, \"alignment\": \"Begin\", \"crossAxis\": \"Begin\", \"children\": [{\"kind\": \"Repeat\", \"count\": 3, \"indexVar\": \"i\", \"template\": {\"kind\": \"MarginContainer\", \"margin\": 4.0, \"child\": {\"kind\": \"Overlay\", \"children\": [{\"kind\": \"Leaf\", \"path\": [\"Slot{i}Bg\"]}, {\"kind\": \"Leaf\", \"path\": [\"Slot{i}Icon\"]}]}}}]}");
        match Layout.fromJson(j) {
            case Ok(Layout.HBoxContainer({separation = _, alignment = _, crossAxis = _, children})) =>
                Assert.assertTrue(List.length(children) == 3);
                // 1 番目 (i=1) の MarginContainer > Overlay > 2 つの Leaf
                match List.nth(1, children) {
                    case Some(Layout.MarginContainer({margin = _,
                                                       child = Layout.Overlay(leaves)})) =>
                        match leaves {
                            case Layout.Leaf({path = bgPath}) ::
                                 Layout.Leaf({path = iconPath}) :: Nil =>
                                Assert.assertTrue(bgPath == "Slot1Bg" :: Nil);
                                Assert.assertTrue(iconPath == "Slot1Icon" :: Nil)
                            case _ => Assert.assertTrue(false)
                        }
                    case _ => Assert.assertTrue(false)
                }
            case _ => Assert.assertTrue(false)
        }

    // ========================================================================
    // ネスト: Padding > VStack > Leaf × 2
    // ========================================================================

    @Test
    def testNestedPaddingVStack(): Unit \ Assert =
        // padding=10 → 内側 (10,10, 80×80)、VStack で 2 つの Leaf (高さ 30) を spacing=10 で
        let mk = sz -> ColorRect.make(sz, {r = 1.0f32, g = 1.0f32, b = 1.0f32});
        let scene = Scene.empty()
            |> Scene.addNode("a", EngineNode.ColorRectWithState(mk({x = 20.0, y = 30.0}), ()))
            |> Scene.addNode("b", EngineNode.ColorRectWithState(mk({x = 20.0, y = 30.0}), ()));
        let layout = Layout.MarginContainer({margin =10.0, child = Layout.VBoxContainer({
            separation =10.0,
            alignment  =MainAxisAlign.Begin,
            crossAxis = CrossAxisAlign.Stretch,
            children  = Layout.Leaf({path = "a" :: Nil}) :: Layout.Leaf({path = "b" :: Nil}) :: Nil
        })});
        let rects = Layout.resolve(origin100x100(), layout, scene);
        // a: (10, 10, 80, 30)、b: (10, 50, 80, 30)
        match Map.get("a" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 10.0, 10.0, 80.0, 30.0))
            case None    => Assert.assertTrue(false)
        };
        match Map.get("b" :: Nil, rects) {
            case Some(r) => Assert.assertTrue(rectApprox(r, 10.0, 50.0, 80.0, 30.0))
            case None    => Assert.assertTrue(false)
        }

}
