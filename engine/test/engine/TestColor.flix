// TestColor — hsv の性質を具体値で固定する: 三原色の位置（h = 0 / 1/3 / 2/3）、
// 彩度ゼロの無彩色化、色相の折り返し。
mod TestColor {

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
}
