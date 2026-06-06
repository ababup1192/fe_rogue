// Tests for EditableNode — 編集対象ノードの抽出と矩形計算
//
// 純粋ヘルパー（boxTopLeftOffset）は直接テスト。
// collectAll / findByNodePath は `GameEngine.Game` の `getTextureInfo` だけ
// 使うので、固定サイズを返すモックハンドラで包んで実シーン相手にテストする

mod TestEditableNode {

    /// editor 単独テスト用の最小 tag enum (NodeTag は consumer 側で定義される型)
    pub enum Tag { case NoTag }


    // ====================================================================
    // モック GameEngine.Game ハンドラ — getTextureInfo のみ意味のある値を返す
    // ====================================================================

    /// すべての texture 名に対して同じ width / height を返すモック。
    /// 他のメソッドはテストで使われない想定で no-op / dummy
    def withMockTextureSize(width: Float64, height: Float64,
                            f: Unit -> a \ ef + GameEngine.Game): a \ ef =
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
        let s: Scene[Tag] = Scene.empty();
        let scene = s |> Scene.addNode("hero",
            EngineNode.Sprite2DWithState(sprite, Tag.NoTag));
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
        let s: Scene[Tag] = Scene.empty();
        let scene = s |> Scene.addNode("a",
            EngineNode.Sprite2DWithState(sprite, Tag.NoTag));
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
        let frames: List[SpriteFrames.Frame] =
            {texture = "frame_a", regionRect = None, duration = 1.0} ::
            {texture = "frame_b", regionRect = None, duration = 1.0} :: Nil;
        let flapAnim: SpriteFrames.Animation =
            {loop = true, speed = 10.0, frames = frames};
        let sf = SpriteFrames.empty()
            |> SpriteFrames.addAnimation("flap", flapAnim);
        let anim = AnimatedSprite2D.make(sf,
            {animation = "flap"},
            {x = 0.0, y = 0.0},
            {x = 2.0, y = 2.0});
        let s: Scene[Tag] = Scene.empty();
        let scene = s |> Scene.addNode("bird",
            EngineNode.AnimSprite2DWithState(anim, Tag.NoTag));
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

