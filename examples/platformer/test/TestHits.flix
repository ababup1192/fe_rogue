// TestHits — assets/hitbox.json のロードの pin: 実ファイルが読めて欠けが無く、
// 宣言どおりの半径であること（Hits.defaults() とのずれもこの 1 本で見つかる）。

mod TestHits {

    /// 実 hitbox.json が読めて欠けが無く、2 キーの半径が宣言どおりで、コード内の
    /// 既定表（Hits.defaults）とも一致すること。
    @Test
    def testHitboxJsonLoads(): Unit \ {Assert, IO} =
        let expectedSummary = "gaps=0 keys=2 player=circle r=12.0 enemy=circle r=10.0";
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
        keySummary(Hits.playerKey(), sheet) + keySummary(Hits.enemyKey(), sheet)

    def keySummary(key: String, sheet: HitDoc.Sheet): String =
        " ${key}=${describeShapes(HitDoc.shapesOf(key, sheet))}"

    /// 形の列の要約（このゲームはどちらも円 1 個）。
    def describeShapes(shapes: List[Hit.HitShape]): String =
        match shapes {
            case Hit.HitShape.CircleH(c) :: Nil => "circle r=${c#r}"
            case _                              => "other"
        }
}
