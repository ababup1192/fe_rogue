// Tests for EditableNode — 編集対象ノードの抽出と矩形計算
//
// 純粋ヘルパー（boxTopLeftOffset）は直接テスト。
// collectAll / findByNodePath は `GameEngine.Game` の `getTextureInfo` だけ
// 使うので、固定サイズを返すモックハンドラで包んで実シーン相手にテストする

mod TestEditableNode {

    // ====================================================================
    // モック GameEngine.Game ハンドラ — getTextureInfo のみ意味のある値を返す
    // ====================================================================

    /// すべての texture 名に対して同じ width / height を返すモック。
    /// 他のメソッドはテストで使われない想定で no-op / dummy
    def withMockTextureSize(width: Float64, height: Float64,
                            f: Unit -> a \ ef + GameEngine.Game): a \ ef =
        run f() with handler GameEngine.Game {
            def render(_, k) = k(())
            def shouldClose(k) = k(false)
            def getDeltaTime(k) = k(0.016)
            def isKeyPressed(_, k) = k(false)
            def getMousePosition(k) = k({x = 0.0, y = 0.0})
            def isMouseButtonPressed(_, k) = k(false)
            def getFontAtlas(_, _) = bug!("font not used")
            def getViewportRect(k) = k({position = {x = 0.0, y = 0.0}, size = {x = 480.0, y = 720.0}})
            def getTextureInfo(_, k) = k(Some({id = 0i32, width = width, height = height}))
            def setCursor(_, k) = k(())
        }

    // ====================================================================
    // boxTopLeftOffset — 純粋関数
    // ====================================================================

