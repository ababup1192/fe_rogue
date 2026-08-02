// TestHits — assets/hitbox.json のロードの pin: 実ファイルが読めて欠けが無く、
// 宣言どおりの寸法であること（Hits.defaults() とのずれもこの 1 本で見つかる）。
// block が無いのは意図: 格子から導出される寸法は JSON の領分ではない。

mod TestHits {

    /// 実 hitbox.json が読めて欠けが無く、2 キーの寸法が宣言どおりで、コード内の
    /// 既定表（Hits.defaults）とも一致すること。
    @Test
    def testHitboxJsonLoads(): Unit \ {Assert, IO} =
        let expectedSummary = "gaps=0 keys=2"
            + " ball=circle r=3.0"
            + " paddle=box 44.0x6.0";
        Assert.assertEq(
            expected = (expectedSummary, expectedSummary),
            (loadSummary(), "gaps=0 keys=2" + sheetSummary(Hits.defaults())))

    /// 読み込み結果を 1 行に落とす（比較を平らにするため）。
    def loadSummary(): String \ IO =
        run {
            match HitDoc.load(Hits.path()) {
                case Ok(sheet) =>
                    "gaps=${List.length(HitDoc.gaps(Hits.requiredKeys(), sheet))} keys=${Map.size(sheet)}"
                        + sheetSummary(sheet)
                case Err(e)    => "error: ${DocJson.describe(e)}"
            }
        } with Fs.FileRead.runWithIO

    /// 2 キーぶんの形の要約。
    def sheetSummary(sheet: HitDoc.Sheet): String =
        keySummary(Hits.ballKey(), sheet)
            + keySummary(Hits.paddleKey(), sheet)

    def keySummary(key: String, sheet: HitDoc.Sheet): String =
        " ${key}=${describeShapes(HitDoc.shapesOf(key, sheet))}"

    /// 形の列の要約（このゲームはどれも 1 形状）。
    def describeShapes(shapes: List[Hit.HitShape]): String =
        match shapes {
            case Hit.HitShape.CircleH(c) :: Nil => "circle r=${c#r}"
            case Hit.HitShape.BoxH(b) :: Nil    => "box ${b#w}x${b#h}"
            case _                              => "other"
        }
}
