// Tests for Scene module
//
// テスト用の軽量状態型 TState を定義して使用する。
// 位置情報は EngineNode (Marker2D) が保持し、TState は追加データなしのタグ。

/// テスト用状態: 追加データなしの最小構成
enum TState with Eq, Order, ToString {
    case TState
}

instance Node[TState] {
    type Aef = {}
}

/// テスト用ヘルパー: 指定位置に Marker2D ノードを持つ EngineNode[TState] を作る
def tmarker(x: Float64, y: Float64): EngineNode[TState] =
    EngineNode.Marker2DWithState(Marker2D.make({x = x, y = y}), TState.TState)

// ========================================================================
// empty
// ========================================================================

/// 空のシーンにはノードがない
@Test
def testSceneEmpty(): Unit \ Assert =
    let scene: Scene[TState] = Scene.empty();
    Assert.assertEq(expected = 0, Scene.states(scene) |> Map.size)

// ========================================================================
// addNode / get
// ========================================================================

/// addNode でルートとして追加し、getState で取得できる
@Test
def testSceneAddNodeAndGet(): Unit \ Assert =
    let scene = Scene.empty()
        |> Scene.addNode("player", tmarker(10.0, 20.0));
    Assert.assertEq(expected = Some(TState.TState), Scene.get("player", scene))

/// 存在しないノードの get は None を返す
@Test
def testSceneGetNone(): Unit \ Assert =
    let scene: Scene[TState] = Scene.empty();
    Assert.assertEq(expected = (None: Option[TState]), Scene.get("missing", scene))

// ========================================================================
// set (状態の更新)
// ========================================================================

/// set でノードの状態を更新できる
@Test
def testSceneSet(): Unit \ Assert =
    let scene = Scene.empty()
        |> Scene.addNode("a", tmarker(0.0, 0.0))
        |> Scene.set("a", TState.TState);
    Assert.assertEq(expected = Some(TState.TState), Scene.get("a", scene))

/// 存在しないノードへの set はシーンを変更しない
@Test
def testSceneSetMissing(): Unit \ Assert =
    let scene: Scene[TState] = Scene.empty()
        |> Scene.set("ghost", TState.TState);
    Assert.assertEq(expected = 0, Scene.states(scene) |> Map.size)

// ========================================================================
// setEngineNode（エンジンノードの更新）
// ========================================================================

