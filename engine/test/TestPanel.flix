/// NineSlice ノード（Godot NineSlice + StyleBoxFlat 相当）の挙動テスト。
/// 背景のみ、枠線つき、setter/getter のラウンドトリップ、toDrawables の枚数を検証する。
mod TestPanel {

    def black(): Color = {r = 0.0f32, g = 0.0f32, b = 0.0f32}
    def white(): Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}

    /// borderWidth=0 のときは toDrawables が背景 1 枚だけを返す
    @Test
    def testToDrawablesBackgroundOnly(): Unit \ Assert =
        let panel = NineSlice.make({x = 100.0, y = 50.0}, black());
        let drawables = NineSlice.toDrawables(panel, {x = 0.0, y = 0.0});
        Assert.assertEq(expected = 1, List.length(drawables))

    /// borderWidth > 0 のときは toDrawables が背景 + 枠線 4 辺 = 計 5 枚を返す
    @Test
    def testToDrawablesWithBorder(): Unit \ Assert =
        let panel = NineSlice.make({x = 100.0, y = 50.0}, black())
            |> NineSlice.setBorderColor(white())
            |> NineSlice.setBorderWidth(2.0);
        let drawables = NineSlice.toDrawables(panel, {x = 0.0, y = 0.0});
        Assert.assertEq(expected = 5, List.length(drawables))

    /// 負の borderWidth は 0 にクランプされる
    @Test
    def testSetBorderWidthClampsNegative(): Unit \ Assert =
        let panel = NineSlice.make({x = 100.0, y = 50.0}, black())
            |> NineSlice.setBorderWidth(-5.0);
        Assert.assertEq(expected = 0.0, NineSlice.getBorderWidth(panel))

    /// 背景色の round-trip
    @Test
    def testBackgroundColorRoundtrip(): Unit \ Assert =
        let panel = NineSlice.make({x = 10.0, y = 10.0}, black())
            |> NineSlice.setBackgroundColor(white());
        Assert.assertEq(expected = 1.0f32, NineSlice.getBackgroundColor(panel)#r)

    /// borderWidth round-trip
    @Test
    def testBorderWidthRoundtrip(): Unit \ Assert =
        let panel = NineSlice.make({x = 10.0, y = 10.0}, black())
            |> NineSlice.setBorderWidth(4.0);
        Assert.assertEq(expected = 4.0, NineSlice.getBorderWidth(panel))

    /// size round-trip
    @Test
    def testSizeRoundtrip(): Unit \ Assert =
        let panel = NineSlice.make({x = 100.0, y = 50.0}, black())
            |> NineSlice.setSize({x = 200.0, y = 80.0});
        Assert.assertEq(expected = 200.0, NineSlice.getSize(panel)#x);
        Assert.assertEq(expected = 80.0, NineSlice.getSize(panel)#y)

    /// cornerRadius round-trip（負はクランプ）
    @Test
    def testCornerRadiusRoundtrip(): Unit \ Assert =
        let panel = NineSlice.make({x = 10.0, y = 10.0}, black())
            |> NineSlice.setCornerRadius(4.0);
        Assert.assertEq(expected = 4.0, NineSlice.getCornerRadius(panel))

    /// cornerRadius=0（既定）は従来どおり: 枠なし→1枚, 枠あり→5枚, style=None。
    @Test
    def testCornerRadiusZeroUsesLegacyRects(): Unit \ Assert =
        let p0 = NineSlice.make({x = 100.0, y = 50.0}, black());
        let p5 = NineSlice.make({x = 100.0, y = 50.0}, black())
            |> NineSlice.setBorderColor(white()) |> NineSlice.setBorderWidth(2.0);
        let d0 = NineSlice.toDrawables(p0, {x = 0.0, y = 0.0});
        let d5 = NineSlice.toDrawables(p5, {x = 0.0, y = 0.0});
        let firstStyleNone = match List.head(d0) {
            case Some(d) => Option.isEmpty(d#style)
            case None    => false
        };
        Assert.assertEq(
            expected = (1, 5, true),
            (List.length(d0), List.length(d5), firstStyleNone))

    /// cornerRadius>0 は styled Drawable 1 枚（style=Some, 塗り色/枠が一致）を返す。
    @Test
    def testCornerRadiusEmitsStyledDrawable(): Unit \ Assert =
        let panel = NineSlice.make({x = 100.0, y = 50.0}, black())
            |> NineSlice.setBorderColor(white()) |> NineSlice.setBorderWidth(2.0)
            |> NineSlice.setCornerRadius(6.0);
        let drawables = NineSlice.toDrawables(panel, {x = 0.0, y = 0.0});
        let info = match List.head(drawables) {
            case Some(d) => match d#style {
                case Some(st) => (List.length(drawables), st#cornerRadius, st#borderWidth)
                case None     => (-1, -1.0, -1.0)
            }
            case None => (-1, -1.0, -1.0)
        };
        Assert.assertEq(expected = (1, 6.0, 2.0), info)

    /// cornerRadius>0 の styled Drawable に、背景色/α は Drawable 本体へ、枠色/α は style へ
    /// 正しく流れていること（色の流路の取り違え防止）。
    @Test
    def testCornerRadiusStyleCarriesColors(): Unit \ Assert =
        let bg = {r = 0.2f32, g = 0.3f32, b = 0.4f32};
        let border = {r = 0.9f32, g = 0.8f32, b = 0.7f32};
        let panel = NineSlice.make({x = 100.0, y = 50.0}, bg)
            |> NineSlice.setBackgroundAlpha(0.8f32)
            |> NineSlice.setBorderColor(border)
            |> NineSlice.setBorderAlpha(0.5f32)
            |> NineSlice.setBorderWidth(2.0)
            |> NineSlice.setCornerRadius(6.0);
        let info = match List.head(NineSlice.toDrawables(panel, {x = 0.0, y = 0.0})) {
            case Some(d) => match d#style {
                case Some(st) => (d#color#r, d#alpha, st#borderColor#r, st#borderAlpha)
                case None     => (-1.0f32, -1.0f32, -1.0f32, -1.0f32)
            }
            case None => (-1.0f32, -1.0f32, -1.0f32, -1.0f32)
        };
        Assert.assertEq(expected = (0.2f32, 0.8f32, 0.9f32, 0.5f32), info)
}
