// Tests for DragInput — マウス入力 → 選択 → ドラッグ → 書き戻し
//
// snapVec2 と applyDrag は純粋なので直接テスト。
// handleMouse は GameEngine.Game / Fs.FileRead / Fs.FileWrite を持つので、
// 書き込みが起きない前提のフレームでは bug!() するモックハンドラで覆い、
// 「クリックのみで write スキップ」の不変条件を検証する

mod TestDragInput {

    // ====================================================================
    // 共通テストヘルパー
    // ====================================================================

    /// 中央基準の Sprite2D を 1 個 root に置いたシーンを作る
    def sceneWithSprite(name: NodeName, pos: Vec2.Vec2): Scene[NodeTag] =
        let sprite = Sprite2D.make("dummy.png", pos, {x = 1.0, y = 1.0});
        let s: Scene[NodeTag] = Scene.empty();
        s |> Scene.addNode(name, EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag))

    /// 「選択中＆ドラッグ開始済み」の EditorStateData を作る
    def draggingState(jsonPath: String, nodePath: NodePath,
                      mouseDown: Vec2.Vec2, nodeGlobal: Vec2.Vec2): Editor.EditorStateData = {
        on = true,
        selected = Some((jsonPath, nodePath)),
        dragOrigin = Some(mouseDown),
        nodeOrigin = Some(nodeGlobal),
        resizeOrigin = None,
        prevF1 = false,
        prevMouseLeft = true,
        prevArrowKeys = KeyboardNudge.initialPrev(),
        prevZ = false,
        rootJsonIndex = Map.empty()
    }

    // ====================================================================
    // snapVec2 — ピクセル整数スナップ
    // ====================================================================

    /// 0.4 は 0 に丸まる
    @Test
    def testSnapVec2RoundsDown(): Unit \ Assert =
        let snapped = DragInput.snapVec2({x = 10.4, y = 20.4});
        Assert.assertEq(expected = (10.0, 20.0), (snapped#x, snapped#y))

    /// 0.6 は 1 に丸まる
    @Test
    def testSnapVec2RoundsUp(): Unit \ Assert =
        let snapped = DragInput.snapVec2({x = 10.6, y = 20.6});
        Assert.assertEq(expected = (11.0, 21.0), (snapped#x, snapped#y))

    /// 負数も round（half-to-even だが整数値はそのまま）
    @Test
    def testSnapVec2NegativeIntegers(): Unit \ Assert =
        let snapped = DragInput.snapVec2({x = -5.0, y = -3.0});
        Assert.assertEq(expected = (-5.0, -3.0), (snapped#x, snapped#y))

    // ====================================================================
    // applyDrag — マウス移動量分だけグローバル位置が動く
    // ====================================================================

    /// selected が None なら scene は変わらない
    @Test
    def testApplyDragWithoutSelectionIsNoOp(): Unit \ Assert =
        let scene = sceneWithSprite("hero", {x = 100.0, y = 100.0});
        let state: Editor.EditorStateData = {
            on = true,
            selected = None,
            dragOrigin = None,
            nodeOrigin = None,
            resizeOrigin = None,
            prevF1 = false,
            prevMouseLeft = true,
            prevArrowKeys = KeyboardNudge.initialPrev(),
            prevZ = false,
            rootJsonIndex = Map.empty()
        };
        let next = DragInput.applyDrag({x = 150.0, y = 150.0}, state, scene);
        let pos = Scene.globalPositionAt("hero" :: Nil, next);
        Assert.assertEq(expected = (100.0, 100.0), (pos#x, pos#y))

    /// マウスを (50, 50) → (80, 70) に動かすと、ノードのグローバル位置も (30, 20) ぶん動く
    @Test
    def testApplyDragMovesNodeByDelta(): Unit \ Assert =
        let scene = sceneWithSprite("hero", {x = 100.0, y = 100.0});
        let state = draggingState("hero.json", "hero" :: Nil,
                                  {x = 50.0, y = 50.0},  // dragOrigin
                                  {x = 100.0, y = 100.0});  // nodeOrigin
        let next = DragInput.applyDrag({x = 80.0, y = 70.0}, state, scene);
        let pos = Scene.globalPositionAt("hero" :: Nil, next);
        // 100 + (80 - 50) = 130, 100 + (70 - 50) = 120
        Assert.assertEq(expected = (130.0, 120.0), (pos#x, pos#y))

    /// 半端なマウス移動は整数ピクセルにスナップされる
    @Test
    def testApplyDragSnapsToIntegerPixels(): Unit \ Assert =
        let scene = sceneWithSprite("hero", {x = 100.0, y = 100.0});
        let state = draggingState("hero.json", "hero" :: Nil,
                                  {x = 50.0, y = 50.0},
                                  {x = 100.0, y = 100.0});
        // delta = (0.4, 0.6) → スナップで (0, 1)
        let next = DragInput.applyDrag({x = 50.4, y = 50.6}, state, scene);
        let pos = Scene.globalPositionAt("hero" :: Nil, next);
        Assert.assertEq(expected = (100.0, 101.0), (pos#x, pos#y))

    // ====================================================================
    // handleMouse — クリック離した時に書き込みが走るかを検証
    //
    // Fs.FileWrite が呼ばれた瞬間に bug!() するハンドラで包む。
    // クリックのみ（位置不変）で release した場合は呼ばれないので test pass、
    // もし内部実装が条件を間違えて書き込んでしまったら bug!() で fail
    // ====================================================================

    // ====================================================================
    // テスト用合成モック環境 — `run { } with X with Y with Z` で複数ハンドラを
    // 1 つの run に連結する（ネストを避ける）
    //   - GameEngine.Game: すべてリリース状態（キー/マウス入力なし）
    //   - Fs.FileRead / Fs.FileWrite: 呼ばれた瞬間に bug!()
    // よって「クリックのみで release」のフレームに JSON 書き戻しが起きると
    // 即テスト失敗になる
    // ====================================================================

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

    /// クリック → そのまま離す（位置不変）で release を迎えたとき、
    /// JSON 書き戻し（Fs.FileWrite）は発生してはならない
    def testHandleMouseClickOnlySkipsWrite(): Unit \
            {Assert, GameEngine.Game, Fs.FileRead, Fs.FileWrite,
             EditHistory.Rewind} =
        let scene = sceneWithSprite("hero", {x = 100.0, y = 100.0});
        // 押下時点で nodeOrigin = (100, 100) を記録した状態を作る。
        // mouseLeft=false (releasedNow), prevMouseLeft=true (前フレーム押下中)
        // ノード位置は動かしていない → moved=false → 書き込み発生しない想定
        let state = draggingState("hero.json", "hero" :: Nil,
                                  {x = 100.0, y = 100.0},  // dragOrigin
                                  {x = 100.0, y = 100.0});  // nodeOrigin
        let (newState, _) = DragInput.handleMouse(
            {pos = {x = 100.0, y = 100.0}, leftDown = false},
            {x = 0.0, y = 0.0},
            state, scene);
        // ドラッグ状態がクリアされている
        Assert.assertEq(
            expected = (true, true),
            (Option.isEmpty(newState#dragOrigin),
             Option.isEmpty(newState#nodeOrigin)))

    @Test
    def testHandleMouseClickOnlySkipsWriteRunner(): Unit \ Assert =
        withForbiddenFs(testHandleMouseClickOnlySkipsWrite)
}