    /// centered=true は左上を半サイズ分マイナスに寄せる
    @Test
    def testBoxTopLeftOffsetCentered(): Unit \ Assert =
        let off = EditableNode.boxTopLeftOffset(true, {x = 20.0, y = 30.0});
        Assert.assertEq(expected = (-10.0, -15.0), (off#x, off#y))

    /// centered=false はゼロ
    @Test
    def testBoxTopLeftOffsetNotCentered(): Unit \ Assert =
        let off = EditableNode.boxTopLeftOffset(false, {x = 20.0, y = 30.0});
        Assert.assertEq(expected = (0.0, 0.0), (off#x, off#y))

    // ====================================================================
    // collectAll — 編集対象タイプのみを拾う
    // ====================================================================

    /// Sprite2D を 1 個置いたシーンから entry が 1 件返る。
    /// width/height は texture サイズ × scale、topLeftOffset は centered=true 由来
    def testCollectAllSingleSprite(): Unit \ {Assert, GameEngine.Game} =
        let sprite = Sprite2D.make("dummy.png", {x = 50.0, y = 60.0}, {x = 1.0, y = 1.0});
        let s: Scene[NodeTag] = Scene.empty();
        let scene = s |> Scene.addNode("hero",
            EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag));
        let index = Map#{"hero" => "test/Hero.scene.json"};
        let entries = EditableNode.collectAll({rootJsonIndex = index, scene = scene});
        Assert.assertEq(
            expected = (1, "hero" :: Nil, 32.0, 32.0, -16.0, -16.0),
            (List.length(entries),
             (List.head(entries) |> Option.map(e -> e#nodePath) |> Option.getWithDefault(Nil)),
             (List.head(entries) |> Option.map(e -> e#width) |> Option.getWithDefault(0.0)),
             (List.head(entries) |> Option.map(e -> e#height) |> Option.getWithDefault(0.0)),
             (List.head(entries) |> Option.map(e -> e#topLeftOffset#x) |> Option.getWithDefault(0.0)),
             (List.head(entries) |> Option.map(e -> e#topLeftOffset#y) |> Option.getWithDefault(0.0))))

    @Test
    def testCollectAllSingleSpriteRunner(): Unit \ Assert =
        withMockTextureSize(32.0, 32.0, () -> testCollectAllSingleSprite())

    /// scale が 2 倍なら entry の width/height も 2 倍
    def testCollectAllSpriteWithScale(): Unit \ {Assert, GameEngine.Game} =
        let sprite = Sprite2D.make("dummy.png", {x = 0.0, y = 0.0}, {x = 2.0, y = 3.0});
        let s: Scene[NodeTag] = Scene.empty();
        let scene = s |> Scene.addNode("a",
            EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag));
        let entries = EditableNode.collectAll(
            {rootJsonIndex = Map#{"a" => "x.json"}, scene = scene});
        Assert.assertEq(
            expected = (Some(20.0), Some(30.0)),  // 10 * 2 = 20, 10 * 3 = 30
            (List.head(entries) |> Option.map(e -> e#width),
             List.head(entries) |> Option.map(e -> e#height)))

    @Test
    def testCollectAllSpriteWithScaleRunner(): Unit \ Assert =
        withMockTextureSize(10.0, 10.0, () -> testCollectAllSpriteWithScale())

    /// AnimatedSprite2D も編集対象として拾われる。
    /// 矩形サイズは現フレームのテクスチャ × scale
    def testCollectAllAnimatedSprite(): Unit \ {Assert, GameEngine.Game} =
        let anim = AnimatedSprite2D.make(
            Map#{"flap" => "frame_a" :: "frame_b" :: Nil},
            {initialAnimation = "flap"},
            {fps = 10.0},
            {x = 0.0, y = 0.0},
            {x = 2.0, y = 2.0});
        let s: Scene[NodeTag] = Scene.empty();
        let scene = s |> Scene.addNode("bird",
            EngineNode.AnimSprite2DWithState(anim, NodeTag.NoTag));
        let entries = EditableNode.collectAll(
            {rootJsonIndex = Map#{"bird" => "Bird.scene.json"}, scene = scene});
        // 16x16 texture × scale 2 = 32x32, centered=true → topLeft (-16, -16)
        Assert.assertEq(
            expected = (1, "bird" :: Nil, 32.0, 32.0, -16.0, -16.0),
            (List.length(entries),
             List.head(entries) |> Option.map(e -> e#nodePath) |> Option.getWithDefault(Nil),
             List.head(entries) |> Option.map(e -> e#width)         |> Option.getWithDefault(0.0),
             List.head(entries) |> Option.map(e -> e#height)        |> Option.getWithDefault(0.0),
             List.head(entries) |> Option.map(e -> e#topLeftOffset#x) |> Option.getWithDefault(0.0),
             List.head(entries) |> Option.map(e -> e#topLeftOffset#y) |> Option.getWithDefault(0.0)))

    @Test
    def testCollectAllAnimatedSpriteRunner(): Unit \ Assert =
        withMockTextureSize(16.0, 16.0, () -> testCollectAllAnimatedSprite())

    /// CanvasLayer / ColorRect など編集対象外ノードは entries に含まれない。
    /// Sprite2D / TextureButton / Label2D だけが拾われる
    def testCollectAllFiltersNonEditable(): Unit \ {Assert, GameEngine.Game} =
        let sprite = Sprite2D.make("dummy.png", {x = 0.0, y = 0.0}, {x = 1.0, y = 1.0});
        let layer = CanvasLayer.make(0i32);
        let rect = ColorRect.make({x = 10.0, y = 10.0}, {r = 1.0f32, g = 1.0f32, b = 1.0f32});
        let btn = TextureButton.make("btn.png", {x = 64.0, y = 32.0});
        let s: Scene[NodeTag] = Scene.empty();
        let scene = s
            |> Scene.addNode("layer", EngineNode.CanvasLayerWithState(layer, NodeTag.NoTag))
            |> Scene.addNode("sprite", EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag))
            |> Scene.addNode("rect", EngineNode.ColorRectWithState(rect, NodeTag.NoTag))
            |> Scene.addNode("button", EngineNode.TextureButtonWithState(btn, NodeTag.NoTag));
        let index = Map#{"layer" => "x.json", "sprite" => "x.json",
                         "rect" => "x.json", "button" => "x.json"};
        let entries = EditableNode.collectAll({rootJsonIndex = index, scene = scene});
        let paths = List.map(e -> e#nodePath, entries) |> List.sortBy(p -> List.head(p));
        Assert.assertEq(
            expected = ("button" :: Nil) :: ("sprite" :: Nil) :: Nil,
            paths)

    @Test
    def testCollectAllFiltersNonEditableRunner(): Unit \ Assert =
        withMockTextureSize(20.0, 20.0, () -> testCollectAllFiltersNonEditable())

    /// rootJsonIndex に登録されていないルートのノードは除外される
    def testCollectAllFiltersByRootIndex(): Unit \ {Assert, GameEngine.Game} =
        let s1 = Sprite2D.make("dummy.png", {x = 0.0, y = 0.0}, {x = 1.0, y = 1.0});
        let s2 = Sprite2D.make("dummy.png", {x = 0.0, y = 0.0}, {x = 1.0, y = 1.0});
        let s: Scene[NodeTag] = Scene.empty();
        let scene = s
            |> Scene.addNode("known", EngineNode.Sprite2DWithState(s1, NodeTag.NoTag))
            |> Scene.addNode("unknown", EngineNode.Sprite2DWithState(s2, NodeTag.NoTag));
        // unknown root は index に入れない
        let index = Map#{"known" => "x.json"};
        let entries = EditableNode.collectAll({rootJsonIndex = index, scene = scene});
        let paths = List.map(e -> e#nodePath, entries);
        Assert.assertEq(expected = ("known" :: Nil) :: Nil, paths)

    @Test
    def testCollectAllFiltersByRootIndexRunner(): Unit \ Assert =
        withMockTextureSize(10.0, 10.0, () -> testCollectAllFiltersByRootIndex())

    // ====================================================================
    // findByNodePath
    // ====================================================================

    /// 指定 NodePath の entry が返る
    def testFindByNodePathHit(): Unit \ {Assert, GameEngine.Game} =
        let sa = Sprite2D.make("dummy.png", {x = 0.0, y = 0.0}, {x = 1.0, y = 1.0});
        let sb = Sprite2D.make("dummy.png", {x = 0.0, y = 0.0}, {x = 1.0, y = 1.0});
        let s: Scene[NodeTag] = Scene.empty();
        let scene = s
            |> Scene.addNode("a", EngineNode.Sprite2DWithState(sa, NodeTag.NoTag))
            |> Scene.addNode("b", EngineNode.Sprite2DWithState(sb, NodeTag.NoTag));
        let index = Map#{"a" => "x.json", "b" => "x.json"};
        let result = EditableNode.findByNodePath(
            {rootJsonIndex = index, scene = scene}, "b" :: Nil);
        Assert.assertEq(
            expected = Some("b" :: Nil),
            result |> Option.map(e -> e#nodePath))

    @Test
    def testFindByNodePathHitRunner(): Unit \ Assert =
        withMockTextureSize(10.0, 10.0, () -> testFindByNodePathHit())

    /// 存在しない NodePath は None
    def testFindByNodePathMiss(): Unit \ {Assert, GameEngine.Game} =
        let sa = Sprite2D.make("dummy.png", {x = 0.0, y = 0.0}, {x = 1.0, y = 1.0});
        let s: Scene[NodeTag] = Scene.empty();
        let scene = s |> Scene.addNode("a", EngineNode.Sprite2DWithState(sa, NodeTag.NoTag));
        let index = Map#{"a" => "x.json"};
        let result = EditableNode.findByNodePath(
            {rootJsonIndex = index, scene = scene}, "zzz" :: Nil);
        Assert.assertEq(expected = true, Option.isEmpty(result))

    @Test
    def testFindByNodePathMissRunner(): Unit \ Assert =
        withMockTextureSize(10.0, 10.0, () -> testFindByNodePathMiss())
}
