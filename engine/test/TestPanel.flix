/// Panel ノード（Godot Panel + StyleBoxFlat 相当）の挙動テスト。
/// 背景のみ、枠線つき、setter/getter のラウンドトリップ、toDrawables の枚数を検証する。
mod TestPanel {

    def black(): Color = {r = 0.0f32, g = 0.0f32, b = 0.0f32}
    def white(): Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}

    /// borderWidth=0 のときは toDrawables が背景 1 枚だけを返す
    @Test
    def testToDrawablesBackgroundOnly(): Unit \ Assert =
        let panel = Panel.make({x = 100.0, y = 50.0}, black());
        let drawables = Panel.toDrawables(panel, {x = 0.0, y = 0.0});
        Assert.assertEq(expected = 1, List.length(drawables))

    /// borderWidth > 0 のときは toDrawables が背景 + 枠線 4 辺 = 計 5 枚を返す
    @Test
    def testToDrawablesWithBorder(): Unit \ Assert =
        let panel = Panel.make({x = 100.0, y = 50.0}, black())
            |> Panel.setBorderColor(white())
            |> Panel.setBorderWidth(2);
        let drawables = Panel.toDrawables(panel, {x = 0.0, y = 0.0});
        Assert.assertEq(expected = 5, List.length(drawables))

    /// 負の borderWidth は 0 にクランプされる
    @Test
    def testSetBorderWidthClampsNegative(): Unit \ Assert =
        let panel = Panel.make({x = 100.0, y = 50.0}, black())
            |> Panel.setBorderWidth(-5);
        Assert.assertEq(expected = 0, Panel.getBorderWidth(panel))

    /// 背景色の round-trip
    @Test
    def testBackgroundColorRoundtrip(): Unit \ Assert =
        let panel = Panel.make({x = 10.0, y = 10.0}, black())
            |> Panel.setBackgroundColor(white());
        Assert.assertEq(expected = 1.0f32, Panel.getBackgroundColor(panel)#r)

    /// borderWidth round-trip
    @Test
    def testBorderWidthRoundtrip(): Unit \ Assert =
        let panel = Panel.make({x = 10.0, y = 10.0}, black())
            |> Panel.setBorderWidth(4);
        Assert.assertEq(expected = 4, Panel.getBorderWidth(panel))

    /// size round-trip
    @Test
    def testSizeRoundtrip(): Unit \ Assert =
        let panel = Panel.make({x = 100.0, y = 50.0}, black())
            |> Panel.setSize({x = 200.0, y = 80.0});
        Assert.assertEq(expected = 200.0, Panel.getSize(panel)#x);
        Assert.assertEq(expected = 80.0, Panel.getSize(panel)#y)
}
