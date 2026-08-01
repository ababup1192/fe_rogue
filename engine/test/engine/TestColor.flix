// TestColor — hsv の性質を具体値で固定する: 三原色の位置（h = 0 / 1/3 / 2/3）、
// 彩度ゼロの無彩色化、色相の折り返し。
mod TestColor {

    /// 明暗の両端と中央で、白または黒へ指定した割合だけ近づく。
    @Test
    def testLightenAndDarkenAtKeyAmounts(): Unit \ Assert =
        let color = { r = 0.25f32, g = 0.5f32, b = 0.75f32 };
        let channels = value -> (value#r, value#g, value#b);
        Assert.assertEq(
            expected = ((0.25f32, 0.5f32, 0.75f32),
                        (0.625f32, 0.75f32, 0.875f32),
                        (1.0f32, 1.0f32, 1.0f32),
                        (0.25f32, 0.5f32, 0.75f32),
                        (0.125f32, 0.25f32, 0.375f32),
                        (0.0f32, 0.0f32, 0.0f32)),
            (channels(Color.lighten(color, 0.0)),
             channels(Color.lighten(color, 0.5)),
             channels(Color.lighten(color, 1.0)),
             channels(Color.darken(color, 0.0)),
             channels(Color.darken(color, 0.5)),
             channels(Color.darken(color, 1.0))))

    /// 範囲外のamountを補正せず、既存ゲームと同じ式をそのまま延長する。
    @Test
    def testLightenAndDarkenDoNotClampAmount(): Unit \ Assert =
        let color = { r = 0.25f32, g = 0.5f32, b = 0.75f32 };
        let light = Color.lighten(color, -1.0);
        let dark = Color.darken(color, 2.0);
        Assert.assertEq(
            expected = ((-0.5f32, 0.0f32, 0.5f32),
                        (-0.25f32, -0.5f32, -0.75f32)),
            ((light#r, light#g, light#b), (dark#r, dark#g, dark#b)))

    /// lightenはamountを、darkenはFloat64で求めた残りをFloat32へ変えてから各色へ使う。
    @Test
    def testLightenAndDarkenKeepFloatConversionOrder(): Unit \ Assert =
        let color = { r = 0.01f32, g = 0.6f32, b = 0.9f32 };
        let amount = 0.6;
        let value = Float64.truncateToFloat32(amount);
        let remaining = Float64.truncateToFloat32(1.0 - amount);
        let light = Color.lighten(color, amount);
        let dark = Color.darken(color, amount);
        Assert.assertEq(
            expected = (color#r + (1.0f32 - color#r) * value,
                        color#g + (1.0f32 - color#g) * value,
                        color#b + (1.0f32 - color#b) * value,
                        color#r * remaining,
                        color#g * remaining,
                        color#b * remaining),
            (light#r, light#g, light#b, dark#r, dark#g, dark#b))

    @Test
    def testHsvHitsPrimariesGreysAndWraps(): Unit \ Assert =
        // h=0 は赤・1/3 は緑・2/3 は青。s=0 は h によらず灰（v がそのまま3チャンネルに出る）。
        // h は 1 周で折り返すので 1.25 と 0.25 は同じ色。
        let rgb = spec -> { let c = Color.hsv(spec); (c#r, c#g, c#b) };
        Assert.assertEq(
            expected = ((1.0f32, 0.0f32, 0.0f32), (0.0f32, 1.0f32, 0.0f32), (0.0f32, 0.0f32, 1.0f32),
                        (0.5f32, 0.5f32, 0.5f32), rgb({ h = 0.25, s = 1.0, v = 1.0 })),
            (rgb({ h = 0.0, s = 1.0, v = 1.0 }),
             rgb({ h = 1.0 / 3.0, s = 1.0, v = 1.0 }),
             rgb({ h = 2.0 / 3.0, s = 1.0, v = 1.0 }),
             rgb({ h = 0.5, s = 0.0, v = 0.5 }),
             rgb({ h = 1.25, s = 1.0, v = 1.0 })))

    /// 色見本の書き方 3 通り（0〜1・0〜255・#rrggbb）が同じ色になる。
    @Test
    def testRgbRgb8AndHexAgree(): Unit \ Assert =
        let ch = Color.channels;
        let black = Color.rgb8(0, 0, 0);
        let fromHex = Color.hex("#63b0ff") |> Option.getWithDefault(black);
        Assert.assertEq(expected = (ch(Color.rgb8(99, 176, 255)), ch(Color.rgb8(99, 176, 255))),
            (ch(fromHex), ch(Color.rgb(99.0 / 255.0, 176.0 / 255.0, 1.0))))

    /// # は省略でき、大文字小文字も通る。6 桁でない・16 進でないものは断る。
    @Test
    def testHexAcceptsShapesAndRejectsOthers(): Unit \ Assert =
        let chOf = Option.map(Color.channels);
        Assert.assertEq(expected = (chOf(Color.hex("#63b0ff")), chOf(Color.hex("#ffffff")), None, None),
            (chOf(Color.hex("63b0ff")), chOf(Color.hex("#FFFFFF")),
             chOf(Color.hex("#fff")), chOf(Color.hex("#gggggg"))))

    /// 2 色の間を混ぜる。両端は元の色そのもの。
    @Test
    def testMixHitsBothEndsAndMiddle(): Unit \ Assert =
        let ch = Color.channels;
        let a = Color.rgb8(0, 0, 0);
        let b = Color.rgb8(255, 100, 50);
        Assert.assertEq(expected = (ch(a), ch(b), ch(Color.rgb(0.5, 100.0 / 255.0 * 0.5, 50.0 / 255.0 * 0.5))),
            (ch(Color.mix(a, b, 0.0)), ch(Color.mix(a, b, 1.0)), ch(Color.mix(a, b, 0.5))))
}
