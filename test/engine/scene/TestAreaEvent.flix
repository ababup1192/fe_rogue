// Tests for AreaEvent module

/// テスト用ヘルパー: 矩形 Area2D を EngineNode[Unit] として作る
def rectAreaNode(x: Float64, y: Float64, w: Float64, h: Float64): EngineNode[Unit] =
    EngineNode.Area2DWithState(Area2D.make({x = x, y = y}, CollisionShape2D.RectShape2D({width = w, height = h})), ())

/// テスト用ヘルパー: 矩形 Area2D の EngineNode[Unit] を設定付きで作る
def rectAreaNodeWith(x: Float64, y: Float64, w: Float64, h: Float64,
                     monitoring: Bool, monitorable: Bool): EngineNode[Unit] =
    EngineNode.Area2DWithState(
        Area2D.make({x = x, y = y}, CollisionShape2D.RectShape2D({width = w, height = h}))
            |> Area2D.setMonitoring(monitoring)
            |> Area2D.setMonitorable(monitorable), ())

/// テスト用ヘルパー: 衝突形状なしの Area2D EngineNode[Unit] を作る
def noShapeAreaNode(x: Float64, y: Float64): EngineNode[Unit] =
    EngineNode.Area2DWithState(
        Area2D.make({x = x, y = y}, CollisionShape2D.RectShape2D({width = 10.0, height = 10.0}))
            |> Area2D.setCollisionShape(None), ())

/// テスト用ヘルパー: detectOverlaps の結果を有向 (selfPath, otherPath) Set として取り出す
def detectedPairs(scene: Scene[Unit]): Set[(NodePath, NodePath)] =
    AreaEvent.toOverlapPairSet(AreaEvent.detectOverlaps(scene))

// ── AreaHandler ディスパッチテスト用の状態型 ──

enum TestAreaState with Eq {
    case RedState
    case BlueState
}

instance Node[TestAreaState] {
    type Aef = {}
}

/// テスト用ヘルパー: TestAreaState 用の矩形 Area2D EngineNode を作る
def testStateAreaNode(x: Float64, y: Float64, w: Float64, h: Float64, state: TestAreaState): EngineNode[TestAreaState] =
    EngineNode.Area2DWithState(Area2D.make({x = x, y = y}, CollisionShape2D.RectShape2D({width = w, height = h})), state)

instance AreaEvent.AreaHandler[TestAreaState] {
    type Aef = {}
    pub def onAreaEntered(selfPath: NodePath, selfState: TestAreaState,
                          _otherPath: NodePath, otherState: TestAreaState,
                          scene: Scene[TestAreaState]): Scene[TestAreaState] =
        match (selfState, otherState) {
            case (TestAreaState.RedState, TestAreaState.BlueState) =>
                Scene.mapEngineNode(selfPath, engineNode ->
                    CanvasItem.setModulate({r = 1.0f32, g = 0.0f32, b = 0.0f32}, engineNode), scene)
            case _ => scene
        }
    redef onAreaExited(selfPath: NodePath, selfState: TestAreaState,
                       _otherPath: NodePath, otherState: TestAreaState,
                       scene: Scene[TestAreaState]): Scene[TestAreaState] =
        match (selfState, otherState) {
            case (TestAreaState.RedState, TestAreaState.BlueState) =>
                Scene.mapEngineNode(selfPath, engineNode ->
                    CanvasItem.setModulate({r = 1.0f32, g = 1.0f32, b = 1.0f32}, engineNode), scene)
            case _ => scene
        }
}

instance Node[Unit] {
    type Aef = {}
}

// ========================================================================
// detectOverlaps: 検出ペアの内容（length ではなく実際のペア集合を確認）
// ========================================================================

/// 重なる 2 ペアからは双方向の (a→b, b→a) が検出される
@Test
def testDetectOverlapsTwoOverlapping(): Unit \ Assert =
    let scene: Scene[Unit] = Scene.empty()
        |> Scene.addNode("a", rectAreaNode(0.0, 0.0, 10.0, 10.0))
        |> Scene.addNode("b", rectAreaNode(5.0, 0.0, 10.0, 10.0));
    Assert.assertEq(
        expected = Set#{("a" :: Nil, "b" :: Nil), ("b" :: Nil, "a" :: Nil)},
        detectedPairs(scene))

