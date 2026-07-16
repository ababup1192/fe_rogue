// TestPreviewHitbox — 当たり形プレビューの純粋な部分 (マス目の割り付け・外接矩形・
// "//" 注釈の収集) を固定する。描画そのもの (PNG の中身) は目視検品に任せ、ここでは座標だけを見る。

mod TestPreviewHitbox {
    use Hit.HitShape

    /// 矩形を比較しやすいタプル (x, y, w, h) へ写す。
    def rectTuple(rect: Rect2.Rect2): (Float64, Float64, Float64, Float64) =
        (rect#position#x, rect#position#y, rect#size#x, rect#size#y)

    // ========================================================================
    // マス目の割り付け
    // ========================================================================

    /// 列数は ceil(sqrt(n)): 1 個 → 1 列、2 個 → 2 列、5 個 → 3 列。
    @Test
    def testColumnsOf(): Unit \ Assert =
        Assert.assertEq(expected = (1, 2, 3),
            (PreviewHitbox.columnsOf(1), PreviewHitbox.columnsOf(2), PreviewHitbox.columnsOf(5)))

    /// 小さい形 (半径 3 の円) だけなら、セル辺は最小の 48px に張り付く。
    @Test
    def testCellSideClampsToMinimum(): Unit \ Assert =
        let sheet = Map#{"shot" => HitShape.CircleH({ dx = 0.0, dy = 0.0, r = 3.0 }) :: Nil};
        Assert.assertEq(expected = 48.0, PreviewHitbox.cellSideOf(sheet))

    /// 大きい形が混ざると、セル辺 = 全形状の最大到達 (|dy| + h/2 = 30) × 2 + 余白 16 = 76。
    /// 全セル同寸なので small のセルも 76 になる (縮尺を揃えて大小を読み違えないため)。
    @Test
    def testCellSideFollowsLargestReach(): Unit \ Assert =
        let sheet = Map#{
            "small" => HitShape.CircleH({ dx = 0.0, dy = 0.0, r = 3.0 }) :: Nil,
            "big"   => HitShape.BoxH({ dx = 0.0, dy = 10.0, w = 20.0, h = 40.0 }) :: Nil
        };
        Assert.assertEq(expected = 76.0, PreviewHitbox.cellSideOf(sheet))

    /// 5 個を 3 列に並べたときのセル矩形 (辺 48)。0 番は左上、4 番は 2 行目の 2 列目。
    ///   ┌─0─┬─1─┬─2─┐
    ///   ├─3─┼─4─┼───┤
    ///   └───┴───┴───┘
    @Test
    def testCellRects(): Unit \ Assert =
        Assert.assertEq(
            expected = ((0.0, 0.0, 48.0, 48.0), (48.0, 48.0, 48.0, 48.0)),
            (rectTuple(PreviewHitbox.cellRectOf(0, 3, 48.0)),
             rectTuple(PreviewHitbox.cellRectOf(4, 3, 48.0))))

    /// キャンバス全体の寸法: 5 個 3 列は 2 行なので 144 × 96。
    @Test
    def testDesignOf(): Unit \ Assert =
        let design = PreviewHitbox.designOf(5, 3, 48.0);
        Assert.assertEq(expected = (144.0, 96.0), (design#x, design#y))

    // ========================================================================
    // 形の外接矩形 (セル中心 (100, 50) に置く。y は下が正)
    // ========================================================================

    /// 円は中心 + (dx, dy) から半径ぶん四方へ、箱は w/2・h/2 ずつ広がる。
    /// box は dx = -3 (左へ) / dy = 3 (下へ) のずれ込み: x = 100-3-5 = 92, y = 50+3-1.5 = 51.5。
    @Test
    def testShapeRects(): Unit \ Assert =
        let center = { x = 100.0, y = 50.0 };
        Assert.assertEq(
            expected = ((97.0, 47.0, 6.0, 6.0), (92.0, 51.5, 10.0, 3.0)),
            (rectTuple(PreviewHitbox.shapeRectOf(center, HitShape.CircleH({ dx = 0.0, dy = 0.0, r = 3.0 }))),
             rectTuple(PreviewHitbox.shapeRectOf(center, HitShape.BoxH({ dx = -3.0, dy = 3.0, w = 10.0, h = 3.0 })))))

    // ========================================================================
    // "//" 注釈の収集
    // ========================================================================

    /// トップの "//" が全体注釈、"hit" 内の "//名前" がそのエンティティの注釈。
    /// 名前の付かない "hit" 内の "//" はどのエンティティの物でもないので拾わない。
    @Test
    def testNotesOf(): Unit \ Assert =
        let text = "{\"//\": \"all\", \"hit\": {\"//\": \"loose\", \"//player\": \"core\", \"player\": []}}";
        Assert.assertEq(
            expected = Some((Some("all"), Map#{"player" => "core"})),
            JsonCompat.parse(text) |> Option.map(PreviewHitbox.notesOf))

    /// 注釈がまったく無い文書では (None, 空 Map)。
    @Test
    def testNotesOfEmpty(): Unit \ Assert =
        let text = "{\"hit\": {\"player\": []}}";
        Assert.assertEq(
            expected = Some((None, (Map.empty(): Map[String, String]))),
            JsonCompat.parse(text) |> Option.map(PreviewHitbox.notesOf))
}
