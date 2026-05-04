// Tests for Overlay — エディタ ON 表示 + 選択枠の描画
//
// Scene 変換が中心なので、ノード追加結果（ファサードの子に何があるか）を確認する形で
// 検証する。`addSelectionBox` は `EditableNode.findByNodePath` 経由で
// `GameEngine.Game.getTextureInfo` を使うのでモックハンドラを噛ませる

mod TestOverlay {

    /// テスト用のダミー FontAtlas（空のグリフマップ）
    def testFontAtlas(): FontAtlas = {
        textureName = "font_test",
        fontSize = 32.0,
        textureSize = 512.0,
        ascent = 0.0,
        descent = 0.0,
        lineGap = 0.0,
        glyphs = Map.empty()
    }

    /// すべての texture が 32x32 を返す GameEngine.Game ハンドラ
    def withMockTexture32(f: Unit -> a \ ef + GameEngine.Game): a \ ef =
        run f() with handler GameEngine.Game {
            def render(_, k) = k(())
            def shouldClose(k) = k(false)
            def getDeltaTime(k) = k(0.016)
            def isKeyPressed(_, k) = k(false)
            def getMousePosition(k) = k({x = 0.0, y = 0.0})
            def isMouseButtonPressed(_, k) = k(false)
            def getFontAtlas(_, _) = bug!("font not used")
            def getViewportRect(k) = k({position = {x = 0.0, y = 0.0}, size = {x = 480.0, y = 720.0}})
            def getTextureInfo(_, k) = k(Some({id = 0i32, width = 32.0, height = 32.0}))
            def setCursor(_, k) = k(())
        }

    // ====================================================================
    // addEditorIndicator — EDITOR ラベルを最前面 CanvasLayer に追加
    // ====================================================================

    /// 空シーンに addEditorIndicator すると、ラベル用 CanvasLayer + その下の Label2D が増える
    @Test
    def testAddEditorIndicatorAddsLayerAndLabel(): Unit \ Assert =
        let s: Scene[NodeTag] = Scene.empty();
        let result = Overlay.addEditorIndicator(testFontAtlas(), s);
        let layerExists =
            Scene.getEngineNode("_editor_indicator_layer" :: Nil, result)
                |> Option.exists(node -> match node {
                    case EngineNode.CanvasLayerWithState(_, _) => true
                    case _ => false
                });
        let labelExists =
            Scene.getEngineNode("_editor_indicator_layer" :: "_editor_indicator_label" :: Nil, result)
                |> Option.exists(node -> match node {
                    case EngineNode.Label2DWithState(_, _) => true
                    case _ => false
                });
        Assert.assertEq(expected = (true, true), (layerExists, labelExists))

