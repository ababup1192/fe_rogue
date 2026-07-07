// TestApp — App の純粋な芯を具体値で固定する: frameOf のエッジ判定（新規押下だけが
// justPressed に立ち、押しっぱなし・離しは立たない）と、applySystems の適用順（追加順 =
// 左から右。+1 して ×2 なら 2、逆なら 1 なので順序が数字に出る）。
// Frame は record なので、比較はタプルへ射影して行う（TestBreakout と同じ流儀）。

mod TestApp {

    /// Frame を比較できるタプル (down, justPressed, dt) へ射影する。
    def frameTuple(frame: App.Frame): (Set[GameEngine.Key], Set[GameEngine.Key], Float64) =
        (frame#down, frame#justPressed, frame#dt)

    // ========================================================================
    // frameOf: エッジ判定
    // ========================================================================

    // 新規押下: 前に無く今ある Left は down にも justPressed にも立つ。dt は素通し。
    @Test
    def testFrameOfNewPressIsEdge(): Unit \ Assert =
        let actual = App.frameOf(prev = Set#{}, current = Set#{GameEngine.Key.Left}, 0.016);
        Assert.assertEq(expected = (Set#{GameEngine.Key.Left}, Set#{GameEngine.Key.Left}, 0.016),
            frameTuple(actual))

    // 押しっぱなし: 前も今もある Left は down のまま、justPressed には立たない。
    @Test
    def testFrameOfHeldKeyIsNotEdge(): Unit \ Assert =
        let actual = App.frameOf(prev = Set#{GameEngine.Key.Left}, current = Set#{GameEngine.Key.Left}, 0.016);
        Assert.assertEq(expected = (Set#{GameEngine.Key.Left}, Set#{}, 0.016),
            frameTuple(actual))

    // 離し: 前にあって今無い Left はどちらにも立たない（離しエッジは追わない）。
    @Test
    def testFrameOfReleaseIsSilent(): Unit \ Assert =
        let actual = App.frameOf(prev = Set#{GameEngine.Key.Left}, current = Set#{}, 0.016);
        Assert.assertEq(expected = (Set#{}, Set#{}, 0.016),
            frameTuple(actual))

    // 混在: 押しっぱなしの Left と新規の Space が並ぶと、エッジは Space だけ。
    @Test
    def testFrameOfMixedKeysSplitEdges(): Unit \ Assert =
        let actual = App.frameOf(
            prev = Set#{GameEngine.Key.Left},
            current = Set#{GameEngine.Key.Left, GameEngine.Key.Space}, 0.016);
        Assert.assertEq(
            expected = (Set#{GameEngine.Key.Left, GameEngine.Key.Space}, Set#{GameEngine.Key.Space}, 0.016),
            frameTuple(actual))

    // ========================================================================
    // applySystems: 追加順 = 適用順
    // ========================================================================

    /// 順序テスト用の Frame（キー無し・dt 0）。
    def emptyFrame(): App.Frame =
        App.frameOf(prev = Set#{}, current = Set#{}, 0.0)

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
    // Controls.inputOf: Frame → Input の写像（連続とエッジの区別）
    // ========================================================================

    /// Input を比較できるタプル (left, right, launch, enter) へ射影する。
    def inputTuple(input: Field.Input): (Bool, Bool, Bool, Bool) =
        (input#left, input#right, input#launch, input#enter)

    // 押しっぱなしの Left/Space/Enter: 移動の left は立つが、エッジ待ちの launch/enter は立たない。
    @Test
    def testInputOfHeldKeys(): Unit \ Assert =
        let held = Set#{GameEngine.Key.Left, GameEngine.Key.Space, GameEngine.Key.Enter};
        let frame = App.frameOf(prev = held, current = held, 0.016);
        Assert.assertEq(expected = (true, false, false, false), inputTuple(Controls.inputOf(frame)))

    // 新規押下の Right/Space/Enter: 全部このフレームで意味を持つ（right は連続・launch/enter はエッジ）。
    @Test
    def testInputOfFreshKeys(): Unit \ Assert =
        let frame = App.frameOf(
            prev = Set#{},
            current = Set#{GameEngine.Key.Right, GameEngine.Key.Space, GameEngine.Key.Enter}, 0.016);
        Assert.assertEq(expected = (false, true, true, true), inputTuple(Controls.inputOf(frame)))

    // 何も押されていなければ noInput と同じ。
    @Test
    def testInputOfNoKeysIsNoInput(): Unit \ Assert =
        Assert.assertEq(expected = inputTuple(Field.noInput()),
            inputTuple(Controls.inputOf(emptyFrame())))
}
