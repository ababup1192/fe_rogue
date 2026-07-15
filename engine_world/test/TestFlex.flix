// TestFlex — Flex（宣言木 → UiLayout 解決）の rect 割当を固定する。
// Float64 の等値比較なので入力は割り切れる数値に限る。割り切れない値（458/5 等）は
// expected 側もレイアウトと同じ式・同じ加算順で書く。
// rect はそのまま Eq できないので (x, y, w, h) の Float64 タプルへ落として比較する。
mod TestFlex {

    /// サイズだけ持つ描画なしの葉。
    def dot(w: Float64, h: Float64): Flex.Node =
        Flex.leaf({ x = w, y = h }, _ -> Nil)

    def rect4(r: Rect2.Rect2): (Float64, Float64, Float64, Float64) =
        (r#position#x, r#position#y, r#size#x, r#size#y)

    def rects(root: Flex.Node, w: Float64, h: Float64): List[(Float64, Float64, Float64, Float64)] =
        Flex.leafRects(root, { position = { x = 0.0, y = 0.0 }, size = { x = w, y = h } })
            |> List.map(rect4)

    // ── 直列・整列・余白 ──

    @Test
    def testRowPlacesLeavesInSequence(): Unit \ Assert =
        let root = Flex.box(Flex.rowStyle(), dot(30.0, 10.0) :: dot(50.0, 10.0) :: Nil);
        Assert.assertEq(
            expected = (0.0, 0.0, 30.0, 10.0) :: (30.0, 0.0, 50.0, 10.0) :: Nil,
            rects(root, 100.0, 20.0))

    @Test
    def testGrowDividesFreeSpaceByWeight(): Unit \ Assert =
        // 1:1:2 の Grow は余り全体（base 0）を重み配分する。中身の葉は Stretch で容器幅を映す。
        def growCol(w: Float64): Flex.Node =
            Flex.box({ width = UiLayout.SizeSpec.Grow(w),
                       crossAlign = UiLayout.CrossAlign.Stretch | Flex.columnStyle() },
                     dot(0.0, 10.0) :: Nil);
        let root = Flex.box(Flex.rowStyle(), growCol(1.0) :: growCol(1.0) :: growCol(2.0) :: Nil);
        Assert.assertEq(
            expected = (0.0, 0.0, 100.0, 10.0) :: (100.0, 0.0, 100.0, 10.0) :: (200.0, 0.0, 200.0, 10.0) :: Nil,
            rects(root, 400.0, 10.0))

    @Test
    def testCenterCentersOnBothAxes(): Unit \ Assert =
        let root = Flex.box({ mainAlign = UiLayout.MainAlign.Center,
                              crossAlign = UiLayout.CrossAlign.Center | Flex.columnStyle() },
                            dot(20.0, 10.0) :: Nil);
        Assert.assertEq(
            expected = (40.0, 20.0, 20.0, 10.0) :: Nil,
            rects(root, 100.0, 50.0))

    @Test
    def testPaddingAndGapOffsetChildren(): Unit \ Assert =
        let root = Flex.box({ padLeft = 5.0, padTop = 7.0, gap = 3.0 | Flex.columnStyle() },
                            dot(10.0, 10.0) :: dot(10.0, 10.0) :: Nil);
        Assert.assertEq(
            expected = (5.0, 7.0, 10.0, 10.0) :: (5.0, 20.0, 10.0, 10.0) :: Nil,
            rects(root, 100.0, 100.0))

    // ── ギャラリー骨格（Px 帯 + Grow 行 ×5、480×530）──

    @Test
    def testGallerySkeletonBandsAndGrowRows(): Unit \ Assert =
        // 帯・行それぞれに Stretch な 0 サイズの葉を置き、帯の位置と行の等分高さを検分する。
        def bandBox(h: Float64): Flex.Node =
            Flex.box({ height = UiLayout.SizeSpec.Px(h),
                       crossAlign = UiLayout.CrossAlign.Stretch | Flex.columnStyle() },
                     dot(0.0, 0.0) :: Nil);
        def rowBox(): Flex.Node =
            Flex.box({ height = UiLayout.SizeSpec.Grow(1.0),
                       crossAlign = UiLayout.CrossAlign.Stretch | Flex.rowStyle() },
                     dot(0.0, 0.0) :: Nil);
        let root = Flex.box({ crossAlign = UiLayout.CrossAlign.Stretch | Flex.columnStyle() },
               bandBox(44.0)
            :: rowBox() :: rowBox() :: rowBox() :: rowBox() :: rowBox()
            :: bandBox(28.0)
            :: Nil);
        // 行高 = 余り 458 の Grow 配分。UiLayout.growShare と同じ式（free * (w/total)、458/5 とは
        // 最下位ビットが違う）で書き、行の y もペン送りと同じ順の逐次加算で書く。
        let rh = (530.0 - 44.0 - 28.0) * (1.0 / 5.0);
        let y1 = 44.0;
        let y2 = y1 + rh;
        let y3 = y2 + rh;
        let y4 = y3 + rh;
        let y5 = y4 + rh;
        let yNote = y5 + rh;
        Assert.assertEq(
            expected = (0.0, 0.0, 480.0, 0.0)
                    :: (0.0, y1, 0.0, rh) :: (0.0, y2, 0.0, rh) :: (0.0, y3, 0.0, rh)
                    :: (0.0, y4, 0.0, rh) :: (0.0, y5, 0.0, rh)
                    :: (0.0, yNote, 480.0, 0.0)
                    :: Nil,
            rects(root, 480.0, 530.0))

    // ── place: 確定 rect が draw に届いて連結される ──

    @Test
    def testPlacePassesRectsToDrawInTreeOrder(): Unit \ Assert =
        def mark(): Color = { r = 1.0f32, g = 1.0f32, b = 1.0f32 };
        let root = Flex.box(Flex.rowStyle(),
               Flex.leaf({ x = 30.0, y = 10.0 },
                         r -> ({ at = r#position, item = Render.box(r#size, mark(), 1) }) :: Nil)
            :: Flex.leaf({ x = 50.0, y = 10.0 },
                         r -> ({ at = r#position, item = Render.box(r#size, mark(), 1) }) :: Nil)
            :: Flex.leafAtCenter({ x = 20.0, y = 10.0 },
                         c -> Render.boxAt(c, { x = 4.0, y = 4.0 }, mark(), 1) :: Nil)
            :: Nil);
        let placed = Flex.place(root, { position = { x = 0.0, y = 0.0 }, size = { x = 100.0, y = 20.0 } });
        // leafAtCenter は中心 (90, 5) を受け、boxAt が半寸ずらすので at = (88, 3)。
        Assert.assertEq(
            expected = (0.0, 0.0) :: (30.0, 0.0) :: (88.0, 3.0) :: Nil,
            placed |> List.map(p -> (p#at#x, p#at#y)))
}
