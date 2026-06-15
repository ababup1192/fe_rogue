// Arc2D の scene.json ビルダー（SceneLoader.buildArc2D）のテスト。
// PackedScene.fromJString で JSON 文字列からテンプレートを作り、instantiate を no-op エフェクト
// ハンドラで実行して、Arc2D ノードが正しいプロパティで構築されることを検証する（実ファイル I/O なし）。

mod TestArc2DLoader {

    /// `{ "type": "Arc2D", ... }` 単体のテンプレート（クールダウン前景リング想定）
    def arc2dTemplate(): PackedScene =
        PackedScene.fromJString({
            source = "test-arc2d",
            jsonText = String.unlines(
                "{" ::
                "  \"type\": \"Arc2D\"," ::
                "  \"name\": \"cooldown_fg\"," ::
                "  \"pos\": [85, 64]," ::
                "  \"radius\": 8," ::
                "  \"width\": 2," ::
                "  \"startAngle\": 0," ::
                "  \"endAngle\": 3.141592653589793," ::
                "  \"segments\": 16," ::
                "  \"color\": {\"r\": 0.2, \"g\": 0.8, \"b\": 1.0}," ::
                "  \"zIndex\": 11" ::
                "}" :: Nil)
        })

    def unitTagParser(): Option[String] -> Result[Util.Json.JsonError, Unit] = _ -> Ok(())

    /// PackedScene.instantiate を no-op エフェクトハンドラで実行する（TestPackedScene と同形）。
    def runInstantiate(template: PackedScene): Scene[Unit] =
        run {
            PackedScene.instantiate({
                opts = PackedScene.defaultOpts(),
                tagParser = unitTagParser(),
                template = template,
                fontAtlas = None,
                scene = Scene.empty()
            })
        } with handler Fs.FileRead {
            def read(_, _) = bug!("unexpected file read")
            def readLines(_, _) = bug!("unexpected file readLines")
            def readBytes(_, _) = bug!("unexpected file readBytes")
        } with handler GameEngine.Game {
            def renderCommands(_, _, _, k) = k(())
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

    /// scene 内の Arc2D inner node を取り出す（型変種の確認も兼ねる）。
    def arc2dAt(path: NodePath, scene: Scene[Unit]): Option[Arc2D] =
        Option.flatMap(n -> match n {
            case EngineNode.Arc2DWithState(arc, _) => Some(arc)
            case _ => None
        }, Scene.getEngineNode(path, scene))

    /// JSON から Arc2D ノードが構築され、ルート名がそのまま使われる
    @Test
    def testArc2DBuilt(): Unit \ Assert =
        let scene = runInstantiate(arc2dTemplate());
        Assert.assertEq(expected = ("cooldown_fg" :: Nil) :: Nil, Scene.preorderPaths(scene))

    /// radius / endAngle / segments が JSON のとおりにパースされる
    @Test
    def testArc2DGeometryParsed(): Unit \ Assert =
        let arc = arc2dAt("cooldown_fg" :: Nil, runInstantiate(arc2dTemplate()));
        Assert.assertEq(expected = Some(8.0), Option.map(Arc2D.getRadius, arc));
        Assert.assertEq(expected = Some(2.0), Option.map(Arc2D.getWidth, arc));
        Assert.assertEq(expected = Some(3.141592653589793), Option.map(Arc2D.getEndAngle, arc));
        Assert.assertEq(expected = Some(16), Option.map(Arc2D.getSegments, arc))

    /// pos / zIndex が CanvasItem / Node2D レベルで反映される
    @Test
    def testArc2DPlacement(): Unit \ Assert =
        let node = Scene.getEngineNode("cooldown_fg" :: Nil, runInstantiate(arc2dTemplate()));
        Assert.assertEq(expected = Some(85.0), Option.map(n -> Node2D.getPosition(n)#x, node));
        Assert.assertEq(expected = Some(11), Option.map(n -> CanvasItem.getZIndex(n), node))
}
