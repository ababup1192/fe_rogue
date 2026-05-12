// Tests for PhysicsBody2D trait
// trait は CharacterBody2D / RigidBody2D の両方で同じ操作を提供する。
// 個別具象型の振る舞いは TestCharacterBody2D / TestRigidBody2D が担うので、
// ここでは「どちらの具象型でも trait API が同様に効く」ことに集中する。

// ========================================================================
// trait 経由でのラウンドトリップ + moveAndCollide（両具象型を一度に検証）
// ========================================================================

/// PhysicsBody2D trait の操作（setLinearVelocity / moveAndCollide）が
/// CharacterBody2D と RigidBody2D の両方で同じ結果になる
///
///   start: position=(10, 20)
///   PhysicsBody2D.setLinearVelocity({x=50, y=-10})
///   PhysicsBody2D.moveAndCollide({x=5, y=-3})
///   → 速度 = (50, -10)、位置 = (15, 17)
@Test
def testPhysicsBody2DUnifiedBehavior(): Unit \ Assert =
    let charBody = CharacterBody2D.make({x = 10.0, y = 20.0}, moveSpeed = 100.0)
        |> PhysicsBody2D.setLinearVelocity({x = 50.0, y = -10.0})
        |> PhysicsBody2D.moveAndCollide({x = 5.0, y = -3.0});
    let rigidBody = RigidBody2D.make({x = 10.0, y = 20.0},
            CollisionShape2D.CircleShape2D({radius = 10.0}))
        |> PhysicsBody2D.setLinearVelocity({x = 50.0, y = -10.0})
        |> PhysicsBody2D.moveAndCollide({x = 5.0, y = -3.0});
    let charVel = PhysicsBody2D.getLinearVelocity(charBody);
    let charPos = Node2D.getPosition(charBody);
    let rigidVel = PhysicsBody2D.getLinearVelocity(rigidBody);
    let rigidPos = Node2D.getPosition(rigidBody);
    let expected = ((50.0, -10.0), (15.0, 17.0));
    Assert.assertEq(
        expected = (expected, expected),
        (((charVel#x, charVel#y), (charPos#x, charPos#y)),
         ((rigidVel#x, rigidVel#y), (rigidPos#x, rigidPos#y))))

/// ゼロモーションでは moveAndCollide で位置が変わらない
@Test
def testPhysicsBody2DMoveAndCollideZeroMotion(): Unit \ Assert =
    let body = RigidBody2D.make({x = 42.0, y = 99.0},
            CollisionShape2D.CircleShape2D({radius = 10.0}))
        |> PhysicsBody2D.moveAndCollide(Vec2.zero());
    let pos = Node2D.getPosition(body);
    Assert.assertEq(expected = (42.0, 99.0), (pos#x, pos#y))
