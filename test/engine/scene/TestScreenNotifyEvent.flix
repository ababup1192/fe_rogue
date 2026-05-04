// Tests for ScreenNotifyEvent — 画面外検出とハンドラ発火（子ノードベース）

// ── テスト用の状態型 ──

enum TestScreenState with Eq, ToString {
    case TrackedState       // notifier 子ノードの親 → 画面外検出の対象
    case TrackedEnteredState // onScreenEntered で遷移した状態
    case TrackedNotifier    // ScreenNotifier2DWithState の state
    case UntrackedState     // notifier なし → 無視
}

instance ScreenNotifyEvent.ScreenNotifyHandler[TestScreenState] {
    redef onScreenExited(path: NodePath, _state: TestScreenState,
                         scene: Scene[TestScreenState]): Scene[TestScreenState] =
        Scene.removeAt(path, scene)

    redef onScreenEntered(path: NodePath, _state: TestScreenState,
                          scene: Scene[TestScreenState]): Scene[TestScreenState] =
        Scene.mapState(path, _ -> TestScreenState.TrackedEnteredState, scene)
}

/// テスト用ヘルパー: TrackedState の RigidBody2D + ScreenNotifier2D 子ノードを作る
def trackedNode(name: String, x: Float64, y: Float64, scene: Scene[TestScreenState]): Scene[TestScreenState] =
    let body = RigidBody2D.make({x = x, y = y},
        CollisionShape2D.CircleShape2D({radius = 10.0}));
    let notifier = VisibleOnScreenNotifier2D.make({x = 20.0, y = 20.0});
    scene
        |> Scene.addNode(name,
            EngineNode.RigidBody2DWithState(body, TestScreenState.TrackedState))
        |> Scene.addChild(name, "notifier",
            EngineNode.ScreenNotifier2DWithState(notifier, TestScreenState.TrackedNotifier))

/// テスト用ヘルパー: UntrackedState の Sprite2D を作る（notifier 子ノードなし）
def untrackedNode(x: Float64, y: Float64): EngineNode[TestScreenState] =
    EngineNode.Sprite2DWithState(
        Sprite2D.make("test", {x = x, y = y}, {x = 1.0, y = 1.0}),
        TestScreenState.UntrackedState)

// ========================================================================
// handleScreenTransitions: 基本動作
// ========================================================================

/// 画面内のノードは削除されない
@Test
def testScreenNotifyKeepOnScreen(): Unit \ Assert =
    let scene: Scene[TestScreenState] = Scene.empty()
        |> trackedNode("a", 100.0, 100.0)
        |> ScreenNotifyEvent.handleScreenTransitions(
            screenWidth = 200, screenHeight = 200);
    Assert.assertTrue(not Option.isEmpty(Scene.getEngineNode("a" :: Nil, scene)))

/// 画面外のノードでも初回（prevOnScreen 未登録）は削除されない
@Test
def testScreenNotifyKeepFirstFrameOffScreen(): Unit \ Assert =
    let scene: Scene[TestScreenState] = Scene.empty()
        |> trackedNode("a", 300.0, 300.0)
        |> ScreenNotifyEvent.handleScreenTransitions(
            screenWidth = 200, screenHeight = 200);
    Assert.assertTrue(not Option.isEmpty(Scene.getEngineNode("a" :: Nil, scene)))

/// 画面内 → 画面外でノードが削除される（screen_exited 相当）
///
///   フレーム1: ノードは画面内 → prevOnScreen に登録
///   フレーム2: ノードを画面外に移動 → onScreenExited 発火 → 削除
@Test
def testScreenNotifyRemovesExitedNode(): Unit \ Assert =
    // フレーム1: 画面内
    let scene1: Scene[TestScreenState] = Scene.empty()
        |> trackedNode("a", 100.0, 100.0)
        |> ScreenNotifyEvent.handleScreenTransitions(
            screenWidth = 200, screenHeight = 200);
    // フレーム2: 画面外に移動
    let scene2 = Scene.setGlobalPosition("a", {x = 300.0, y = 300.0}, scene1)
        |> ScreenNotifyEvent.handleScreenTransitions(
            screenWidth = 200, screenHeight = 200);
    Assert.assertTrue(Option.isEmpty(Scene.getEngineNode("a" :: Nil, scene2)))

// ========================================================================
// handleScreenTransitions: 複数ノード
// ========================================================================

/// 複数ノードのうち画面外に出たものだけ削除される
@Test
def testScreenNotifySelectiveRemoval(): Unit \ Assert =
    // フレーム1: 両方画面内
    let scene1: Scene[TestScreenState] = Scene.empty()
        |> trackedNode("a", 50.0, 50.0)
        |> trackedNode("b", 150.0, 150.0)
        |> ScreenNotifyEvent.handleScreenTransitions(
            screenWidth = 200, screenHeight = 200);
    // フレーム2: "a" は画面内のまま、"b" を画面外に移動
    let scene2 = Scene.setGlobalPosition("b", {x = 300.0, y = 300.0}, scene1)
        |> ScreenNotifyEvent.handleScreenTransitions(
            screenWidth = 200, screenHeight = 200);
    let aExists = not Option.isEmpty(Scene.getEngineNode("a" :: Nil, scene2));
    let bExists = not Option.isEmpty(Scene.getEngineNode("b" :: Nil, scene2));
    Assert.assertEq(expected = (true, false), (aExists, bExists))

// ========================================================================
// handleScreenTransitions: notifier なしのノード
// ========================================================================