    /// 子のいない CanvasLayer は編集対象 entries に含まれない（bbox 算出不能のため）。
    /// Sprite2D / TextureButton / ColorRect は拾われる
    def testCollectAllFiltersNonEditable(): Unit \ {Assert, GameEngine.Game} =
        let sprite = Sprite2D.make("dummy.png", {x = 0.0, y = 0.0}, {x = 1.0, y = 1.0});
        let layer = CanvasLayer.make(0i32);
        let rect = ColorRect.make({x = 10.0, y = 10.0}, {r = 1.0f32, g = 1.0f32, b = 1.0f32});
        let btn = TextureButton.make("btn.png", {x = 64.0, y = 32.0});
        let s: Scene[Tag] = Scene.empty();
        let scene = s
            |> Scene.addNode("layer", EngineNode.CanvasLayerWithState(layer, Tag.NoTag))
            |> Scene.addNode("sprite", EngineNode.Sprite2DWithState(sprite, Tag.NoTag))
            |> Scene.addNode("rect", EngineNode.ColorRectWithState(rect, Tag.NoTag))
            |> Scene.addNode("button", EngineNode.TextureButtonWithState(btn, Tag.NoTag));
        let index = Map#{"layer" => "x.json", "sprite" => "x.json",
                         "rect" => "x.json", "button" => "x.json"};
        let entries = EditableNode.collectAll({rootJsonIndex = index, scene = scene});
        let paths = List.map(e -> e#nodePath, entries) |> List.sortBy(p -> List.head(p));
        Assert.assertEq(
            expected = ("button" :: Nil) :: ("rect" :: Nil) :: ("sprite" :: Nil) :: Nil,
            paths)

    @Test
    def testCollectAllFiltersNonEditableRunner(): Unit \ Assert =
        withMockTextureSize(20.0, 20.0, () -> testCollectAllFiltersNonEditable())

    /// rootJsonIndex に登録されていないルートのノードは除外される
    def testCollectAllFiltersByRootIndex(): Unit \ {Assert, GameEngine.Game} =
        let s1 = Sprite2D.make("dummy.png", {x = 0.0, y = 0.0}, {x = 1.0, y = 1.0});
        let s2 = Sprite2D.make("dummy.png", {x = 0.0, y = 0.0}, {x = 1.0, y = 1.0});
        let s: Scene[Tag] = Scene.empty();
        let scene = s
            |> Scene.addNode("known", EngineNode.Sprite2DWithState(s1, Tag.NoTag))
            |> Scene.addNode("unknown", EngineNode.Sprite2DWithState(s2, Tag.NoTag));
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
        let s: Scene[Tag] = Scene.empty();
        let scene = s
            |> Scene.addNode("a", EngineNode.Sprite2DWithState(sa, Tag.NoTag))
            |> Scene.addNode("b", EngineNode.Sprite2DWithState(sb, Tag.NoTag));
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
        let s: Scene[Tag] = Scene.empty();
        let scene = s |> Scene.addNode("a", EngineNode.Sprite2DWithState(sa, Tag.NoTag));
        let index = Map#{"a" => "x.json"};
        let result = EditableNode.findByNodePath(
            {rootJsonIndex = index, scene = scene}, "zzz" :: Nil);
        Assert.assertEq(expected = true, Option.isEmpty(result))

    @Test
    def testFindByNodePathMissRunner(): Unit \ Assert =
        withMockTextureSize(10.0, 10.0, () -> testFindByNodePathMiss())

    // ====================================================================
    // PackedScene プレハブ由来ノードの編集対象認識
    // PackedScene.instantiate が SceneEntry に sourceTemplate を埋めるため、
    // rootJsonIndex に live name が登録されていなくてもプレハブは編集対象になる。
    // jsonNodePath は live path の先頭 (例 "ground_0") をテンプレートの root name
    // ("ground") に翻訳した path を返す。
    // ====================================================================

    /// rootJsonIndex に "ground_0" が無くても sourceTemplate があれば編集対象になる
    def testPrefabInstanceRecognizedViaSourceTemplate(): Unit \ {Assert, GameEngine.Game} =
        let sprite = Sprite2D.make("ground.png", {x = 0.0, y = 0.0}, {x = 1.0, y = 1.0});
        let template: SourceTemplate = {
            jsonPath = "src/scenes/Ground.scene.json",
            rootName = "ground"
        };
        let s: Scene[Tag] = Scene.empty();
        let scene = s
            |> Scene.addNode("ground_0", EngineNode.Sprite2DWithState(sprite, Tag.NoTag))
            |> Scene.tagWithSourceTemplate("ground_0" :: Nil, template);
        let entries = EditableNode.collectAll(
            {rootJsonIndex = Map.empty(), scene = scene});
        Assert.assertEq(
            expected = (1, Some("src/scenes/Ground.scene.json"), Some("ground" :: Nil)),
            (List.length(entries),
             List.head(entries) |> Option.map(e -> e#jsonPath),
             List.head(entries) |> Option.map(e -> e#jsonNodePath)))

    @Test
    def testPrefabInstanceRecognizedViaSourceTemplateRunner(): Unit \ Assert =
        withMockTextureSize(32.0, 32.0,
            () -> testPrefabInstanceRecognizedViaSourceTemplate())

    /// プレハブの子ノード "ground_0/sprite" は jsonNodePath が "ground/sprite" に翻訳される
    def testPrefabChildJsonNodePathTranslated(): Unit \ {Assert, GameEngine.Game} =
        let parent = CanvasLayer.make(0i32);
        let sprite = Sprite2D.make("g.png", {x = 0.0, y = 0.0}, {x = 1.0, y = 1.0});
        let template: SourceTemplate = {
            jsonPath = "src/scenes/Ground.scene.json",
            rootName = "ground"
        };
        let s: Scene[Tag] = Scene.empty();
        let scene = s
            |> Scene.addNode("ground_0", EngineNode.CanvasLayerWithState(parent, Tag.NoTag))
            |> Scene.addChild("ground_0", "sprite",
                EngineNode.Sprite2DWithState(sprite, Tag.NoTag))
            |> Scene.tagWithSourceTemplate("ground_0" :: Nil, template);
        let result = EditableNode.findByNodePath(
            {rootJsonIndex = Map.empty(), scene = scene},
            "ground_0" :: "sprite" :: Nil);
        Assert.assertEq(
            expected = Some(("ground" :: "sprite" :: Nil, "src/scenes/Ground.scene.json")),
            result |> Option.map(e -> (e#jsonNodePath, e#jsonPath)))

    @Test
    def testPrefabChildJsonNodePathTranslatedRunner(): Unit \ Assert =
        withMockTextureSize(32.0, 32.0,
            () -> testPrefabChildJsonNodePathTranslated())

    /// 静的シーン（sourceTemplate 無し、rootJsonIndex 経由）では jsonNodePath == nodePath
    def testStaticSceneJsonNodePathEqualsLivePath(): Unit \ {Assert, GameEngine.Game} =
        let sprite = Sprite2D.make("hero.png", {x = 0.0, y = 0.0}, {x = 1.0, y = 1.0});
        let s: Scene[Tag] = Scene.empty();
        let scene = s |> Scene.addNode("hero",
            EngineNode.Sprite2DWithState(sprite, Tag.NoTag));
        let index = Map#{"hero" => "Hero.scene.json"};
        let result = EditableNode.findByNodePath(
            {rootJsonIndex = index, scene = scene}, "hero" :: Nil);
        Assert.assertEq(
            expected = Some(("hero" :: Nil, "hero" :: Nil)),
            result |> Option.map(e -> (e#nodePath, e#jsonNodePath)))

    @Test
    def testStaticSceneJsonNodePathEqualsLivePathRunner(): Unit \ Assert =
        withMockTextureSize(32.0, 32.0,
            () -> testStaticSceneJsonNodePathEqualsLivePath())

    // ====================================================================
    // Area2D の編集対象認識・リサイズ・スナップショット
    // ====================================================================

    /// Area2D は RectShape2D を持っていれば collectAll に拾われる。
    /// bbox は shape の (width, height) で中央オフセット
    def testCollectAllPicksRectArea2D(): Unit \ {Assert, GameEngine.Game} =
        let shape = CollisionShape2D.RectShape2D({width = 40.0, height = 20.0});
        let area = Area2D.make({x = 50.0, y = 60.0}, shape);
        let s: Scene[Tag] = Scene.empty();
        let scene = s
            |> Scene.addNode("a", EngineNode.Area2DWithState(area, Tag.NoTag));
        let entries = EditableNode.collectAll(
            {rootJsonIndex = Map#{"a" => "a.json"}, scene = scene});
        Assert.assertEq(
            expected = (1, Some(40.0), Some(20.0), Some(-20.0), Some(-10.0)),
            (List.length(entries),
             List.head(entries) |> Option.map(e -> e#width),
             List.head(entries) |> Option.map(e -> e#height),
             List.head(entries) |> Option.map(e -> e#topLeftOffset#x),
             List.head(entries) |> Option.map(e -> e#topLeftOffset#y)))

    @Test
    def testCollectAllPicksRectArea2DRunner(): Unit \ Assert =
        withMockTextureSize(32.0, 32.0, () -> testCollectAllPicksRectArea2D())

    /// CircleShape2D の Area2D は radius * 2 の正方形 bbox を返す
    def testCollectAllPicksCircleArea2D(): Unit \ {Assert, GameEngine.Game} =
        let shape = CollisionShape2D.CircleShape2D({radius = 13.0});
        let area = Area2D.make({x = 0.0, y = 0.0}, shape);
        let s: Scene[Tag] = Scene.empty();
        let scene = s
            |> Scene.addNode("a", EngineNode.Area2DWithState(area, Tag.NoTag));
        let entries = EditableNode.collectAll(
            {rootJsonIndex = Map#{"a" => "a.json"}, scene = scene});
        Assert.assertEq(
            expected = (1, Some(26.0), Some(26.0)),
            (List.length(entries),
             List.head(entries) |> Option.map(e -> e#width),
             List.head(entries) |> Option.map(e -> e#height)))

    @Test
    def testCollectAllPicksCircleArea2DRunner(): Unit \ Assert =
        withMockTextureSize(32.0, 32.0, () -> testCollectAllPicksCircleArea2D())

    /// CollisionShape を持たない Area2D は edit 対象から外れる
    def testCollectAllSkipsArea2DWithoutShape(): Unit \ {Assert, GameEngine.Game} =
        let shape = CollisionShape2D.RectShape2D({width = 10.0, height = 10.0});
        let area = Area2D.make({x = 0.0, y = 0.0}, shape)
            |> Area2D.setCollisionShape(None);
        let s: Scene[Tag] = Scene.empty();
        let scene = s
            |> Scene.addNode("a", EngineNode.Area2DWithState(area, Tag.NoTag));
        let entries = EditableNode.collectAll(
            {rootJsonIndex = Map#{"a" => "a.json"}, scene = scene});
        Assert.assertEq(expected = 0, List.length(entries))

    @Test
    def testCollectAllSkipsArea2DWithoutShapeRunner(): Unit \ Assert =
        withMockTextureSize(32.0, 32.0,
            () -> testCollectAllSkipsArea2DWithoutShape())

    /// Area2D の snapshot は prevShape に元の CollisionShape2D を保持する
    @Test
    def testArea2DSnapshotCapturesShape(): Unit \ Assert =
        let shape = CollisionShape2D.RectShape2D({width = 40.0, height = 20.0});
        let area = Area2D.make({x = 0.0, y = 0.0}, shape);
        let node: EngineNode[Unit] = EngineNode.Area2DWithState(area, ());
        let snap = EditableNode.snapshotForResize("a" :: Nil, node);
        let shapeDims = match snap#prevShape {
            case Some(CollisionShape2D.RectShape2D(r)) => Some((r#width, r#height))
            case _ => None
        };
        Assert.assertEq(expected = Some((40.0, 20.0)), shapeDims)

    /// Area2D を ratio (2.0, 1.5) でリサイズすると、shape が (80, 30) に拡大される
    @Test
    def testArea2DResizeScalesShape(): Unit \ Assert =
        let shape = CollisionShape2D.RectShape2D({width = 40.0, height = 20.0});
        let area = Area2D.make({x = 0.0, y = 0.0}, shape);
        let node: EngineNode[Unit] = EngineNode.Area2DWithState(area, ());
        let snap = EditableNode.snapshotForResize("a" :: Nil, node);
        let resized = EditableNode.applyResizeFromSnapshot(snap, {x = 2.0, y = 1.5})(node);
        let newDims = match resized {
            case EngineNode.Area2DWithState(a, _) =>
                match CollisionObject2D.getCollisionShape(a) {
                    case Some(CollisionShape2D.RectShape2D(r)) => Some((r#width, r#height))
                    case _ => None
                }
            case _ => None
        };
        Assert.assertEq(expected = Some((80.0, 30.0)), newDims)

    /// Area2D の resizeFieldUpdates は "shape" キーで FieldValue.ShapeValue を返す
    @Test
    def testArea2DResizeFieldUpdatesIncludesShape(): Unit \ Assert =
        let shape = CollisionShape2D.RectShape2D({width = 40.0, height = 20.0});
        let area = Area2D.make({x = 0.0, y = 0.0}, shape);
        let node: EngineNode[Unit] = EngineNode.Area2DWithState(area, ());
        let updates = EditableNode.resizeFieldUpdates(node);
        let keys = List.map(u -> u#key, updates);
        Assert.assertEq(expected = "shape" :: Nil, keys)

    /// コリジョン可視化は **outline のみ** であること（内側 fill は描画しない）。
    /// Godot のエディタと同じく、下の sprite が完全に見えるよう fill は除いている
    @Test
    def testCollisionOverlayIsOutlineOnly(): Unit \ Assert =
        let bird = RigidBody2D.make({x = 144.0, y = 256.0},
            CollisionShape2D.CircleShape2D({radius = 13.0}));
        let areaShape = CollisionShape2D.CircleShape2D({radius = 13.0});
        let area = Area2D.make({x = 0.0, y = 0.0}, areaShape);
        let s: Scene[Tag] = Scene.empty();
        let scene = s
            |> Scene.addNode("bird", EngineNode.RigidBody2DWithState(bird, Tag.NoTag))
            |> Scene.addChild("bird", "area",
                EngineNode.Area2DWithState(area, Tag.NoTag));
        let transform = Camera2D.identityTransform();
        let withOverlay = Overlay.addCollisionShapes(transform, Tag.NoTag, scene);
        // _editor_collision_layer の中の "bird_0", "bird_1" … と "bird/area_0", "bird/area_1" …
        // を順に見て、ColorRect の alpha が 0.4 / 1.0 のいずれかであることを確認する
        let layerChildren = Scene.getChildrenAt("_editor_collision_layer" :: Nil, withOverlay);
        let alphas = List.filterMap(name -> {
            let path = "_editor_collision_layer" :: name :: Nil;
            match Scene.getEngineNode(path, withOverlay) {
                case Some(EngineNode.ColorRectWithState(ColorRect.ColorRect(rec), _)) =>
                    Some(rec#alpha)
                case _ => None
            }
        }, layerChildren);
        // outline only — すべての alpha が 1.0 で、fill alpha 0.4 のものが含まれないこと
        let allOpaqueOutline = List.forAll(a -> a == 1.0f32, alphas);
        let count = List.length(alphas);
        Assert.assertEq(expected = (true, true), (allOpaqueOutline, count > 0))

    /// area の position を動かす → bird/sprite の global position が変わらない、
    /// かつ toDrawables 経由で sprite drawable が生成されること
    @Test
    def testMovingArea2DDoesNotRemoveSibling(): Unit \ Assert =
        let bird = RigidBody2D.make({x = 144.0, y = 256.0},
            CollisionShape2D.CircleShape2D({radius = 13.0}));
        let frames: List[SpriteFrames.Frame] =
            {texture = "f1", regionRect = None, duration = 1.0} :: Nil;
        let anim: SpriteFrames.Animation = {loop = true, speed = 10.0, frames = frames};
        let sf = SpriteFrames.empty() |> SpriteFrames.addAnimation("flap", anim);
        let spriteNode = AnimatedSprite2D.make(sf, {animation = "flap"},
            {x = 0.0, y = 0.0}, {x = 2.0, y = 2.0});
        let areaShape = CollisionShape2D.CircleShape2D({radius = 13.0});
        let area = Area2D.make({x = 0.0, y = 0.0}, areaShape);
        let s: Scene[Tag] = Scene.empty();
        let scene = s
            |> Scene.addNode("bird", EngineNode.RigidBody2DWithState(bird, Tag.NoTag))
            |> Scene.addChild("bird", "sprite",
                EngineNode.AnimSprite2DWithState(spriteNode, Tag.NoTag))
            |> Scene.addChild("bird", "area",
                EngineNode.Area2DWithState(area, Tag.NoTag));
        // bird/area を global (164, 256) に動かす（local (20, 0) になる）
        let moved = Scene.setGlobalPositionAt("bird" :: "area" :: Nil,
            {x = 164.0, y = 256.0}, scene);
        // sprite ノードがまだ scene にあること、global pos が変わっていないこと
        let spritePresent = match Scene.getEngineNode("bird" :: "sprite" :: Nil, moved) {
            case Some(EngineNode.AnimSprite2DWithState(_, _)) => true
            case _ => false
        };
        let spriteGlobal = Scene.globalPositionAt("bird" :: "sprite" :: Nil, moved);
        let areaGlobal = Scene.globalPositionAt("bird" :: "area" :: Nil, moved);
        Assert.assertEq(
            expected = (true, (144.0, 256.0), (164.0, 256.0)),
            (spritePresent,
             (spriteGlobal#x, spriteGlobal#y),
             (areaGlobal#x, areaGlobal#y)))
}
