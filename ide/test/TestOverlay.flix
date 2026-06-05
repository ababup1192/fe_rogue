// Tests for Overlay — 選択枠の描画
//
// Scene 変換が中心なので、ノード追加結果（ファサードの子に何があるか）を確認する形で
// 検証する。`addSelectionBox` は `EditableNode.findByNodePath` 経由で
// `GameEngine.Game.getTextureInfo` を使うのでモックハンドラを噛ませる

mod TestOverlay {

    /// editor 単独テスト用の最小 tag enum (NodeTag は consumer 側で定義される型)
    pub enum Tag { case NoTag }


    /// すべての texture が 32x32 を返す GameEngine.Game ハンドラ
    def withMockTexture32(f: Unit -> a \ ef + GameEngine.Game): a \ ef =
        run f() with handler GameEngine.Game {
            def renderCommands(_, _, _, k) = k(())
            def initTileBuffer(_, k) = k((0i32, 0i32))
            def shouldClose(k) = k(false)
            def getDeltaTime(k) = k(16 |> Duration.millis)
            def isKeyPressed(_, k) = k(false)
            def getMousePosition(k) = k({x = 0.0, y = 0.0})
            def isMouseButtonPressed(_, k) = k(false)
            def consumeScrollDelta(k) = k(0.0)
            def getFontAtlas(_, _) = bug!("font not used")
            def getViewportRect(k) = k({position = {x = 0.0, y = 0.0}, size = {x = 480.0, y = 720.0}})
            def getTextureInfo(_, k) = k(Some({id = 0i32, width = 32.0, height = 32.0}))
            def setCursor(_, k) = k(())
        }

    // ====================================================================
    // addSelectionBox — 選択中ノードを 4 辺で囲む
    // ====================================================================

    /// selected = None なら scene は変わらない
    @Test
    def testAddSelectionBoxNoneIsNoOp(): Unit \ Assert =
        let s: Scene[Tag] = Scene.empty();
        let scene = s;
        let result = withMockTexture32(() ->
            Overlay.addSelectionBox(Map.empty(), None, Camera2D.identityTransform(), Tag.NoTag, scene));
        let boxLayerAbsent = Option.isEmpty(
            Scene.getEngineNode("_editor_box_layer" :: Nil, result));
        Assert.assertEq(expected = true, boxLayerAbsent)

