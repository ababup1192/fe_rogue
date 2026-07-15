// TestUiMeta — meta 文字列「接頭辞 + 番号」の読み取り規約を固定する。
mod TestUiMeta {

    @Test
    def testIndexOfMatches(): Unit \ Assert =
        Assert.assertEq(expected = Some(2), UiMeta.indexOf("novel/choice/", "novel/choice/2"))

    @Test
    def testIndexOfPrefixMismatchIsNone(): Unit \ Assert =
        Assert.assertEq(expected = None, UiMeta.indexOf("novel/choice/", "menu/item/2"))

    @Test
    def testIndexOfNonNumberIsNone(): Unit \ Assert =
        Assert.assertEq(expected = None, UiMeta.indexOf("novel/choice/", "novel/choice/abc"))

    @Test
    def testIndexOfEmptyRestIsNone(): Unit \ Assert =
        // 接頭辞だけで番号が無い meta は項目を指せない。
        Assert.assertEq(expected = None, UiMeta.indexOf("novel/choice/", "novel/choice/"))
}
