// Tests for Game module — Scene 全体の構造ヘルパーとフェーズ遷移

// ── 共通ヘルパー ──

/// GameEngine.Audio のモック (no-op)
def withMockAudio(f: Unit -> a \ ef + GameEngine.Audio): a \ ef =
    run f() with handler GameEngine.Audio {
        def playAudio(_, k)     = k(())
        def stopAudio(_, k)     = k(())
        def setVolume(_, _, k)  = k(())
        def setLooping(_, _, k) = k(())
    }

/// GameEngine.Game のモック (no-op、デフォルト値返却)。
/// HUDScene.addHUD など SceneLoader.loadSceneWithFont を呼ぶ箇所で要求される。
def withMockGame(f: Unit -> a \ ef + GameEngine.Game): a \ ef =
    run f() with handler GameEngine.Game {
        def renderCommands(_, _, k)     = k(())
        def initTileBuffer(_, k)        = k((0i32, 0i32))
        def shouldClose(k)              = k(false)
        def getDeltaTime(k)             = k(Duration.seconds(0.016))
        def isKeyPressed(_, k)          = k(false)
        def getMousePosition(k)         = k({x = 0.0, y = 0.0})
        def isMouseButtonPressed(_, k)  = k(false)
        def consumeScrollDelta(k)       = k(0.0)
        def getFontAtlas(_, k)          = k(testFontAtlas())
        def getViewportRect(k)          = k({position = Vec2.zero(), size = {x = 480.0, y = 720.0}})
        def getTextureInfo(_, k)        = k(None)
        def setCursor(_, k)             = k(())
    }

/// テスト用のダミー FontAtlas
def testFontAtlas(): FontAtlas = {
    textureName = "font_test",
    fontSize    = 32.0,
    textureSize = 512.0,
    ascent      = 0.0,
    descent     = 0.0,
    lineGap     = 0.0,
    glyphs      = Map.empty()
}

/// Menu シーン構築。Fs.FileRead (HUDScene が scene.json を読む) と GameEngine.Game
/// は test helper で discharge する。@Test は \ Assert しか許さないため、
/// 最終的に unchecked_cast で effect を消す (IO は実行時には実際に走る)。
def testMenuScene(): Scene[NodeTag] =
    unchecked_cast(
        (run {
            withMockGame(() -> Game.buildMenuScene(testFontAtlas()))
        } with Fs.FileRead.runWithIO)
        as _ \ {})

/// Playing シーン構築 (GameEngine.Audio + Game + Fs.FileRead のモック付き)
def testPlayingScene(): Scene[NodeTag] =
    unchecked_cast(
        (run {
            withMockAudio(() -> withMockGame(() -> Game.buildPlayingScene(testFontAtlas())))
        } with Fs.FileRead.runWithIO)
        as _ \ {})

// ── テスト ──

/// Menu シーンには player / hud / mob_timer / start_timer / score_timer / mob_path / background が含まれる
@Test
def testMenuSceneHasCoreNodes(): Unit \ Assert =
    let scene = testMenuScene();
    Assert.assertEq(
        expected = (true, true, true, true, true, true, true),
        (
            Option.nonEmpty(Scene.getEngineNode("background" :: Nil, scene)),
            Option.nonEmpty(Scene.getEngineNode(PlayerScene.playerPath(), scene)),
            Option.nonEmpty(Scene.getEngineNode(HUDScene.hudPath(), scene)),
            Option.nonEmpty(Scene.getEngineNode(Game.mobTimerPath(), scene)),
            Option.nonEmpty(Scene.getEngineNode(Game.startTimerPath(), scene)),
            Option.nonEmpty(Scene.getEngineNode(Game.scoreTimerPath(), scene)),
            Option.nonEmpty(Scene.getEngineNode("mob_path" :: Nil, scene))
        ))

/// Menu シーンでは StartButton が表示状態にある
@Test
def testMenuSceneShowsStartButton(): Unit \ Assert =
    Assert.assertEq(expected = true, HUDScene.isStartButtonVisible(testMenuScene()))

/// Playing シーンでは StartButton が非表示
@Test
def testPlayingSceneHidesStartButton(): Unit \ Assert =
    Assert.assertEq(expected = false, HUDScene.isStartButtonVisible(testPlayingScene()))

/// Playing シーンでは StartTimer が running (Get Ready 表示中)
@Test
def testPlayingSceneStartsStartTimer(): Unit \ Assert =
    let scene = testPlayingScene();
    let running = match Scene.getEngineNode(Game.startTimerPath(), scene) {
        case Some(EngineNode.TimerWithState(timer, _)) => Timer.isRunning(timer)
        case _                                          => false
    };
    Assert.assertEq(expected = true, running)

/// canStart は Menu / GameOver(StartButton 可視) で true、Playing で false
@Test
def testCanStartInMenu(): Unit \ Assert =
    let scene = testMenuScene();
    let result = run Game.canStart(scene) with handler GamePhaseState {
        def get(k)    = k(GamePhase.Menu)
        def put(_, k) = k(())
    };
    Assert.assertEq(expected = true, result)

@Test
def testCannotStartWhilePlaying(): Unit \ Assert =
    let scene = testPlayingScene();
    let result = run Game.canStart(scene) with handler GamePhaseState {
        def get(k)    = k(GamePhase.Playing)
        def put(_, k) = k(())
    };
    Assert.assertEq(expected = false, result)

/// GamePhase 等価性
@Test
def testGamePhaseEquality(): Unit \ Assert =
    Assert.assertEq(
        expected = (true, false),
        (GamePhase.Menu == GamePhase.Menu, GamePhase.Menu == GamePhase.Playing))

/// PlayerScene.getPlayerData が初期状態を返す
@Test
def testPlayerInitialData(): Unit \ Assert =
    let dataOpt = PlayerScene.getPlayerData(testMenuScene());
    let ok = match dataOpt {
        case Some(d) =>
            let v = d#velocity;
            d#hit == false and v#x == 0.0 and v#y == 0.0
        case None => false
    };
    Assert.assertEq(expected = true, ok)
