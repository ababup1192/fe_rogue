// Tests for InputEvent — キー・マウス入力差分の検出と InputHandler 発火

// ── テスト用の状態型 ──
// "log" ノードに押下/離脱・マウスイベントを Tag 付きで蓄積する

enum TestInputEvt with Eq, ToString {
    case Pressed(GameEngine.Key)
    case Released(GameEngine.Key)
    case MousePressed(GameEngine.MouseButton, Float64, Float64)
    case MouseReleased(GameEngine.MouseButton, Float64, Float64)
    case MouseMotion(Float64, Float64, Float64, Float64)
}

enum TestInputState with Eq {
    case EventLog(List[TestInputEvt])
}

instance Node[TestInputState] {
    type Aef = {}
}

instance InputEvent.InputHandler[TestInputState] {
    type Aef = {}
    redef onKeyPressed(key: GameEngine.Key,
                       scene: Scene[TestInputState]): Scene[TestInputState] =
        appendEvent(TestInputEvt.Pressed(key), scene)

    redef onKeyReleased(key: GameEngine.Key,
                        scene: Scene[TestInputState]): Scene[TestInputState] =
        appendEvent(TestInputEvt.Released(key), scene)

    redef onMouseButtonPressed(btn: GameEngine.MouseButton,
                               pos: Vec2.Vec2,
                               scene: Scene[TestInputState]): Scene[TestInputState] =
        appendEvent(TestInputEvt.MousePressed(btn, pos#x, pos#y), scene)

    redef onMouseButtonReleased(btn: GameEngine.MouseButton,
                                pos: Vec2.Vec2,
                                scene: Scene[TestInputState]): Scene[TestInputState] =
        appendEvent(TestInputEvt.MouseReleased(btn, pos#x, pos#y), scene)

    redef onMouseMotion(pos: Vec2.Vec2,
                       relative: Vec2.Vec2,
                       scene: Scene[TestInputState]): Scene[TestInputState] =
        appendEvent(TestInputEvt.MouseMotion(pos#x, pos#y, relative#x, relative#y), scene)
}

/// "log" ノードのイベントログにイベントを追加する
def appendEvent(evt: TestInputEvt, scene: Scene[TestInputState]): Scene[TestInputState] =
    Scene.mapState("log" :: Nil, st ->
        match st {
            case TestInputState.EventLog(evts) => TestInputState.EventLog(evt :: evts)
        }, scene)

/// 空のイベントログを持つテスト用シーン
def emptyLogScene(): Scene[TestInputState] =
    let rect = ColorRect.make({x = 1.0, y = 1.0}, {r = 0.0f32, g = 0.0f32, b = 0.0f32});
    Scene.empty()
        |> Scene.addNode("log",
            EngineNode.ColorRectWithState(rect, TestInputState.EventLog(Nil)))

/// シーンからイベントログを取り出す（古い順に並べ直す）
def extractLog(scene: Scene[TestInputState]): List[TestInputEvt] =
    match Scene.getState("log" :: Nil, scene) {
        case Some(TestInputState.EventLog(evts)) => List.reverse(evts)
        case _ => bug!("log node missing")
    }

/// 入力状態をパラメータ化したハンドラ
def runWithInput(keys: Set[GameEngine.Key],
                 buttons: Set[GameEngine.MouseButton],
                 mousePos: Vec2.Vec2,
                 f: Unit -> a \ GameEngine.Game): a =
    run f() with handler GameEngine.Game {
        def render(_, k) = k(())
        def shouldClose(k) = k(false)
        def getDeltaTime(k) = k(0.016)
        def isKeyPressed(key, k) = k(Set.memberOf(key, keys))
        def getMousePosition(k) = k(mousePos)
        def isMouseButtonPressed(btn, k) = k(Set.memberOf(btn, buttons))
        def getFontAtlas(_, _) = bug!("font not used")
        def getViewportRect(k) = k({position = Vec2.zero(), size = {x = 480.0, y = 720.0}})
        def getTextureInfo(_, k) = k(None)
        def setCursor(_, k) = k(())
    }

/// 後方互換: 指定キーが押されている GameEngine.Game ハンドラ
def runWithKeys(keys: Set[GameEngine.Key], f: Unit -> a \ GameEngine.Game): a =
    runWithInput(keys, Set.empty(), Vec2.zero(), f)

// ========================================================================
// currentKeys: 走査と Set 構築
// ========================================================================

/// 何も押されていなければ空集合
@Test
def testCurrentKeysEmpty(): Unit \ Assert =
    let keys = runWithKeys(Set.empty(), () -> InputEvent.currentKeys());
    Assert.assertEq(expected = 0, Set.size(keys))

/// 押されているキーのみが含まれる
@Test
def testCurrentKeysSingle(): Unit \ Assert =
    let keys = runWithKeys(
        Set.singleton(GameEngine.Key.W),
        () -> InputEvent.currentKeys());
    Assert.assertTrue(Set.memberOf(GameEngine.Key.W, keys));
    Assert.assertEq(expected = 1, Set.size(keys))

/// 複数キーが押されていれば全部含まれる
@Test
def testCurrentKeysMultiple(): Unit \ Assert =
    let pressed = Set.empty()
        |> Set.insert(GameEngine.Key.W)
        |> Set.insert(GameEngine.Key.D)
        |> Set.insert(GameEngine.Key.Space);
    let keys = runWithKeys(pressed, () -> InputEvent.currentKeys());
    Assert.assertEq(expected = 3, Set.size(keys));
    Assert.assertTrue(Set.memberOf(GameEngine.Key.W, keys));
    Assert.assertTrue(Set.memberOf(GameEngine.Key.D, keys));
    Assert.assertTrue(Set.memberOf(GameEngine.Key.Space, keys))

// ========================================================================
// handleInput: 押下イベントの発火
// ========================================================================

/// 初フレームで押されているキーは onKeyPressed 発火
@Test
def testHandleInputFiresPressedOnFirstFrame(): Unit \ Assert =
    let scene = runWithKeys(
        Set.singleton(GameEngine.Key.W),
        () -> InputEvent.handleInput(emptyLogScene()));
    Assert.assertEq(expected = TestInputEvt.Pressed(GameEngine.Key.W) :: Nil,
                    extractLog(scene))

/// 押しっぱなしのキーは 2 フレーム目では発火しない
@Test
def testHandleInputNoFireOnHold(): Unit \ Assert =
    let pressed = Set.singleton(GameEngine.Key.W);
    let frame1 = runWithKeys(pressed, () -> InputEvent.handleInput(emptyLogScene()));
    let frame2 = runWithKeys(pressed, () -> InputEvent.handleInput(frame1));
    // フレーム1 の Pressed のみがログに残り、フレーム2 では追加発火なし
    Assert.assertEq(expected = TestInputEvt.Pressed(GameEngine.Key.W) :: Nil,
                    extractLog(frame2))

/// 押されたキーがリリースされると onKeyReleased 発火
@Test
def testHandleInputFiresReleasedOnRelease(): Unit \ Assert =
    let frame1 = runWithKeys(Set.singleton(GameEngine.Key.W),
        () -> InputEvent.handleInput(emptyLogScene()));
    let frame2 = runWithKeys(Set.empty(),
        () -> InputEvent.handleInput(frame1));
    Assert.assertEq(
        expected = TestInputEvt.Pressed(GameEngine.Key.W) ::
                   TestInputEvt.Released(GameEngine.Key.W) :: Nil,
        extractLog(frame2))

/// 押されていないキーがリリースされても何も発火しない
@Test
def testHandleInputNoFireOnNonPressedRelease(): Unit \ Assert =
    let scene = runWithKeys(Set.empty(),
        () -> InputEvent.handleInput(emptyLogScene()));
    Assert.assertEq(expected = (Nil: List[TestInputEvt]), extractLog(scene))

/// 複数キーの同時押下が 1 フレームで発火する
@Test
def testHandleInputMultipleKeysOnSameFrame(): Unit \ Assert =
    let pressed = Set.empty()
        |> Set.insert(GameEngine.Key.A)
        |> Set.insert(GameEngine.Key.D);
    let scene = runWithKeys(pressed,
        () -> InputEvent.handleInput(emptyLogScene()));
    Assert.assertEq(expected = 2, List.length(extractLog(scene)));
    Assert.assertTrue(List.memberOf(TestInputEvt.Pressed(GameEngine.Key.A), extractLog(scene)));
    Assert.assertTrue(List.memberOf(TestInputEvt.Pressed(GameEngine.Key.D), extractLog(scene)))

/// 押下と離脱が同フレームで両方起きる（A は離す、B は新たに押す）
@Test
def testHandleInputPressAndReleaseSameFrame(): Unit \ Assert =
    let frame1 = runWithKeys(Set.singleton(GameEngine.Key.A),
        () -> InputEvent.handleInput(emptyLogScene()));
    let frame2 = runWithKeys(Set.singleton(GameEngine.Key.S),
        () -> InputEvent.handleInput(frame1));
    let log = extractLog(frame2);
    Assert.assertTrue(List.memberOf(TestInputEvt.Pressed(GameEngine.Key.A), log));
    Assert.assertTrue(List.memberOf(TestInputEvt.Released(GameEngine.Key.A), log));
    Assert.assertTrue(List.memberOf(TestInputEvt.Pressed(GameEngine.Key.S), log))

// ========================================================================
// prevKeyState の更新
// ========================================================================

/// handleInput 後 prevKeyState が現在状態に更新される
@Test
def testHandleInputUpdatesPrevState(): Unit \ Assert =
    let pressed = Set.singleton(GameEngine.Key.Enter);
    let scene = runWithKeys(pressed,
        () -> InputEvent.handleInput(emptyLogScene()));
    Assert.assertEq(expected = pressed, Scene.getPrevKeyState(scene))

/// 何も押されていなければ prevKeyState は空集合のまま
@Test
def testHandleInputEmptyPrevState(): Unit \ Assert =
    let scene = runWithKeys(Set.empty(),
        () -> InputEvent.handleInput(emptyLogScene()));
    Assert.assertEq(expected = 0, Set.size(Scene.getPrevKeyState(scene)))

// ========================================================================
// allKeys
// ========================================================================

/// allKeys は宣言された Key を全て含む
@Test
def testAllKeysContainsAll(): Unit \ Assert =
    let keys = GameEngine.allKeys();
    Assert.assertEq(expected = 16, List.length(keys));
    Assert.assertTrue(List.memberOf(GameEngine.Key.W, keys));
    Assert.assertTrue(List.memberOf(GameEngine.Key.Escape, keys));
    Assert.assertTrue(List.memberOf(GameEngine.Key.F1, keys));
    Assert.assertTrue(List.memberOf(GameEngine.Key.LeftShift, keys));
    Assert.assertTrue(List.memberOf(GameEngine.Key.Z, keys));
    Assert.assertTrue(List.memberOf(GameEngine.Key.LeftCtrl, keys));
    Assert.assertTrue(List.memberOf(GameEngine.Key.LeftSuper, keys))

// ========================================================================
// currentMouseButtons / allMouseButtons
// ========================================================================

/// 何も押されていなければ空集合
@Test
def testCurrentMouseButtonsEmpty(): Unit \ Assert =
    let btns = runWithInput(Set.empty(), Set.empty(), Vec2.zero(),
        () -> InputEvent.currentMouseButtons());
    Assert.assertEq(expected = 0, Set.size(btns))

/// 押されているマウスボタンのみが含まれる
@Test
def testCurrentMouseButtonsSingle(): Unit \ Assert =
    let pressed = Set.singleton(GameEngine.MouseButton.Left);
    let btns = runWithInput(Set.empty(), pressed, Vec2.zero(),
        () -> InputEvent.currentMouseButtons());
    Assert.assertTrue(Set.memberOf(GameEngine.MouseButton.Left, btns));
    Assert.assertEq(expected = 1, Set.size(btns))

/// allMouseButtons は宣言された MouseButton を全て含む
@Test
def testAllMouseButtonsContainsAll(): Unit \ Assert =
    let btns = GameEngine.allMouseButtons();
    Assert.assertEq(expected = 3, List.length(btns));
    Assert.assertTrue(List.memberOf(GameEngine.MouseButton.Left, btns));
    Assert.assertTrue(List.memberOf(GameEngine.MouseButton.Right, btns));
    Assert.assertTrue(List.memberOf(GameEngine.MouseButton.Middle, btns))

// ========================================================================
// handleInput: マウスボタン押下/離脱イベント
// ========================================================================

/// 初フレームで押されているマウスボタンは onMouseButtonPressed 発火
@Test
def testHandleInputFiresMouseButtonPressed(): Unit \ Assert =
    let pos = {x = 100.0, y = 200.0};
    let scene = runWithInput(Set.empty(),
        Set.singleton(GameEngine.MouseButton.Left), pos,
        () -> InputEvent.handleInput(emptyLogScene()));
    Assert.assertEq(
        expected = TestInputEvt.MousePressed(GameEngine.MouseButton.Left, 100.0, 200.0) :: Nil,
        extractLog(scene))

/// 押しっぱなしのマウスボタンは 2 フレーム目で発火しない
@Test
def testHandleInputNoFireOnMouseButtonHold(): Unit \ Assert =
    let pressed = Set.singleton(GameEngine.MouseButton.Left);
    let pos = {x = 50.0, y = 60.0};
    let frame1 = runWithInput(Set.empty(), pressed, pos,
        () -> InputEvent.handleInput(emptyLogScene()));
    let frame2 = runWithInput(Set.empty(), pressed, pos,
        () -> InputEvent.handleInput(frame1));
    Assert.assertEq(
        expected = TestInputEvt.MousePressed(GameEngine.MouseButton.Left, 50.0, 60.0) :: Nil,
        extractLog(frame2))

/// マウスボタンがリリースされると onMouseButtonReleased 発火
@Test
def testHandleInputFiresMouseButtonReleased(): Unit \ Assert =
    let pos = {x = 10.0, y = 20.0};
    let frame1 = runWithInput(Set.empty(),
        Set.singleton(GameEngine.MouseButton.Right), pos,
        () -> InputEvent.handleInput(emptyLogScene()));
    let frame2 = runWithInput(Set.empty(), Set.empty(), pos,
        () -> InputEvent.handleInput(frame1));
    Assert.assertEq(
        expected = TestInputEvt.MousePressed(GameEngine.MouseButton.Right, 10.0, 20.0) ::
                   TestInputEvt.MouseReleased(GameEngine.MouseButton.Right, 10.0, 20.0) :: Nil,
        extractLog(frame2))

// ========================================================================
// handleInput: マウス移動
// ========================================================================

/// 初フレームではマウス位置が確定していないので onMouseMotion は発火しない
@Test
def testHandleInputNoMouseMotionOnFirstFrame(): Unit \ Assert =
    let scene = runWithInput(Set.empty(), Set.empty(), {x = 10.0, y = 20.0},
        () -> InputEvent.handleInput(emptyLogScene()));
    Assert.assertEq(expected = (Nil: List[TestInputEvt]), extractLog(scene))

/// 2 フレーム目で位置が変化していれば onMouseMotion 発火（relative = current - prev）
@Test
def testHandleInputFiresMouseMotion(): Unit \ Assert =
    let pos1 = {x = 10.0, y = 20.0};
    let pos2 = {x = 50.0, y = 60.0};
    let frame1 = runWithInput(Set.empty(), Set.empty(), pos1,
        () -> InputEvent.handleInput(emptyLogScene()));
    let frame2 = runWithInput(Set.empty(), Set.empty(), pos2,
        () -> InputEvent.handleInput(frame1));
    Assert.assertEq(
        expected = TestInputEvt.MouseMotion(50.0, 60.0, 40.0, 40.0) :: Nil,
        extractLog(frame2))

/// 位置が変化していなければ onMouseMotion は発火しない
@Test
def testHandleInputNoMouseMotionWhenStationary(): Unit \ Assert =
    let pos = {x = 100.0, y = 100.0};
    let frame1 = runWithInput(Set.empty(), Set.empty(), pos,
        () -> InputEvent.handleInput(emptyLogScene()));
    let frame2 = runWithInput(Set.empty(), Set.empty(), pos,
        () -> InputEvent.handleInput(frame1));
    Assert.assertEq(expected = (Nil: List[TestInputEvt]), extractLog(frame2))

// ========================================================================
// prev*State の更新（マウス）
// ========================================================================

/// handleInput 後 prevMouseButtonState が現在状態に更新される
@Test
def testHandleInputUpdatesPrevMouseButtonState(): Unit \ Assert =
    let pressed = Set.singleton(GameEngine.MouseButton.Middle);
    let scene = runWithInput(Set.empty(), pressed, Vec2.zero(),
        () -> InputEvent.handleInput(emptyLogScene()));
    Assert.assertEq(expected = pressed, Scene.getPrevMouseButtonState(scene))

/// handleInput 後 prevMousePosition が現在位置に更新される
@Test
def testHandleInputUpdatesPrevMousePosition(): Unit \ Assert =
    let pos = {x = 42.0, y = 84.0};
    let scene = runWithInput(Set.empty(), Set.empty(), pos,
        () -> InputEvent.handleInput(emptyLogScene()));
    match Scene.getPrevMousePosition(scene) {
        case Some(p) => Assert.assertEq(expected = (42.0, 84.0), (p#x, p#y))
        case None => Assert.assertTrue(false)
    }

/// 初期状態の prevMousePosition は None
@Test
def testEmptySceneHasNoPrevMousePosition(): Unit \ Assert =
    let scene: Scene[TestInputState] = Scene.empty();
    Assert.assertTrue(Option.isEmpty(Scene.getPrevMousePosition(scene)))
