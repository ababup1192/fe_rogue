// TestPreviewItems — 汎用プレビュー口の純粋な部分 (宣言列のパース・外接矩形) と
// 封筒の返し分けを固定する。描画そのもの (PNG の中身) は curl + 目視検品に任せ、
// ここでは座標と応答の形だけを見る。

mod TestPreviewItems {

    /// テスト用の items JSON を描き物の列に解く。ここで JSON 自体が解けないのはテストの書き間違い。
    def itemsOf(text: String): Result[String, List[PreviewItems.Item]] =
        match DocJson.parse(text) {
            case Some(json) => PreviewItems.itemsFromJson(json)
            case None       => bug!("test json does not parse: ${text}")
        }

    /// 矩形を比較しやすいタプル (x, y, w, h) へ写す。
    def rectTuple(rect: Rect2.Rect2): (Float64, Float64, Float64, Float64) =
        (rect#position#x, rect#position#y, rect#size#x, rect#size#y)

    /// 描き物の列を外接矩形タプルの列へ写す (パース結果の中身を座標で観察する)。
    def rectsOf(text: String): Result[String, List[(Float64, Float64, Float64, Float64)]] =
        itemsOf(text) |> Result.map(List.map(item -> rectTuple(PreviewItems.rectOf(item))))

    // ========================================================================
    // 各 type の正常パースと外接矩形
    // ========================================================================

    /// box は左上 (x, y) + w×h がそのまま外接矩形。id / alpha / outline が付いても矩形は変わらない。
    @Test
    def testBoxRect(): Unit \ Assert =
        Assert.assertEq(
            expected = Ok((10.0, 20.0, 8.0, 8.0) :: Nil),
            rectsOf("[{\"id\": \"spawns/3\", \"type\": \"box\", \"x\": 10, \"y\": 20, \"w\": 8, \"h\": 8, " +
                    "\"color\": \"#e05050\", \"alpha\": 0.9, \"z\": 2, \"outline\": \"#ffffff\"}]"))

    /// circle は (x, y) が中心なので、外接矩形は「中心 - r の正方形」: (40, 60, r=6) → (34, 54, 12, 12)。
    @Test
    def testCircleRect(): Unit \ Assert =
        Assert.assertEq(
            expected = Ok((34.0, 54.0, 12.0, 12.0) :: Nil),
            rectsOf("[{\"type\": \"circle\", \"x\": 40, \"y\": 60, \"r\": 6, \"color\": \"#50e050\"}]"))

    /// 水平線 (0,226)→(320,226) 太さ 1 は、太さの半分ずつ上下へ張り出す: (0, 225.5, 320, 1)。
    @Test
    def testLineRect(): Unit \ Assert =
        Assert.assertEq(
            expected = Ok((0.0, 225.5, 320.0, 1.0) :: Nil),
            rectsOf("[{\"type\": \"line\", \"x1\": 0, \"y1\": 226, \"x2\": 320, \"y2\": 226, " +
                    "\"width\": 1, \"color\": \"#8899aa\"}]"))

    /// text の幅は 0.6em/字 の概算 (クリック当たり枠用途): size 8 × 2 字 → 幅 9.6・高さ 8。
    @Test
    def testTextRectEstimate(): Unit \ Assert =
        Assert.assertEq(
            expected = Ok((4.0, 4.0, 9.6, 8.0) :: Nil),
            rectsOf("[{\"type\": \"text\", \"x\": 4, \"y\": 4, \"size\": 8, \"text\": \"ab\"}]"))

    /// sprite は左上 (x, y) + 表示寸 w×h がそのまま外接矩形 (テクスチャの実寸は見ない)。
    @Test
    def testSpriteRect(): Unit \ Assert =
        Assert.assertEq(
            expected = Ok((40.0, 40.0, 16.0, 16.0) :: Nil),
            rectsOf("[{\"id\": \"p1\", \"type\": \"sprite\", \"x\": 40, \"y\": 40, " +
                    "\"texture\": \"enemy_sheet\", \"w\": 16, \"h\": 16, \"z\": 2}]"))

    // ========================================================================
    // id の有無 (rects へのエコー対象の選別)
    // ========================================================================

    /// id を付けた item だけ Some(id) — 応答の rects には Some の物だけが載る。
    @Test
    def testIdOnlyOnLabeledItems(): Unit \ Assert =
        Assert.assertEq(
            expected = Ok(Some("spawns/3") :: None :: Nil),
            itemsOf("[{\"id\": \"spawns/3\", \"type\": \"box\", \"x\": 1, \"y\": 2, \"w\": 3, \"h\": 4}, " +
                    "{\"type\": \"circle\", \"x\": 5, \"y\": 6, \"r\": 7}]")
                |> Result.map(List.map(PreviewItems.idOf)))

    // ========================================================================
    // 壊れた宣言 (どの item かが分かる Err で全体を止める)
    // ========================================================================

    /// 未知の type は「何番目の何か」が分かる Err (0 番が正常でも 1 番で止める)。
    @Test
    def testUnknownTypeErr(): Unit \ Assert =
        Assert.assertEq(
            expected = Err("items[1]: type 'blob' は知らない種類です (box / circle / line / text / sprite)"),
            itemsOf("[{\"type\": \"circle\", \"x\": 1, \"y\": 2, \"r\": 3}, {\"type\": \"blob\"}]")
                |> Result.map(List.length))

    /// 数値であるべき座標に文字列が来たら、item とキーの名指しで Err。
    @Test
    def testNonNumericCoordErr(): Unit \ Assert =
        Assert.assertEq(
            expected = Err("items[0] (box): x が数値ではありません"),
            itemsOf("[{\"type\": \"box\", \"x\": \"10\", \"y\": 20, \"w\": 8, \"h\": 8}]")
                |> Result.map(List.length))

    /// 必須キーの欠落も同じ形の Err (circle に r が無い)。
    @Test
    def testMissingFieldErr(): Unit \ Assert =
        Assert.assertEq(
            expected = Err("items[0] (circle): r がありません"),
            itemsOf("[{\"type\": \"circle\", \"x\": 1, \"y\": 2}]") |> Result.map(List.length))

    /// items が配列ですらないときも Err (黙って空扱いにしない)。
    @Test
    def testItemsNotArrayErr(): Unit \ Assert =
        Assert.assertEq(
            expected = Err("items は配列で送ってください"),
            itemsOf("\"box\"") |> Result.map(List.length))

    // ========================================================================
    // respond の返し分け (封筒不正 = 400 / 空の宣言列 = 200 の ok:true)
    // ========================================================================

    /// JSON ですらない body は封筒不正で HTTP 400。
    @Test
    def testBadBodyIs400(): Unit \ {Assert, IO} =
        let caches = Caches.make();
        let (status, _json) = PreviewItems.respond("testdata/proj", caches, "not json");
        Assert.assertEq(expected = 400, status)

    /// items が空でも ok:true — design どおりの寸法の PNG (背景 = clearColor の黒) が返る。
    /// PNG の中身 (真っ黒) は目視検品に任せ、ここでは base64 が PNG 署名 "iVBOR" で始まる事だけ見る。
    @Test
    def testEmptyItemsRendersBlankPng(): Unit \ {Assert, IO} =
        let caches = Caches.make();
        let (status, json) = PreviewItems.respond("testdata/proj", caches,
            "{\"items\": [], \"design\": {\"w\": 8, \"h\": 6}, \"scale\": 1}");
        let body = JsonCodec.expectObject(json) |> Option.getWithDefault(Map.empty());
        Assert.assertEq(
            expected = (200, Some(true), Some(8), Some(6), Some(true)),
            (status,
             Map.get("ok", body) |> Option.flatMap(JsonCodec.expectBool),
             Map.get("width", body) |> Option.flatMap(JsonCodec.expectInt),
             Map.get("height", body) |> Option.flatMap(JsonCodec.expectInt),
             Map.get("png", body)
                 |> Option.flatMap(JsonCodec.expectString)
                 |> Option.map(png -> String.startsWith(prefix = "iVBOR", png))))
}
