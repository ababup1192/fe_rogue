// Tests for CameraScene — カメラ追従設定とビューポートオフセット
// 共通ヘルパーは TestGame.flix を参照

// ========================================================================
// カメラの初期構築
// ========================================================================

/// カメラの初期状態（enabled / anchor / offset / position）
///   addCamera は鳥の初期 X (144) に配置、FixedTopLeft、offset=(-72, 0) で有効化される
@Test
def testCameraInitialState(): Unit \ {Assert, Fs.FileRead} =
    match Scene.getEngineNode("camera" :: Nil, testScene()) {
        case Some(EngineNode.Camera2DWithState(cam, _)) =>
            Assert.assertEq(
                expected = (true, Camera2DAnchorMode.FixedTopLeft, (-72.0, 0.0), (144.0, 0.0)),
                (Camera2D.isEnabled(cam),
                 Camera2D.getAnchorMode(cam),
                 vecToTuple(Camera2D.getOffset(cam)),
                 vecToTuple(Node2D.getPosition(cam))))
        case _ => bug!("camera not found")
    }

// ========================================================================
// Camera2D ビューポートオフセット（CameraScene が依存する挙動）
// ========================================================================

/// AnchorMode を設定すると Camera2D.getAnchorMode が新しい値を返す。
/// 旧テスト (testCameraViewportOffsetByAnchorMode) は engine から
/// Camera2D.getViewportOffset(cam, viewport) が削除されたため、
/// アンカー設定のラウンドトリップ確認に縮約した。
@Test
def testCameraAnchorModeSetGet(): Unit \ Assert =
    let fixedCam = Camera2D.makeWithOffset({x = 200.0, y = 0.0}, {x = -72.0, y = 0.0})
        |> Camera2D.setAnchorMode(Camera2DAnchorMode.FixedTopLeft);
    let dragCam = Camera2D.make({x = 200.0, y = 256.0});
    Assert.assertEq(
        expected = (Camera2DAnchorMode.FixedTopLeft, Camera2DAnchorMode.DragCenter),
        (Camera2D.getAnchorMode(fixedCam),
         Camera2D.getAnchorMode(dragCam)))

// ========================================================================
// 追従: process が target の X 座標に合わせる
// ========================================================================

/// テストヘルパー: camera ノードに process を 1 回適用する
def runCameraProcess(delta: Float64, scene: Scene[NodeTag]): Scene[NodeTag] =
    match Scene.getEngineNode("camera" :: Nil, scene) {
        case Some(camNode) =>
            let (newCam, newScene) = CameraScene.process(Duration.seconds(delta), camNode, scene);
            Scene.setEngineNode("camera" :: Nil, newCam, newScene)
        case None => bug!("camera not found")
    }

/// テストヘルパー: camera の (position.x, shake.remaining, shake.intensity) を取り出す
def cameraStateOf(scene: Scene[NodeTag]): (Float64, Float64, Float64) =
    match (Scene.getEngineNode("camera" :: Nil, scene),
           Scene.getState("camera" :: Nil, scene)) {
        case (Some(EngineNode.Camera2DWithState(cam, _)), Some(NodeTag.Camera(data))) =>
            (Node2D.getPosition(cam)#x, data#shake#shakeRemaining, data#shake#shakeIntensity)
        case _ => bug!("camera not found")
    }

/// process は target（鳥）の X 位置にカメラを追従させる
@Test
def testCameraFollowsTargetX(): Unit \ {Assert, Fs.FileRead} =
    let scene = testScene()
        |> BirdScene.mapBirdBody((body, birdData) ->
            (Node2D.setPosition({x = 800.0, y = 200.0}, body), birdData))
        |> runCameraProcess(0.016);
    let (camX, _, _) = cameraStateOf(scene);
    Assert.assertEq(expected = 800.0, camX)

// ========================================================================
// シェイク: triggerShake → process でオフセット消費・強度減衰
// ========================================================================

/// triggerShake はシェイクを発火し、process が 1 フレーム消費すると
/// shakeRemaining が delta ぶん減り、intensity は 0.9 倍に減衰する
///
///   triggerShake(intensity=3.0, duration=0.18)
///   → frame0: remaining=0.18, intensity=3.0
///   process(delta=0.016)
///   → frame1: remaining ≈ 0.18 - 0.016 = 0.164, intensity = 3.0 × 0.9 = 2.7
@Test
def testCameraShakeDecaysOnProcess(): Unit \ {Assert, Fs.FileRead} =
    let triggered = withMockRandom(() ->
        testScene() |> CameraScene.triggerShake(3.0, 0.18));
    let advanced = runCameraProcess(0.016, triggered);
    let (_, remainingBefore, intensityBefore) = cameraStateOf(triggered);
    let (_, remainingAfter, intensityAfter) = cameraStateOf(advanced);
    let near = (a, b) -> Float64.abs(a - b) < 0.001;
    Assert.assertEq(
        expected = (true, 3.0, true, 2.7),
        (near(remainingBefore, 0.18),
         intensityBefore,
         near(remainingAfter,  0.164),
         intensityAfter))

/// シェイクが残り時間を使い切ったら基準オフセットに戻り、状態も非アクティブに固まる
///   shakeDuration を超える delta を 1 度に与えると残り時間 ≤ 0 で消化
@Test
def testCameraShakeStopsWhenRemainingExpires(): Unit \ {Assert, Fs.FileRead} =
    let triggered = withMockRandom(() ->
        testScene() |> CameraScene.triggerShake(3.0, 0.18));
    // 0.5 秒 → 0.18 を超えて消化
    let expired = runCameraProcess(0.5, triggered);
    // 続けて 0.016 進めても remaining はマイナス側で停滞しない（≤ 0 ブランチ）
    let stable = runCameraProcess(0.016, expired);
    let cameraOffsetOf = scene -> match Scene.getEngineNode("camera" :: Nil, scene) {
        case Some(EngineNode.Camera2DWithState(cam, _)) => vecToTuple(Camera2D.getOffset(cam))
        case _ => bug!("camera not found")
    };
    // 期限切れ後は基準オフセット (-72, 0) に戻る
    Assert.assertEq(
        expected = ((-72.0, 0.0), (-72.0, 0.0)),
        (cameraOffsetOf(expired), cameraOffsetOf(stable)))
