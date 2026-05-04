// Tests for VisibleOnScreenNotifier2D module

// ========================================================================
// make
// ========================================================================

/// make で中心基準の矩形が生成される
@Test
def testVisibleOnScreenNotifierMake(): Unit \ Assert =
    let notifier = VisibleOnScreenNotifier2D.make({x = 20.0, y = 10.0});
    let rect = VisibleOnScreenNotifier2D.getRect(notifier);
    Assert.assertEq(expected = (-10.0, -5.0, 20.0, 10.0),
        (rect#position#x, rect#position#y, rect#size#x, rect#size#y))

// ========================================================================
// isOnScreen
// ========================================================================

/// 画面中央にあるノードは画面内
///
///   +--screen--+
///   |  [node]  |
///   +----------+
///
@Test
def testIsOnScreenCenter(): Unit \ Assert =
    let notifier = VisibleOnScreenNotifier2D.make({x = 20.0, y = 20.0});
    Assert.assertEq(expected = true,
        VisibleOnScreenNotifier2D.isOnScreen(
            {x = 100.0, y = 100.0}, notifier,
            screenWidth = 200,
            screenHeight = 200))

/// 画面の右端をはみ出しているが一部重なっている場合は画面内
@Test
def testIsOnScreenPartiallyVisible(): Unit \ Assert =
    let notifier = VisibleOnScreenNotifier2D.make({x = 20.0, y = 20.0});
    Assert.assertEq(expected = true,
        VisibleOnScreenNotifier2D.isOnScreen(
            {x = 195.0, y = 100.0}, notifier,
            screenWidth = 200,
            screenHeight = 200))

/// 完全に画面の右側に出ている場合は画面外
///
///   +--screen--+     [node]
///   |          |
///   +----------+
///
@Test
def testIsOnScreenFullyRight(): Unit \ Assert =
    let notifier = VisibleOnScreenNotifier2D.make({x = 20.0, y = 20.0});
    Assert.assertEq(expected = false,
        VisibleOnScreenNotifier2D.isOnScreen(
            {x = 220.0, y = 100.0}, notifier,
            screenWidth = 200,
            screenHeight = 200))

/// 完全に画面の左側に出ている場合は画面外
@Test
def testIsOnScreenFullyLeft(): Unit \ Assert =
    let notifier = VisibleOnScreenNotifier2D.make({x = 20.0, y = 20.0});
    Assert.assertEq(expected = false,
        VisibleOnScreenNotifier2D.isOnScreen(
            {x = -20.0, y = 100.0}, notifier,
            screenWidth = 200,
            screenHeight = 200))

/// 完全に画面の上に出ている場合は画面外
@Test
def testIsOnScreenFullyAbove(): Unit \ Assert =
    let notifier = VisibleOnScreenNotifier2D.make({x = 20.0, y = 20.0});
    Assert.assertEq(expected = false,
        VisibleOnScreenNotifier2D.isOnScreen(
            {x = 100.0, y = -20.0}, notifier,
            screenWidth = 200,
            screenHeight = 200))

/// 完全に画面の下に出ている場合は画面外
@Test
def testIsOnScreenFullyBelow(): Unit \ Assert =
    let notifier = VisibleOnScreenNotifier2D.make({x = 20.0, y = 20.0});
    Assert.assertEq(expected = false,
        VisibleOnScreenNotifier2D.isOnScreen(
            {x = 100.0, y = 220.0}, notifier,
            screenWidth = 200,
            screenHeight = 200))

/// makeWithRect で直接 Rect2 を指定した場合
@Test
def testIsOnScreenWithRect(): Unit \ Assert =
    let notifier = VisibleOnScreenNotifier2D.makeWithRect({
        position = {x = 0.0, y = 0.0},
        size = {x = 10.0, y = 10.0}
    });
    Assert.assertEq(expected = true,
        VisibleOnScreenNotifier2D.isOnScreen(
            {x = -5.0, y = 50.0}, notifier,
            screenWidth = 200,
            screenHeight = 200))

/// 通知領域がちょうど画面端に接する場合は画面外（strict less-than）
@Test
def testIsOnScreenTouchingEdge(): Unit \ Assert =
    let notifier = VisibleOnScreenNotifier2D.make({x = 20.0, y = 20.0});
    Assert.assertEq(expected = false,
        VisibleOnScreenNotifier2D.isOnScreen(
            {x = 210.0, y = 100.0}, notifier,
            screenWidth = 200,
            screenHeight = 200))