/// 「検出ゼロ」になる 3 つのケース:
///   - 離れている / 衝突形状なし / 両方 monitoring=false かつ monitorable=false
@Test
def testDetectOverlapsNoOverlapCases(): Unit \ Assert =
    let separated: Scene[Unit] = Scene.empty()
        |> Scene.addNode("a", rectAreaNode(0.0, 0.0, 4.0, 4.0))
        |> Scene.addNode("b", rectAreaNode(100.0, 100.0, 4.0, 4.0));
    let noShape: Scene[Unit] = Scene.empty()
        |> Scene.addNode("a", rectAreaNode(0.0, 0.0, 10.0, 10.0))
        |> Scene.addNode("b", noShapeAreaNode(5.0, 0.0));
    let bothFlagsOff: Scene[Unit] = Scene.empty()
        |> Scene.addNode("a", rectAreaNodeWith(0.0, 0.0, 10.0, 10.0, false, false))
        |> Scene.addNode("b", rectAreaNodeWith(5.0, 0.0, 10.0, 10.0, false, false));
    let empty: Set[(NodePath, NodePath)] = Set.empty();
    Assert.assertEq(
        expected = (empty, empty, empty),
        (detectedPairs(separated), detectedPairs(noShape), detectedPairs(bothFlagsOff)))

