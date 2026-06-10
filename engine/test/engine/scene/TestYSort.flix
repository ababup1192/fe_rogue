// Tests for Y-sort — Godot CanvasItem.y_sort_enabled 準拠の描画順
//
// Scene.toDrawables の最終 zIndex 安定ソートと renderOrderPaths の Y-sort 挙動を検証する。
// `Scene.toDrawables` は `GameEngine.Game` エフェクトを要求するので、
// テスト本体は `withMockTexture32` ヘルパで包む。

mod TestYSort {

    /// engine 単体テスト用の最小 tag enum
    pub enum Tag with Eq, ToString { case NoTag }

    /// すべての texture が 32x32 を返す GameEngine.Game ハンドラ。
    /// toDrawables 内で getTextureInfo は呼ばれないが、API シグネチャ上必要。
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

    /// position.y を指定して Sprite2D ノードを作る
    def spriteAtY(name: String, y: Float64, scene: Scene[Tag]): Scene[Tag] =
        let sprite = Sprite2D.make(name + ".png", {x = 0.0, y = y}, {x = 1.0, y = 1.0});
        Scene.addNode(name, EngineNode.Sprite2DWithState(sprite, Tag.NoTag), scene)

    /// 子 Sprite2D を Marker2D 親に追加する
    def spriteChildAtY(parent: String, name: String, y: Float64,
                        zIndex: Int32, scene: Scene[Tag]): Scene[Tag] =
        let sprite = Sprite2D.make(name + ".png", {x = 0.0, y = y}, {x = 1.0, y = 1.0})
            |> CanvasItem.setZIndex(zIndex);
        Scene.addChildAt(parent :: Nil, name, EngineNode.Sprite2DWithState(sprite, Tag.NoTag), scene)

