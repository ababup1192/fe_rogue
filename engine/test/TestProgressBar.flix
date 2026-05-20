/// ProgressBar ノード（Godot ProgressBar + Range 相当）の挙動テスト。
/// Range のクランプ、4 fillMode の塗り位置・サイズ、toDrawables の枚数を検証する。
mod TestProgressBar {

    def black(): Color = {r = 0.0f32, g = 0.0f32, b = 0.0f32}
    def white(): Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}
    def green(): Color = {r = 0.0f32, g = 1.0f32, b = 0.0f32}

    /// borderWidth=0 のときは toDrawables が背景 + 塗り = 計 2 枚を返す
    @Test
    def testToDrawablesNoBorder(): Unit \ Assert =
        let bar = ProgressBar.make({x = 100.0, y = 10.0}, 100.0, green())
            |> ProgressBar.setValue(50.0);
        let drawables = ProgressBar.toDrawables(bar, {x = 0.0, y = 0.0});
        Assert.assertEq(expected = 2, List.length(drawables))

    /// borderWidth > 0 のときは toDrawables が背景 + 塗り + 枠線 4 辺 = 計 6 枚
    @Test
    def testToDrawablesWithBorder(): Unit \ Assert =
        let bar = ProgressBar.make({x = 100.0, y = 10.0}, 100.0, green())
            |> ProgressBar.setBorderColor(white())
            |> ProgressBar.setBorderWidth(1)
            |> ProgressBar.setValue(50.0);
        let drawables = ProgressBar.toDrawables(bar, {x = 0.0, y = 0.0});
        Assert.assertEq(expected = 6, List.length(drawables))

    /// border の内側に fill が inset される: full HP でも fill は (1,1)-(99,9) 内側にとどまる
    @Test
    def testFillInsetInsideBorder(): Unit \ Assert =
        let bar = ProgressBar.make({x = 100.0, y = 10.0}, 100.0, green())
            |> ProgressBar.setBorderWidth(1)
            |> ProgressBar.setValue(100.0);
        let drawables = ProgressBar.toDrawables(bar, {x = 0.0, y = 0.0});
        let fill = match List.nth(1, drawables) {
            case Some(d) => d
            case None    => unreachable!()
        };
        // fill は border 1px ぶん内側からスタート
        Assert.assertEq(expected = 1.0, fill#position#x);
        Assert.assertEq(expected = 1.0, fill#position#y);
        // 内側サイズは 100-2=98, 10-2=8
        Assert.assertEq(expected = 98.0, fill#scale#x);
        Assert.assertEq(expected = 8.0, fill#scale#y)

    /// `setValue(max+1)` は max にクランプされる
    @Test
    def testValueClampedToMax(): Unit \ Assert =
        let bar = ProgressBar.make({x = 100.0, y = 10.0}, 100.0, green())
            |> ProgressBar.setValue(150.0);
        Assert.assertEq(expected = 100.0, ProgressBar.getValue(bar))

    /// `setValue(min-1)` は min にクランプされる
    @Test
    def testValueClampedToMin(): Unit \ Assert =
        let bar = ProgressBar.make({x = 100.0, y = 10.0}, 100.0, green())
            |> ProgressBar.setMinValue(10.0)
            |> ProgressBar.setValue(0.0);
        Assert.assertEq(expected = 10.0, ProgressBar.getValue(bar))

    /// `min == max` のとき塗りは 0 幅でゼロ割落ちしない（2 枚返る）
    @Test
    def testZeroRangeNoDivByZero(): Unit \ Assert =
        let bar = ProgressBar.make({x = 100.0, y = 10.0}, 100.0, green())
            |> ProgressBar.setMinValue(100.0)
            |> ProgressBar.setValue(100.0);
        let drawables = ProgressBar.toDrawables(bar, {x = 0.0, y = 0.0});
        // 2 枚（背景 + 塗り（0 幅））返る
        Assert.assertEq(expected = 2, List.length(drawables));
        // 塗りの scale.x が 0
        let fill = match List.nth(1, drawables) {
            case Some(d) => d
            case None    => unreachable!()
        };
        Assert.assertEq(expected = 0.0, fill#scale#x)

    /// fillMode=LeftToRight, value=50/max=100 で塗り矩形の scale.x が size.x * 0.5
    @Test
    def testFillModeLeftToRight(): Unit \ Assert =
        let bar = ProgressBar.make({x = 100.0, y = 10.0}, 100.0, green())
            |> ProgressBar.setValue(50.0);
        let drawables = ProgressBar.toDrawables(bar, {x = 0.0, y = 0.0});
        let fill = match List.nth(1, drawables) {
            case Some(d) => d
            case None    => unreachable!()
        };
        Assert.assertEq(expected = 0.0, fill#position#x);
        Assert.assertEq(expected = 50.0, fill#scale#x);
        Assert.assertEq(expected = 10.0, fill#scale#y)

    /// fillMode=RightToLeft で value=25/max=100 → 塗りは右側 25px、左端 = 75
    @Test
    def testFillModeRightToLeft(): Unit \ Assert =
        let bar = ProgressBar.make({x = 100.0, y = 10.0}, 100.0, green())
            |> ProgressBar.setFillMode(FillMode.RightToLeft)
            |> ProgressBar.setValue(25.0);
        let drawables = ProgressBar.toDrawables(bar, {x = 0.0, y = 0.0});
        let fill = match List.nth(1, drawables) {
            case Some(d) => d
            case None    => unreachable!()
        };
        Assert.assertEq(expected = 75.0, fill#position#x);
        Assert.assertEq(expected = 25.0, fill#scale#x)

    /// fillMode=BottomToTop で value=50/max=100 → 塗りは下半分（pos.y = h/2、scale.y = h/2）
    @Test
    def testFillModeBottomToTop(): Unit \ Assert =
        let bar = ProgressBar.make({x = 8.0, y = 100.0}, 100.0, green())
            |> ProgressBar.setFillMode(FillMode.BottomToTop)
            |> ProgressBar.setValue(50.0);
        let drawables = ProgressBar.toDrawables(bar, {x = 0.0, y = 0.0});
        let fill = match List.nth(1, drawables) {
            case Some(d) => d
            case None    => unreachable!()
        };
        Assert.assertEq(expected = 50.0, fill#position#y);
        Assert.assertEq(expected = 50.0, fill#scale#y)

    /// fillMode=TopToBottom で value=25/max=100 → 塗りは上 25px（pos.y=0、scale.y=25）
    @Test
    def testFillModeTopToBottom(): Unit \ Assert =
        let bar = ProgressBar.make({x = 8.0, y = 100.0}, 100.0, green())
            |> ProgressBar.setFillMode(FillMode.TopToBottom)
            |> ProgressBar.setValue(25.0);
        let drawables = ProgressBar.toDrawables(bar, {x = 0.0, y = 0.0});
        let fill = match List.nth(1, drawables) {
            case Some(d) => d
            case None    => unreachable!()
        };
        Assert.assertEq(expected = 0.0, fill#position#y);
        Assert.assertEq(expected = 25.0, fill#scale#y)

    /// 負の borderWidth は 0 にクランプされる（Panel と同じ振る舞い）
    @Test
    def testSetBorderWidthClampsNegative(): Unit \ Assert =
        let bar = ProgressBar.make({x = 100.0, y = 10.0}, 100.0, green())
            |> ProgressBar.setBorderWidth(-5);
        Assert.assertEq(expected = 0, ProgressBar.getBorderWidth(bar))

    /// value round-trip
    @Test
    def testValueRoundtrip(): Unit \ Assert =
        let bar = ProgressBar.make({x = 100.0, y = 10.0}, 100.0, green())
            |> ProgressBar.setValue(42.0);
        Assert.assertEq(expected = 42.0, ProgressBar.getValue(bar))

    /// minValue / maxValue round-trip
    @Test
    def testMinMaxRoundtrip(): Unit \ Assert =
        let bar = ProgressBar.make({x = 100.0, y = 10.0}, 100.0, green())
            |> ProgressBar.setMinValue(10.0)
            |> ProgressBar.setMaxValue(50.0);
        Assert.assertEq(expected = 10.0, ProgressBar.getMinValue(bar));
        Assert.assertEq(expected = 50.0, ProgressBar.getMaxValue(bar))

    /// setMaxValue で現在値が新しい max を上回ったら一緒に切り下がる
    @Test
    def testSetMaxValueClampsCurrentValue(): Unit \ Assert =
        let bar = ProgressBar.make({x = 100.0, y = 10.0}, 100.0, green())
            |> ProgressBar.setValue(80.0)
            |> ProgressBar.setMaxValue(50.0);
        Assert.assertEq(expected = 50.0, ProgressBar.getValue(bar))

    /// setMinValue で現在値が新しい min を下回ったら一緒に引き上がる
    @Test
    def testSetMinValueRaisesCurrentValue(): Unit \ Assert =
        let bar = ProgressBar.make({x = 100.0, y = 10.0}, 100.0, green())
            |> ProgressBar.setValue(5.0)
            |> ProgressBar.setMinValue(20.0);
        Assert.assertEq(expected = 20.0, ProgressBar.getValue(bar))

    /// fillColor round-trip
    @Test
    def testFillColorRoundtrip(): Unit \ Assert =
        let bar = ProgressBar.make({x = 10.0, y = 10.0}, 100.0, black())
            |> ProgressBar.setFillColor(green());
        Assert.assertEq(expected = 1.0f32, ProgressBar.getFillColor(bar)#g)

    /// fillMode round-trip
    @Test
    def testFillModeRoundtrip(): Unit \ Assert =
        let bar = ProgressBar.make({x = 10.0, y = 10.0}, 100.0, green())
            |> ProgressBar.setFillMode(FillMode.TopToBottom);
        Assert.assertEq(expected = FillMode.TopToBottom, ProgressBar.getFillMode(bar))

    /// size round-trip
    @Test
    def testSizeRoundtrip(): Unit \ Assert =
        let bar = ProgressBar.make({x = 100.0, y = 10.0}, 100.0, green())
            |> ProgressBar.setSize({x = 200.0, y = 20.0});
        Assert.assertEq(expected = 200.0, ProgressBar.getSize(bar)#x);
        Assert.assertEq(expected = 20.0, ProgressBar.getSize(bar)#y)

    /// tickInterval=0（デフォルト）なら tick は描画されない（背景 + 塗り = 2 枚のまま）
    @Test
    def testNoTicksWhenIntervalZero(): Unit \ Assert =
        let bar = ProgressBar.make({x = 100.0, y = 10.0}, 100.0, green());
        let drawables = ProgressBar.toDrawables(bar, {x = 0.0, y = 0.0});
        Assert.assertEq(expected = 2, List.length(drawables))

    /// max=10, interval=2, value=max → tick 値は 2, 4, 6, 8 の 4 本（borderWidth=0 → 2 + 4 = 6 枚）
    /// tick は fill 領域のみ描画されるので value を max にして全 tick を可視化する
    @Test
    def testTickCountFromInterval(): Unit \ Assert =
        let bar = ProgressBar.make({x = 100.0, y = 10.0}, 10.0, green())
            |> ProgressBar.setTickInterval(2.0)
            |> ProgressBar.setValue(10.0);
        let drawables = ProgressBar.toDrawables(bar, {x = 0.0, y = 0.0});
        // 背景 1 + 塗り 1 + tick 4 = 6
        Assert.assertEq(expected = 6, List.length(drawables))

    /// border + tick の組み合わせ。max=10, interval=5, value=max, borderWidth=1
    /// → bg 1 + fill 1 + tick 1 (v=5) + border 4 = 7
    @Test
    def testTickWithBorderCount(): Unit \ Assert =
        let bar = ProgressBar.make({x = 100.0, y = 10.0}, 10.0, green())
            |> ProgressBar.setTickInterval(5.0)
            |> ProgressBar.setBorderWidth(1)
            |> ProgressBar.setValue(10.0);
        let drawables = ProgressBar.toDrawables(bar, {x = 0.0, y = 0.0});
        Assert.assertEq(expected = 7, List.length(drawables))

    /// LeftToRight, max=10, interval=5, value=max → tick (v=5) は
    /// inner 中央 (x=50.0) を中央寄せした位置 (x=49.5) に置かれる
    @Test
    def testTickPositionLeftToRight(): Unit \ Assert =
        let bar = ProgressBar.make({x = 100.0, y = 10.0}, 10.0, green())
            |> ProgressBar.setTickInterval(5.0)
            |> ProgressBar.setValue(10.0);
        let drawables = ProgressBar.toDrawables(bar, {x = 0.0, y = 0.0});
        // 順序: bg, fill, tick_1
        let tick = match List.nth(2, drawables) {
            case Some(d) => d
            case None    => unreachable!()
        };
        Assert.assertEq(expected = 49.5, tick#position#x);
        Assert.assertEq(expected = 1.0, tick#scale#x);
        Assert.assertEq(expected = 10.0, tick#scale#y)

    /// tick は value 未満の位置のみ描画される（empty 領域には描画しない）。
    /// max=10, interval=1, value=3 → tickValues=[1,2,...,9] のうち v<3 のみ → 2 ticks
    @Test
    def testTicksClippedToFillArea(): Unit \ Assert =
        let bar = ProgressBar.make({x = 100.0, y = 10.0}, 10.0, green())
            |> ProgressBar.setTickInterval(1.0)
            |> ProgressBar.setValue(3.0);
        let drawables = ProgressBar.toDrawables(bar, {x = 0.0, y = 0.0});
        // 背景 1 + 塗り 1 + tick 2 (v=1, v=2) = 4
        Assert.assertEq(expected = 4, List.length(drawables))

    /// value=0 のとき tick は 1 つも描画されない（empty bar）
    @Test
    def testNoTicksWhenValueZero(): Unit \ Assert =
        let bar = ProgressBar.make({x = 100.0, y = 10.0}, 10.0, green())
            |> ProgressBar.setTickInterval(1.0);  // value=0 が make デフォルト
        let drawables = ProgressBar.toDrawables(bar, {x = 0.0, y = 0.0});
        Assert.assertEq(expected = 2, List.length(drawables))

    /// tickInterval round-trip
    @Test
    def testTickIntervalRoundtrip(): Unit \ Assert =
        let bar = ProgressBar.make({x = 100.0, y = 10.0}, 100.0, green())
            |> ProgressBar.setTickInterval(5.0);
        Assert.assertEq(expected = 5.0, ProgressBar.getTickInterval(bar))

    /// 負の tickWidth は 0 にクランプ
    @Test
    def testSetTickWidthClampsNegative(): Unit \ Assert =
        let bar = ProgressBar.make({x = 100.0, y = 10.0}, 100.0, green())
            |> ProgressBar.setTickWidth(-3);
        Assert.assertEq(expected = 0, ProgressBar.getTickWidth(bar))

    /// tickWidth=0 のときは tick が描画されない（interval > 0 でも）
    @Test
    def testTickWidthZeroSkipsRender(): Unit \ Assert =
        let bar = ProgressBar.make({x = 100.0, y = 10.0}, 10.0, green())
            |> ProgressBar.setTickInterval(2.0)
            |> ProgressBar.setTickWidth(0);
        let drawables = ProgressBar.toDrawables(bar, {x = 0.0, y = 0.0});
        Assert.assertEq(expected = 2, List.length(drawables))
}
