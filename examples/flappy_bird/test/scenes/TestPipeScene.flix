// Tests for PipeScene — パイプの構築・配置・衝突応答・リサイクル
// 共通ヘルパーは TestGame.flix を参照

// ========================================================================
// 難易度カーブ: gapSpriteOffset
// ========================================================================

/// 縦ギャップは score=0 で広く（offset=250）、score≥10 で狭く（offset=202）に固定。
/// 1〜9 は線形補間で徐々に狭まる。
///   score=0  → 250        （初心者向け）
///   score=5  → 226        （境界の中央: 250 + (202-250)×0.5 = 226）
///   score=10 → 202        （通常難易度の境界）
///   score=20 → 202        （≥10 で頭打ち）
@Test
def testPipeGapSpriteOffsetCurve(): Unit \ Assert =
    Assert.assertEq(
        expected = (250.0, 226.0, 202.0, 202.0),
        (PipeScene.gapSpriteOffset(0),
         PipeScene.gapSpriteOffset(5),
         PipeScene.gapSpriteOffset(10),
         PipeScene.gapSpriteOffset(20)))

// ========================================================================
// パイプの構造
// ========================================================================

/// パイプペアの bottom 子ノードは StaticBody2D + PipePart タグ + monitorable=true
@Test
def testPipeIsMonitorableStaticBody(): Unit \ {Assert, Fs.FileRead} =
    let pair0 = PipeScene.pairName(0);
    match Scene.getEngineNode(PipeScene.bottomPath(pair0), testScene()) {
        case Some(EngineNode.StaticBody2DWithState(body, NodeTag.PipePart)) =>
            Assert.assertTrue(CollisionObject2D.isMonitorable(body))
        case _ => bug!("Expected StaticBody2DWithState with PipePart tag")
    }

// ========================================================================
// パイプの配置（mock random=0.5 → gapY=200.0、score=0 → easyOffset=250）
// ========================================================================

/// 3 ペアの bottom 位置と最初のペアの top 位置
///   gapY = 110 + (290-110) × 0.5 = 200, easyOffset = 250
///   bottom_0: (576, 450), bottom_1: (758, 450), bottom_2: (940, 450)
///   top_0:    (576, -50)   ← 上下 250px ずつ離れる
///   X 間隔は pipeSpacingX = 182
@Test
def testPipeInitialPositions(): Unit \ {Assert, Fs.FileRead} =
    let scene = testScene();
    let bottomOf = i -> vecToTuple(Scene.globalPositionAt(PipeScene.bottomPath(PipeScene.pairName(i)), scene));
    let top0 = vecToTuple(Scene.globalPositionAt(PipeScene.topPath(PipeScene.pairName(0)), scene));
    Assert.assertEq(
        expected = ((576.0, 450.0), (758.0, 450.0), (940.0, 450.0), (576.0, -50.0)),
        (bottomOf(0), bottomOf(1), bottomOf(2), top0))

// ========================================================================
// spawnPipePairAt（テスト用 API）
// ========================================================================

/// spawnPipePairAt で指定位置（gapY=200）にペアが配置される
///   normalSpriteOffset=202 → top=(400, -2), bottom=(400, 402)
@Test
def testSpawnPipePairAt(): Unit \ Assert =
    let scene = Scene.empty()
        |> PipeScene.spawnPipePairAt(0, 400.0, 200.0);
    let pair0 = PipeScene.pairName(0);
    let topPos = Scene.globalPositionAt(PipeScene.topPath(pair0), scene);
    let bottomPos = Scene.globalPositionAt(PipeScene.bottomPath(pair0), scene);
    Assert.assertEq(expected = ((400.0, -2.0), (400.0, 402.0)),
        (vecToTuple(topPos), vecToTuple(bottomPos)))

// ========================================================================
// パイプ衝突応答
// ========================================================================

/// Flapping → Hit 遷移時に当該パイプが鳥の collisionExceptions に登録される
/// （bird.gd HitState._init `add_collision_exception_with(other_body)` 相当）
@Test
def testBirdPipeCollisionFlappingToHit(): Unit \ {Assert, Fs.FileRead} =
    let pipePath = PipeScene.topPath(PipeScene.pairName(0));
    let scene = withMockAudioAndState(() -> BirdScene.onBirdHitPipe(pipePath = pipePath, testScene()));
    match Scene.getEngineNode("bird" :: Nil, scene) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            Assert.assertEq(
                expected = (BirdState.Hit, true),
                (BirdScene.getBirdData(scene)#state,
                 RigidBody2D.hasCollisionException(pipePath, body)))
        case _ => bug!("bird not found")
    }

