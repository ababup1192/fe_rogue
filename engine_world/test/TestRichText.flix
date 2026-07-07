// TestRichText — スパン列の素の文章・長さ・先頭切り出し（文字送り連携）を具体値で固定する。
// place（描画）は atlas が要るのでここでは扱わない — 幾何は消費側の view guard が守る。
mod TestRichText {

    def spans(): List[RichText.Span] =
        RichText.colored("あお", {r = 0.0f32, g = 0.0f32, b = 1.0f32})
            :: RichText.plain("は")
            :: RichText.strong("嘘つき")
            :: RichText.plain("だよ") :: Nil

    @Test
    def testPlainTextAndLength(): Unit \ Assert =
        // 見た目を除いた素の文章と合計文字数。
        Assert.assertEq(expected = ("あおは嘘つきだよ", 8),
            (RichText.plainText(spans()), RichText.length(spans())))

    @Test
    def testTakeCutsAcrossSpanBoundaries(): Unit \ Assert =
        // 先頭 4 文字 = 「あおは嘘」。3 スパン目（太字）の途中で切れ、太字属性は保たれる。
        let cut = RichText.take(4, spans());
        let bolds = cut |> List.map(span -> span#bold);
        Assert.assertEq(expected = ("あおは嘘", false :: false :: true :: Nil, 3),
            (RichText.plainText(cut), bolds, List.length(cut)))

    @Test
    def testTakeZeroAndOverrun(): Unit \ Assert =
        // 0 文字なら空、全長以上なら全部（それ以上は増えない）。
        Assert.assertEq(expected = ("", "あおは嘘つきだよ"),
            (RichText.plainText(RichText.take(0, spans())),
             RichText.plainText(RichText.take(99, spans()))))
}