/// setEngineNode でエンジンノードを更新し、位置が変わることを確認
@Test
def testSceneSetEngineNode(): Unit \ Assert =
    let scene = Scene.empty()
        |> Scene.addNode("a", tmarker(0.0, 0.0))
        |> Scene.setEngineNode("a" :: Nil, tmarker(99.0, 99.0));
    let gp = Scene.globalPosition("a", scene);
    Assert.assertEq(expected = (99.0, 99.0), (gp#x, gp#y))

// ========================================================================
// remove（ルートノード）
// ========================================================================

/// ルートノードを remove で削除できる
@Test
def testSceneRemoveRoot(): Unit \ Assert =
    let scene = Scene.empty()
        |> Scene.addNode("a", tmarker(0.0, 0.0))
        |> Scene.remove("a");
    Assert.assertEq(expected = (None: Option[TState]), Scene.get("a", scene))

// ========================================================================
// states（ルートノード一覧）
// ========================================================================

/// states はルートノードの状態を Map として返す
@Test
def testSceneStates(): Unit \ Assert =
    let scene = Scene.empty()
        |> Scene.addNode("a", tmarker(1.0, 0.0))
        |> Scene.addNode("b", tmarker(2.0, 0.0));
    Assert.assertEq(expected = 2, Scene.states(scene) |> Map.size)

// ========================================================================
// addChild / getParent / getChildren
// ========================================================================

/// addChild で親子関係を構築し、getParent / getChildren で取得できる
///
///   root
///    └─ child
///
@Test
def testSceneAddChild(): Unit \ Assert =
    let scene = Scene.empty()
        |> Scene.addNode("root", tmarker(0.0, 0.0))
        |> Scene.addChild("root", "child", tmarker(10.0, 0.0));
    let parent = Scene.getParent("root" :: "child" :: Nil, scene);
    let children = Scene.getChildren("root", scene);
    Assert.assertEq(expected = (Some("root" :: Nil), "child" :: Nil), (parent, children))

/// addChild で追加した子ノードを getState で取得できる
@Test
def testSceneAddChildGet(): Unit \ Assert =
    let scene = Scene.empty()
        |> Scene.addNode("root", tmarker(0.0, 0.0))
        |> Scene.addChild("root", "child", tmarker(10.0, 0.0));
    Assert.assertEq(expected = Some(TState.TState), Scene.getState("root" :: "child" :: Nil, scene))

/// 存在しない親への addChild はシーンを変更しない
@Test
def testSceneAddChildMissingParent(): Unit \ Assert =
    let scene: Scene[TState] = Scene.empty()
        |> Scene.addChild("ghost", "child", tmarker(0.0, 0.0));
    Assert.assertEq(expected = 0, Scene.nodeCount(scene))

/// 深い階層の親子関係を構築できる
///
///   root
///    └─ a
///        └─ b
///
@Test
def testSceneDeepHierarchy(): Unit \ Assert =
    let scene = Scene.empty()
        |> Scene.addNode("root", tmarker(0.0, 0.0))
        |> Scene.addChild("root", "a", tmarker(0.0, 0.0))
        |> Scene.addChildAt("root" :: "a" :: Nil, "b", tmarker(0.0, 0.0));
    let parentOfB = Scene.getParent("root" :: "a" :: "b" :: Nil, scene);
    let childrenOfA = Scene.getChildrenAt("root" :: "a" :: Nil, scene);
    Assert.assertEq(expected = (Some("root" :: "a" :: Nil), "b" :: Nil), (parentOfB, childrenOfA))

/// ルートノードの getParent は None を返す
@Test
def testSceneGetParentRoot(): Unit \ Assert =
    let scene = Scene.empty()
        |> Scene.addNode("root", tmarker(0.0, 0.0));
    Assert.assertEq(expected = (None: Option[NodePath]), Scene.getParent("root" :: Nil, scene))

/// 存在しないノードの getChildren は空リストを返す
@Test
def testSceneGetChildrenMissing(): Unit \ Assert =
    let scene: Scene[TState] = Scene.empty();
    Assert.assertEq(expected = (Nil: List[NodeName]), Scene.getChildren("missing", scene))

// ========================================================================
// remove（子ノードの再帰削除）
// ========================================================================

/// 親を削除すると子も再帰的に削除される
///
///   root            (remove "root")
///    └─ a       →   空のシーン
///        └─ b
///
@Test
def testSceneRemoveRecursive(): Unit \ Assert =
    let scene = Scene.empty()
        |> Scene.addNode("root", tmarker(0.0, 0.0))
        |> Scene.addChild("root", "a", tmarker(0.0, 0.0))
        |> Scene.addChildAt("root" :: "a" :: Nil, "b", tmarker(0.0, 0.0))
        |> Scene.remove("root");
    Assert.assertEq(expected = 0, Scene.nodeCount(scene))

/// 中間ノードを削除すると、その子も消え、親の children から除去される
///
///   root              root
///    └─ a     →      (children = [])
///        └─ b
///
@Test
def testSceneRemoveMiddle(): Unit \ Assert =
    let scene = Scene.empty()
        |> Scene.addNode("root", tmarker(0.0, 0.0))
        |> Scene.addChild("root", "a", tmarker(0.0, 0.0))
        |> Scene.addChildAt("root" :: "a" :: Nil, "b", tmarker(0.0, 0.0))
        |> Scene.removeAt("root" :: "a" :: Nil);
    let aExists = Scene.getState("root" :: "a" :: Nil, scene);
    let bExists = Scene.getState("root" :: "a" :: "b" :: Nil, scene);
    let rootChildren = Scene.getChildren("root", scene);
    Assert.assertEq(
        expected = ((None: Option[TState]), (None: Option[TState]), (Nil: List[NodeName])),
        (aExists, bExists, rootChildren)
    )

// ========================================================================
// globalPosition
// ========================================================================

/// ルートノードの globalPosition はローカル座標と同じ
@Test
def testSceneGlobalPositionRoot(): Unit \ Assert =
    let scene = Scene.empty()
        |> Scene.addNode("root", tmarker(100.0, 50.0));
    let gp = Scene.globalPosition("root", scene);
    Assert.assertEq(expected = (100.0, 50.0), (gp#x, gp#y))

/// 親子の position が合算される
///
///   root (100, 100)
///    └─ a (50, 50)     → globalPositionAt("root"::"a"::Nil) = (150, 150)
///        └─ b (10, 10) → globalPositionAt("root"::"a"::"b"::Nil) = (160, 160)
///
@Test
def testSceneGlobalPositionChain(): Unit \ Assert =
    let scene = Scene.empty()
        |> Scene.addNode("root", tmarker(100.0, 100.0))
        |> Scene.addChild("root", "a", tmarker(50.0, 50.0))
        |> Scene.addChildAt("root" :: "a" :: Nil, "b", tmarker(10.0, 10.0));
    let gpA = Scene.globalPositionAt("root" :: "a" :: Nil, scene);
    let gpB = Scene.globalPositionAt("root" :: "a" :: "b" :: Nil, scene);
    Assert.assertEq(
        expected = (150.0, 150.0, 160.0, 160.0),
        (gpA#x, gpA#y, gpB#x, gpB#y)
    )

/// 親を移動すると、子・孫の globalPosition が連動して変わる
@Test
def testSceneMovingParentMovesChildren(): Unit \ Assert =
    let scene = Scene.empty()
        |> Scene.addNode("root", tmarker(100.0, 100.0))
        |> Scene.addChild("root", "a", tmarker(50.0, 50.0))
        |> Scene.addChildAt("root" :: "a" :: Nil, "b", tmarker(10.0, 10.0));
    let beforeA = Scene.globalPositionAt("root" :: "a" :: Nil, scene);
    let beforeB = Scene.globalPositionAt("root" :: "a" :: "b" :: Nil, scene);
    let moved = Scene.setEngineNode("root" :: Nil, tmarker(200.0, 200.0), scene);
    let afterA = Scene.globalPositionAt("root" :: "a" :: Nil, moved);
    let afterB = Scene.globalPositionAt("root" :: "a" :: "b" :: Nil, moved);
    Assert.assertEq(
        expected = (150.0, 150.0, 160.0, 160.0,
                    250.0, 250.0, 260.0, 260.0),
        (beforeA#x, beforeA#y, beforeB#x, beforeB#y,
         afterA#x,  afterA#y,  afterB#x,  afterB#y)
    )

/// 中間ノードを移動すると、その子だけが影響を受け、親は変わらない
@Test
def testSceneMovingMiddleNodeMovesDescendants(): Unit \ Assert =
    let scene = Scene.empty()
        |> Scene.addNode("root", tmarker(100.0, 100.0))
        |> Scene.addChild("root", "a", tmarker(50.0, 50.0))
        |> Scene.addChildAt("root" :: "a" :: Nil, "b", tmarker(10.0, 10.0))
        |> Scene.setEngineNode("root" :: "a" :: Nil, tmarker(200.0, 200.0));
    let gpRoot = Scene.globalPosition("root", scene);
    let gpA = Scene.globalPositionAt("root" :: "a" :: Nil, scene);
    let gpB = Scene.globalPositionAt("root" :: "a" :: "b" :: Nil, scene);
    Assert.assertEq(
        expected = (100.0, 100.0, 300.0, 300.0, 310.0, 310.0),
        (gpRoot#x, gpRoot#y, gpA#x, gpA#y, gpB#x, gpB#y)
    )

/// 存在しないノードの globalPosition は zero を返す
@Test
def testSceneGlobalPositionMissing(): Unit \ Assert =
    let scene: Scene[TState] = Scene.empty();
    let gp = Scene.globalPosition("missing", scene);
    Assert.assertEq(expected = (0.0, 0.0), (gp#x, gp#y))

// ========================================================================
// setGlobalPosition
// ========================================================================

/// setGlobalPosition でグローバル座標を指定すると、ローカル座標が逆算される
@Test
def testSceneSetGlobalPosition(): Unit \ Assert =
    let scene = Scene.empty()
        |> Scene.addNode("root", tmarker(100.0, 0.0))
        |> Scene.addChild("root", "a", tmarker(10.0, 0.0))
        |> Scene.setGlobalPositionAt("root" :: "a" :: Nil, {x = 200.0, y = 0.0});
    let gp = Scene.globalPositionAt("root" :: "a" :: Nil, scene);
    Assert.assertEq(expected = (200.0, 0.0), (gp#x, gp#y))

// ========================================================================
// preorderPaths
// ========================================================================

/// preorder 順でパスが返される（親→子、深さ優先）
///
///   root
///    ├─ a
///    │   └─ a1
///    └─ b
///
@Test
def testScenePreorderPaths(): Unit \ Assert =
    let scene = Scene.empty()
        |> Scene.addNode("root", tmarker(0.0, 0.0))
        |> Scene.addChild("root", "a", tmarker(0.0, 0.0))
        |> Scene.addChildAt("root" :: "a" :: Nil, "a1", tmarker(0.0, 0.0))
        |> Scene.addChild("root", "b", tmarker(0.0, 0.0));
    let paths = Scene.preorderPaths(scene);
    Assert.assertEq(
        expected = ("root" :: Nil) :: ("root" :: "a" :: Nil) :: ("root" :: "a" :: "a1" :: Nil) :: ("root" :: "b" :: Nil) :: Nil,
        paths
    )

/// 複数ルートの場合、roots のキー順で走査される
@Test
def testScenePreorderMultipleRoots(): Unit \ Assert =
    let scene = Scene.empty()
        |> Scene.addNode("x", tmarker(0.0, 0.0))
        |> Scene.addNode("y", tmarker(0.0, 0.0))
        |> Scene.addChild("x", "x1", tmarker(0.0, 0.0));
    let paths = Scene.preorderPaths(scene);
    Assert.assertEq(
        expected = ("x" :: Nil) :: ("x" :: "x1" :: Nil) :: ("y" :: Nil) :: Nil,
        paths
    )

// ========================================================================
// nodeCount
// ========================================================================

/// nodeCount はツリー全体のノード数を返す
@Test
def testSceneNodeCount(): Unit \ Assert =
    let scene = Scene.empty()
        |> Scene.addNode("root", tmarker(0.0, 0.0))
        |> Scene.addChild("root", "a", tmarker(0.0, 0.0))
        |> Scene.addChildAt("root" :: "a" :: Nil, "b", tmarker(0.0, 0.0));
    Assert.assertEq(expected = 3, Scene.nodeCount(scene))

// ========================================================================
// processAll（preorder 順で実行される）
// ========================================================================

/// processAll はエラーなく全ノードを走査できる
@Test
def testSceneProcessAll(): Unit \ Assert =
    let scene = Scene.empty()
            |> Scene.addNode("root", tmarker(0.0, 0.0))
            |> Scene.addChild("root", "a", tmarker(1.0, 0.0))
            |> Scene.processAll(0.016f64, false);
    let gp = Scene.globalPositionAt("root" :: "a" :: Nil, scene);
    Assert.assertEq(expected = (1.0, 0.0), (gp#x, gp#y))

// ========================================================================
// 同名子ノードの衝突テスト
// ========================================================================

/// 異なる親の下に同名の子ノードを追加しても衝突しない
@Test
def testSceneSameChildNameDifferentParents(): Unit \ Assert =
    let scene = Scene.empty()
        |> Scene.addNode("frog", tmarker(0.0, 0.0))
        |> Scene.addNode("turtle", tmarker(10.0, 0.0))
        |> Scene.addChild("frog", "sprite", tmarker(1.0, 1.0))
        |> Scene.addChild("turtle", "sprite", tmarker(2.0, 2.0));
    let frogPos = Scene.globalPositionAt("frog" :: "sprite" :: Nil, scene);
    let turtlePos = Scene.globalPositionAt("turtle" :: "sprite" :: Nil, scene);
    Assert.assertEq(
        expected = (1.0, 1.0, 12.0, 2.0),
        (frogPos#x, frogPos#y, turtlePos#x, turtlePos#y)
    )
