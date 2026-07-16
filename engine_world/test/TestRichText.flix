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

    // ========================================================================
    // wrapLinesBy: 行折り（place と同じ規則。幅は外から与えるのでテストは純粋）
    // ========================================================================

    /// 全角 2・半角 1 の近似幅（呼び側がスクロール勘定に使うのと同じ形）。
    def unitWidth(ch: Char): Float64 = if (Char.isAscii(ch)) 1.0 else 2.0

    // 幅 6 なら全角 3 字ずつで折れる(ちょうど収まる字は同じ行、あふれた字から次の行)。
    @Test
    def testWrapBreaksAtWidth(): Unit \ Assert =
        let lines = RichText.wrapLinesBy(unitWidth, 6.0, spans());
        Assert.assertEq(expected = "あおは" :: "嘘つき" :: "だよ" :: Nil,
            lines |> List.map(RichText.plainText))

    // 1 スパンの途中で折れても、両側の断片に太字属性が残る。
    @Test
    def testWrapKeepsAttributesAcrossBreak(): Unit \ Assert =
        let lines = RichText.wrapLinesBy(unitWidth, 4.0, RichText.strong("嘘つき") :: Nil);
        let flags = lines |> List.map(line -> line |> List.map(span -> span#bold));
        Assert.assertEq(expected = (("嘘つ" :: "き" :: Nil), (true :: Nil) :: (true :: Nil) :: Nil),
            (lines |> List.map(RichText.plainText), flags))

    // '\n' でも折れる。空行は空の行として残る（黙って消えない）。
    @Test
    def testWrapHonorsNewline(): Unit \ Assert =
        let lines = RichText.wrapLinesBy(unitWidth, 99.0, RichText.plain("a\n\nb") :: Nil);
        Assert.assertEq(expected = "a" :: "" :: "b" :: Nil,
            lines |> List.map(RichText.plainText))

    // 行頭では折らない: maxWidth より広い字も 1 字は必ず置く（無限ループを作らない）。
    @Test
    def testWrapPlacesOversizeCharAtLineStart(): Unit \ Assert =
        let lines = RichText.wrapLinesBy(unitWidth, 1.0, RichText.plain("あい") :: Nil);
        Assert.assertEq(expected = "あ" :: "い" :: Nil,
            lines |> List.map(RichText.plainText))

    // 行数の規約: 空の入力も「空行 1 つ」で 0 行にはならず、末尾の '\n' は空行を残す。
    // 行数を高さの予約・スクロールの勘定に使う呼び側が頼る性質なので pin する。
    @Test
    def testWrapLineCountConvention(): Unit \ Assert =
        Assert.assertEq(expected = ("" :: Nil, "" :: Nil, "a" :: "" :: Nil),
            (RichText.wrapLinesBy(unitWidth, 9.0, Nil) |> List.map(RichText.plainText),
             RichText.wrapLinesBy(unitWidth, 9.0, RichText.plain("") :: Nil) |> List.map(RichText.plainText),
             RichText.wrapLinesBy(unitWidth, 9.0, RichText.plain("a\n") :: Nil) |> List.map(RichText.plainText)))
}
