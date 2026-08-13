// TestUiScroll — 末尾基準スクロールの勘定を具体値で固定する: 上限 clamp・両端で止まる・
// 表示範囲の先頭・「まだある」印の出し分け。単位は呼び側が決めるのでテストは行数のつもり。
mod TestUiScroll {

    /// 内容 30 行を 18 行のビューポートで見る（バックログの典型）。
    def size(): { content = Int32, viewport = Int32 } = { content = 30, viewport = 18 }

    @Test
    def testMaxOffsetIsOverflow(): Unit \ Assert =
        // 遡れる上限 = はみ出した行数。収まっているなら 0。
        Assert.assertEq(expected = (12, 0),
            (UiScroll.maxOffset(size()),
             UiScroll.maxOffset({ content = 5, viewport = 18 })))

    @Test
    def testScrollByStopsAtBothEnds(): Unit \ Assert =
        // 大きく遡っても上限で止まり、大きく戻しても 0 で止まる（端で閉じたりしない）。
        let atTop = UiScroll.scrollBy(999, size(), 0);
        Assert.assertEq(expected = (12, 0),
            (atTop, UiScroll.scrollBy(-999, size(), atTop)))

    @Test
    def testTopFollowsOffset(): Unit \ Assert =
        // offset 0 = 末尾張り付き（先頭は content - viewport）。遡るほど先頭が上がる。
        Assert.assertEq(expected = (12, 9, 0),
            (UiScroll.top(size(), 0), UiScroll.top(size(), 3), UiScroll.top(size(), 12)))

    @Test
    def testMoreMarkersAtEnds(): Unit \ Assert =
        // 末尾では上にだけ、途中では両方、一番上では下にだけ「まだある」。
        Assert.assertEq(
            expected = ((true, false), (true, true), (false, true)),
            ((UiScroll.moreAbove(size(), 0), UiScroll.moreBelow(size(), 0)),
             (UiScroll.moreAbove(size(), 3), UiScroll.moreBelow(size(), 3)),
             (UiScroll.moreAbove(size(), 12), UiScroll.moreBelow(size(), 12))))

    @Test
    def testFittingContentNeverScrolls(): Unit \ Assert =
        // ビューポートに収まる内容はどう操作しても 0 のままで、印も出ない。
        let fits = { content = 5, viewport = 18 };
        Assert.assertEq(
            expected = (0, false, false),
            (UiScroll.scrollBy(7, fits, 0), UiScroll.moreAbove(fits, 0), UiScroll.moreBelow(fits, 0)))

    @Test
    def testStaleOffsetShowsNoPhantomMarker(): Unit \ Assert =
        // 内容が縮んで古い offset が上限を超えていても、全部見えているなら ▼ を出さない
        // (top も 0 に張り付く)。offset を World に持つ呼び側で起きる形。
        let shrunk = { content = 3, viewport = 18 };
        Assert.assertEq(
            expected = (0, false),
            (UiScroll.top(shrunk, 5), UiScroll.moreBelow(shrunk, 5)))

    // ========================================================================
    // ピクセル版(行高 11px・30 行 = 330px を 198px のビューポートで見る = 上の行版と同じ形)
    // ========================================================================

    def sizePx(): { contentPx = Float64, viewportPx = Float64 } =
        { contentPx = 330.0, viewportPx = 198.0 }

    @Test
    def testPxScrollClampsAndStops(): Unit \ Assert =
        // 上限 132px(= 12 行ぶん)で止まり、大きく戻しても 0 で止まる。NaN は位置を汚さない。
        let atTop = UiScroll.scrollByPx(9999.0, sizePx(), 0.0);
        Assert.assertEq(
            expected = (132.0, 0.0, 5.0),
            (atTop,
             UiScroll.scrollByPx(-9999.0, sizePx(), atTop),
             UiScroll.scrollByPx(Float64.nan(), sizePx(), 5.0)))

    @Test
    def testRowWindowOnGrid(): Unit \ Assert =
        // 格子上(offset 0 = 末尾)ではずれ無し・ちょうど 18 行。first は 12 行目から。
        let w = UiScroll.rowWindow(11.0, sizePx(), 0.0);
        Assert.assertEq(expected = (12, 0.0, 18), (w#first, w#shift, w#count))

    @Test
    def testRowWindowMidRow(): Unit \ Assert =
        // 行の途中(5px 遡り)では: top = 127px → 行 11 から、6px 上へずらして 19 行描く
        // (部分行が上下に 1 行ずつ増えるぶん)。
        let w = UiScroll.rowWindow(11.0, sizePx(), 5.0);
        Assert.assertEq(expected = (11, 6.0, 19), (w#first, w#shift, w#count))

    @Test
    def testStepRowSnapsToGrid(): Unit \ Assert =
        // 途中位置(5px)から: 遡る 1 行はまず次の境界(11px)へ、戻る 1 行は手前の境界(0px)へ。
        // 格子上からは丸ごと 1 行(11px)動く。
        Assert.assertEq(
            expected = (11.0, 0.0, 22.0),
            (UiScroll.stepRow(11.0, 1, sizePx(), 5.0),
             UiScroll.stepRow(11.0, -1, sizePx(), 5.0),
             UiScroll.stepRow(11.0, 1, sizePx(), 11.0)))
}