/// monitoring / monitorable フラグの組合せで方向が決まる
///   selfPath は「監視している側」。a→b は a.monitoring=true かつ b.monitorable=true で発生する。
///
///   - a.monitoring=false  : a は何も見ない → b→a のみ（b が a を見る）
///   - a.monitorable=false : a は見られない → a→b のみ（a が b を見るが b には見えない）
@Test
def testDetectOverlapsAsymmetricFlags(): Unit \ Assert =
    let aMonitoringOff: Scene[Unit] = Scene.empty()
        |> Scene.addNode("a", rectAreaNodeWith(0.0, 0.0, 10.0, 10.0, false, true))
        |> Scene.addNode("b", rectAreaNode(5.0, 0.0, 10.0, 10.0));
    let aMonitorableOff: Scene[Unit] = Scene.empty()
        |> Scene.addNode("a", rectAreaNodeWith(0.0, 0.0, 10.0, 10.0, true, false))
        |> Scene.addNode("b", rectAreaNode(5.0, 0.0, 10.0, 10.0));
    Assert.assertEq(
        expected = (Set#{("b" :: Nil, "a" :: Nil)},
                    Set#{("a" :: Nil, "b" :: Nil)}),
        (detectedPairs(aMonitoringOff), detectedPairs(aMonitorableOff)))

/// 3 ノード a/b/c が互いに重なる場合、3 ペア × 2 方向 = 6 件が a-b, a-c, b-c を網羅
@Test
def testDetectOverlapsThreeNodes(): Unit \ Assert =
    let scene: Scene[Unit] = Scene.empty()
        |> Scene.addNode("a", rectAreaNode(0.0, 0.0, 10.0, 10.0))
        |> Scene.addNode("b", rectAreaNode(5.0, 0.0, 10.0, 10.0))
        |> Scene.addNode("c", rectAreaNode(3.0, 0.0, 4.0, 4.0));
    let a = "a" :: Nil; let b = "b" :: Nil; let c = "c" :: Nil;
    Assert.assertEq(
        expected = Set#{(a, b), (b, a), (a, c), (c, a), (b, c), (c, b)},
        detectedPairs(scene))

/// 親子配置でも globalPosition で重なりが判定される
///   parent(100, 0) > child(local 0, 0) の child global = (100, 0)
///   other(101, 0) と child は重なる
@Test
def testDetectOverlapsWithParentChild(): Unit \ Assert =
    let scene: Scene[Unit] = Scene.empty()
        |> Scene.addNode("parent", rectAreaNode(100.0, 0.0, 4.0, 4.0))
        |> Scene.addChild("parent", "child", rectAreaNode(0.0, 0.0, 4.0, 4.0))
        |> Scene.addNode("other", rectAreaNode(101.0, 0.0, 4.0, 4.0));
    let childPath = "parent" :: "child" :: Nil;
    let otherPath = "other" :: Nil;
    Assert.assertTrue(Set.memberOf((childPath, otherPath), detectedPairs(scene)))

// ========================================================================
// handleOverlaps: AreaHandler ディスパッチ
// ========================================================================

/// RedState ↔ BlueState の重なりで onAreaEntered が走り Red 側の modulate が赤になる。
/// Blue 側 / 同種同士 (Red↔Red) / 重なりなし では何も発火せず modulate は白のまま。
@Test
def testHandleOverlapsDispatch(): Unit \ Assert =
    let redBlueOverlap: Scene[TestAreaState] = Scene.empty()
        |> Scene.addNode("red", testStateAreaNode(0.0, 0.0, 10.0, 10.0, TestAreaState.RedState))
        |> Scene.addNode("blue", testStateAreaNode(5.0, 0.0, 10.0, 10.0, TestAreaState.BlueState));
    let redRedOverlap: Scene[TestAreaState] = Scene.empty()
        |> Scene.addNode("r1", testStateAreaNode(0.0, 0.0, 10.0, 10.0, TestAreaState.RedState))
        |> Scene.addNode("r2", testStateAreaNode(5.0, 0.0, 10.0, 10.0, TestAreaState.RedState));
    let separated: Scene[TestAreaState] = Scene.empty()
        |> Scene.addNode("red", testStateAreaNode(0.0, 0.0, 4.0, 4.0, TestAreaState.RedState))
        |> Scene.addNode("blue", testStateAreaNode(100.0, 0.0, 4.0, 4.0, TestAreaState.BlueState));
    let modulateOf = (path, scene) -> match Scene.getEngineNode(path, scene) {
        case Some(engineNode) =>
            let c = CanvasItem.getModulate(engineNode);
            (c#r, c#g, c#b)
        case None => bug!("node missing")
    };
    let red = modulateOf("red" :: Nil,
        (Scene.processAll(0.016, false, redBlueOverlap) |> AreaEvent.handleOverlaps));
    let blue = modulateOf("blue" :: Nil,
        (Scene.processAll(0.016, false, redBlueOverlap) |> AreaEvent.handleOverlaps));
    let r1 = modulateOf("r1" :: Nil,
        (Scene.processAll(0.016, false, redRedOverlap) |> AreaEvent.handleOverlaps));
    let separatedRed = modulateOf("red" :: Nil,
        (Scene.processAll(0.016, false, separated) |> AreaEvent.handleOverlaps));
    let white = (1.0f32, 1.0f32, 1.0f32);
    let red_ = (1.0f32, 0.0f32, 0.0f32);
    Assert.assertEq(
        expected = (red_, white, white, white),
        (red, blue, r1, separatedRed))

// ========================================================================
// onAreaExited: 重なりが切れた時の発火
// ========================================================================

/// 前フレームで重なっていたペアが離れると onAreaExited が走り modulate が白に戻り、
/// prevOverlaps セットも空になる
///
///  フレーム1:  [red]<--重なり-->[blue]   → 赤くなる
///  フレーム2:  [red]          [blue]    → 離脱 → modulate 白に戻る
@Test
def testHandleOverlapsFiresExitOnSeparation(): Unit \ Assert =
    let scene: Scene[TestAreaState] = Scene.empty()
        |> Scene.addNode("red", testStateAreaNode(0.0, 0.0, 10.0, 10.0, TestAreaState.RedState))
        |> Scene.addNode("blue", testStateAreaNode(5.0, 0.0, 10.0, 10.0, TestAreaState.BlueState));
    let sceneAfterEnter = Scene.processAll(0.016, false, scene) |> AreaEvent.handleOverlaps;
    let separatedScene: Scene[TestAreaState] = Scene.empty()
        |> Scene.addNode("red", testStateAreaNode(0.0, 0.0, 4.0, 4.0, TestAreaState.RedState))
        |> Scene.addNode("blue", testStateAreaNode(100.0, 0.0, 4.0, 4.0, TestAreaState.BlueState))
        |> Scene.setPrevOverlaps(Scene.getPrevOverlaps(sceneAfterEnter));
    let result = Scene.processAll(0.016, false, separatedScene) |> AreaEvent.handleOverlaps;
    let modulate = match Scene.getEngineNode("red" :: Nil, result) {
        case Some(engineNode) =>
            let c = CanvasItem.getModulate(engineNode);
            (c#r, c#g, c#b)
        case None => bug!("red node missing")
    };
    Assert.assertEq(
        expected = (0, (1.0f32, 1.0f32, 1.0f32)),
        (Set.size(Scene.getPrevOverlaps(result)), modulate))
