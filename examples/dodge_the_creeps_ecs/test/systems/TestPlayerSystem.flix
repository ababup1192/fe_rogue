// PlayerSystem のテスト — clampPlayerSystem（純粋）/ playerInputSystem（mock Game）

mod TestPlayerSystem {

    /// 入力ゼロの mock Game（playerInputSystem が触るのは isKeyPressed のみ）。
    def withMockGame(f: Unit -> a \ ef + GameEngine.Game): a \ ef =
        run f() with handler GameEngine.Game {
            def renderCommands(_, _, _, k)  = k(())
            def initTileBuffer(_, k)        = k((0i32, 0i32))
            def shouldClose(k)              = k(false)
            def getDeltaTime(k)             = k(Duration.seconds(0.1))
            def isKeyPressed(_, k)          = k(false)
            def getMousePosition(k)         = k({x = 0.0, y = 0.0})
            def isMouseButtonPressed(_, k)  = k(false)
            def consumeScrollDelta(k)       = k(0.0)
            def getFontAtlas(_, k)          = k(testFontAtlas())
            def getViewportRect(k)          = k({position = Vec2.zero(), size = {x = 480.0, y = 720.0}})
            def getTextureInfo(_, k)        = k(None)
            def setCursor(_, k)             = k(())
        }

    def testFontAtlas(): FontAtlas = {
        textureName = "font_test", fontSize = 32.0, textureSize = 512.0,
        ascent = 0.0, descent = 0.0, lineGap = 0.0, glyphs = Map.empty()
    }

    def playingWithPlayerAt(pos: Vec2.Vec2): World =
        let World.World(w0) = World.empty();
        let playing = World.World({phase = GamePhase.Playing | w0});
        World.spawnPlayer(pos, 30.0, playing)

    /// 画面外の player は半径ぶん内側へクランプされる（r=30 → x∈[30,450], y∈[30,690]）。
    @Test
    def testClampKeepsPlayerInScreen(): Unit \ Assert =
        let world = playingWithPlayerAt({x = 1000.0, y = -50.0});
        let after = PlayerSystem.clampPlayerSystem(world);
        let World.World(w) = after;
        let pid = w#player |> Option.getWithDefault(0);
        let p = Map.get(pid, w#positions) |> Option.getWithDefault(Vec2.zero());
        Assert.assertEq(expected = true, p#x == 450.0 and p#y == 30.0)

    /// 画面内の player はクランプで動かない。
    @Test
    def testClampNoopWhenInside(): Unit \ Assert =
        let world = playingWithPlayerAt({x = 240.0, y = 450.0});
        let after = PlayerSystem.clampPlayerSystem(world);
        let World.World(w) = after;
        let pid = w#player |> Option.getWithDefault(0);
        let p = Map.get(pid, w#positions) |> Option.getWithDefault(Vec2.zero());
        Assert.assertEq(expected = true, p#x == 240.0 and p#y == 450.0)

    /// 入力なしなら velocity[player] は 0 に設定される。
    @Test
    def testInputSetsZeroVelocityWithNoKeys(): Unit \ Assert =
        let world = playingWithPlayerAt({x = 240.0, y = 450.0});
        let after = withMockGame(() -> PlayerSystem.playerInputSystem(world));
        let World.World(w) = after;
        let pid = w#player |> Option.getWithDefault(0);
        let v = Map.get(pid, w#velocities) |> Option.getWithDefault({x = 9.0, y = 9.0});
        Assert.assertEq(expected = true, v#x == 0.0 and v#y == 0.0)
}
