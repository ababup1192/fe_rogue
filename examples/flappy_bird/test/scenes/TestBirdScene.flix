// Tests for BirdScene — 鳥の構築・物理・状態遷移
// 共通ヘルパー（testScene / withMockX / runFlap / runBirdPhysicsProcess 等）は TestGame.flix を参照

// ========================================================================
// 鳥の初期配置
// ========================================================================

/// 鳥の初期状態（位置・状態・X 速度・gravity scale・初期アニメ）
///   addBird は画面中央付近 (144, 256) に Flapping 状態で配置し、
///   重力スケール 1.0、X 速度 100、アニメは "flap" で開始する
@Test
def testBirdInitialState(): Unit \ {Assert, Fs.FileRead} =
    let scene = testScene();
    let pos = Scene.globalPosition("bird", scene);
    let birdData = BirdScene.getBirdData(scene);
    match (Scene.getEngineNode("bird" :: Nil, scene),
           Scene.getEngineNode("bird" :: "sprite" :: Nil, scene)) {
        case (Some(EngineNode.RigidBody2DWithState(body, _)),
              Some(EngineNode.AnimSprite2DWithState(sprite, _))) =>
            Assert.assertEq(
                expected = ((144.0, 256.0), BirdState.Flapping, 1.0, 100.0, "flap"),
                (vecToTuple(pos),
                 birdData#state,
                 RigidBody2D.getGravityScale(body),
                 RigidBody2D.getLinearVelocity(body)#x,
                 AnimatedSprite2D.getCurrentAnimation(sprite)))
        case _ => bug!("bird or bird/sprite not found")
    }

/// 鳥の Area2D 子ノードは BirdArea タグを持ち、衝突検知側として monitoring=true
@Test
def testBirdAreaChild(): Unit \ {Assert, Fs.FileRead} =
    let scene = testScene();
    match (Scene.getState("bird" :: "area" :: Nil, scene),
           Scene.getEngineNode("bird" :: "area" :: Nil, scene)) {
        case (Some(NodeTag.BirdArea), Some(EngineNode.Area2DWithState(area, _))) =>
            Assert.assertTrue(CollisionObject2D.isMonitoring(area))
        case _ => bug!("bird area not found")
    }

// ========================================================================
// 重力: RigidBody2D が重力で落下する
// ========================================================================

/// 重力により鳥が下方向に落下する（0.5 秒積分で y > 400）
@Test
def testBirdFallsWithGravity(): Unit \ {Assert, Fs.FileRead} =
    let scene = testScene()
        |> PhysicsStep.integrate(0.5, PhysicsStep.defaultGravity());
    let pos = Scene.globalPosition("bird", scene);
    Assert.assertTrue(pos#y > 400.0)

// ========================================================================
// フラップ: 上方向の速度が設定される
// ========================================================================

/// flap で linear velocity y が -300、angular velocity が -3.0 に設定される
@Test
def testFlapSetsVelocity(): Unit \ {Assert, Fs.FileRead} =
    let scene = runFlap(testScene());
    match Scene.getEngineNode("bird" :: Nil, scene) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            Assert.assertEq(
                expected = (-300.0, -3.0),
                (RigidBody2D.getLinearVelocity(body)#y,
                 RigidBody2D.getAngularVelocity(body)))
        case _ => bug!("bird not found")
    }

/// flap 直後に重力を適用すると、上昇優位で y が初期位置より上にくる
@Test
def testFlapThenGravity(): Unit \ {Assert, Fs.FileRead} =
    let scene = testScene()
        |> runFlap
        |> PhysicsStep.integrate(0.02, PhysicsStep.defaultGravity());
    let pos = Scene.globalPosition("bird", scene);
    Assert.assertTrue(pos#y < 256.0)

// ========================================================================
// 回転制御: clampRotation
// ========================================================================

/// 回転が -30° 未満の場合、-30° にクランプされ、角速度が 0 にリセットされる
@Test
def testClampRotationMin(): Unit \ {Assert, Fs.FileRead} =
    let scene = testScene()
        |> BirdScene.mapBirdBody((body, birdData) ->
            (body |> Node2D.setRotation(-1.0) |> RigidBody2D.setAngularVelocity(-3.0), birdData))
        |> runBirdPhysicsProcess;
    match Scene.getEngineNode("bird" :: Nil, scene) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            let rot = Node2D.getRotation(body);
            let expected = -30.0 * Vec2.pi() / 180.0;
            let rotMatches = Float64.abs(rot - expected) < 0.001;
            let angVelReset = RigidBody2D.getAngularVelocity(body) == 0.0;
            Assert.assertEq(expected = (true, true), (rotMatches, angVelReset))
        case _ => bug!("bird not found")
    }

