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

    /// マウス無し（ボタン未押下）。キーだけを見るテストの frameOf に渡す。
    def noMouse(): { prevDown = Bool, down = Bool } = { prevDown = false, down = false }

    /// キー無し・dt 0 の Frame。
    def emptyFrame(): App.Frame =
        App.frameOf(prev = Set#{}, current = Set#{}, 0.0, testViewport(), Vec2.zero(), noMouse())

    // ========================================================================
    // frameOf: エッジ判定
    // ========================================================================

    // 新規押下: 前に無く今ある Left は down にも justPressed にも立つ。dt は素通し。
    @Test
    def testFrameOfNewPressIsEdge(): Unit \ Assert =
        let actual = App.frameOf(prev = Set#{}, current = Set#{GameEngine.Key.Left}, 0.016, testViewport(), Vec2.zero(), noMouse());
        Assert.assertEq(expected = (Set#{GameEngine.Key.Left}, Set#{GameEngine.Key.Left}, 0.016),
            frameTuple(actual))

    // 押しっぱなし: 前も今もある Left は down のまま、justPressed には立たない。
    @Test
    def testFrameOfHeldKeyIsNotEdge(): Unit \ Assert =
        let actual = App.frameOf(prev = Set#{GameEngine.Key.Left}, current = Set#{GameEngine.Key.Left}, 0.016, testViewport(), Vec2.zero(), noMouse());
        Assert.assertEq(expected = (Set#{GameEngine.Key.Left}, Set#{}, 0.016),
            frameTuple(actual))

    // 離し: 前にあって今無い Left はどちらにも立たない（離しエッジは追わない）。
    @Test
    def testFrameOfReleaseIsSilent(): Unit \ Assert =
        let actual = App.frameOf(prev = Set#{GameEngine.Key.Left}, current = Set#{}, 0.016, testViewport(), Vec2.zero(), noMouse());
        Assert.assertEq(expected = (Set#{}, Set#{}, 0.016),
            frameTuple(actual))

    // 混在: 押しっぱなしの Left と新規の Space が並ぶと、エッジは Space だけ。
    @Test
    def testFrameOfMixedKeysSplitEdges(): Unit \ Assert =
        let actual = App.frameOf(
            prev = Set#{GameEngine.Key.Left},
            current = Set#{GameEngine.Key.Left, GameEngine.Key.Space}, 0.016, testViewport(), Vec2.zero(), noMouse());
        Assert.assertEq(
            expected = (Set#{GameEngine.Key.Left, GameEngine.Key.Space}, Set#{GameEngine.Key.Space}, 0.016),
            frameTuple(actual))

    // ========================================================================
    // frameOf: マウスのエッジ判定（キーと同じ考え方）
    // ========================================================================

    // 新規押下: 前に離れていて今押されていれば mouseDown と mouseClicked の両方が立つ。
    // cursor は素通し。
    @Test
    def testFrameOfMousePressIsEdge(): Unit \ Assert =
        let actual = App.frameOf(prev = Set#{}, current = Set#{}, 0.016, testViewport(),
            { x = 10.0, y = 20.0 }, { prevDown = false, down = true });
        Assert.assertEq(expected = (true, true, (10.0, 20.0)),
            (actual#mouseDown, actual#mouseClicked, (actual#cursor#x, actual#cursor#y)))

    // 押しっぱなし: 前も今も押されていれば mouseDown のみ（クリックのエッジは立たない）。
    @Test
    def testFrameOfHeldMouseIsNotEdge(): Unit \ Assert =
        let actual = App.frameOf(prev = Set#{}, current = Set#{}, 0.016, testViewport(),
            Vec2.zero(), { prevDown = true, down = true });
        Assert.assertEq(expected = (true, false), (actual#mouseDown, actual#mouseClicked))

    // 離し: どちらも立たない。
    @Test
    def testFrameOfMouseReleaseIsSilent(): Unit \ Assert =
        let actual = App.frameOf(prev = Set#{}, current = Set#{}, 0.016, testViewport(),
            Vec2.zero(), { prevDown = true, down = false });
        Assert.assertEq(expected = (false, false), (actual#mouseDown, actual#mouseClicked))

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
        let frameWith = keys -> App.frameOf(prev = keys, current = keys, 0.016, testViewport(), Vec2.zero(), noMouse());
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
        let composed = App.composeScene(None, 1.0, sceneDesign(),
            { world = boxAtOrigin() :: Nil, hud = boxAtOrigin() :: Nil });
        Assert.assertEq(expected = (2, Some((0.0, 0.0))), (List.length(composed), atOf(composed)))

    // camera あり: world の絵だけがずれ（原点は design/2 - center へ）、hud は不動のまま。
    @Test
    def testComposeSceneShiftsWorldButNotHud(): Unit \ Assert =
        let composed = App.composeScene(Some({ x = 100.0, y = 50.0 }), 1.0, sceneDesign(),
            { world = boxAtOrigin() :: Nil, hud = boxAtOrigin() :: Nil });
        let hudAt = List.head(List.drop(1, composed)) |> Option.map(p -> (p#at#x, p#at#y));
        Assert.assertEq(expected = (Some((60.0, 70.0)), Some((0.0, 0.0))), (atOf(composed), hudAt))

    // center に置いた item は画面中央 design/2 に着地する（round-trip）。
    @Test
    def testComposeSceneLandsCenterAtMiddle(): Unit \ Assert =
        let center = { x = 100.0, y = 50.0 };
        let onCenter = { at = center | boxAtOrigin() };
        let composed = App.composeScene(Some(center), 1.0, sceneDesign(),
            { world = onCenter :: Nil, hud = Nil });
        Assert.assertEq(expected = Some((160.0, 120.0)), atOf(composed))

    // ========================================================================
    // composeScene / visibleOf: 寄り引き（zoom ≠ 1）の合成
    // ========================================================================

    // zoom 2 倍: center に置いた item は画面中央に着地したまま、Box の大きさは 2 倍になる。
    @Test
    def testComposeSceneAtZoomTwoScalesAroundCenter(): Unit \ Assert =
        let center = { x = 100.0, y = 50.0 };
        let onCenter = { at = center | boxAtOrigin() };
        let composed = App.composeScene(Some(center), 2.0, sceneDesign(),
            { world = onCenter :: Nil, hud = Nil });
        let size = match List.head(composed) |> Option.map(p -> p#item) {
            case Some(Render.Item.Box(b)) => (b#size#x, b#size#y)
            case _                        => bug!("composeScene の先頭は Box のはず")
        };
        Assert.assertEq(expected = (Some((160.0, 120.0)), (2.0, 2.0)), (atOf(composed), size))

    // zoom 2 倍: center から (10, 0) 離れた item は画面中央から (20, 0) 離れて着地する。
    @Test
    def testComposeSceneAtZoomTwoScalesOffsets(): Unit \ Assert =
        let center = { x = 100.0, y = 50.0 };
        let offCenter = { at = { x = 110.0, y = 50.0 } | boxAtOrigin() };
        let composed = App.composeScene(Some(center), 2.0, sceneDesign(),
            { world = offCenter :: Nil, hud = Nil });
        Assert.assertEq(expected = Some((180.0, 120.0)), atOf(composed))

    // camera 無し（center = None）でも zoom ≠ 1 なら画面中央 design/2 を軸に寄る:
    // 中央 (160,120) に置いた item は動かず、Box の大きさだけ 2 倍になる（zoom の黙殺はしない）。
    @Test
    def testComposeSceneAtZoomTwoWithoutCameraZoomsAroundScreenCenter(): Unit \ Assert =
        let onMiddle = { at = { x = 160.0, y = 120.0 } | boxAtOrigin() };
        let composed = App.composeScene(None, 2.0, sceneDesign(),
            { world = onMiddle :: Nil, hud = Nil });
        let size = match List.head(composed) |> Option.map(p -> p#item) {
            case Some(Render.Item.Box(b)) => (b#size#x, b#size#y)
            case _                        => bug!("composeScene の先頭は Box のはず")
        };
        Assert.assertEq(expected = (Some((160.0, 120.0)), (2.0, 2.0)), (atOf(composed), size))

    // 同じ規則が可視範囲にも効く: camera 無し + zoom 2 は design/2 中心の 160×120。
    @Test
    def testVisibleOfAtZoomTwoWithoutCameraCentersOnScreen(): Unit \ Assert =
        let visible = App.visibleOf(None, 2.0, sceneDesign());
        Assert.assertEq(expected = ((80.0, 60.0), (160.0, 120.0)),
            ((visible#position#x, visible#position#y), (visible#size#x, visible#size#y)))

    // zoom 2 倍の可視範囲: 大きさは design の半分（160×120）で、center を中心に据える。
    @Test
    def testVisibleOfAtZoomTwoShrinksSeenRect(): Unit \ Assert =
        let visible = App.visibleOf(Some({ x = 100.0, y = 50.0 }), 2.0, sceneDesign());
        Assert.assertEq(expected = ((20.0, -10.0), (160.0, 120.0)),
            ((visible#position#x, visible#position#y), (visible#size#x, visible#size#y)))

    // ========================================================================
    // visibleOf: ViewCtx の visible（見えている world 矩形）の源
    // ========================================================================

    // camera なし: 原点起点の design 全体が見えている。
    @Test
    def testVisibleOfWithoutCameraIsDesignRect(): Unit \ Assert =
        let visible = App.visibleOf(None, 1.0, sceneDesign());
        Assert.assertEq(expected = ((0.0, 0.0), (320.0, 240.0)),
            ((visible#position#x, visible#position#y), (visible#size#x, visible#size#y)))

    // camera あり: center − design/2 を左上とする design 大の矩形。
    // composeScene のずらし（testComposeSceneShiftsWorldButNotHud と同じ center）と表裏一体。
    @Test
    def testVisibleOfWithCameraCentersRect(): Unit \ Assert =
        let visible = App.visibleOf(Some({ x = 100.0, y = 50.0 }), 1.0, sceneDesign());
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
        let frame = App.frameOf(prev = Set#{}, current = Set#{GameEngine.Key.Escape}, 0.016, testViewport(), Vec2.zero(), noMouse());
        let wantsQuit = App.make(0)#quit;
        Assert.assertEq(expected = true, wantsQuit(frame, 0))

    // 押しっぱなしの Escape では終了しない（起動時に押されていたキーの誤発火を防ぐ）。
    @Test
    def testQuitDefaultIgnoresHeldEscape(): Unit \ Assert =
        let frame = App.frameOf(
            prev = Set#{GameEngine.Key.Escape}, current = Set#{GameEngine.Key.Escape}, 0.016, testViewport(), Vec2.zero(), noMouse());
        let wantsQuit = App.make(0)#quit;
        Assert.assertEq(expected = false, wantsQuit(frame, 0))

    // quitWhen は判定を丸ごと差し替える（World も見られる）。
    @Test
    def testQuitWhenReplacesJudge(): Unit \ Assert =
        let app = App.make(9) |> App.quitWhen((_frame, n) -> n == 9);
        let wantsQuit = app#quit;
        Assert.assertEq(expected = true, wantsQuit(emptyFrame(), 9))
}