/// Hit 状態で同じパイプ（exception 登録済）と再衝突しても状態は変わらない
@Test
def testBirdPipeCollisionHitNoChange(): Unit \ {Assert, Fs.FileRead} =
    let pipePath = PipeScene.topPath(PipeScene.pairName(0));
    let scene = withMockAudioAndState(() ->
        testScene()
            |> BirdScene.handleHit(pipePath)
            |> BirdScene.onBirdHitPipe(pipePath = pipePath));
    Assert.assertEq(expected = BirdState.Hit, BirdScene.getBirdData(scene)#state)

/// Hit 状態で別パイプ（exception 未登録）に衝突したら Grounded に遷移する
/// （パイプの上に着地して回り続ける現象の防止）
@Test
def testBirdPipeCollisionHitToGroundedOnDifferentPipe(): Unit \ {Assert, Fs.FileRead} =
    let hitPipePath = PipeScene.topPath(PipeScene.pairName(0));
    let landedPipePath = PipeScene.bottomPath(PipeScene.pairName(1));
    let scene = withMockAudioAndState(() ->
        testScene()
            |> BirdScene.handleHit(hitPipePath)
            |> BirdScene.onBirdHitPipe(pipePath = landedPipePath));
    Assert.assertEq(expected = BirdState.Grounded, BirdScene.getBirdData(scene)#state)

/// Grounded 状態でパイプ衝突しても状態は変わらない
@Test
def testBirdPipeCollisionGroundedNoChange(): Unit \ {Assert, Fs.FileRead} =
    let pipePath = PipeScene.topPath(PipeScene.pairName(0));
    let scene = withMockAudioAndState(() ->
        testScene()
            |> BirdScene.handleGrounded
            |> BirdScene.onBirdHitPipe(pipePath = pipePath));
    Assert.assertEq(expected = BirdState.Grounded, BirdScene.getBirdData(scene)#state)

// ========================================================================
// パイプリサイクル（NodeRemovedHandler 経由）
// ========================================================================

/// パイプペアが画面外になると process で親ごとリサイクルされる
/// 自殺主体は親 Marker2D（NodeTag.Pipe）。サブツリー削除で top/bottom/coin がまとめて消える
@Test
def testPipeRecyclesWhenOffScreen(): Unit \ {Assert, Fs.FileRead} =
    let pair0 = PipeScene.pairName(0);
    let result = withMockRandom(() -> withMockRecycle(() -> {
        let initial = testScene();
        // bird を pipe_0(x=576) より遠く（x=2000）に移動 → camera 追従後 viewportLeftX=1928
        let movedBird = Scene.setGlobalPositionAt("bird" :: Nil,
            {x = 2000.0, y = 200.0}, initial);
        Scene.processAll(0.016, false, movedBird)
    }));
    let pairCount = List.length(Scene.getNodesInGroup(PipeScene.pipeGroup(), result));
    let pair0Removed = Option.isEmpty(Scene.getEngineNode(pair0 :: Nil, result));
    // pipe_0 は削除され、新 pair が spawn されているのでペア数 3 維持
    Assert.assertEq(expected = (3, true), (pairCount, pair0Removed))

/// コインを通過した（NodeTag.NoTag になった）後でも、pipe ペアが
/// 画面外になればリサイクルされる
/// 再発防止: 自殺判定を Coin に置くと NoTag 化により発動しなくなるため、親 Pipe を主体とする
@Test
def testPipeRecyclesAfterCoinPassed(): Unit \ {Assert, Fs.FileRead} =
    let pair0 = PipeScene.pairName(0);
    let result = withMockRandom(() -> withMockRecycle(() -> {
        let initial = testScene();
        // pipe_0 のコインを通過済み（NoTag）にする
        let afterPass = Scene.setState(PipeScene.coinPath(pair0), NodeTag.NoTag, initial);
        // bird を pipe_0 より遠くに移動 → pipe_0 が画面外
        let movedBird = Scene.setGlobalPositionAt("bird" :: Nil,
            {x = 2000.0, y = 200.0}, afterPass);
        Scene.processAll(0.016, false, movedBird)
    }));
    let pairCount = List.length(Scene.getNodesInGroup(PipeScene.pipeGroup(), result));
    let pair0Removed = Option.isEmpty(Scene.getEngineNode(pair0 :: Nil, result));
    Assert.assertEq(expected = (3, true), (pairCount, pair0Removed))