/// 落下中（vel.y > 0）は角速度が 1.5 に固定される
@Test
def testClampRotationFallAngularVelocity(): Unit \ {Assert, Fs.FileRead} =
    let scene = testScene()
        |> BirdScene.mapBirdBody((body, birdData) ->
            (body |> Node2D.setRotation(0.0)
                  |> RigidBody2D.setAngularVelocity(0.5)
                  |> RigidBody2D.setLinearVelocity({x = 100.0, y = 50.0}),
             birdData))
        |> runBirdPhysicsProcess;
    match Scene.getEngineNode("bird" :: Nil, scene) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            Assert.assertEq(expected = 1.5, RigidBody2D.getAngularVelocity(body))
        case _ => bug!("bird not found")
    }

/// 上昇中（vel.y <= 0）は角速度が保持される
@Test
def testClampRotationKeepsAngularVelocityWhenRising(): Unit \ {Assert, Fs.FileRead} =
    let scene = testScene()
        |> BirdScene.mapBirdBody((body, birdData) ->
            (body |> Node2D.setRotation(0.0)
                  |> RigidBody2D.setAngularVelocity(-3.0)
                  |> RigidBody2D.setLinearVelocity({x = 100.0, y = -150.0}),
             birdData))
        |> runBirdPhysicsProcess;
    match Scene.getEngineNode("bird" :: Nil, scene) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            Assert.assertEq(expected = -3.0, RigidBody2D.getAngularVelocity(body))
        case _ => bug!("bird not found")
    }

// ========================================================================
// Y クランプ: 画面上端で鳥が止まる（本家 Flappy Bird 準拠の独自追加）
// ========================================================================

/// Y < 0 + 上向き速度時：位置を 0 にクランプし上向き速度をゼロ化、横速度は保持される
@Test
def testFlappingClampsCeilingFromAbove(): Unit \ {Assert, Fs.FileRead} =
    let scene = testScene()
        |> BirdScene.mapBirdBody((body, birdData) ->
            (body |> Node2D.setPosition({x = 144.0, y = -20.0})
                  |> RigidBody2D.setLinearVelocity({x = 100.0, y = -300.0}),
             birdData))
        |> runBirdPhysicsProcess;
    match Scene.getEngineNode("bird" :: Nil, scene) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            let pos = Node2D.getPosition(body);
            let vel = RigidBody2D.getLinearVelocity(body);
            Assert.assertEq(
                expected = (0.0, 0.0, 100.0),
                (pos#y, vel#y, vel#x))
        case _ => bug!("bird not found")
    }

/// Y < 0 でも下向き速度（vel.y > 0）は保持される（上向きのみゼロ化）
@Test
def testFlappingClampsCeilingKeepsDownwardVelocity(): Unit \ {Assert, Fs.FileRead} =
    let scene = testScene()
        |> BirdScene.mapBirdBody((body, birdData) ->
            (body |> Node2D.setPosition({x = 144.0, y = -20.0})
                  |> RigidBody2D.setLinearVelocity({x = 100.0, y = 50.0}),
             birdData))
        |> runBirdPhysicsProcess;
    match Scene.getEngineNode("bird" :: Nil, scene) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            Assert.assertEq(expected = 50.0, RigidBody2D.getLinearVelocity(body)#y)
        case _ => bug!("bird not found")
    }

/// Y >= 0 ならクランプされない（位置・速度ともに保持）
@Test
def testFlappingNoClampWhenBelowCeiling(): Unit \ {Assert, Fs.FileRead} =
    let scene = testScene()
        |> BirdScene.mapBirdBody((body, birdData) ->
            (body |> Node2D.setPosition({x = 144.0, y = 100.0})
                  |> RigidBody2D.setLinearVelocity({x = 100.0, y = -300.0}),
             birdData))
        |> runBirdPhysicsProcess;
    match Scene.getEngineNode("bird" :: Nil, scene) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            Assert.assertEq(
                expected = (100.0, -300.0),
                vecToTuple(RigidBody2D.getLinearVelocity(body)))
        case _ => bug!("bird not found")
    }

