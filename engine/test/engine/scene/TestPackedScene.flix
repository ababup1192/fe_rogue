// Tests for PackedScene module
//
// fromJsonString で JSON 文字列からテンプレートを構築し、instantiate の各オプションを検証する。
// 実ファイル I/O は走らないが、API シグネチャ上必要なので Fs.FileRead / GameEngine.Game を
// no-op ハンドラで run する。

// ========================================================================
// テストヘルパ
// ========================================================================

/// 単純な StaticBody2D テンプレート（子なし）
def singleNodeTemplate(): PackedScene =
    PackedScene.fromJsonString({
        source = "test-template",
        jsonText = String.unlines(
            "{" ::
            "  \"type\": \"StaticBody2D\"," ::
            "  \"name\": \"ground\"," ::
            "  \"pos\": [0, 0]," ::
            "  \"shape\": {\"kind\": \"RectShape2D\", \"width\": 100, \"height\": 20}" ::
            "}" :: Nil)
    })

/// StaticBody2D + 子 Sprite2D のテンプレート（子ツリーのコピー検証用）
def nodeWithChildTemplate(): PackedScene =
    PackedScene.fromJsonString({
        source = "test-template-child",
        jsonText = String.unlines(
            "{" ::
            "  \"type\": \"StaticBody2D\"," ::
            "  \"name\": \"root\"," ::
            "  \"pos\": [0, 0]," ::
            "  \"shape\": {\"kind\": \"RectShape2D\", \"width\": 50, \"height\": 50}," ::
            "  \"children\": [" ::
            "    {" ::
            "      \"type\": \"Sprite2D\"," ::
            "      \"name\": \"icon\"," ::
            "      \"pos\": [5, 7]," ::
            "      \"scale\": [1, 1]," ::
            "      \"texture\": \"dummy\"" ::
            "    }" ::
            "  ]" ::
            "}" :: Nil)
    })

/// タグ無視 tagParser（テスト用、Unit を返す）
def unitTagParser(): Option[String] -> Result[Json.JsonError, Unit] = _ -> Ok(())

/// PackedScene.instantiate を no-op エフェクトハンドラで実行する。
/// 引数を直接渡すことで closure を作らず、JVM の method-size 制限を回避する。
def runInstantiate(args: InstantiateArgs[Unit]): Scene[Unit] =
    run {
        PackedScene.instantiate(args)
    } with handler Fs.FileRead {
        def read(_, _) = bug!("unexpected file read")
        def readLines(_, _) = bug!("unexpected file readLines")
        def readBytes(_, _) = bug!("unexpected file readBytes")
    } with handler GameEngine.Game {
        def renderCommands(_, _, k) = k(())
        def initTileBuffer(_, k) = k((0i32, 0i32))
        def shouldClose(k) = k(false)
        def getDeltaTime(k) = k(16 |> Duration.millis)
        def isKeyPressed(_, k) = k(false)
        def getMousePosition(k) = k(Vec2.zero())
        def isMouseButtonPressed(_, k) = k(false)
        def consumeScrollDelta(k) = k(0.0)
        def getFontAtlas(_, _) = bug!("font not used")
        def getViewportRect(k) = k({position = Vec2.zero(), size = {x = 480.0, y = 720.0}})
        def getTextureInfo(_, k) = k(None)
        def setCursor(_, k) = k(())
    }

// ========================================================================
// テストケース
// ========================================================================

/// 1 回 instantiate でテンプレートのルートノード名がそのまま scene に追加される
@Test
def testInstantiateSingleNode(): Unit \ Assert =
    let template = singleNodeTemplate();
    let scene = runInstantiate({
        opts = PackedScene.defaultOpts(),
        tagParser = unitTagParser(),
        template = template,
        fontAtlas = None,
        scene = Scene.empty()
    });
    Assert.assertEq(
        expected = ("ground" :: Nil) :: Nil,
        Scene.preorderPaths(scene))

/// 同じテンプレートを別名で 2 回 instantiate するとルートが 2 つ並ぶ
@Test
def testInstantiateTwiceWithNameOverride(): Unit \ Assert =
    let template = singleNodeTemplate();
    let s1 = runInstantiate({
        opts = {parentPath = Nil, nameOverride = Some("a"), positionOverride = None},
        tagParser = unitTagParser(),
        template = template,
        fontAtlas = None,
        scene = Scene.empty()
    });
    let s2 = runInstantiate({
        opts = {parentPath = Nil, nameOverride = Some("b"), positionOverride = None},
        tagParser = unitTagParser(),
        template = template,
        fontAtlas = None,
        scene = s1
    });
    Assert.assertEq(
        expected = Set#{"a" :: Nil, "b" :: Nil},
        List.toSet(Scene.preorderPaths(s2)))

/// positionOverride が global position に反映される
@Test
def testInstantiateWithPositionOverride(): Unit \ Assert =
    let template = singleNodeTemplate();
    let scene = runInstantiate({
        opts = {parentPath = Nil, nameOverride = Some("at100"),
                positionOverride = Some({x = 100.0, y = 200.0})},
        tagParser = unitTagParser(),
        template = template,
        fontAtlas = None,
        scene = Scene.empty()
    });
    let pos = Scene.globalPositionAt("at100" :: Nil, scene);
    Assert.assertEq(expected = (100.0, 200.0), (pos#x, pos#y))

/// parentPath を指定するとそのノード配下に挿入される
/// 子の globalPosition は parent.x (50) + child.local.x (10) = 60
@Test
def testInstantiateAtParentPath(): Unit \ Assert =
    let template = singleNodeTemplate();
    let parentNode: EngineNode[Unit] =
        EngineNode.Marker2DWithState(Marker2D.make({x = 50.0, y = 0.0}), ());
    let base = Scene.empty() |> Scene.addNode("parent", parentNode);
    let scene = runInstantiate({
        opts = {parentPath = "parent" :: Nil, nameOverride = Some("child"),
                positionOverride = Some({x = 10.0, y = 0.0})},
        tagParser = unitTagParser(),
        template = template,
        fontAtlas = None,
        scene = base
    });
    let pos = Scene.globalPositionAt("parent" :: "child" :: Nil, scene);
    Assert.assertEq(expected = (60.0, 0.0), (pos#x, pos#y))

/// 子を持つテンプレートを instantiate すると子ツリー（icon, pos=(5,7)）が保持される
@Test
def testInstantiateChildrenPreserved(): Unit \ Assert =
    let template = nodeWithChildTemplate();
    let scene = runInstantiate({
        opts = {parentPath = Nil, nameOverride = Some("root"), positionOverride = None},
        tagParser = unitTagParser(),
        template = template,
        fontAtlas = None,
        scene = Scene.empty()
    });
    let iconPos = Scene.globalPositionAt("root" :: "icon" :: Nil, scene);
    Assert.assertEq(expected = (5.0, 7.0), (iconPos#x, iconPos#y))
