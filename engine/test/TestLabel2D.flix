// Tests for Text module

mod TestLabel2D {

    def approx(a: Float64, b: Float64): Bool =
        Float64.abs(a - b) < 0.001

    /// 等幅 advance=10、ascent=8、descent=2、lineGap=0、fontSize=16。
    /// 'A','B','C' のみ登録、scale=1.0 (fontSize=16 / atlas#fontSize=16) のサンプルアトラス。
    def sampleAtlas(): FontAtlas =
        let metrics: TextLayout.GlyphMetrics = {
            xOff = 0.0, yOff = 0.0, glyphW = 10.0, glyphH = 10.0,
            advance = 10.0, s0 = 0.0, t0 = 0.0, s1 = 1.0, t1 = 1.0
        };
        let glyphs = Map.empty()
            |> Map.insert(65, metrics)   // 'A'
            |> Map.insert(66, metrics)   // 'B'
            |> Map.insert(67, metrics);  // 'C'
        ({
            textureName = "atlas",
            fontSize    = 16.0,
            textureSize = 256.0,
            ascent      = 8.0,
            descent     = 2.0,
            lineGap     = 0.0,
            glyphs      = glyphs
        }: FontAtlas)

    // ========================================================================
    // measure — 1 行
    // ========================================================================

    /// 単一行 "ABC" は advance(10) * 3 = 30、高さは lineHeight = ascent+descent+lineGap = 10
    @Test
    def testMeasureSingleLine(): Unit \ Assert =
        let label = Text.make("ABC", sampleAtlas(), 16.0);
        let sz = Text.measure(label);
        Assert.assertTrue(approx(sz#x, 30.0));
        Assert.assertTrue(approx(sz#y, 10.0))

    /// 空文字列でも高さ 1 行分は確保される
    @Test
    def testMeasureEmptyString(): Unit \ Assert =
        let label = Text.make("", sampleAtlas(), 16.0);
        let sz = Text.measure(label);
        Assert.assertTrue(approx(sz#x, 0.0));
        Assert.assertTrue(approx(sz#y, 10.0))

    // ========================================================================
    // measure — 複数行
    // ========================================================================

    /// 2 行 "AB\nC" は max(2,1)*10=20、高さは 2*10=20
    @Test
    def testMeasureTwoLines(): Unit \ Assert =
        let label = Text.make("AB\nC", sampleAtlas(), 16.0);
        let sz = Text.measure(label);
        Assert.assertTrue(approx(sz#x, 20.0));
        Assert.assertTrue(approx(sz#y, 20.0))

    /// 3 行 "A\nBC\nA" は max=20、高さは 3*10=30
    @Test
    def testMeasureThreeLines(): Unit \ Assert =
        let label = Text.make("A\nBC\nA", sampleAtlas(), 16.0);
        let sz = Text.measure(label);
        Assert.assertTrue(approx(sz#x, 20.0));
        Assert.assertTrue(approx(sz#y, 30.0))

    // ========================================================================
    // measure — fontSize スケーリング
    // ========================================================================

    /// fontSize = atlas#fontSize の 2 倍 (32.0) なら、scale = 2.0 で全体が倍
    @Test
    def testMeasureScaledFontSize(): Unit \ Assert =
        let label = Text.make("AB", sampleAtlas(), 32.0);
        let sz = Text.measure(label);
        // advance(10)*2 chars * scale(2) = 40、高さ 10 * 2 = 20
        Assert.assertTrue(approx(sz#x, 40.0));
        Assert.assertTrue(approx(sz#y, 20.0))

    /// 半分の fontSize なら半分のサイズ
    @Test
    def testMeasureHalfFontSize(): Unit \ Assert =
        let label = Text.make("ABC", sampleAtlas(), 8.0);
        let sz = Text.measure(label);
        // advance(10)*3 chars * scale(0.5) = 15、高さ 10 * 0.5 = 5
        Assert.assertTrue(approx(sz#x, 15.0));
        Assert.assertTrue(approx(sz#y, 5.0))

    // ========================================================================
    // measure — 未登録グリフ
    // ========================================================================

    /// アトラスに無い文字は advance 0 として扱う
    @Test
    def testMeasureUnknownGlyph(): Unit \ Assert =
        let label = Text.make("AXC", sampleAtlas(), 16.0);
        let sz = Text.measure(label);
        // 'A'(10) + 'X'(0) + 'C'(10) = 20
        Assert.assertTrue(approx(sz#x, 20.0));
        Assert.assertTrue(approx(sz#y, 10.0))

}