// ========================================================================
// 統合: フラップ → 物理積分 → 回転クランプ
// ========================================================================

/// フラップ直後の物理積分＋回転クランプ後、回転はクランプ範囲内、
/// 角速度は負（フラップで設定された -3.0 が保持される）
@Test
def testFlapIntegrateClamp(): Unit \ {Assert, Fs.FileRead} =
    let scene = testScene()
        |> runFlap
        |> PhysicsStep.integrate(0.02, PhysicsStep.defaultGravity())
        |> runBirdPhysicsProcess;
    match Scene.getEngineNode("bird" :: Nil, scene) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            let rot = Node2D.getRotation(body);
            let minRot = -30.0 * Vec2.pi() / 180.0;
            let maxRot = Vec2.pi() / 2.0;
            let inRange = rot >= minRot and rot <= maxRot;
            let angVelNeg = RigidBody2D.getAngularVelocity(body) < 0.0;
            Assert.assertEq(expected = (true, true), (inRange, angVelNeg))
        case _ => bug!("bird not found")
    }

// ========================================================================
// AnimatedSprite2D: フレーム進行
// ========================================================================

/// processAll で鳥のスプライトアニメーションが進行する
/// fps=10, 0.15s 後にフレーム 1（bird_orange_1）に進む
@Test
def testBirdSpriteAnimationAdvances(): Unit \ {Assert, Fs.FileRead} =
    match withMockRandom(() -> withMockRecycle(() -> testScene() |> Scene.processAll(0.15, false)))
        |> Scene.getEngineNode("bird" :: "sprite" :: Nil) {
        case Some(EngineNode.AnimSprite2DWithState(sprite, _)) =>
            Assert.assertEq(expected = "bird_orange_1", AnimatedSprite2D.currentTexture(sprite))
        case _ => bug!("bird sprite not found after process")
    }

// ========================================================================
// 鳥の状態遷移 — handleHit / handleGrounded
// ========================================================================

/// Grounded 状態にすると速度がゼロ・重力無効・state=Grounded になる
@Test
def testHandleGroundedFreezesBird(): Unit \ {Assert, Fs.FileRead} =
    let scene = withMockAudioAndState(() ->
        testScene()
            |> runFlap
            |> BirdScene.handleGrounded);
    match Scene.getEngineNode("bird" :: Nil, scene) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            Assert.assertEq(
                expected = ((0.0, 0.0), 0.0, BirdState.Grounded),
                (vecToTuple(RigidBody2D.getLinearVelocity(body)),
                 RigidBody2D.getGravityScale(body),
                 BirdScene.getBirdData(scene)#state))
        case _ => bug!("bird not found")
    }

/// Flying 状態（Menu）の鳥は Space キー入力を無視し速度ゼロのまま動かない
/// （Flapping 状態だけが flap 動作を実行する分岐ロジック）
@Test
def testFlyingStateIgnoresFlapInput(): Unit \ {Assert, Fs.FileRead} =
    let scene = runFlap(testMenuScene());
    match Scene.getEngineNode("bird" :: Nil, scene) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            Assert.assertEq(
                expected = ((0.0, 0.0), 0.0),
                (vecToTuple(RigidBody2D.getLinearVelocity(body)),
                 RigidBody2D.getAngularVelocity(body)))
        case _ => bug!("bird not found")
    }

/// Hit 状態にすると angular velocity が 2.0 になる（落下回転演出）
@Test
def testHandleHitSetsAngularVelocity(): Unit \ {Assert, Fs.FileRead} =
    let pipePath = PipeScene.topPath(PipeScene.pairName(0));
    let scene = withMockAudioAndState(() ->
        testScene()
            |> BirdScene.handleHit(pipePath));
    match Scene.getEngineNode("bird" :: Nil, scene) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            Assert.assertEq(expected = 2.0, RigidBody2D.getAngularVelocity(body))
        case _ => bug!("bird not found")
    }
