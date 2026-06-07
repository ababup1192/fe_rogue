/// FloorCatalog の Saveable round-trip と純粋ロジックの境界条件を固定する。
///
/// 観点:
///   - FloorResource の round-trip で主要フィールドが保たれる (Saveable は段階 8 で新規追加)
///   - 必須フィールド (label) が欠落した JSON は decode 失敗で None
///   - pickWeighted の境界: 空配列 / 合計 0 → None、1 件 → 必ずその id を返す
///   - randomCountInRange の境界: max < min の不正範囲は min を返す (defensive fallback)
mod TestFloorCatalog {

    use FloorCatalog.{FloorCatalog, FloorResource, SpawnEntry, SpawnRange, GenerationConfig}

    // ════════════════════════════════════════════════════════
    // フィクスチャ
    // ════════════════════════════════════════════════════════

    /// 1 フロア (f01) 分のサンプル。monsters / items を 1 件ずつ持つ最小構成。
    def sampleFloor(): FloorResource = {
        label           = "1F",
        generation      = ({roomCount = 5}: GenerationConfig),
        monsters        = ({id = "goblin", percent = 70}: SpawnEntry) :: Nil,
        items           = ({id = "noviceStaff", percent = 50}: SpawnEntry) :: Nil,
        monstersPerRoom = ({min = 1, max = 2}: SpawnRange),
        itemsPerRoom    = ({min = 0, max = 1}: SpawnRange)
    }

    // ════════════════════════════════════════════════════════
    // Saveable round-trip: 主要フィールドが戻る
    // ════════════════════════════════════════════════════════

    /// 1 件 (f01) の floor を catalog に詰めて Saveable.toJson → fromJson すると
    /// label / generation#roomCount / monsters 件数 / monstersPerRoom#max が戻る
    @Test
    def testCatalogRoundTripPreservesFloor(): Unit \ Assert =
        let container = CatalogContainer.CatalogContainer({
            containerKey = "floors",
            entries      = Map#{"f01" => sampleFloor()},
            meta         = (Map.empty(): Map[String, Json.JsonElement])
        });
        let catalog = FloorCatalog.FloorCatalog.FloorCatalog(container);
        let encoded = Saveable.toJson(catalog);
        let decoded: Option[FloorCatalog] = Saveable.fromJson(encoded);
        match decoded {
            case Some(restored) =>
                let floor = FloorCatalog.get("f01", restored);
                Assert.assertEq(
                    expected = ("1F", 5, 1, 2),
                    (floor#label,
                     floor#generation#roomCount,
                     List.length(floor#monsters),
                     floor#monstersPerRoom#max))
            case None => bug!("expected floor catalog round-trip to succeed")
        }

    // ════════════════════════════════════════════════════════
    // フロア進行順 (order) — firstFloorId / nextFloorId
    // ════════════════════════════════════════════════════════

    /// 本番 floors.json の "order" 配列 (f01..f10) を実際にロードして、
    /// 先頭フロアと「次フロア」の遷移（最終フロア f10 の次は None = クリア）を固定する。
    /// load() は schema 整合性検査も通るので、order 追加が既存の検査を壊していないことも兼ねる。
    @Test
    def testFloorOrderProgression(): Unit \ {Assert, Fs.FileRead} =
        let catalog = FloorCatalog.load();
        Assert.assertEq(
            expected = ("f01", Some("f02"), Some("f10"), None),
            (FloorCatalog.firstFloorId(catalog),
             FloorCatalog.nextFloorId("f01", catalog),
             FloorCatalog.nextFloorId("f09", catalog),
             FloorCatalog.nextFloorId("f10", catalog)))

    // ════════════════════════════════════════════════════════
    // pickWeighted の境界
    // ════════════════════════════════════════════════════════

    /// 空配列を渡すと None (Math.Random は呼ばれない)
    @Test
    def testPickWeightedReturnsNoneForEmpty(): Unit \ {Assert, Math.Random} =
        Assert.assertEq(expected = None, FloorCatalog.pickWeighted((Nil: List[SpawnEntry])))

    /// 合計 percent <= 0 (全部 0) なら None
    @Test
    def testPickWeightedReturnsNoneForZeroSum(): Unit \ {Assert, Math.Random} =
        let entries = ({id = "a", percent = 0}: SpawnEntry) ::
                       ({id = "b", percent = 0}: SpawnEntry) :: Nil;
        Assert.assertEq(expected = None, FloorCatalog.pickWeighted(entries))

    /// 1 件だけのエントリは必ずその id を返す (randomFloat64 の値に依存しない)
    @Test
    def testPickWeightedSingleEntryAlwaysReturnsIt(): Unit \ {Assert, Math.Random} =
        let entries = ({id = "goblin", percent = 100}: SpawnEntry) :: Nil;
        Assert.assertEq(expected = Some("goblin"), FloorCatalog.pickWeighted(entries))

    // ════════════════════════════════════════════════════════
    // randomCountInRange の境界 (defensive fallback)
    // ════════════════════════════════════════════════════════

    /// max < min の不正な範囲では min を返す (panic ではなく defensive fallback)
    @Test
    def testRandomCountInRangeMaxLessThanMinReturnsMin(): Unit \ {Assert, Math.Random} =
        let badRange = ({min = 5, max = 2}: SpawnRange);
        Assert.assertEq(expected = 5, FloorCatalog.randomCountInRange(badRange))

    /// min == max なら必ずその値を返す (range 幅 1)
    @Test
    def testRandomCountInRangeWhenMinEqualsMaxReturnsThat(): Unit \ {Assert, Math.Random} =
        let singleRange = ({min = 3, max = 3}: SpawnRange);
        Assert.assertEq(expected = 3, FloorCatalog.randomCountInRange(singleRange))
}