    /// Drawable リストから texture 名のリストを抽出する（順序確認用）
    def textures(drawables: List[GameEngine.Drawable]): List[String] =
        List.map(d -> d#texture, drawables)

    // ========================================================================
    // 1. デフォルト無効: Y-sort なしならツリー順（Map キー順）
    // ========================================================================

    /// Marker2D 親（ySortEnabled=false）配下の子 Sprite2D は y に関係なくキー順で並ぶ
    def testDefaultDisabledKeepsTreeOrder(): Unit \ {Assert, GameEngine.Game} =
        let parent = Marker2D.make(Vec2.zero());
        let scene = Scene.empty()
            |> Scene.addNode("P", EngineNode.Marker2DWithState(parent, Tag.NoTag))
            |> spriteChildAtY("P", "a_high", 200.0, 0)
            |> spriteChildAtY("P", "b_low", 10.0, 0);
        let result = Scene.toDrawables(Camera2D.identityTransform(), scene);
        // キー昇順 "a_high" → "b_low"。Y は a_high が大きいが Y-sort 無効なのでキー順
        Assert.assertEq(expected = "a_high.png" :: "b_low.png" :: Nil, textures(result))

    @Test
    def testDefaultDisabledKeepsTreeOrderRunner(): Unit \ Assert =
        withMockTexture32(testDefaultDisabledKeepsTreeOrder)

    // ========================================================================
    // 2. Y-sort 有効: 子は global_y 昇順
    // ========================================================================

    /// Marker2D 親に ySortEnabled=true をセットすると子は y 昇順で描画される
    def testYSortReordersByGlobalY(): Unit \ {Assert, GameEngine.Game} =
        let parent = Marker2D.make(Vec2.zero())
            |> CanvasItem.setYSortEnabled(true);
        let scene = Scene.empty()
            |> Scene.addNode("P", EngineNode.Marker2DWithState(parent, Tag.NoTag))
            |> spriteChildAtY("P", "a_high", 200.0, 0)
            |> spriteChildAtY("P", "b_low", 10.0, 0);
        let result = Scene.toDrawables(Camera2D.identityTransform(), scene);
        // y=10 (b_low) → y=200 (a_high) の順
        Assert.assertEq(expected = "b_low.png" :: "a_high.png" :: Nil, textures(result))

    @Test
    def testYSortReordersByGlobalYRunner(): Unit \ Assert =
        withMockTexture32(testYSortReordersByGlobalY)

    // ========================================================================
    // 3. 同 Y のタイブレーク: 安定ソートで Map キー順
    // ========================================================================

    /// Y が同値なら、安定ソートにより Map キー順（"a_same" → "b_same"）で並ぶ
    def testYSortStableOnTie(): Unit \ {Assert, GameEngine.Game} =
        let parent = Marker2D.make(Vec2.zero())
            |> CanvasItem.setYSortEnabled(true);
        let scene = Scene.empty()
            |> Scene.addNode("P", EngineNode.Marker2DWithState(parent, Tag.NoTag))
            |> spriteChildAtY("P", "a_same", 100.0, 0)
            |> spriteChildAtY("P", "b_same", 100.0, 0);
        let result = Scene.toDrawables(Camera2D.identityTransform(), scene);
        Assert.assertEq(expected = "a_same.png" :: "b_same.png" :: Nil, textures(result))

    @Test
    def testYSortStableOnTieRunner(): Unit \ Assert =
        withMockTexture32(testYSortStableOnTie)

    // ========================================================================
    // 4. z_index がバケットを支配: 同バケット内のみ Y-sort
    // ========================================================================

    /// 子 A (y=200, z=0) と B (y=10, z=1) は Y-sort 有効でも z バケット順
    /// （z=0 が先、z=1 が後）になる。Y-sort は同 z 内のタイブレークでしかない
    def testZIndexDominatesYSort(): Unit \ {Assert, GameEngine.Game} =
        let parent = Marker2D.make(Vec2.zero())
            |> CanvasItem.setYSortEnabled(true);
        let scene = Scene.empty()
            |> Scene.addNode("P", EngineNode.Marker2DWithState(parent, Tag.NoTag))
            |> spriteChildAtY("P", "a_z0", 200.0, 0)
            |> spriteChildAtY("P", "b_z1", 10.0, 1);
        let result = Scene.toDrawables(Camera2D.identityTransform(), scene);
        // Y のみ見れば b → a だが、z=0 (a) が z=1 (b) より先に描画される
        Assert.assertEq(expected = "a_z0.png" :: "b_z1.png" :: Nil, textures(result))

    @Test
    def testZIndexDominatesYSortRunner(): Unit \ Assert =
        withMockTexture32(testZIndexDominatesYSort)

    // ========================================================================
    // 5. ネスト Y-sort: 内側親は独立した y-sort コンテキスト
    // ========================================================================

    /// outer (ySort=true, y=0)
    ///   ├── inner (ySort=true, y=100)
    ///   │     ├── a (local y=50  → global 150)
    ///   │     └── b (local y=-20 → global 80)
    ///   └── c (y=200)
    ///
    /// outer の子は inner (global y=100) と c (global y=200) の順 → inner が先
    /// inner の子は b (global 80) → a (global 150) の順
    /// 期待全体順: inner → b → a → c
    def testNestedYSort(): Unit \ {Assert, GameEngine.Game} =
        let outer = Marker2D.make(Vec2.zero())
            |> CanvasItem.setYSortEnabled(true);
        let inner = Marker2D.make({x = 0.0, y = 100.0})
            |> CanvasItem.setYSortEnabled(true);
        let scene = Scene.empty()
            |> Scene.addNode("outer", EngineNode.Marker2DWithState(outer, Tag.NoTag))
            |> Scene.addChildAt("outer" :: Nil, "inner",
                EngineNode.Marker2DWithState(inner, Tag.NoTag))
            |> Scene.addChildAt("outer" :: "inner" :: Nil, "a_inner",
                EngineNode.Sprite2DWithState(
                    Sprite2D.make("a_inner.png", {x = 0.0, y = 50.0}, {x = 1.0, y = 1.0}),
                    Tag.NoTag))
            |> Scene.addChildAt("outer" :: "inner" :: Nil, "b_inner",
                EngineNode.Sprite2DWithState(
                    Sprite2D.make("b_inner.png", {x = 0.0, y = -20.0}, {x = 1.0, y = 1.0}),
                    Tag.NoTag))
            |> Scene.addChildAt("outer" :: Nil, "c_outer",
                EngineNode.Sprite2DWithState(
                    Sprite2D.make("c_outer.png", {x = 0.0, y = 200.0}, {x = 1.0, y = 1.0}),
                    Tag.NoTag));
        let result = Scene.toDrawables(Camera2D.identityTransform(), scene);
        // Marker2D は描画 0 件なので Drawable リストには現れない。
        // 期待: b_inner (global y=80) → a_inner (global y=150) → c_outer (global y=200)
        Assert.assertEq(
            expected = "b_inner.png" :: "a_inner.png" :: "c_outer.png" :: Nil,
            textures(result))

    @Test
    def testNestedYSortRunner(): Unit \ Assert =
        withMockTexture32(testNestedYSort)

    // ========================================================================
    // 6. CanvasLayer 配下は別バケット: y-sort で混ざらない
    // ========================================================================

    /// world: Marker2D(ySort=true) の子 hi_y (y=200)
    /// hud:   CanvasLayer (layer=1) の子 lo_y (y=10)
    ///
    /// CanvasLayer の layerOffset (=layerStride) が zIndex に加算されるので、
    /// HUD 配下の lo_y は world 配下の hi_y より z が大きく、必ず後に描画される。
    /// Y-sort が混ざることはない
    def testCanvasLayerSeparatesYSort(): Unit \ {Assert, GameEngine.Game} =
        let world = Marker2D.make(Vec2.zero())
            |> CanvasItem.setYSortEnabled(true);
        let hud = CanvasLayer.make(1);
        let scene = Scene.empty()
            |> Scene.addNode("world", EngineNode.Marker2DWithState(world, Tag.NoTag))
            |> spriteChildAtY("world", "hi_y", 200.0, 0)
            |> Scene.addNode("hud", EngineNode.CanvasLayerWithState(hud, Tag.NoTag))
            |> Scene.addChildAt("hud" :: Nil, "lo_y",
                EngineNode.Sprite2DWithState(
                    Sprite2D.make("lo_y.png", {x = 0.0, y = 10.0}, {x = 1.0, y = 1.0}),
                    Tag.NoTag));
        let result = Scene.toDrawables(Camera2D.identityTransform(), scene);
        // hi_y (z=0) が先、lo_y (z=0+layerStride=10000) が後
        Assert.assertEq(expected = "hi_y.png" :: "lo_y.png" :: Nil, textures(result))

    @Test
    def testCanvasLayerSeparatesYSortRunner(): Unit \ Assert =
        withMockTexture32(testCanvasLayerSeparatesYSort)

    // ========================================================================
    // 7. root レベルは y-sort されない（Godot Viewport ルートは y_sort 無効）
    // ========================================================================

    /// ルートに置いた Sprite2D 2 体は Map キー順で描画される（Y を見ない）
    /// → root レベルで Y-sort したい場合は明示的に Marker2D ルートで包む必要がある
    def testRootsAreNotYSorted(): Unit \ {Assert, GameEngine.Game} =
        let scene = Scene.empty()
            |> spriteAtY("a_high", 200.0)
            |> spriteAtY("b_low", 10.0);
        let result = Scene.toDrawables(Camera2D.identityTransform(), scene);
        Assert.assertEq(expected = "a_high.png" :: "b_low.png" :: Nil, textures(result))

    @Test
    def testRootsAreNotYSortedRunner(): Unit \ Assert =
        withMockTexture32(testRootsAreNotYSorted)

    // ========================================================================
    // 8. ySortEnabled の getter / setter ラウンドトリップ
    // ========================================================================

    /// Marker2D の ySortEnabled が getter / setter で往復できる
    @Test
    def testMarker2DYSortRoundTrip(): Unit \ Assert =
        let m = Marker2D.make(Vec2.zero());
        let after = CanvasItem.setYSortEnabled(true, m);
        Assert.assertEq(expected = (false, true),
            (CanvasItem.isYSortEnabled(m), CanvasItem.isYSortEnabled(after)))

    /// Sprite2D / AnimatedSprite2D / TileMapLayer に挿げ替えても getter が正しい
    /// （Sprite2D についてのみテスト — 他は同パターン）
    @Test
    def testSprite2DYSortRoundTrip(): Unit \ Assert =
        let s = Sprite2D.make("x.png", Vec2.zero(), {x = 1.0, y = 1.0});
        let after = CanvasItem.setYSortEnabled(true, s);
        Assert.assertEq(expected = (false, true),
            (CanvasItem.isYSortEnabled(s), CanvasItem.isYSortEnabled(after)))

    /// EngineNode 経由のディスパッチでも getter / setter が機能する
    @Test
    def testEngineNodeYSortDispatch(): Unit \ Assert =
        let m = Marker2D.make(Vec2.zero());
        let en: EngineNode[Tag] = EngineNode.Marker2DWithState(m, Tag.NoTag);
        let enOn = CanvasItem.setYSortEnabled(true, en);
        Assert.assertEq(expected = (false, true),
            (CanvasItem.isYSortEnabled(en), CanvasItem.isYSortEnabled(enOn)))

    /// Y-sort 非対応の variant (CharacterBody2D 等) では setter は no-op、
    /// getter は常に false（CanvasItem trait の default 実装）
    @Test
    def testEngineNodeYSortNoOpForUnsupported(): Unit \ Assert =
        let body = CharacterBody2D.make(Vec2.zero(), {moveSpeed = 0.0});
        let en: EngineNode[Tag] = EngineNode.Body2DWithState(body, Tag.NoTag);
        let enToggled = CanvasItem.setYSortEnabled(true, en);
        Assert.assertEq(expected = (false, false),
            (CanvasItem.isYSortEnabled(en), CanvasItem.isYSortEnabled(enToggled)))

}