/// notifier なし（UntrackedState）のノードは監視されない
@Test
def testScreenNotifyIgnoresUntrackedNode(): Unit \ Assert =
    // フレーム1: 画面内
    let scene1: Scene[TestScreenState] = Scene.empty()
        |> Scene.addNode("a", untrackedNode(100.0, 100.0))
        |> ScreenNotifyEvent.handleScreenTransitions(
            screenWidth = 200, screenHeight = 200);
    // フレーム2: 画面外に移動しても削除されない
    let scene2 = Scene.setGlobalPosition("a", {x = 300.0, y = 300.0}, scene1)
        |> ScreenNotifyEvent.handleScreenTransitions(
            screenWidth = 200, screenHeight = 200);
    Assert.assertTrue(not Option.isEmpty(Scene.getEngineNode("a" :: Nil, scene2)))

// ========================================================================
// handleScreenTransitions: prevOnScreen の更新
// ========================================================================

/// 画面内ノードの親パスが prevOnScreen に登録される
@Test
def testScreenNotifyUpdatesPrevOnScreen(): Unit \ Assert =
    let scene: Scene[TestScreenState] = Scene.empty()
        |> trackedNode("a", 100.0, 100.0)
        |> ScreenNotifyEvent.handleScreenTransitions(
            screenWidth = 200, screenHeight = 200);
    Assert.assertTrue(Set.memberOf("a" :: Nil, Scene.getPrevOnScreen(scene)))

/// 画面外ノードは prevOnScreen に登録されない
@Test
def testScreenNotifyDoesNotTrackOffScreen(): Unit \ Assert =
    let scene: Scene[TestScreenState] = Scene.empty()
        |> trackedNode("a", 300.0, 300.0)
        |> ScreenNotifyEvent.handleScreenTransitions(
            screenWidth = 200, screenHeight = 200);
    Assert.assertFalse(Set.memberOf("a" :: Nil, Scene.getPrevOnScreen(scene)))

/// 削除されたノードは prevOnScreen からも消える
@Test
def testScreenNotifyRemovedNodeClearedFromPrevOnScreen(): Unit \ Assert =
    // フレーム1: 画面内
    let scene1: Scene[TestScreenState] = Scene.empty()
        |> trackedNode("a", 100.0, 100.0)
        |> ScreenNotifyEvent.handleScreenTransitions(
            screenWidth = 200, screenHeight = 200);
    // フレーム2: 画面外 → 削除
    let scene2 = Scene.setGlobalPosition("a", {x = 300.0, y = 300.0}, scene1)
        |> ScreenNotifyEvent.handleScreenTransitions(
            screenWidth = 200, screenHeight = 200);
    Assert.assertFalse(Set.memberOf("a" :: Nil, Scene.getPrevOnScreen(scene2)))

// ========================================================================
// handleScreenTransitions: onScreenEntered
// ========================================================================

/// 初回フレームで画面内のノードに onScreenEntered が発火する
@Test
def testScreenNotifyEnteredFirstFrame(): Unit \ Assert =
    let scene: Scene[TestScreenState] = Scene.empty()
        |> trackedNode("a", 100.0, 100.0)
        |> ScreenNotifyEvent.handleScreenTransitions(
            screenWidth = 200, screenHeight = 200);
    Assert.assertEq(expected = Some(TestScreenState.TrackedEnteredState),
        Scene.getState("a" :: Nil, scene))

/// 初回フレームで画面外のノードには onScreenEntered が発火しない
@Test
def testScreenNotifyNotEnteredFirstFrameOffScreen(): Unit \ Assert =
    let scene: Scene[TestScreenState] = Scene.empty()
        |> trackedNode("a", 300.0, 300.0)
        |> ScreenNotifyEvent.handleScreenTransitions(
            screenWidth = 200, screenHeight = 200);
    Assert.assertEq(expected = Some(TestScreenState.TrackedState),
        Scene.getState("a" :: Nil, scene))

/// 画面外 → 画面内で onScreenEntered が発火する
///
///   フレーム1: ノードは画面外 → prevOnScreen に未登録
///   フレーム2: ノードを画面内に移動 → onScreenEntered 発火
@Test
def testScreenNotifyEnteredAfterMove(): Unit \ Assert =
    // フレーム1: 画面外
    let scene1: Scene[TestScreenState] = Scene.empty()
        |> trackedNode("a", 300.0, 300.0)
        |> ScreenNotifyEvent.handleScreenTransitions(
            screenWidth = 200, screenHeight = 200);
    // フレーム2: 画面内に移動
    let scene2 = Scene.setGlobalPosition("a", {x = 100.0, y = 100.0}, scene1)
        |> ScreenNotifyEvent.handleScreenTransitions(
            screenWidth = 200, screenHeight = 200);
    Assert.assertEq(expected = Some(TestScreenState.TrackedEnteredState),
        Scene.getState("a" :: Nil, scene2))

/// 画面内に留まるノードには onScreenEntered が再発火しない（2フレーム目以降）
@Test
def testScreenNotifyNoReEnteredWhileOnScreen(): Unit \ Assert =
    // フレーム1: 画面内 → onScreenEntered で TrackedEnteredState になる
    let scene1: Scene[TestScreenState] = Scene.empty()
        |> trackedNode("a", 100.0, 100.0)
        |> ScreenNotifyEvent.handleScreenTransitions(
            screenWidth = 200, screenHeight = 200);
    // 状態を TrackedState に戻す（再発火しないことを確認するため）
    let scene1b = Scene.mapState("a" :: Nil, _ -> TestScreenState.TrackedState, scene1);
    // フレーム2: まだ画面内 → onScreenEntered は発火しない
    let scene2 = ScreenNotifyEvent.handleScreenTransitions(
            screenWidth = 200, screenHeight = 200, scene1b);
    Assert.assertEq(expected = Some(TestScreenState.TrackedState),
        Scene.getState("a" :: Nil, scene2))