    /// 選択中 entry がない（rootJsonIndex に登録外）なら何も追加しない
    def testAddSelectionBoxUnknownRootIsNoOp(): Unit \ {Assert, GameEngine.Game} =
        let sprite = Sprite2D.make("dummy.png", {x = 0.0, y = 0.0}, {x = 1.0, y = 1.0});
        let s: Scene[Tag] = Scene.empty();
        let scene = s |> Scene.addNode("hero",
            EngineNode.Sprite2DWithState(sprite, Tag.NoTag));
        // index に "hero" を入れていない → entry が見つからない
        let result = Overlay.addSelectionBox(
            Map.empty(),
            Some({jsonPath = "hero.json", nodePath = "hero" :: Nil, jsonNodePath = "hero" :: Nil}),
            Camera2D.identityTransform(),
            Tag.NoTag,
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
        let s: Scene[Tag] = Scene.empty();
        let scene = s |> Scene.addNode("hero",
            EngineNode.Sprite2DWithState(sprite, Tag.NoTag));
        let index = Map#{"hero" => "hero.json"};
        // マウスはスプライト矩形の遥か外
        let result = Overlay.addHoverBox(index, {x = 500.0, y = 500.0}, None,
                                         Camera2D.identityTransform(),
                                         Tag.NoTag,
                                         scene);
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
        let s: Scene[Tag] = Scene.empty();
        let scene = s |> Scene.addNode("hero",
            EngineNode.Sprite2DWithState(sprite, Tag.NoTag));
        let index = Map#{"hero" => "hero.json"};
        // hero を選択中、マウスも hero の上
        let result = Overlay.addHoverBox(
            index,
            {x = 100.0, y = 100.0},
            Some({jsonPath = "hero.json", nodePath = "hero" :: Nil, jsonNodePath = "hero" :: Nil}),
            Camera2D.identityTransform(),
            Tag.NoTag,
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
        let s: Scene[Tag] = Scene.empty();
        let scene = s
            |> Scene.addNode("hero", EngineNode.Sprite2DWithState(heroSprite, Tag.NoTag))
            |> Scene.addNode("coin", EngineNode.Sprite2DWithState(coinSprite, Tag.NoTag));
        let index = Map#{"hero" => "hero.json", "coin" => "coin.json"};
        // hero を選択中、マウスは coin 上
        let result = Overlay.addHoverBox(
            index,
            {x = 200.0, y = 200.0},
            Some({jsonPath = "hero.json", nodePath = "hero" :: Nil, jsonNodePath = "hero" :: Nil}),
            Camera2D.identityTransform(),
            Tag.NoTag,
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
        let s: Scene[Tag] = Scene.empty();
        let scene = s |> Scene.addNode("hero",
            EngineNode.Sprite2DWithState(sprite, Tag.NoTag));
        let index = Map#{"hero" => "hero.json"};
        let result = Overlay.addSelectionBox(
            index,
            Some({jsonPath = "hero.json", nodePath = "hero" :: Nil, jsonNodePath = "hero" :: Nil}),
            Camera2D.identityTransform(),
            Tag.NoTag,
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
        let s: Scene[Tag] = Scene.empty();
        let scene = s |> Scene.addNode("hero",
            EngineNode.Sprite2DWithState(sprite, Tag.NoTag));
        let result = Overlay.addCollisionShapes(Camera2D.identityTransform(), Tag.NoTag, scene);
        let children = Scene.getChildrenAt("_editor_collision_layer" :: Nil, result);
        Assert.assertEq(expected = (true, 0), (Option.nonEmpty(
            Scene.getEngineNode("_editor_collision_layer" :: Nil, result)),
            List.length(children)))

    /// RectShape2D の Area2D が 1 つあると、CanvasLayer の下に
    /// 上下左右の outline 4 枚の ColorRect が追加される（fill は描画しない）
    @Test
    def testAddCollisionShapesRectAddsOutlineOnly(): Unit \ Assert =
        let area = Area2D.make({x = 100.0, y = 100.0},
            CollisionShape2D.RectShape2D({width = 32.0, height = 16.0}));
        let s: Scene[Tag] = Scene.empty();
        let scene = s |> Scene.addNode("trigger",
            EngineNode.Area2DWithState(area, Tag.NoTag));
        let result = Overlay.addCollisionShapes(Camera2D.identityTransform(), Tag.NoTag, scene);
        let children = Scene.getChildrenAt("_editor_collision_layer" :: Nil, result);
        // 上下左右の outline 4 枚（fill は描画しない）
        Assert.assertEq(expected = 4, List.length(children))

    /// CircleShape2D（半径 5、フチ太さ 1）はリング outline をスキャンラインで描く。
    /// 上下キャップ行（内側がない）2 枚 + 内側がある 9 行 × 2 枚（左右 edge のみ） = 20 枚
    ///
    ///   y=-5: outerHalf>0, innerHalf=0    -> 全幅 outline 1 枚
    ///   y=-4..4 (9 行): innerHalf>0       -> 左 outline + 右 outline 2 枚（fill 削除）
    ///   y=+5: outerHalf>0, innerHalf=0    -> 全幅 outline 1 枚
    @Test
    def testAddCollisionShapesCircleAddsRingOutlineOnly(): Unit \ Assert =
        let area = Area2D.make({x = 100.0, y = 100.0},
            CollisionShape2D.CircleShape2D({radius = 5.0}));
        let s: Scene[Tag] = Scene.empty();
        let scene = s |> Scene.addNode("ball",
            EngineNode.Area2DWithState(area, Tag.NoTag));
        let result = Overlay.addCollisionShapes(Camera2D.identityTransform(), Tag.NoTag, scene);
        let count = Scene.getChildrenAt("_editor_collision_layer" :: Nil, result)
            |> List.length;
        Assert.assertEq(expected = 20, count)

    /// すべての ColorRect が不透明な outline（alpha = 1.0）であること。
    /// fill が削除されたため、translucent な要素（alpha < 1.0）は存在しない
    @Test
    def testAddCollisionShapesAllOutlinesAreOpaque(): Unit \ Assert =
        let area = Area2D.make({x = 50.0, y = 50.0},
            CollisionShape2D.RectShape2D({width = 10.0, height = 10.0}));
        let s: Scene[Tag] = Scene.empty();
        let scene = s |> Scene.addNode("box",
            EngineNode.Area2DWithState(area, Tag.NoTag));
        let result = Overlay.addCollisionShapes(Camera2D.identityTransform(), Tag.NoTag, scene);
        let alphas = Scene.getChildrenAt("_editor_collision_layer" :: Nil, result)
            |> List.map(childName ->
                match Scene.getEngineNode("_editor_collision_layer" :: childName :: Nil, result) {
                    case Some(EngineNode.ColorRectWithState(ColorRect.ColorRect(r), _)) => r#alpha
                    case _ => bug!("collision overlay child should be a ColorRect")
                });
        let translucentCount = List.count(a -> a < 1.0f32, alphas);
        let opaqueCount = List.count(a -> a >= 1.0f32, alphas);
        // fill は無いので translucent は 0 枚、outline 4 枚すべて不透明
        Assert.assertEq(expected = (0, 4), (translucentCount, opaqueCount))
}
