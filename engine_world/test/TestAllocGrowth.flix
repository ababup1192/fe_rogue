// TestAllocGrowth — 割り当てバイト数の増え方が N に比例したままかを見る。
// 畳み込みの中の List.append は要素 1 つごとに acc を作り直すので、割り当てが N の二乗に
// 膨らむ。時間ではなくバイト数で見るので、熱・JIT・GC・マシンの速さに動かされない。
// 絶対バイト数は JDK やエスケープ解析で動くので pin せず、N を 8 倍にしたときの比だけを見る。
mod TestAllocGrowth {

    /// 'A' だけを送り 10 で持つ atlas（size 16 で等倍）。
    def sampleAtlas(): FontAtlas =
        let metrics = ({
            xOff = 0.0, yOff = 0.0, glyphW = 10.0, glyphH = 10.0,
            advance = 10.0, s0 = 0.0, t0 = 0.0, s1 = 1.0, t1 = 1.0
        }: TextLayout.GlyphMetrics);
        ({
            textureName = "atlas",
            fontSize    = 16.0,
            textureSize = 256.0,
            ascent      = 8.0,
            descent     = 2.0,
            lineGap     = 0.0,
            glyphs      = Map.empty() |> Map.insert(65, metrics)
        }: FontAtlas)

    /// maxWidth を極大にして全部を 1 行に閉じる（折り返すと N を増やしても行数が増えるだけで
    /// 1 行の文字数＝狙った N が増えない）。
    def placeChars(n: Int32): Int32 =
        let p = ({ atlas = sampleAtlas(), size = 16.0, baseTint = ({r = 0.1, g = 0.2, b = 0.3}: Color),
                   z = 40, pos = ({x = 0.0, y = 0.0}: Vec2.Vec2),
                   maxWidth = 1.0e9, lineGap = 3.0 }: RichText.Placement);
        RichText.place(p, RichText.plain(String.repeat(n, "A")) :: Nil) |> List.length

    def sustainNames(n: Int32): Int32 =
        let next = List.range(0, n) |> List.map(i -> ({ name = "s${i}", volume = 0.5, pitch = 1.0 }: App.Sustain));
        let ops = App.sustainOps(Nil, next);
        List.length(ops#start)

    /// 割り当てバイト数を読める JVM である（読めないと以下の 2 つは 0 しか見ない）
    @Test
    def testThreadAllocatedMemoryIsEnabled(): Unit \ Assert =
        Assert.assertTrue(AllocMeter.isThreadAllocatedMemoryEnabled())

    /// RichText.place の割り当ては 1 行の文字数に比例する（8 倍で 16 倍を超えない）
    @Test
    def testPlaceAllocatesLinearlyInLineLength(): Unit \ Assert =
        let small = AllocMeter.measureBytes(3, _ -> placeChars(100));
        let large = AllocMeter.measureBytes(3, _ -> placeChars(800));
        let ratio = Int64.toFloat64(large) / Int64.toFloat64(small);
        Assert.assertTrue(ratio < 16.0)

    /// App.sustainOps の割り当ては宣言の本数に比例する（8 倍で 16 倍を超えない）
    @Test
    def testSustainOpsAllocatesLinearlyInDeclarationCount(): Unit \ Assert =
        let small = AllocMeter.measureBytes(3, _ -> sustainNames(100));
        let large = AllocMeter.measureBytes(3, _ -> sustainNames(800));
        let ratio = Int64.toFloat64(large) / Int64.toFloat64(small);
        Assert.assertTrue(ratio < 16.0)
}
