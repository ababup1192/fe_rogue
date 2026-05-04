// Tests for Area2D module

/// テスト用ヘルパー: 1×1 の矩形 Area2D を原点に生成
def mkArea(): Area2D =
    Area2D.make(Vec2.zero(), CollisionShape2D.RectShape2D({width = 1.0, height = 1.0}))

// ========================================================================
// make: デフォルト値（位置・monitoring・monitorable・priority・visible）
// ========================================================================

/// make 直後のデフォルト値
@Test
def testArea2DMakeDefaults(): Unit \ Assert =
    let area = Area2D.make({x = 10.0, y = 20.0},
        CollisionShape2D.RectShape2D({width = 32.0, height = 32.0}));
    Assert.assertEq(
        expected = (10.0, 20.0, true, true, 0i32, true),
        (Node2D.getPosition(area)#x,
         Node2D.getPosition(area)#y,
         CollisionObject2D.isMonitoring(area),
         CollisionObject2D.isMonitorable(area),
         CollisionObject2D.getCollisionPriority(area),
         CanvasItem.isVisible(area)))

// ========================================================================
// setter のラウンドトリップ
// ========================================================================

/// 全 setter を 1 度ずつ通し、書き換えた値が getter から返る
@Test
def testArea2DSettersRoundTrip(): Unit \ Assert =
    let area = mkArea()
        |> Node2D.setPosition({x = 100.0, y = 200.0})
        |> Area2D.setMonitoring(false)
        |> Area2D.setMonitorable(false)
        |> CanvasItem.setZIndex(5)
        |> CanvasItem.hide;
    Assert.assertEq(
        expected = ((100.0, 200.0), false, false, 5, false),
        ((Node2D.getPosition(area)#x, Node2D.getPosition(area)#y),
         CollisionObject2D.isMonitoring(area),
         CollisionObject2D.isMonitorable(area),
         CanvasItem.getZIndex(area),
         CanvasItem.isVisible(area)))

// ========================================================================
// 計算ロジック（オフセット加算 / 親子合算）
// ========================================================================

/// translate は現在位置にオフセットを加算する
///
///   (10, 10) -- translate(5, -3) --> (15, 7)
@Test
def testArea2DTranslate(): Unit \ Assert =
    let moved = Area2D.make({x = 10.0, y = 10.0},
        CollisionShape2D.RectShape2D({width = 1.0, height = 1.0}))
        |> Node2D.translate({x = 5.0, y = -3.0});
    let pos = Node2D.getPosition(moved);
    Assert.assertEq(expected = (15.0, 7.0), (pos#x, pos#y))

/// 親子関係で globalPosition が合算される
///
///   parent(100, 100)
///     └── child(16, 20)   →  globalPosition = (116, 120)
@Test
def testArea2DGlobalPosition(): Unit \ Assert =
    let parent = Area2D.make({x = 100.0, y = 100.0},
        CollisionShape2D.RectShape2D({width = 1.0, height = 1.0}));
    let child = Area2D.make({x = 16.0, y = 20.0},
        CollisionShape2D.RectShape2D({width = 32.0, height = 24.0}));
    let scene: Scene[Unit] = Scene.empty()
        |> Scene.addNode("player", EngineNode.Area2DWithState(parent, ()))
        |> Scene.addChild("player", "hitbox", EngineNode.Area2DWithState(child, ()));
    let gp = Scene.globalPositionAt("player" :: "hitbox" :: Nil, scene);
    Assert.assertEq(expected = (116.0, 120.0), (gp#x, gp#y))
