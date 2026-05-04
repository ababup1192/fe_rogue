// Tests for PhysicsStep module

// テスト用の最小限 state 型（trait インスタンスを置くために組み込み型でなくユーザ定義型を使う）
enum TestPhysicsState with Eq { case S }

instance Node[TestPhysicsState] {
    type Aef = {}
}
instance AreaEvent.AreaHandler[TestPhysicsState] {
    type Aef = {}
    pub def onAreaEntered(_selfPath: NodePath, _selfState: TestPhysicsState,
                          _otherPath: NodePath, _otherState: TestPhysicsState,
                          scene: Scene[TestPhysicsState]): Scene[TestPhysicsState] = scene
}

// ========================================================================
// defaultGravity
// ========================================================================

/// デフォルト重力は下方向 980 pixels/sec²
@Test
def testPhysicsStepDefaultGravity(): Unit \ Assert =
    let gravity = PhysicsStep.defaultGravity();
    Assert.assertEq(expected = (0.0, 980.0), (gravity#x, gravity#y))

// ========================================================================
// 重力加速
// ========================================================================

/// 1秒間の重力加速で linearVelocity.y が 980 増加する
///
///   gravity = (0, 980)
///   初速 = (0, 0)
///   1秒後 → linearVelocity.y ≈ 980
///
@Test
def testPhysicsStepGravityAcceleration(): Unit \ Assert =
    let shape = CollisionShape2D.CircleShape2D({radius = 10.0});
    let body = RigidBody2D.make({x = 100.0, y = 100.0}, shape);
    let scene = Scene.empty()
        |> Scene.addNode("ball", EngineNode.RigidBody2DWithState(body, TestPhysicsState.S));
    let gravity = PhysicsStep.defaultGravity();
    let updated = PhysicsStep.integrate(1.0, gravity, scene);
    match Scene.getEngineNode("ball" :: Nil, updated) {
        case Some(EngineNode.RigidBody2DWithState(updatedBody, _)) =>
            let vel = RigidBody2D.getLinearVelocity(updatedBody);
            // 重力 980 * gravityScale 1.0 * delta 1.0 = 980
            // ダンピング 0 → factor = 1.0 → vel 変わらず
            Assert.assertEq(expected = (0.0, 980.0), (vel#x, vel#y))
        case _ => bug!("Expected RigidBody2DWithState")
    }

// ========================================================================
// gravityScale = 0 で重力無効化
// ========================================================================

/// gravityScale=0 なら重力が適用されない
@Test
def testPhysicsStepNoGravityWhenScaleZero(): Unit \ Assert =
    let shape = CollisionShape2D.CircleShape2D({radius = 10.0});
    let body = RigidBody2D.make({x = 0.0, y = 0.0}, shape)
        |> RigidBody2D.setGravityScale(0.0)
        |> RigidBody2D.setLinearVelocity({x = 50.0, y = 0.0});
    let scene = Scene.empty()
        |> Scene.addNode("ball", EngineNode.RigidBody2DWithState(body, TestPhysicsState.S));
    let updated = PhysicsStep.integrate(1.0, PhysicsStep.defaultGravity(), scene);
    match Scene.getEngineNode("ball" :: Nil, updated) {
        case Some(EngineNode.RigidBody2DWithState(updatedBody, _)) =>
            let vel = RigidBody2D.getLinearVelocity(updatedBody);
            // 重力なし、ダンピングなし → 速度不変
            Assert.assertEq(expected = (50.0, 0.0), (vel#x, vel#y))
        case _ => bug!("Expected RigidBody2DWithState")
    }

// ========================================================================
// 速度積分
// ========================================================================

/// 初速 (100, 0) で 0.5 秒後に位置が (50, 0) 移動する（重力なし）
@Test
def testPhysicsStepPositionIntegration(): Unit \ Assert =
    let shape = CollisionShape2D.CircleShape2D({radius = 10.0});
    let body = RigidBody2D.make({x = 0.0, y = 0.0}, shape)
        |> RigidBody2D.setGravityScale(0.0)
        |> RigidBody2D.setLinearVelocity({x = 100.0, y = 0.0});
    let scene = Scene.empty()
        |> Scene.addNode("ball", EngineNode.RigidBody2DWithState(body, TestPhysicsState.S));
    let updated = PhysicsStep.integrate(0.5, Vec2.zero(), scene);
    match Scene.getEngineNode("ball" :: Nil, updated) {
        case Some(EngineNode.RigidBody2DWithState(updatedBody, _)) =>
            let pos = Node2D.getPosition(updatedBody);
            Assert.assertEq(expected = (50.0, 0.0), (pos#x, pos#y))
        case _ => bug!("Expected RigidBody2DWithState")
    }

/// 角速度による回転積分
@Test
def testPhysicsStepRotationIntegration(): Unit \ Assert =
    let shape = CollisionShape2D.CircleShape2D({radius = 10.0});
    let body = RigidBody2D.make({x = 0.0, y = 0.0}, shape)
        |> RigidBody2D.setGravityScale(0.0)
        |> RigidBody2D.setAngularVelocity(2.0);
    let scene = Scene.empty()
        |> Scene.addNode("ball", EngineNode.RigidBody2DWithState(body, TestPhysicsState.S));
    let updated = PhysicsStep.integrate(0.5, Vec2.zero(), scene);
    match Scene.getEngineNode("ball" :: Nil, updated) {
        case Some(EngineNode.RigidBody2DWithState(updatedBody, _)) =>
            // 角速度 2.0 rad/s * 0.5 s = 1.0 rad
            Assert.assertEq(expected = 1.0, Node2D.getRotation(updatedBody))
        case _ => bug!("Expected RigidBody2DWithState")
    }

// ========================================================================
// ダンピング
// ========================================================================

/// linearDamp が速度を減衰させる
///
///   初速 = 100, damp = 1.0, delta = 1.0
///   factor = 1 + 1.0 * 1.0 = 2.0
///   重力後速度 = 100 (gravityScale=0)
///   ダンピング後速度 = 100 / 2.0 = 50
///
@Test
def testPhysicsStepLinearDamping(): Unit \ Assert =
    let shape = CollisionShape2D.CircleShape2D({radius = 10.0});
    let body = RigidBody2D.make({x = 0.0, y = 0.0}, shape)
        |> RigidBody2D.setGravityScale(0.0)
        |> RigidBody2D.setLinearVelocity({x = 100.0, y = 0.0})
        |> RigidBody2D.setLinearDamp(1.0);
    let scene = Scene.empty()
        |> Scene.addNode("ball", EngineNode.RigidBody2DWithState(body, TestPhysicsState.S));
    let updated = PhysicsStep.integrate(1.0, Vec2.zero(), scene);
    match Scene.getEngineNode("ball" :: Nil, updated) {
        case Some(EngineNode.RigidBody2DWithState(updatedBody, _)) =>
            let vel = RigidBody2D.getLinearVelocity(updatedBody);
            Assert.assertEq(expected = (50.0, 0.0), (vel#x, vel#y))
        case _ => bug!("Expected RigidBody2DWithState")
    }

/// angularDamp が角速度を減衰させる
@Test
def testPhysicsStepAngularDamping(): Unit \ Assert =
    let shape = CollisionShape2D.CircleShape2D({radius = 10.0});
    let body = RigidBody2D.make({x = 0.0, y = 0.0}, shape)
        |> RigidBody2D.setGravityScale(0.0)
        |> RigidBody2D.setAngularVelocity(4.0)
        |> RigidBody2D.setAngularDamp(1.0);
    let scene = Scene.empty()
        |> Scene.addNode("ball", EngineNode.RigidBody2DWithState(body, TestPhysicsState.S));
    let updated = PhysicsStep.integrate(1.0, Vec2.zero(), scene);
    match Scene.getEngineNode("ball" :: Nil, updated) {
        case Some(EngineNode.RigidBody2DWithState(updatedBody, _)) =>
            // angularVelocity 4.0 / (1 + 1.0 * 1.0) = 2.0
            Assert.assertEq(expected = 2.0, RigidBody2D.getAngularVelocity(updatedBody))
        case _ => bug!("Expected RigidBody2DWithState")
    }

// ========================================================================
// 非 RigidBody2D ノードは影響を受けない
// ========================================================================

/// Sprite2D ノードは PhysicsStep で変更されない
@Test
def testPhysicsStepIgnoresNonRigidBody(): Unit \ Assert =
    let sprite = Sprite2D.make("test", {x = 10.0, y = 20.0}, {x = 1.0, y = 1.0});
    let scene = Scene.empty()
        |> Scene.addNode("sprite", EngineNode.Sprite2DWithState(sprite, TestPhysicsState.S));
    let updated = PhysicsStep.integrate(1.0, PhysicsStep.defaultGravity(), scene);
    match Scene.getEngineNode("sprite" :: Nil, updated) {
        case Some(node) =>
            let pos = Node2D.getPosition(node);
            // 位置が変わっていないことを確認
            Assert.assertEq(expected = (10.0, 20.0), (pos#x, pos#y))
        case _ => bug!("Expected Sprite2DWithState")
    }

// ========================================================================
// 複数 RigidBody2D ノード
// ========================================================================

/// 複数の RigidBody2D がそれぞれ独立に物理更新される
@Test
def testPhysicsStepMultipleBodies(): Unit \ Assert =
    let shape = CollisionShape2D.CircleShape2D({radius = 5.0});
    let bodyA = RigidBody2D.make({x = 0.0, y = 0.0}, shape)
        |> RigidBody2D.setGravityScale(0.0)
        |> RigidBody2D.setLinearVelocity({x = 10.0, y = 0.0});
    let bodyB = RigidBody2D.make({x = 100.0, y = 0.0}, shape)
        |> RigidBody2D.setGravityScale(0.0)
        |> RigidBody2D.setLinearVelocity({x = -20.0, y = 0.0});
    let scene = Scene.empty()
        |> Scene.addNode("a", EngineNode.RigidBody2DWithState(bodyA, TestPhysicsState.S))
        |> Scene.addNode("b", EngineNode.RigidBody2DWithState(bodyB, TestPhysicsState.S));
    let updated = PhysicsStep.integrate(1.0, Vec2.zero(), scene);
    let posA = Scene.getEngineNode("a" :: Nil, updated) |> Option.map(Node2D.getPosition);
    let posB = Scene.getEngineNode("b" :: Nil, updated) |> Option.map(Node2D.getPosition);
    match (posA, posB) {
        case (Some(pa), Some(pb)) =>
            Assert.assertEq(expected = (10.0, 0.0, 80.0, 0.0), (pa#x, pa#y, pb#x, pb#y))
        case _ => bug!("Expected both nodes")
    }

// ========================================================================
// step（physicsProcess + integrate 統合）
// ========================================================================

/// step は physicsProcess → integrate の順で実行される
@Test
def testPhysicsStepStepCallsPhysicsProcess(): Unit \ Assert =
    let shape = CollisionShape2D.CircleShape2D({radius = 10.0});
    let body = RigidBody2D.make({x = 0.0, y = 0.0}, shape)
        |> RigidBody2D.setGravityScale(0.0);
    let scene = Scene.empty()
        |> Scene.addNode("ball", EngineNode.RigidBody2DWithState(body, TestPhysicsState.S));
    // Node[TestPhysicsState] の physicsProcess はデフォルト no-op なので integrate と同じ結果
    let updated = PhysicsStep.step(1.0, false, Vec2.zero(), scene);
    match Scene.getEngineNode("ball" :: Nil, updated) {
        case Some(EngineNode.RigidBody2DWithState(updatedBody, _)) =>
            let pos = Node2D.getPosition(updatedBody);
            // 速度 0、重力 0 → 位置不変
            Assert.assertEq(expected = (0.0, 0.0), (pos#x, pos#y))
        case _ => bug!("Expected RigidBody2DWithState")
    }

// ========================================================================
// resolveStaticCollisions: collisionExceptions による skip
// ========================================================================

/// addCollisionException で登録した StaticBody2D とは押し戻されない
/// （Godot add_collision_exception_with 相当）
@Test
def testPhysicsStepResolveSkipsExceptionPair(): Unit \ Assert =
    let rigidShape = CollisionShape2D.CircleShape2D({radius = 10.0});
    let staticShape = CollisionShape2D.RectShape2D({width = 20.0, height = 20.0});
    let staticPath = "wall" :: Nil;
    // 重なり位置に配置（rigid 中心 = static 中心 → 完全に貫通）
    let rigidBody = RigidBody2D.make({x = 0.0, y = 0.0}, rigidShape)
        |> RigidBody2D.addCollisionException(staticPath);
    let staticBody = StaticBody2D.make({x = 0.0, y = 0.0}, staticShape);
    let scene = Scene.empty()
        |> Scene.addNode("ball", EngineNode.RigidBody2DWithState(rigidBody, TestPhysicsState.S))
        |> Scene.addNode("wall", EngineNode.StaticBody2DWithState(staticBody, TestPhysicsState.S));
    let updated = PhysicsStep.resolveStaticCollisions(scene);
    let pos = Scene.globalPosition("ball", updated);
    // exception 登録済み → MTV は適用されず位置不変
    Assert.assertEq(expected = (0.0, 0.0), (pos#x, pos#y))

/// 例外なし／重なりあり → MTV による押し戻しが適用される（既存挙動の回帰確認）
@Test
def testPhysicsStepResolveAppliesWithoutException(): Unit \ Assert =
    let rigidShape = CollisionShape2D.CircleShape2D({radius = 10.0});
    let staticShape = CollisionShape2D.RectShape2D({width = 20.0, height = 20.0});
    // 同じ位置、exception なし
    let rigidBody = RigidBody2D.make({x = 0.0, y = 0.0}, rigidShape);
    let staticBody = StaticBody2D.make({x = 0.0, y = 0.0}, staticShape);
    let scene = Scene.empty()
        |> Scene.addNode("ball", EngineNode.RigidBody2DWithState(rigidBody, TestPhysicsState.S))
        |> Scene.addNode("wall", EngineNode.StaticBody2DWithState(staticBody, TestPhysicsState.S));
    let updated = PhysicsStep.resolveStaticCollisions(scene);
    let pos = Scene.globalPosition("ball", updated);
    // 例外なし → MTV が適用されて位置が変化（具体値は MTV の方向選択次第なので不変ではないことだけ確認）
    Assert.assertTrue(pos#x != 0.0 or pos#y != 0.0)
