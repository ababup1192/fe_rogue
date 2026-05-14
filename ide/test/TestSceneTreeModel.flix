// Tests for SceneTreeModel — JSON シーンツリー → 中間ツリーモデル変換の純粋ロジック
//
// 検証の観点:
//   - JSON の type/name から「[Type] Name」ラベルが組み立てられるか
//   - children 配列で 1 段降りるとノードパスがインデックス列で積み上がるか
//   - 型情報が無い / 想定外の形でも安全にフォールバック表示できるか

mod TestSceneTreeModel {

    // ========================================================================
    // labelFor — JSON 要素 1 つから 1 行ラベルを作る
    // ========================================================================

    /// "type" と "name" が揃っているとき "[type] name" 形式になる
    @Test
    def testLabelForTypedNamedObject(): Unit \ Assert =
        let elem = Json.JsonElement.JsonObject(Map#{
            "type" => Json.JsonElement.JsonString("Sprite2D"),
            "name" => Json.JsonElement.JsonString("hero")});
        Assert.assertEq(expected = "[Sprite2D] hero", SceneTreeModel.labelFor(elem))

    /// "type" が無いと "Node" がデフォルトとして使われる
    @Test
    def testLabelForMissingTypeUsesNodeDefault(): Unit \ Assert =
        let elem = Json.JsonElement.JsonObject(Map#{
            "name" => Json.JsonElement.JsonString("hero")});
        Assert.assertEq(expected = "[Node] hero", SceneTreeModel.labelFor(elem))

    /// "name" が無いと "<unnamed>" プレースホルダになる
    @Test
    def testLabelForMissingNameUsesPlaceholder(): Unit \ Assert =
        let elem = Json.JsonElement.JsonObject(Map#{
            "type" => Json.JsonElement.JsonString("Sprite2D")});
        Assert.assertEq(expected = "[Sprite2D] <unnamed>", SceneTreeModel.labelFor(elem))

    /// ルートが JsonArray の場合は "<root array>" 表示
    @Test
    def testLabelForArrayIsRootArrayMarker(): Unit \ Assert =
        let elem = Json.JsonElement.JsonArray(Vector#{});
        Assert.assertEq(expected = "<root array>", SceneTreeModel.labelFor(elem))

    /// 文字列や数値など想定外の値は "<invalid>" でクラッシュさせない
    @Test
    def testLabelForUnsupportedReturnsInvalidMarker(): Unit \ Assert =
        Assert.assertEq(
            expected = ("<invalid>", "<invalid>", "<invalid>"),
            (SceneTreeModel.labelFor(Json.JsonElement.JsonString("x")),
             SceneTreeModel.labelFor(Json.JsonElement.JsonNumber(1.0ff)),
             SceneTreeModel.labelFor(Json.JsonElement.JsonNull)))

    // ========================================================================
    // fromJson — JSON ツリー全体を TreeModelNode に変換する
    // ========================================================================

    /// children を持たない単一ノードはラベルだけのリーフになる。
    /// ルートのノードパスは Nil。
    ///
    /// 入力:  { type: "Sprite2D", name: "hero" }
    /// 期待:  TreeModelNode { label: "[Sprite2D] hero", nodePath: [], children: [] }
    @Test
    def testFromJsonLeafNode(): Unit \ Assert =
        let elem = Json.JsonElement.JsonObject(Map#{
            "type" => Json.JsonElement.JsonString("Sprite2D"),
            "name" => Json.JsonElement.JsonString("hero")});
        let tree = SceneTreeModel.fromJson(elem);
        Assert.assertEq(
            expected = ("[Sprite2D] hero", (Nil: List[Int32]), 0),
            (SceneTreeModel.labelOf(tree),
             SceneTreeModel.nodePathOf(tree),
             List.length(SceneTreeModel.childrenOf(tree))))

    /// children: [a, b] の構造で、各子のノードパスが [0] と [1] になる。
    ///
    /// 入力:  {
    ///          type: "Parent", name: "p",
    ///          children: [
    ///            { type: "Child", name: "a" },
    ///            { type: "Child", name: "b" }
    ///          ]
    ///        }
    /// 期待: ルート children が 2 件、それぞれ nodePath = [0] / [1]
    @Test
    def testFromJsonChildrenGetSequentialNodePaths(): Unit \ Assert =
        let childA = Json.JsonElement.JsonObject(Map#{
            "type" => Json.JsonElement.JsonString("Child"),
            "name" => Json.JsonElement.JsonString("a")});
        let childB = Json.JsonElement.JsonObject(Map#{
            "type" => Json.JsonElement.JsonString("Child"),
            "name" => Json.JsonElement.JsonString("b")});
        let root = Json.JsonElement.JsonObject(Map#{
            "type"     => Json.JsonElement.JsonString("Parent"),
            "name"     => Json.JsonElement.JsonString("p"),
            "children" => Json.JsonElement.JsonArray(Vector#{childA, childB})});
        let children = SceneTreeModel.fromJson(root) |> SceneTreeModel.childrenOf;
        match children {
            case first :: second :: Nil =>
                Assert.assertEq(
                    expected = (("[Child] a", 0i32 :: Nil),
                                ("[Child] b", 1i32 :: Nil)),
                    ((SceneTreeModel.labelOf(first),  SceneTreeModel.nodePathOf(first)),
                     (SceneTreeModel.labelOf(second), SceneTreeModel.nodePathOf(second))))
            case _ => bug!("expected exactly 2 child TreeModelNodes")
        }

    /// 孫ノードのノードパスは [親 idx, 自分 idx] のように積まれる。
    /// ルート -> [0] -> [0,0]
    ///
    /// 入力:  {
    ///          name: "root",
    ///          children: [
    ///            { name: "child",
    ///              children: [
    ///                { name: "grandchild" }
    ///              ]
    ///            }
    ///          ]
    ///        }
    @Test
    def testFromJsonGrandchildNodePathStacksIndices(): Unit \ Assert =
        let grandchild = Json.JsonElement.JsonObject(Map#{
            "name" => Json.JsonElement.JsonString("grandchild")});
        let child = Json.JsonElement.JsonObject(Map#{
            "name"     => Json.JsonElement.JsonString("child"),
            "children" => Json.JsonElement.JsonArray(Vector#{grandchild})});
        let root = Json.JsonElement.JsonObject(Map#{
            "name"     => Json.JsonElement.JsonString("root"),
            "children" => Json.JsonElement.JsonArray(Vector#{child})});
        let tree = SceneTreeModel.fromJson(root);
        match SceneTreeModel.childrenOf(tree) {
            case firstChild :: Nil =>
                match SceneTreeModel.childrenOf(firstChild) {
                    case firstGrandchild :: Nil =>
                        Assert.assertEq(
                            expected = 0i32 :: 0i32 :: Nil,
                            SceneTreeModel.nodePathOf(firstGrandchild))
                    case _ => bug!("expected exactly 1 grandchild TreeModelNode")
                }
            case _ => bug!("expected exactly 1 child TreeModelNode")
        }

    /// ルートが JsonArray の場合、配列の各要素が直接の子になる
    @Test
    def testFromJsonRootArrayElementsBecomeChildren(): Unit \ Assert =
        let elemA = Json.JsonElement.JsonObject(Map#{
            "type" => Json.JsonElement.JsonString("Node"),
            "name" => Json.JsonElement.JsonString("a")});
        let elemB = Json.JsonElement.JsonObject(Map#{
            "type" => Json.JsonElement.JsonString("Node"),
            "name" => Json.JsonElement.JsonString("b")});
        let arrayRoot = Json.JsonElement.JsonArray(Vector#{elemA, elemB});
        let tree = SceneTreeModel.fromJson(arrayRoot);
        Assert.assertEq(
            expected = ("<root array>", 2),
            (SceneTreeModel.labelOf(tree),
             List.length(SceneTreeModel.childrenOf(tree))))
}
