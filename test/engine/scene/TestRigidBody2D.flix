// Tests for RigidBody2D module

/// テスト用ヘルパー: 円形 RigidBody2D を生成
def mkRigidBody(): RigidBody2D =
    RigidBody2D.make({x = 0.0, y = 0.0}, CollisionShape2D.CircleShape2D({radius = 10.0}))

// ========================================================================
// make: デフォルト値
// ========================================================================

/// make 直後のデフォルト値（位置・visible・zIndex・gravityScale・mass・bounce・linearDamp・
/// monitoring・monitorable）
@Test
def testRigidBody2DMakeDefaults(): Unit \ Assert =
    let body = RigidBody2D.make({x = 100.0, y = 200.0},
        CollisionShape2D.CircleShape2D({radius = 10.0}));
    Assert.assertEq(
        expected = (100.0, 200.0, true, 0, 1.0, 1.0, 0.0, 0.0, false, true),
        (Node2D.getPosition(body)#x,
         Node2D.getPosition(body)#y,
         CanvasItem.isVisible(body),
         CanvasItem.getZIndex(body),
         RigidBody2D.getGravityScale(body),
         RigidBody2D.getMass(body),
         RigidBody2D.getBounce(body),
         RigidBody2D.getLinearDamp(body),
         CollisionObject2D.isMonitoring(body),
         CollisionObject2D.isMonitorable(body)))

// ========================================================================
// 各 setter のラウンドトリップ（pipe で全プロパティを書き換えてから読み戻す）
// ========================================================================

/// 全 setter を 1 度ずつ通し、書き換えた値が getter から返る
@Test
def testRigidBody2DSettersRoundTrip(): Unit \ Assert =
    let body = mkRigidBody()
        |> Node2D.setPosition({x = 50.0, y = 75.0})
        |> Node2D.setRotation(1.57)
        |> RigidBody2D.setLinearVelocity({x = 100.0, y = -50.0})
        |> RigidBody2D.setAngularVelocity(3.14)
        |> RigidBody2D.setGravityScale(0.5)
        |> RigidBody2D.setMass(5.0)
        |> RigidBody2D.setBounce(0.8)
        |> RigidBody2D.setLinearDamp(2.0)
        |> RigidBody2D.setAngularDamp(1.5)
        |> RigidBody2D.setPriority(5)
        |> CanvasItem.hide;
    Assert.assertEq(
        expected = ((50.0, 75.0), 1.57, (100.0, -50.0), 3.14,
                    0.5, 5.0, 0.8, 2.0, 1.5, 5, false),
        ((Node2D.getPosition(body)#x, Node2D.getPosition(body)#y),
         Node2D.getRotation(body),
         (RigidBody2D.getLinearVelocity(body)#x, RigidBody2D.getLinearVelocity(body)#y),
         RigidBody2D.getAngularVelocity(body),
         RigidBody2D.getGravityScale(body),
         RigidBody2D.getMass(body),
         RigidBody2D.getBounce(body),
         RigidBody2D.getLinearDamp(body),
         RigidBody2D.getAngularDamp(body),
         CollisionObject2D.getCollisionPriority(body),
         CanvasItem.isVisible(body)))

// ========================================================================
// collisionExceptions（Godot add_collision_exception_with 相当）
// ========================================================================

/// addCollisionException で登録した path のみ hasCollisionException が true を返す
///   - 初期状態 (空)            → false
///   - 登録した path            → true
///   - 登録していない別 path    → false
@Test
def testRigidBody2DCollisionExceptions(): Unit \ Assert =
    let registered = "pipe_0_top" :: Nil;
    let unregistered = "pipe_1_top" :: Nil;
    let initial = mkRigidBody();
    let withException = initial |> RigidBody2D.addCollisionException(registered);
    Assert.assertEq(
        expected = (false, true, false),
        (RigidBody2D.hasCollisionException(registered, initial),
         RigidBody2D.hasCollisionException(registered, withException),
         RigidBody2D.hasCollisionException(unregistered, withException)))
