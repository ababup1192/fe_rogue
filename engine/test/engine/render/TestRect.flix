/// Rect（単色矩形＋枠線・角丸・斜線ハッチ）の挙動テスト。
/// 素の塗り、枠線/角丸/縞つきの styled 化、setter/getter のラウンドトリップ、
/// toDrawable が色をどの流路（本体 or style）へ流すかを検証する。
mod TestRect {

    def black(): Color = {r = 0.0, g = 0.0, b = 0.0}
    def white(): Color = {r = 1.0, g = 1.0, b = 1.0}

    /// 枠線・角丸・縞がどれも無いときは style=None（素の塗り 1 枚）
    @Test
    def testPlainRectHasNoStyle(): Unit \ Assert =
        let rect = Rect.make({x = 100.0, y = 50.0}, black());
        let d = Rect.toDrawable(rect, {x = 0.0, y = 0.0});
        Assert.assertEq(expected = true, Option.isEmpty(DrawCmd.styleOf(d)))

    /// 枠線（width>0 かつ alpha>0）を付けると styled Drawable（style=Some）になり、
    /// borderWidth が style に流れる
    @Test
    def testBorderEmitsStyled(): Unit \ Assert =
        let rect = Rect.make({x = 100.0, y = 50.0}, black())
            |> Rect.setBorderColor(white())
            |> Rect.setBorderAlpha(1.0)
            |> Rect.setBorderWidth(2.0);
        let d = Rect.toDrawable(rect, {x = 0.0, y = 0.0});
        let bw = match DrawCmd.styleOf(d) {
            case Some(st) => DrawCmd.styleToSpec(st)#borderWidth
            case None     => -1.0
        };
        Assert.assertEq(expected = 2.0, bw)

    /// 枠線を付けても alpha=0 なら styled にならない（見えない枠は描かない）
    @Test
    def testBorderAlphaZeroStaysPlain(): Unit \ Assert =
        let rect = Rect.make({x = 100.0, y = 50.0}, black())
            |> Rect.setBorderWidth(2.0);
        let d = Rect.toDrawable(rect, {x = 0.0, y = 0.0});
        Assert.assertEq(expected = true, Option.isEmpty(DrawCmd.styleOf(d)))

    /// 負の borderWidth は 0 にクランプされる
    @Test
    def testSetBorderWidthClampsNegative(): Unit \ Assert =
        let rect = Rect.make({x = 100.0, y = 50.0}, black())
            |> Rect.setBorderWidth(-5.0);
        Assert.assertEq(expected = 0.0, Rect.getBorderWidth(rect))

    /// borderWidth round-trip
    @Test
    def testBorderWidthRoundtrip(): Unit \ Assert =
        let rect = Rect.make({x = 10.0, y = 10.0}, black())
            |> Rect.setBorderWidth(4.0);
        Assert.assertEq(expected = 4.0, Rect.getBorderWidth(rect))

    /// size round-trip
    @Test
    def testSizeRoundtrip(): Unit \ Assert =
        let rect = Rect.make({x = 100.0, y = 50.0}, black())
            |> Rect.setSize({x = 200.0, y = 80.0});
        Assert.assertEq(expected = 200.0, Rect.getSize(rect)#x);
        Assert.assertEq(expected = 80.0, Rect.getSize(rect)#y)

    /// cornerRadius>0 は styled Drawable（style=Some, cornerRadius 一致）を返す
    @Test
    def testCornerRadiusEmitsStyled(): Unit \ Assert =
        let rect = Rect.make({x = 100.0, y = 50.0}, black())
            |> Rect.setCornerRadius(6.0);
        let cr = match DrawCmd.styleOf(Rect.toDrawable(rect, {x = 0.0, y = 0.0})) {
            case Some(st) => DrawCmd.styleToSpec(st)#cornerRadius
            case None     => -1.0
        };
        Assert.assertEq(expected = 6.0, cr)

    /// 縞（width>0 かつ alpha>0）も styled 化のトリガになる
    @Test
    def testStripeEmitsStyled(): Unit \ Assert =
        let rect = Rect.make({x = 100.0, y = 50.0}, black())
            |> Rect.setStripe(white(), 0.5, 1.0, 2.0);
        let d = Rect.toDrawable(rect, {x = 0.0, y = 0.0});
        Assert.assertEq(expected = false, Option.isEmpty(DrawCmd.styleOf(d)))

    /// styled Drawable では 塗り色/α は Drawable 本体へ、枠色/α は style へ流れる
    /// （色の流路の取り違え防止）
    @Test
    def testStyledDrawableCarriesColors(): Unit \ Assert =
        let bg = {r = 0.2, g = 0.3, b = 0.4};
        let border = {r = 0.9, g = 0.8, b = 0.7};
        let rect = Rect.make({x = 100.0, y = 50.0}, bg)
            |> Rect.setAlpha(0.8)
            |> Rect.setBorderColor(border)
            |> Rect.setBorderAlpha(0.5)
            |> Rect.setBorderWidth(2.0)
            |> Rect.setCornerRadius(6.0);
        let d = Rect.toDrawable(rect, {x = 0.0, y = 0.0});
        let info = match DrawCmd.styleOf(d) {
            case Some(st) =>
                let s = DrawCmd.styleToSpec(st);
                (DrawCmd.colorOf(d)#r, DrawCmd.alphaOf(d), s#borderColor#r, s#borderAlpha)
            case None     => (-1.0, -1.0, -1.0, -1.0)
        };
        Assert.assertEq(expected = (0.2, 0.8, 0.9, 0.5), info)
}
