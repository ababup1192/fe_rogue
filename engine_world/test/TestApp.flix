// TestApp — App の純粋な芯を具体値で固定する: frameOf のエッジ判定（新規押下だけが
// justPressed に立ち、押しっぱなし・離しは立たない）、applySystems の適用順（追加順 =
// 左から右。+1 して ×2 なら 2、逆なら 1 なので順序が数字に出る）、quit の既定
// （Escape のエッジで終了・押しっぱなしでは終了しない）。
// Frame は record なので、比較はタプルへ射影して行う。

mod TestApp {

    /// Frame を比較できるタプル (down, justPressed, dt) へ射影する。
    def frameTuple(frame: App.Frame): (Set[GameEngine.Key], Set[GameEngine.Key], Float64) =
        (frame#down, frame#justPressed, frame#dt)

    /// テスト用の design サイズ。ここのテストは viewport を見ないので値は任意。
    def testViewport(): Vec2.Vec2 = { x = 320.0, y = 240.0 }

    /// キー無し・dt 0 の Frame。
    def emptyFrame(): App.Frame =
        App.frameOf(prev = Set#{}, current = Set#{}, 0.0, testViewport())

    // ========================================================================
    // frameOf: エッジ判定
    // ========================================================================

    // 新規押下: 前に無く今ある Left は down にも justPressed にも立つ。dt は素通し。
    @Test
    def testFrameOfNewPressIsEdge(): Unit \ Assert =
        let actual = App.frameOf(prev = Set#{}, current = Set#{GameEngine.Key.Left}, 0.016, testViewport());
        Assert.assertEq(expected = (Set#{GameEngine.Key.Left}, Set#{GameEngine.Key.Left}, 0.016),
            frameTuple(actual))

    // 押しっぱなし: 前も今もある Left は down のまま、justPressed には立たない。
    @Test
    def testFrameOfHeldKeyIsNotEdge(): Unit \ Assert =
        let actual = App.frameOf(prev = Set#{GameEngine.Key.Left}, current = Set#{GameEngine.Key.Left}, 0.016, testViewport());
        Assert.assertEq(expected = (Set#{GameEngine.Key.Left}, Set#{}, 0.016),
            frameTuple(actual))

    // 離し: 前にあって今無い Left はどちらにも立たない（離しエッジは追わない）。
    @Test
    def testFrameOfReleaseIsSilent(): Unit \ Assert =
        let actual = App.frameOf(prev = Set#{GameEngine.Key.Left}, current = Set#{}, 0.016, testViewport());
        Assert.assertEq(expected = (Set#{}, Set#{}, 0.016),
            frameTuple(actual))

    // 混在: 押しっぱなしの Left と新規の Space が並ぶと、エッジは Space だけ。
    @Test
    def testFrameOfMixedKeysSplitEdges(): Unit \ Assert =
        let actual = App.frameOf(
            prev = Set#{GameEngine.Key.Left},
            current = Set#{GameEngine.Key.Left, GameEngine.Key.Space}, 0.016, testViewport());
        Assert.assertEq(
            expected = (Set#{GameEngine.Key.Left, GameEngine.Key.Space}, Set#{GameEngine.Key.Space}, 0.016),
            frameTuple(actual))

    // ========================================================================
    // applySystems: 追加順 = 適用順
    // ========================================================================

    // +1 → ×2 の順なら (0+1)*2 = 2。逆順なら 0*2+1 = 1 なので、順序の取り違えは数字に出る。
    @Test
    def testApplySystemsRunsInOrder(): Unit \ Assert =
        let systems = ((_frame, n) -> n + 1) :: ((_frame, n) -> n * 2) :: Nil;
        Assert.assertEq(expected = 2, App.applySystems(emptyFrame(), systems, 0))

    // システム無しなら World はそのまま。
    @Test
    def testApplySystemsEmptyIsIdentity(): Unit \ Assert =
        Assert.assertEq(expected = 7, App.applySystems(emptyFrame(), Nil, 7))

    // ========================================================================
    // axis: 負・正キーの押し下げ → -1 / 0 / +1
    // ========================================================================

    // 正キーだけ +1・負キーだけ -1・無押下 0・両押しは打ち消して 0。押しっぱなしも効く（down 判定）。
    @Test
    def testAxisFoldsKeysToScalar(): Unit \ Assert =
        let frameWith = keys -> App.frameOf(prev = keys, current = keys, 0.016, testViewport());
        let pos = App.axis(negative = GameEngine.Key.Left, positive = GameEngine.Key.Right, frameWith(Set#{GameEngine.Key.Right}));
        let neg = App.axis(negative = GameEngine.Key.Left, positive = GameEngine.Key.Right, frameWith(Set#{GameEngine.Key.Left}));
        let idle = App.axis(negative = GameEngine.Key.Left, positive = GameEngine.Key.Right, frameWith(Set#{}));
        let both = App.axis(negative = GameEngine.Key.Left, positive = GameEngine.Key.Right, frameWith(Set#{GameEngine.Key.Left, GameEngine.Key.Right}));
        Assert.assertEq(expected = (1.0, -1.0, 0.0, 0.0), (pos, neg, idle, both))

    // ========================================================================
    // composeScene: camera は world の絵だけに掛かり、hud には掛からない
    // ========================================================================

    def sceneDesign(): Vec2.Vec2 = { x = 320.0, y = 240.0 }

    def boxAtOrigin(): Render.PlacedItem =
        { at = { x = 0.0, y = 0.0 },
          item = Render.box({ x = 1.0, y = 1.0 }, { r = 1.0f32, g = 0.0f32, b = 0.0f32 }, 0) }

    def atOf(items: List[Render.PlacedItem]): Option[(Float64, Float64)] =
        List.head(items) |> Option.map(p -> (p#at#x, p#at#y))

    // camera なし: world の絵は恒等・hud が後ろに繋がる（順序も本数もそのまま）。
    @Test
    def testComposeSceneWithoutCameraIsIdentityAppend(): Unit \ Assert =
        let composed = App.composeScene(None, sceneDesign(),
            { world = boxAtOrigin() :: Nil, hud = boxAtOrigin() :: Nil });
        Assert.assertEq(expected = (2, Some((0.0, 0.0))), (List.length(composed), atOf(composed)))

    // camera あり: world の絵だけがずれ（原点は design/2 - center へ）、hud は不動のまま。
    @Test
    def testComposeSceneShiftsWorldButNotHud(): Unit \ Assert =
        let composed = App.composeScene(Some({ x = 100.0, y = 50.0 }), sceneDesign(),
            { world = boxAtOrigin() :: Nil, hud = boxAtOrigin() :: Nil });
        let hudAt = List.head(List.drop(1, composed)) |> Option.map(p -> (p#at#x, p#at#y));
        Assert.assertEq(expected = (Some((60.0, 70.0)), Some((0.0, 0.0))), (atOf(composed), hudAt))

    // center に置いた item は画面中央 design/2 に着地する（round-trip）。
    @Test
    def testComposeSceneLandsCenterAtMiddle(): Unit \ Assert =
        let center = { x = 100.0, y = 50.0 };
        let onCenter = { at = center | boxAtOrigin() };
        let composed = App.composeScene(Some(center), sceneDesign(),
            { world = onCenter :: Nil, hud = Nil });
        Assert.assertEq(expected = Some((160.0, 120.0)), atOf(composed))

    // ========================================================================
    // visibleOf: ViewCtx の visible（見えている world 矩形）の源
    // ========================================================================

    // camera なし: 原点起点の design 全体が見えている。
    @Test
    def testVisibleOfWithoutCameraIsDesignRect(): Unit \ Assert =
        let visible = App.visibleOf(None, sceneDesign());
        Assert.assertEq(expected = ((0.0, 0.0), (320.0, 240.0)),
            ((visible#position#x, visible#position#y), (visible#size#x, visible#size#y)))

    // camera あり: center − design/2 を左上とする design 大の矩形。
    // composeScene のずらし（testComposeSceneShiftsWorldButNotHud と同じ center）と表裏一体。
    @Test
    def testVisibleOfWithCameraCentersRect(): Unit \ Assert =
        let visible = App.visibleOf(Some({ x = 100.0, y = 50.0 }), sceneDesign());
        Assert.assertEq(expected = ((-60.0, -70.0), (320.0, 240.0)),
            ((visible#position#x, visible#position#y), (visible#size#x, visible#size#y)))

    // ========================================================================
    // makeWith: 初期 World は design サイズから組める
    // ========================================================================

    // makeWith の init は design サイズを受け取る（launch が画面サイズを渡して呼ぶ）。
    // 320 の半分 = 160 が出れば、画面中央のような導出をゲーム側がベタ書きせずに書ける。
    @Test
    def testMakeWithBuildsInitFromViewport(): Unit \ Assert =
        let app = App.makeWith(design -> design#x / 2.0);
        let init = app#init;
        Assert.assertEq(expected = 160.0, init(testViewport()))

    // make(値) は design サイズに依らず同じ初期 World を返す（既存ゲームの入口は不変）。
    @Test
    def testMakeIgnoresViewport(): Unit \ Assert =
        let init = App.make(42)#init;
        Assert.assertEq(expected = 42, init(testViewport()))

    // ========================================================================
    // quit: 既定は Escape のエッジ・quitWhen で差し替え
    // ========================================================================

    // 既定の quit は Escape の新規押下で true。
    @Test
    def testQuitDefaultFiresOnEscapeEdge(): Unit \ Assert =
        let frame = App.frameOf(prev = Set#{}, current = Set#{GameEngine.Key.Escape}, 0.016, testViewport());
        let wantsQuit = App.make(0)#quit;
        Assert.assertEq(expected = true, wantsQuit(frame, 0))

    // 押しっぱなしの Escape では終了しない（起動時に押されていたキーの誤発火を防ぐ）。
    @Test
    def testQuitDefaultIgnoresHeldEscape(): Unit \ Assert =
        let frame = App.frameOf(
            prev = Set#{GameEngine.Key.Escape}, current = Set#{GameEngine.Key.Escape}, 0.016, testViewport());
        let wantsQuit = App.make(0)#quit;
        Assert.assertEq(expected = false, wantsQuit(frame, 0))

    // quitWhen は判定を丸ごと差し替える（World も見られる）。
    @Test
    def testQuitWhenReplacesJudge(): Unit \ Assert =
        let app = App.make(9) |> App.quitWhen((_frame, n) -> n == 9);
        let wantsQuit = app#quit;
        Assert.assertEq(expected = true, wantsQuit(emptyFrame(), 9))
}
