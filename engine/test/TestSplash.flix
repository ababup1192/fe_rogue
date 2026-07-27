// 起動画面の「約束」だけを確かめる。
// 置き場所・色・ロゴの大きさ・ゲージの太さは演出なので、ここでは見ない（目視の仕事）。

mod TestSplash {

    /// 数が分かっていないとき（全体の本数が 0 以下）は進み具合を名乗らない。
    @Test
    def testRatioUnknownWhenNoTotal(): Unit \ Assert =
        Assert.assertEq(expected = None, Splash.clampRatio(0, 0));
        Assert.assertEq(expected = None, Splash.clampRatio(3, -1))

    /// 進み具合は必ず 0..1 に収まる（数え違いで棒が画面からはみ出さない）。
    @Test
    def testRatioClampedToUnitRange(): Unit \ Assert =
        Assert.assertEq(expected = Some(0.0), Splash.clampRatio(0, 4));
        Assert.assertEq(expected = Some(0.5), Splash.clampRatio(2, 4));
        Assert.assertEq(expected = Some(1.0), Splash.clampRatio(4, 4));
        Assert.assertEq(expected = Some(1.0), Splash.clampRatio(9, 4));
        Assert.assertEq(expected = Some(0.0), Splash.clampRatio(-3, 4))

    /// 流れる帯の位置は 1 周ぶんの端数（何秒経っても 0..1 の中を回り続ける）。
    @Test
    def testTurnsWrapAround(): Unit \ Assert =
        Assert.assertEq(expected = 0.0, Splash.turnsOf(0.0));
        Assert.assertEq(expected = 0.25, Splash.turnsOf(3.25));
        Assert.assertEq(expected = 0.0, Splash.turnsOf(12.0))

    /// 進み具合が 0 のときだけ棒が 1 本減る（何も進んでいないのに進んで見えないように）。
    /// 枚数そのものでなく差を見るので、絵に飾りを足しても壊れない。
    @Test
    def testGaugeShowsNoFillAtZero(): Unit \ Assert =
        let boxes = v -> Splash.drawables(v) |> List.count(d -> String.isEmpty(d#texture));
        let design = { x = 320.0, y = 240.0 };
        let half = boxes(Splash.bootView(design, "loading...", Some(0.5), 0.0));
        let zero = boxes(Splash.bootView(design, "loading...", Some(0.0), 0.0));
        let unknown = boxes(Splash.bootView(design, "loading...", None, 0.0));
        Assert.assertEq(expected = half - 1, zero);
        // 本数が分からないときは流れる帯が出る（溜まる棒と同じ本数）。
        Assert.assertEq(expected = half, unknown)

    /// 文言に無い字があっても落ちない。組み込みフォントは ASCII だけなので、
    /// 日本語を渡したら「その字が出ない」だけで済む。
    @Test
    def testNonAsciiPhraseIsDroppedNotFatal(): Unit \ Assert =
        let design = { x = 320.0, y = 240.0 };
        let ascii = Splash.drawables(Splash.bootView(design, "abc", Some(0.5), 0.0));
        let mixed = Splash.drawables(Splash.bootView(design, "abc日本語", Some(0.5), 0.0));
        Assert.assertEq(expected = List.length(ascii), List.length(mixed))
}
