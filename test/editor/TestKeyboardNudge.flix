// Tests for KeyboardNudge — 矢印キーで選択ノードを 1px / 10px 単位で動かす
//
// pressEdges / nudgeDelta は純粋関数なので直接テスト。
// applyNudge は GameEngine.Game / Fs.FileRead / Fs.FileWrite を持つので、
// 「動きが起きないケース」では bug!() するモックハンドラで覆い、
// 「クリックのみ／選択なし／既押下キー」で write が発火しないことを検証する

mod TestKeyboardNudge {

    // ====================================================================
    // pressEdges — エッジ検出の純粋関数
    // ====================================================================

    /// 前 false → 今 true は edge=true
    @Test
    def testPressEdgesFreshPressIsEdge(): Unit \ Assert =
        let prev = {up = false, down = false, left = false, right = false};
        let cur  = {up = true,  down = false, left = false, right = false};
        let edges = KeyboardNudge.pressEdges(prev, cur);
        Assert.assertEq(
            expected = (true, false, false, false),
            (edges#up, edges#down, edges#left, edges#right))

    /// 前 true → 今 true は edge=false（押しっぱなしは edge にならない）
    @Test
    def testPressEdgesHeldKeyIsNotEdge(): Unit \ Assert =
        let prev = {up = true, down = false, left = false, right = false};
        let cur  = {up = true, down = false, left = false, right = false};
        let edges = KeyboardNudge.pressEdges(prev, cur);
        Assert.assertEq(expected = false, edges#up)

    /// 前 true → 今 false は edge=false（離した瞬間は edge にしない）
    @Test
    def testPressEdgesReleaseIsNotEdge(): Unit \ Assert =
        let prev = {up = true,  down = false, left = false, right = false};
        let cur  = {up = false, down = false, left = false, right = false};
        let edges = KeyboardNudge.pressEdges(prev, cur);
        Assert.assertEq(expected = false, edges#up)

    // ====================================================================
    // nudgeDelta — 押下エッジ → 移動量
    // ====================================================================

    /// 右だけエッジなら +1px x 方向
    @Test
    def testNudgeDeltaRightOnePixel(): Unit \ Assert =
        let edges = {up = false, down = false, left = false, right = true};
        let delta = KeyboardNudge.nudgeDelta(edges, 1.0);
        Assert.assertEq(expected = (1.0, 0.0), (delta#x, delta#y))

    /// 左だけエッジなら -1px x 方向
    @Test
    def testNudgeDeltaLeftOnePixel(): Unit \ Assert =
        let edges = {up = false, down = false, left = true, right = false};
        let delta = KeyboardNudge.nudgeDelta(edges, 1.0);
        Assert.assertEq(expected = (-1.0, 0.0), (delta#x, delta#y))

    /// 上下同時エッジは打ち消し合ってゼロ
    @Test
    def testNudgeDeltaUpDownCancels(): Unit \ Assert =
        let edges = {up = true, down = true, left = false, right = false};
        let delta = KeyboardNudge.nudgeDelta(edges, 1.0);
        Assert.assertEq(expected = (0.0, 0.0), (delta#x, delta#y))

    /// 右下同時エッジは斜め移動
    @Test
    def testNudgeDeltaRightDownDiagonal(): Unit \ Assert =
        let edges = {up = false, down = true, left = false, right = true};
        let delta = KeyboardNudge.nudgeDelta(edges, 1.0);
        Assert.assertEq(expected = (1.0, 1.0), (delta#x, delta#y))

    /// step=10 で 10px 移動（Shift 押下時の挙動）
    @Test
    def testNudgeDeltaShiftStepIsTenPixels(): Unit \ Assert =
        let edges = {up = false, down = false, left = false, right = true};
        let delta = KeyboardNudge.nudgeDelta(edges, 10.0);
        Assert.assertEq(expected = (10.0, 0.0), (delta#x, delta#y))

    /// 全部 false なら delta もゼロ
    @Test
    def testNudgeDeltaNoKeysIsZero(): Unit \ Assert =
        let edges = {up = false, down = false, left = false, right = false};
        let delta = KeyboardNudge.nudgeDelta(edges, 1.0);
        Assert.assertEq(expected = (0.0, 0.0), (delta#x, delta#y))

    // ====================================================================
    // applyNudge — 全体フロー（write 発火しないケース）
    // ====================================================================

    /// 中央基準の Sprite2D を 1 個 root に置いたシーン
    def sceneWithSprite(name: NodeName, pos: Vec2.Vec2): Scene[NodeTag] =
        let sprite = Sprite2D.make("dummy.png", pos, {x = 1.0, y = 1.0});
        let s: Scene[NodeTag] = Scene.empty();
        s |> Scene.addNode(name, EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag))

    /// 選択中だが矢印キー押下なし、prev も全 false の state
    def quietState(jsonPath: String, nodePath: NodePath): Editor.EditorStateData = {
        on = true,
        selected = Some((jsonPath, nodePath)),
        dragOrigin = None,
        nodeOrigin = None,
        resizeOrigin = None,
        prevF1 = false,
        prevMouseLeft = false,
        prevArrowKeys = KeyboardNudge.initialPrev(),
        prevZ = false,
        rootJsonIndex = Map.empty()
    }

    /// 押下キーなし＆ prev も無し → エッジは立たない → 書き込みも発生しない
    def testApplyNudgeNoKeysNoWrite(): Unit \
            {Assert, GameEngine.Game, Fs.FileRead, Fs.FileWrite, EditHistory.Rewind} =
        let scene = sceneWithSprite("hero", {x = 100.0, y = 100.0});
        let state = quietState("hero.json", "hero" :: Nil);
        let curArrows = KeyboardNudge.initialPrev();
        let next = KeyboardNudge.applyNudge(state, curArrows, scene);
        let pos = Scene.globalPositionAt("hero" :: Nil, next);
        Assert.assertEq(expected = (100.0, 100.0), (pos#x, pos#y))

    @Test
    def testApplyNudgeNoKeysNoWriteRunner(): Unit \ Assert =
        withForbiddenFs(testApplyNudgeNoKeysNoWrite)

    /// 選択ノードがない → 何もしない
    def testApplyNudgeNoSelectionNoWrite(): Unit \
            {Assert, GameEngine.Game, Fs.FileRead, Fs.FileWrite, EditHistory.Rewind} =
        let scene = sceneWithSprite("hero", {x = 100.0, y = 100.0});
        // prev=false, cur=true（右）— 通常なら書き込みが発生するが selected=None なのでスキップ
        let state: Editor.EditorStateData = {
            on = true,
            selected = None,
            dragOrigin = None,
            nodeOrigin = None,
            resizeOrigin = None,
            prevF1 = false,
            prevMouseLeft = false,
            prevArrowKeys = KeyboardNudge.initialPrev(),
            prevZ = false,
            rootJsonIndex = Map.empty()
        };
        let curArrows = {up = false, down = false, left = false, right = true};
        let next = KeyboardNudge.applyNudge(state, curArrows, scene);
        let pos = Scene.globalPositionAt("hero" :: Nil, next);
        Assert.assertEq(expected = (100.0, 100.0), (pos#x, pos#y))

    @Test
    def testApplyNudgeNoSelectionNoWriteRunner(): Unit \ Assert =
        withForbiddenFs(testApplyNudgeNoSelectionNoWrite)

    /// 押しっぱなし（prev=true, cur=true）はエッジが立たない → 書き込みなし
    def testApplyNudgeHeldKeyNoWrite(): Unit \
            {Assert, GameEngine.Game, Fs.FileRead, Fs.FileWrite, EditHistory.Rewind} =
        let scene = sceneWithSprite("hero", {x = 100.0, y = 100.0});
        let state: Editor.EditorStateData = {
            on = true,
            selected = Some(("hero.json", "hero" :: Nil)),
            dragOrigin = None,
            nodeOrigin = None,
            resizeOrigin = None,
            prevF1 = false,
            prevMouseLeft = false,
            prevArrowKeys = {up = false, down = false, left = false, right = true},
            prevZ = false,
            rootJsonIndex = Map.empty()
        };
        let curArrows = {up = false, down = false, left = false, right = true};
        let next = KeyboardNudge.applyNudge(state, curArrows, scene);
        let pos = Scene.globalPositionAt("hero" :: Nil, next);
        Assert.assertEq(expected = (100.0, 100.0), (pos#x, pos#y))

    @Test
    def testApplyNudgeHeldKeyNoWriteRunner(): Unit \ Assert =
        withForbiddenFs(testApplyNudgeHeldKeyNoWrite)

    /// 書き込みが発生してはいけない場面用のモック環境。
    /// GameEngine.Game は LeftShift 押下=false / 他全 false、
    /// Fs.FileRead / FileWrite は呼ばれた瞬間に bug!()
    def withForbiddenFs(f: Unit -> a \
            {Assert, GameEngine.Game, Fs.FileRead, Fs.FileWrite,
             EditHistory.Rewind}): a \ Assert =
        run {
            f()
        } with handler EditHistory.Rewind {
            def save(_, _) = bug!("unexpected EditHistory.save")
            def rewind(_) = bug!("unexpected EditHistory.rewind")
        } with handler Fs.FileWrite {
            def write(_, _, _) = bug!("unexpected file write")
            def writeLines(_, _, _) = bug!("unexpected file writeLines")
            def writeBytes(_, _, _) = bug!("unexpected file writeBytes")
            def append(_, _, _) = bug!("unexpected file append")
            def appendLines(_, _, _) = bug!("unexpected file appendLines")
            def appendBytes(_, _, _) = bug!("unexpected file appendBytes")
            def truncate(_, _) = bug!("unexpected file truncate")
            def copyWith(_, _, _, _) = bug!("unexpected file copyWith")
            def moveWith(_, _, _, _) = bug!("unexpected file moveWith")
            def delete(_, _) = bug!("unexpected file delete")
            def mkDir(_, _) = bug!("unexpected file mkDir")
            def mkDirs(_, _) = bug!("unexpected file mkDirs")
            def mkTempDir(_, _) = bug!("unexpected file mkTempDir")
        } with handler Fs.FileRead {
            def read(_, _) = bug!("unexpected file read")
            def readLines(_, _) = bug!("unexpected file readLines")
            def readBytes(_, _) = bug!("unexpected file readBytes")
        } with handler GameEngine.Game {
            def render(_, k) = k(())
            def shouldClose(k) = k(false)
            def getDeltaTime(k) = k(0.016)
            def isKeyPressed(_, k) = k(false)
            def getMousePosition(k) = k({x = 0.0, y = 0.0})
            def isMouseButtonPressed(_, k) = k(false)
            def getFontAtlas(_, _) = bug!("font not used")
            def getViewportRect(k) = k({position = {x = 0.0, y = 0.0}, size = {x = 480.0, y = 720.0}})
            def getTextureInfo(_, k) = k(Some({id = 0i32, width = 32.0, height = 32.0}))
            def setCursor(_, k) = k(())
        }
}