    /// addEditorIndicator は元のシーンの他のノードを破壊しない
    @Test
    def testAddEditorIndicatorPreservesExistingNodes(): Unit \ Assert =
        let sprite = Sprite2D.make("dummy.png", {x = 0.0, y = 0.0}, {x = 1.0, y = 1.0});
        let s: Scene[NodeTag] = Scene.empty();
        let scene = s |> Scene.addNode("hero",
            EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag));
        let result = Overlay.addEditorIndicator(testFontAtlas(), scene);
        let heroStillThere = Option.nonEmpty(
            Scene.getEngineNode("hero" :: Nil, result));
        Assert.assertEq(expected = true, heroStillThere)

    // ====================================================================
    // addSelectionBox — 選択中ノードを 4 辺で囲む
    // ====================================================================

    /// selected = None なら scene は変わらない
    @Test
    def testAddSelectionBoxNoneIsNoOp(): Unit \ Assert =
        let s: Scene[NodeTag] = Scene.empty();
        let scene = s;
        let result = withMockTexture32(() ->
            Overlay.addSelectionBox(Map.empty(), None, {x = 0.0, y = 0.0}, scene));
        let boxLayerAbsent = Option.isEmpty(
            Scene.getEngineNode("_editor_box_layer" :: Nil, result));
        Assert.assertEq(expected = true, boxLayerAbsent)

    /// 選択中 entry がない（rootJsonIndex に登録外）なら何も追加しない
    def testAddSelectionBoxUnknownRootIsNoOp(): Unit \ {Assert, GameEngine.Game} =
        let sprite = Sprite2D.make("dummy.png", {x = 0.0, y = 0.0}, {x = 1.0, y = 1.0});
        let s: Scene[NodeTag] = Scene.empty();
        let scene = s |> Scene.addNode("hero",
            EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag));
        // index に "hero" を入れていない → entry が見つからない
        let result = Overlay.addSelectionBox(
            Map.empty(),
            Some(("hero.json", "hero" :: Nil)),
            {x = 0.0, y = 0.0},
            scene);
        let boxLayerAbsent = Option.isEmpty(
            Scene.getEngineNode("_editor_box_layer" :: Nil, result));
        Assert.assertEq(expected = true, boxLayerAbsent)

    @Test
    def testAddSelectionBoxUnknownRootIsNoOpRunner(): Unit \ Assert =
        withMockTexture32(testAddSelectionBoxUnknownRootIsNoOp)

    // ====================================================================
    // addHoverBox — マウス位置の編集対象に薄い枠を描く
    // ====================================================================

    /// マウスがどのノード上にもないなら hover 層は追加されない
    def testAddHoverBoxNoHitIsNoOp(): Unit \ {Assert, GameEngine.Game} =
        let sprite = Sprite2D.make("dummy.png", {x = 100.0, y = 100.0}, {x = 1.0, y = 1.0});
        let s: Scene[NodeTag] = Scene.empty();
        let scene = s |> Scene.addNode("hero",
            EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag));
        let index = Map#{"hero" => "hero.json"};
        // マウスはスプライト矩形の遥か外
        let result = Overlay.addHoverBox(index, {x = 500.0, y = 500.0}, None,
                                         {x = 0.0, y = 0.0}, scene);
        let hoverLayerAbsent = Option.isEmpty(
            Scene.getEngineNode("_editor_hover_layer" :: Nil, result));
        Assert.assertEq(expected = true, hoverLayerAbsent)

    @Test
    def testAddHoverBoxNoHitIsNoOpRunner(): Unit \ Assert =
        withMockTexture32(testAddHoverBoxNoHitIsNoOp)

    /// マウスが選択中ノードと同じノードを指しているなら、hover 枠は描かない
    /// （選択枠と二重描画になるのを避ける）
    def testAddHoverBoxSkipsWhenSameAsSelected(): Unit \ {Assert, GameEngine.Game} =
        let sprite = Sprite2D.make("dummy.png", {x = 100.0, y = 100.0}, {x = 1.0, y = 1.0});
        let s: Scene[NodeTag] = Scene.empty();
        let scene = s |> Scene.addNode("hero",
            EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag));
        let index = Map#{"hero" => "hero.json"};
        // hero を選択中、マウスも hero の上
        let result = Overlay.addHoverBox(
            index,
            {x = 100.0, y = 100.0},
            Some(("hero.json", "hero" :: Nil)),
            {x = 0.0, y = 0.0},
            scene);
        let hoverLayerAbsent = Option.isEmpty(
            Scene.getEngineNode("_editor_hover_layer" :: Nil, result));
        Assert.assertEq(expected = true, hoverLayerAbsent)

    @Test
    def testAddHoverBoxSkipsWhenSameAsSelectedRunner(): Unit \ Assert =
        withMockTexture32(testAddHoverBoxSkipsWhenSameAsSelected)

    /// マウスが選択中ノードと違うノード上なら hover 枠が追加される
    def testAddHoverBoxAddsLayerWhenDifferent(): Unit \ {Assert, GameEngine.Game} =
        let heroSprite = Sprite2D.make("dummy.png", {x = 100.0, y = 100.0}, {x = 1.0, y = 1.0});
        let coinSprite = Sprite2D.make("dummy.png", {x = 200.0, y = 200.0}, {x = 1.0, y = 1.0});
        let s: Scene[NodeTag] = Scene.empty();
        let scene = s
            |> Scene.addNode("hero", EngineNode.Sprite2DWithState(heroSprite, NodeTag.NoTag))
            |> Scene.addNode("coin", EngineNode.Sprite2DWithState(coinSprite, NodeTag.NoTag));
        let index = Map#{"hero" => "hero.json", "coin" => "coin.json"};
        // hero を選択中、マウスは coin 上
        let result = Overlay.addHoverBox(
            index,
            {x = 200.0, y = 200.0},
            Some(("hero.json", "hero" :: Nil)),
            {x = 0.0, y = 0.0},
            scene);
        let isCanvasLayer = node -> match node {
            case EngineNode.CanvasLayerWithState(_, _) => true
            case _ => false
        };
        let hoverLayerExists =
            Scene.getEngineNode("_editor_hover_layer" :: Nil, result)
                |> Option.exists(isCanvasLayer);
        Assert.assertEq(expected = true, hoverLayerExists)

    @Test
    def testAddHoverBoxAddsLayerWhenDifferentRunner(): Unit \ Assert =
        withMockTexture32(testAddHoverBoxAddsLayerWhenDifferent)

    /// 選択中ノードがあれば 4 辺の ColorRect が追加される（top/bottom/left/right）
    def testAddSelectionBoxAddsFourEdges(): Unit \ {Assert, GameEngine.Game} =
        let sprite = Sprite2D.make("dummy.png", {x = 100.0, y = 100.0}, {x = 1.0, y = 1.0});
        let s: Scene[NodeTag] = Scene.empty();
        let scene = s |> Scene.addNode("hero",
            EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag));
        let index = Map#{"hero" => "hero.json"};
        let result = Overlay.addSelectionBox(
            index,
            Some(("hero.json", "hero" :: Nil)),
            {x = 0.0, y = 0.0},
            scene);
        let isColorRect = node -> match node {
            case EngineNode.ColorRectWithState(_, _) => true
            case _                                   => false
        };
        let layerName = "_editor_box_layer";
        let top = Scene.getEngineNode(layerName :: "top" :: Nil, result)
            |> Option.exists(isColorRect);
        let bottom = Scene.getEngineNode(layerName :: "bottom" :: Nil, result)
            |> Option.exists(isColorRect);
        let left = Scene.getEngineNode(layerName :: "left" :: Nil, result)
            |> Option.exists(isColorRect);
        let right = Scene.getEngineNode(layerName :: "right" :: Nil, result)
            |> Option.exists(isColorRect);
        Assert.assertEq(expected = (true, true, true, true), (top, bottom, left, right))

    @Test
    def testAddSelectionBoxAddsFourEdgesRunner(): Unit \ Assert =
        withMockTexture32(testAddSelectionBoxAddsFourEdges)

    // ====================================================================
    // addCollisionShapes — 衝突形状を半透明 ColorRect 群で塗りつぶす
    // ====================================================================

    /// 衝突形状のないシーン（Sprite だけ）に addCollisionShapes すると、
    /// CanvasLayer は作られるがその下に子は付かない
    @Test
    def testAddCollisionShapesNoShapesAddsEmptyLayer(): Unit \ Assert =
        let sprite = Sprite2D.make("dummy.png", {x = 100.0, y = 100.0}, {x = 1.0, y = 1.0});
        let s: Scene[NodeTag] = Scene.empty();
        let scene = s |> Scene.addNode("hero",
            EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag));
        let result = Overlay.addCollisionShapes({x = 0.0, y = 0.0}, scene);
        let children = Scene.getChildrenAt("_editor_collision_layer" :: Nil, result);
        Assert.assertEq(expected = (true, 0), (Option.nonEmpty(
            Scene.getEngineNode("_editor_collision_layer" :: Nil, result)),
            List.length(children)))

    /// RectShape2D の Area2D が 1 つあると、CanvasLayer の下に
    /// 中身 1 枚 + 4 辺のフチで合計 5 枚の ColorRect が追加される
    @Test
    def testAddCollisionShapesRectAddsFillAndOutline(): Unit \ Assert =
        let area = Area2D.make({x = 100.0, y = 100.0},
            CollisionShape2D.RectShape2D({width = 32.0, height = 16.0}));
        let s: Scene[NodeTag] = Scene.empty();
        let scene = s |> Scene.addNode("trigger",
            EngineNode.Area2DWithState(area, NodeTag.NoTag));
        let result = Overlay.addCollisionShapes({x = 0.0, y = 0.0}, scene);
        let children = Scene.getChildrenAt("_editor_collision_layer" :: Nil, result);
        // 内側 fill 1 + 上下左右の outline 4 = 5
        Assert.assertEq(expected = 5, List.length(children))

    /// CircleShape2D（半径 5、フチ太さ 1）はリング方式で多数の ColorRect を生成する。
    /// 上下キャップ行（内側がない）2 枚 + 内側がある 9 行 × 3 枚 = 29 枚
    ///
    ///   y=-5: outerHalf≈3.32, innerHalf=0    -> 全幅 outline 1 枚
    ///   y=-4..4 (9 行): innerHalf>0          -> 左 outline + 中央 fill + 右 outline 3 枚
    ///   y=+5: outerHalf≈3.32, innerHalf=0    -> 全幅 outline 1 枚
    @Test
    def testAddCollisionShapesCircleAddsRingScanLines(): Unit \ Assert =
        let area = Area2D.make({x = 100.0, y = 100.0},
            CollisionShape2D.CircleShape2D({radius = 5.0}));
        let s: Scene[NodeTag] = Scene.empty();
        let scene = s |> Scene.addNode("ball",
            EngineNode.Area2DWithState(area, NodeTag.NoTag));
        let result = Overlay.addCollisionShapes({x = 0.0, y = 0.0}, scene);
        let count = Scene.getChildrenAt("_editor_collision_layer" :: Nil, result)
            |> List.length;
        Assert.assertEq(expected = 29, count)

    /// fill 部分は半透明（alpha < 1.0）、outline 部分は不透明（alpha = 1.0）。
    /// 5 枚の子のうち、alpha 値の集合が想定の組み合わせになっていることを確認する
    @Test
    def testAddCollisionShapesFillTranslucentOutlineOpaque(): Unit \ Assert =
        let area = Area2D.make({x = 50.0, y = 50.0},
            CollisionShape2D.RectShape2D({width = 10.0, height = 10.0}));
        let s: Scene[NodeTag] = Scene.empty();
        let scene = s |> Scene.addNode("box",
            EngineNode.Area2DWithState(area, NodeTag.NoTag));
        let result = Overlay.addCollisionShapes({x = 0.0, y = 0.0}, scene);
        let alphas = Scene.getChildrenAt("_editor_collision_layer" :: Nil, result)
            |> List.map(childName ->
                match Scene.getEngineNode("_editor_collision_layer" :: childName :: Nil, result) {
                    case Some(EngineNode.ColorRectWithState(ColorRect.ColorRect(r), _)) => r#alpha
                    case _ => bug!("collision overlay child should be a ColorRect")
                });
        let translucentCount = List.count(a -> a < 1.0f32, alphas);
        let opaqueCount = List.count(a -> a >= 1.0f32, alphas);
        // 矩形は内側 fill 1 枚（半透明）+ 4 辺の outline（不透明）
        Assert.assertEq(expected = (1, 4), (translucentCount, opaqueCount))
}
