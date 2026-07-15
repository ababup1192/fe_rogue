// TestInputMap — 意図表の芯（firedIn）を具体値で固定する: 同時押しは表の順で全部発火、
// 同じ意図が複数キーで立っても 1 回（重複加算の事故防止）、firstTap は先勝ち。
// Frame 版は taps = justPressed（エッジ）/ held = down（押しっぱなし）を見ることだけ確かめる。
// 軸への合成は InputMap の仕事ではない（ゲームのハンドリング側が fold する）。

mod TestInputMap {

    /// メニュー操作の見本の意図。テストはこの enum を表に載せて運ばれ方を見る。
    enum Menu with Eq, ToString {
        case Confirm
        case Cancel
    }

    /// 移動の見本の意図（held 用）。
    enum Walk with Eq, ToString {
        case WalkLeft
        case WalkRight
        case WalkUp
    }

    /// 決定は Z と Enter の両対応、取消は X。taps 系テスト共通の表。
    def menuTable(): InputMap.Table[Menu] =
        (GameEngine.Key.Z, Menu.Confirm) ::
        (GameEngine.Key.Enter, Menu.Confirm) ::
        (GameEngine.Key.X, Menu.Cancel) :: Nil

    /// WASD と矢印の両対応の移動表（held 系テスト共通）。
    def walkTable(): InputMap.Table[Walk] =
        (GameEngine.Key.A, Walk.WalkLeft) ::
        (GameEngine.Key.Left, Walk.WalkLeft) ::
        (GameEngine.Key.D, Walk.WalkRight) ::
        (GameEngine.Key.Right, Walk.WalkRight) ::
        (GameEngine.Key.W, Walk.WalkUp) ::
        (GameEngine.Key.Up, Walk.WalkUp) :: Nil

    // ========================================================================
    // firedIn: 表 × キー集合 → 意図（順序・重複・未登録・空）
    // ========================================================================

    // Z だけ押せば Confirm が 1 つ。
    @Test
    def testFiredSingleKey(): Unit \ Assert =
        Assert.assertEq(expected = Menu.Confirm :: Nil,
            InputMap.firedIn(menuTable(), Set#{GameEngine.Key.Z}))

    // Enter 押しでも同じ Confirm（同じ意図に複数キー）。
    @Test
    def testFiredAlternateKeySameIntent(): Unit \ Assert =
        Assert.assertEq(expected = Menu.Confirm :: Nil,
            InputMap.firedIn(menuTable(), Set#{GameEngine.Key.Enter}))

    // 同時押しは表の順で全部発火する（Enter と X → Confirm, Cancel の順）。
    @Test
    def testFiredSimultaneousKeysInTableOrder(): Unit \ Assert =
        Assert.assertEq(expected = Menu.Confirm :: Menu.Cancel :: Nil,
            InputMap.firedIn(menuTable(), Set#{GameEngine.Key.X, GameEngine.Key.Enter}))

    // 同じ意図が 2 系統のキーで同時に立っても 1 回だけ（A と ← で二重加速しない）。
    @Test
    def testFiredSameIntentTwiceIsOnce(): Unit \ Assert =
        Assert.assertEq(expected = Walk.WalkLeft :: Nil,
            InputMap.firedIn(walkTable(), Set#{GameEngine.Key.A, GameEngine.Key.Left}))

    // 表に無いキー・無押下は空（移動の fold なら初期値がそのまま残る）。
    @Test
    def testFiredUnmappedOrIdleIsEmpty(): Unit \ Assert =
        Assert.assertEq(
            expected = ((Nil: List[Menu]), (Nil: List[Menu])),
            (InputMap.firedIn(menuTable(), Set#{GameEngine.Key.Space}),
             InputMap.firedIn(menuTable(), Set#{})))

    // WASD と矢印の混在: 別々の意図はそれぞれ出る（軸への合成は呼び側の仕事）。
    @Test
    def testFiredMixesWasdAndArrows(): Unit \ Assert =
        Assert.assertEq(expected = Walk.WalkRight :: Walk.WalkUp :: Nil,
            InputMap.firedIn(walkTable(), Set#{GameEngine.Key.D, GameEngine.Key.Up}))

    // ========================================================================
    // Frame 版: taps = justPressed（エッジ）/ held = down（押しっぱなし）
    // ========================================================================

    def frameOfKeys(prev: Set[GameEngine.Key], current: Set[GameEngine.Key]): App.Frame =
        App.frameOf(prev = prev, current = current, 0.016, { x = 320.0, y = 240.0 },
            { prevCursor = None, cursor = Vec2.zero() }, { prevDown = false, down = false })

    // taps はエッジ: 押しっぱなしでは発火しない。
    @Test
    def testTapsReadJustPressedNotHeld(): Unit \ Assert =
        let frame = frameOfKeys(Set#{GameEngine.Key.Z}, Set#{GameEngine.Key.Z});
        Assert.assertEq(expected = (Nil: List[Menu]), InputMap.taps(menuTable(), frame))

    // held は押しっぱなし: 押し続けている間も出続ける。
    @Test
    def testHeldReadsHeldKeys(): Unit \ Assert =
        let frame = frameOfKeys(Set#{GameEngine.Key.A}, Set#{GameEngine.Key.A});
        Assert.assertEq(expected = Walk.WalkLeft :: Nil, InputMap.held(walkTable(), frame))

    // firstTap は先勝ち（Z は X より表で前 → Confirm）。
    @Test
    def testFirstTapPicksTableOrderWinner(): Unit \ Assert =
        let frame = frameOfKeys(Set#{}, Set#{GameEngine.Key.Z, GameEngine.Key.X});
        Assert.assertEq(expected = Some(Menu.Confirm), InputMap.firstTap(menuTable(), frame))

    // 何も押されていなければ None。
    @Test
    def testFirstTapNoneWhenNothingPressed(): Unit \ Assert =
        let frame = frameOfKeys(Set#{}, Set#{});
        Assert.assertEq(expected = (None: Option[Menu]), InputMap.firstTap(menuTable(), frame))
}
