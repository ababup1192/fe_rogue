// TestUiExtract — text の wrap（折り返し幅の解決）と fit（枠に収める縮小）の規則を固定する。
// 折り返しの行割りそのものは engine の TestText の担当範囲（ここでは繰り返さない）。
mod TestUiExtract {

    // ── 道具 ──

    /// 等幅 advance=10・ascent=8・descent=2・lineGap=0・fontSize=10 のサンプルアトラス。
    /// 'A' のみ登録。fontSize 10 なら scale=1 で 1 文字 10px・1 行 10px と暗算できる。
    def sampleAtlas(): FontAtlas =
        let metrics: TextLayout.GlyphMetrics = {
            xOff = 0.0, yOff = 0.0, glyphW = 10.0, glyphH = 10.0,
            advance = 10.0, s0 = 0.0, t0 = 0.0, s1 = 1.0, t1 = 1.0
        };
        ({
            textureName = "atlas",
            fontSize    = 10.0,
            textureSize = 256.0,
            ascent      = 8.0,
            descent     = 2.0,
            lineGap     = 0.0,
            glyphs      = Map.empty() |> Map.insert(65, metrics)
        }: FontAtlas)

    def white(): Color = { r = 1.0f32, g = 1.0f32, b = 1.0f32 }

    /// 'A' 6 文字（fontSize 10 で幅 60px）の TextComp。
    def sixCharComp(wrap: UiWidget.TextWrap, fit: Option[UiWidget.TextFit]): UiWidget.TextComp =
        { text = "AAAAAA", font = "ui", fontSize = 10.0, tint = white(), zIndex = 0,
          wrap = wrap, fit = fit }

    // ========================================================================
    // wrap 宣言 → 折り返し幅の解決
    // ========================================================================

    /// off は折らない・auto は自分の矩形幅・数値はその幅。3 宣言を一度に確認する
    @Test
    def testResolvedWrapOfThreeKinds(): Unit \ Assert =
        let rectWidth = 120.0;
        let got = (
            UiExtract.resolvedWrapOf(sixCharComp(UiWidget.TextWrap.WrapOff, None), rectWidth),
            UiExtract.resolvedWrapOf(sixCharComp(UiWidget.TextWrap.WrapAuto, None), rectWidth),
            UiExtract.resolvedWrapOf(sixCharComp(UiWidget.TextWrap.WrapPx(96.0), None), rectWidth)
        );
        Assert.assertEq(expected = (None, Some(120.0), Some(96.0)), got)

    /// 内在サイズの計測に効くのは数値の wrap だけ（auto は矩形が決まる前なので効かせない）
    @Test
    def testIntrinsicWrapOnlyPx(): Unit \ Assert =
        let got = (
            UiExtract.intrinsicWrapOf(sixCharComp(UiWidget.TextWrap.WrapOff, None)),
            UiExtract.intrinsicWrapOf(sixCharComp(UiWidget.TextWrap.WrapAuto, None)),
            UiExtract.intrinsicWrapOf(sixCharComp(UiWidget.TextWrap.WrapPx(96.0), None))
        );
        Assert.assertEq(expected = (None, None, Some(96.0)), got)

    // ========================================================================
    // fit: 折った後の縦が収まるまで fontSize を刻みで下げる
    // ========================================================================

    /// 幅 30 で折る 'A'×6（60px）は fontSize 10 で 2 行 20px。矩形の縦 15 に収まるまで
    /// 1 刻みで下げると、fontSize 7 で 4+2 文字の 2 行 14px になり初めて収まる。
    ///   10 → 3+3 文字 20px / 9 → 18px / 8 → 16px / 7 → 14px ≦ 15 ✓
    @Test
    def testFittedFontSizeShrinksUntilHeightFits(): Unit \ Assert =
        let comp = sixCharComp(UiWidget.TextWrap.WrapPx(30.0),
                               Some({ step = 1.0, minSize = 6.0 }));
        let got = UiExtract.fittedFontSize(comp, sampleAtlas(), Some(30.0), 15.0);
        Assert.assertEq(expected = 7.0, got)

    /// どれだけ縮めても収まらない矩形（縦 5px）では minSize=6 で打ち切る（無限に縮めない）
    @Test
    def testFittedFontSizeStopsAtMinSize(): Unit \ Assert =
        let comp = sixCharComp(UiWidget.TextWrap.WrapPx(30.0),
                               Some({ step = 1.0, minSize = 6.0 }));
        let got = UiExtract.fittedFontSize(comp, sampleAtlas(), Some(30.0), 5.0);
        Assert.assertEq(expected = 6.0, got)

    /// fit 宣言が無ければ fontSize はそのまま（縦がはみ出していても縮めない）
    @Test
    def testNoFitKeepsFontSize(): Unit \ Assert =
        let comp = sixCharComp(UiWidget.TextWrap.WrapPx(30.0), None);
        let got = UiExtract.fittedFontSize(comp, sampleAtlas(), Some(30.0), 5.0);
        Assert.assertEq(expected = 10.0, got)
}
