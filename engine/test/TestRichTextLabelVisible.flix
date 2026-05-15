/// RichTextLabel の visibleCharacters / visibleRatio (Godot 準拠 typewriter) の挙動テスト。
/// BBCode タグは可視文字数に算入されないこと、setter/getter のラウンドトリップ、
/// `totalCharCount` が `Markup.BBCode.visibleLength` と整合することを検証する。
mod TestRichTextLabelVisible {

    /// 等幅 advance=10、ascent=8、descent=2、fontSize=16 のサンプルアトラス（最小限）
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

    def makeLabel(text: String): RichTextLabel =
        RichTextLabel.make(text, sampleAtlas(), 16.0, {x = 200.0, y = 100.0})

    // ── 初期値 ──

    /// make の直後は `visibleCharacters = -1` / `visibleRatio = -1.0` (= 制限なし)
    @Test
    def testDefaultsUnlimited(): Unit \ Assert =
        let label = makeLabel("ABC");
        Assert.assertEq(expected = -1, RichTextLabel.getVisibleCharacters(label));
        Assert.assertEq(expected = -1.0, RichTextLabel.getVisibleRatio(label))

    // ── setter / getter のラウンドトリップ ──

    @Test
    def testSetVisibleCharactersRoundtrip(): Unit \ Assert =
        let label = makeLabel("ABC") |> RichTextLabel.setVisibleCharacters(2);
        Assert.assertEq(expected = 2, RichTextLabel.getVisibleCharacters(label))

    @Test
    def testSetVisibleRatioRoundtrip(): Unit \ Assert =
        let label = makeLabel("ABC") |> RichTextLabel.setVisibleRatio(0.5);
        Assert.assertEq(expected = 0.5, RichTextLabel.getVisibleRatio(label))

    // ── totalCharCount: BBCode タグを算入しない ──

    /// プレーン "ABC" は 3
    @Test
    def testTotalCharCountPlain(): Unit \ Assert =
        Assert.assertEq(expected = 3, RichTextLabel.totalCharCount(makeLabel("ABC")))

    /// `[color=red]ABC[/color]` のタグ部分は文字数 0、本文 3 のみ算入
    @Test
    def testTotalCharCountIgnoresColorTags(): Unit \ Assert =
        Assert.assertEq(expected = 3, RichTextLabel.totalCharCount(makeLabel("[color=red]ABC[/color]")))

    /// `[b]A[/b]BC` も 3
    @Test
    def testTotalCharCountIgnoresBoldTags(): Unit \ Assert =
        Assert.assertEq(expected = 3, RichTextLabel.totalCharCount(makeLabel("[b]A[/b]BC")))

    /// 改行 `\n` は文字数 1（行レイアウト用に保持）
    @Test
    def testTotalCharCountCountsNewline(): Unit \ Assert =
        Assert.assertEq(expected = 3, RichTextLabel.totalCharCount(makeLabel("A\nB")))

    @Test
    def testTotalCharCountEmpty(): Unit \ Assert =
        Assert.assertEq(expected = 0, RichTextLabel.totalCharCount(makeLabel("")))

    // ── sliceVisible との整合: 同じ Markup.BBCode API に乗っている ──

    /// 上限なし時に visibleCharacters = totalCharCount で全表示と等価になることを確認。
    /// 直接 toDrawables を呼ばず、低レイヤ Markup.BBCode.sliceVisible で内部一致を取る。
    @Test
    def testSliceVisibleConsistentWithTotal(): Unit \ Assert =
        let text = "[color=red]A[/color]BC";
        let n    = RichTextLabel.totalCharCount(makeLabel(text));
        Assert.assertEq(expected = "[color=red]A[/color]BC", Markup.BBCode.sliceVisible(text, n))

    /// visibleCharacters = 1 で先頭 1 文字までが露出。色タグは結果に残る。
    @Test
    def testSliceVisibleOneCharKeepsTag(): Unit \ Assert =
        Assert.assertEq(expected = "[color=red]A[/color]", Markup.BBCode.sliceVisible("[color=red]ABC[/color]", 1))

    /// visibleCharacters = 0 で本文ゼロ（タグは未露出のまま）
    @Test
    def testSliceVisibleZero(): Unit \ Assert =
        Assert.assertEq(expected = "", Markup.BBCode.sliceVisible("[color=red]ABC[/color]", 0))

    /// 文字数を超える指定は安全に「全表示」へクランプ（sliceVisible はそのまま全文を返す）
    @Test
    def testSliceVisibleOverflowKeepsAll(): Unit \ Assert =
        Assert.assertEq(expected = "ABC", Markup.BBCode.sliceVisible("ABC", 999))
}
