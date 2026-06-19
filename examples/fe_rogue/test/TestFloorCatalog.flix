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

    /// 1 フロア (f01) 分のサンプル。monsters / items / マッププールを 1〜2 件持つ最小構成。
    def sampleFloor(): FloorResource = {
        label           = "1F",
        name            = "始まりの洞窟",
        generation      = ({roomCount = 5}: GenerationConfig),
        monsters        = ({id = "goblin", percent = 70}: SpawnEntry) :: Nil,
        items           = ({id = "noviceStaff", percent = 50}: SpawnEntry) :: Nil,
        monstersPerRoom = ({min = 1, max = 2}: SpawnRange),
        itemsPerRoom    = ({min = 0, max = 1}: SpawnRange),
        roomMaps        = ({id = "room_1", percent = 60}: SpawnEntry) ::
                          ({id = "room_2", percent = 40}: SpawnEntry) :: Nil,
        horizontalMaps  = ({id = "pathway_horizontal_1", percent = 100}: SpawnEntry) :: Nil,
        verticalMaps    = ({id = "pathway_vertical_1", percent = 100}: SpawnEntry) :: Nil,
        chests          = ({id = "wooden", percent = 100}: SpawnEntry) :: Nil,
        chestsPerFloor  = ({min = 0, max = 1}: SpawnRange)
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
            meta         = (Map.empty(): Map[String, Util.Json.Json])
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

    /// マッププール (roomMaps/horizontalMaps/verticalMaps) も round-trip で保たれる。
    /// 件数と先頭 roomMaps の (id, percent) を固定する。
    @Test
    def testCatalogRoundTripPreservesMapPools(): Unit \ Assert =
        let container = CatalogContainer.CatalogContainer({
            containerKey = "floors",
            entries      = Map#{"f01" => sampleFloor()},
            meta         = (Map.empty(): Map[String, Util.Json.Json])
        });
        let catalog = FloorCatalog.FloorCatalog.FloorCatalog(container);
        let encoded = Saveable.toJson(catalog);
        let decoded: Option[FloorCatalog] = Saveable.fromJson(encoded);
        match decoded {
            case Some(restored) =>
                let floor = FloorCatalog.get("f01", restored);
                let firstRoom = List.head(floor#roomMaps);
                Assert.assertEq(
                    expected = (2, 1, 1, Some(("room_1", 60))),
                    (List.length(floor#roomMaps),
                     List.length(floor#horizontalMaps),
                     List.length(floor#verticalMaps),
                     Option.map(e -> (e#id, e#percent), firstRoom)))
            case None => bug!("expected map-pool round-trip to succeed")
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

    // ════════════════════════════════════════════════════════
    // 後方互換: chests を持たない旧形式 floor JSON もデコードできる
    // ════════════════════════════════════════════════════════

    /// chests / chestsPerFloor を持たない（宝箱導入前の）floor JSON。
    def legacyFloorJson(): String = String.unlines(
        "{" ::
        "  \"label\": \"1F\"," ::
        "  \"generation\": { \"roomCount\": 2 }," ::
        "  \"monsters\": [{\"id\": \"goblin\", \"percent\": 100}]," ::
        "  \"items\": [{\"id\": \"iron_sword\", \"percent\": 100}]," ::
        "  \"monstersPerRoom\": { \"min\": 1, \"max\": 2 }," ::
        "  \"itemsPerRoom\": { \"min\": 0, \"max\": 1 }" ::
        "}" :: Nil)

    /// chests キーが無くてもデコードに成功し、chests=空 / chestsPerFloor={0,0} に既定化される
    /// （= 既存 floors.json を壊さない後方互換の担保）。
    @Test
    def testDecodeFloorWithoutChestsDefaultsEmpty(): Unit \ Assert =
        let decoded = JsonCompat.parse(legacyFloorJson())
            |> Option.flatMap(FloorCatalogCodec.decodeFloor)
            |> Option.map(f -> (List.length(f#chests), f#chestsPerFloor#min, f#chestsPerFloor#max));
        Assert.assertEq(expected = Some((0, 0, 0)), decoded)
}
