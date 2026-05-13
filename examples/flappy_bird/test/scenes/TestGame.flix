// Tests for Flappy Bird Game module — シーン全体の構造と共通ヘルパー

// ========================================================================
// 共通ヘルパー（同ディレクトリの TestXxxScene.flix 群と共有）
// ========================================================================

/// Math.Random のモックハンドラ（randomFloat64 → 0.5）
/// effect 多相にしてあるので body に他の effect が混ざっても通る
def withMockRandom(f: Unit -> a \ ef + Math.Random): a \ ef =
    run f() with handler Math.Random {
        def randomFloat64(k) = k(0.5)
        def randomInt64(k) = k(42i64)
    }

/// Recycle のモックハンドラ。実 spawn 関数に委譲する（内部で Math.Random を使う）
/// 単独では使えないので呼び出し元で必ず withMockRandom と組み合わせること
def withMockRecycle(f: Unit -> a \ ef + Recycle): a \ ef + Math.Random =
    run f() with handler Recycle {
        def ground(scene, k) = k(GroundScene.spawnRecycledGround(scene))
        def pipe(scene, k) =
            k(PipeScene.spawnRecycledPair(ScoreScene.getScore(scene), scene))
    }

/// GameEngine.Audio のモックハンドラ（playAudio/stopAudio は no-op）。
/// 他のエフェクト（Fs.FileRead など）は呼び出し元へ伝播する
def withMockAudio(f: Unit -> a \ ef + GameEngine.Audio): a \ ef =
    run f() with handler GameEngine.Audio {
        def playAudio(_, k) = k(())
        def stopAudio(_, k) = k(())
    }

/// GameEngine.Audio + BirdStateChanged のモックハンドラ
/// handleHit / handleGrounded を経由するテスト用。BirdStateChanged は scene をそのまま返す（shake 無効）。
/// 他のエフェクト（Fs.FileRead など）は呼び出し元へ伝播する
def withMockAudioAndState(f: Unit -> a \ ef + GameEngine.Audio + BirdStateChanged): a \ ef =
    run {
        f()
    } with handler GameEngine.Audio {
        def playAudio(_, k) = k(())
        def stopAudio(_, k) = k(())
    } with handler BirdStateChanged {
        def emit(_, scene, k) = k(scene)
    }

/// テスト用のダミー FontAtlas（空のグリフマップ）
def testFontAtlas(): FontAtlas = {
    textureName = "font_test",
    fontSize = 32.0,
    textureSize = 512.0,
    ascent = 0.0,
    descent = 0.0,
    lineGap = 0.0,
    glyphs = Map.empty()
}

/// buildPlayingScene のシーンを取得（Math.Random をモックで処理）。
/// GroundScene.scene.json などを読み込むため Fs.FileRead を伴う
def testScene(): Scene[NodeTag] \ Fs.FileRead =
    withMockRandom(() -> Game.buildPlayingScene(testFontAtlas(), 0))

/// buildMenuScene のシーンを取得（MenuScene.scene.json を読み込むため Fs.FileRead を伴う）
def testMenuScene(): Scene[NodeTag] \ Fs.FileRead =
    Game.buildMenuScene(testFontAtlas(), 0)

/// Vec2 をタプルに変換するヘルパー
def vecToTuple(v: Vec2.Vec2): (Float64, Float64) = (v#x, v#y)

/// 鳥のノードに BirdScene.physicsProcess を適用するテストヘルパー
/// （旧 BirdScene.clampRotation の代替: physicsProcess は Flapping 状態のみ動作）
def runBirdPhysicsProcess(scene: Scene[NodeTag]): Scene[NodeTag] =
    match Scene.getEngineNode("bird" :: Nil, scene) {
        case Some(node) =>
            let (newNode, newScene) = BirdScene.physicsProcess(0.0, node, "bird" :: Nil, scene);
            Scene.setEngineNode("bird" :: Nil, newNode, newScene)
        case None => bug!("bird not found")
    }

/// 鳥に Space キー入力経由で flap を発火させるテストヘルパー
def runFlap(scene: Scene[NodeTag]): Scene[NodeTag] =
    withMockAudio(() -> BirdScene.input(BirdInputEvent.KeyPressed(GameEngine.Key.Space), scene))

// ========================================================================
// buildPlayingScene: シーン全体構造
// ========================================================================

/// シーン全体の構造（合計ノード 31 / ルート 9 / ground 2 / pipe 3）
///   bird(+sprite+area) + camera + background(+bg_sprite)
///   + hud(+score_label+best_score_label)
///   + ground × 2 (+sprite) + pipe × 3 (Marker2D 親 + top(+sprite) + bottom(+sprite) + coin)
///   = 31 ノード、ルート 9 個
@Test
def testBuildSceneStructure(): Unit \ {Assert, Fs.FileRead} =
    let scene = testScene();
    Assert.assertEq(
        expected = (31, 9, 2, 3),
        (Scene.nodeCount(scene),
         Map.size(Scene.states(scene)),
         List.length(Scene.getNodesInGroup(GroundScene.groundGroup(), scene)),
         List.length(Scene.getNodesInGroup(PipeScene.pipeGroup(), scene))))

// ========================================================================
// 背景
// ========================================================================

/// 背景は CanvasLayer（drawLayer=-1）として構築される
@Test
def testBackgroundIsCanvasLayer(): Unit \ {Assert, Fs.FileRead} =
    match Scene.getEngineNode("background" :: Nil, testScene()) {
        case Some(EngineNode.CanvasLayerWithState(cl, _)) =>
            Assert.assertEq(expected = -1, CanvasLayer.getDrawLayer(cl))
        case _ => bug!("background not found")
    }
