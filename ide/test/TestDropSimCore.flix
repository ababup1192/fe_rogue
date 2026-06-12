// DropSimCore の純ロジック検証。
//
// IDE が再実装したドロップ抽選が fe_rogue の FloorCatalog/ItemScene/ChestScene と
// 同じ振る舞いをすること（パリティ）と、N 回集計が正しいことを固定する。
// 抽選は Math.Random を使うので RNG 依存テストは `\ {Assert, Math.Random}`、
// パース/構造テストは `\ Assert`。統計テストは緩い許容で flaky を避ける。
mod TestDropSimCore {

    use Util.Json.Json.{JObject, JArray, JString}

    // ─── フィクスチャ ────────────────────────────────────────────────

    def entryJson(id: String, pct: Int32): Util.Json.Json =
        JObject(Map#{"id" => JString(id), "percent" => NodeInspector.intToJson(pct)})

    def rangeJson(mn: Int32, mx: Int32): Util.Json.Json =
        JObject(Map#{"min" => NodeInspector.intToJson(mn), "max" => NodeInspector.intToJson(mx)})

    /// roomCount / itemsPerRoom / items / chests を指定してフロア record を作る。
    def floorJson(roomCount: Int32, iprMin: Int32, iprMax: Int32,
                   items: Vector[Util.Json.Json], chests: Vector[Util.Json.Json]): Util.Json.Json =
        JObject(Map#{
            "generation"     => JObject(Map#{"roomCount" => NodeInspector.intToJson(roomCount)}),
            "itemsPerRoom"   => rangeJson(iprMin, iprMax),
            "items"          => JArray(items),
            "chests"         => JArray(chests),
            "chestsPerFloor" => rangeJson(1, 1)
        })

    // ─── パース ──────────────────────────────────────────────────────

    /// generation.roomCount=5 → 対象部屋 = 5-1 = 4（anchor 除外）。
    @Test
    def testParseFloorTargetRooms(): Unit \ Assert =
        let floor = DropSimCore.parseFloor(floorJson(5, 2, 3, Vector#{entryJson("a", 10)}, Vector#{}));
        Assert.assertEq(expected = 4, floor#targetRooms)

    /// roomCount=1 → 対象部屋 0（床ドロップなし、負にしない）。
    @Test
    def testParseFloorTargetRoomsClampZero(): Unit \ Assert =
        let floor = DropSimCore.parseFloor(floorJson(1, 2, 3, Vector#{entryJson("a", 10)}, Vector#{}));
        Assert.assertEq(expected = 0, floor#targetRooms)

    /// items 配列が id/percent に正しくパースされ Σpercent が出る。
    @Test
    def testParseEntriesSum(): Unit \ Assert =
        let es = DropSimCore.parseEntries(Some(JArray(Vector#{entryJson("a", 12), entryJson("b", 8)})));
        Assert.assertEq(expected = (2, 20), (List.length(es), List.foldLeft((acc, e) -> acc + e#percent, 0, es)))

    // ─── 抽選（FloorCatalog パリティ） ──────────────────────────────────

    /// 1 件だけなら必ずその id（乱数値に依らず）。
    @Test
    def testPickWeightedSingle(): Unit \ {Assert, Math.Random} =
        Assert.assertEq(expected = Some("only"),
            DropSimCore.pickWeighted(({id = "only", percent = 7}: DropSimCore.Entry) :: Nil))

    /// 空 / 合計 percent<=0 は None（FloorCatalog.pickWeighted と同じ境界）。
    @Test
    def testPickWeightedEmptyAndZero(): Unit \ {Assert, Math.Random} =
        let empty = DropSimCore.pickWeighted((Nil: List[DropSimCore.Entry]));
        let zero  = DropSimCore.pickWeighted(({id = "x", percent = 0}: DropSimCore.Entry) :: Nil);
        Assert.assertEq(expected = (None, None), (empty, zero))

    /// min==max なら必ずその値。max<min は min（defensive、FloorCatalog と同じ）。
    @Test
    def testRandomCountInRangeBoundaries(): Unit \ {Assert, Math.Random} =
        let fixed = DropSimCore.randomCountInRange({min = 2, max = 2});
        let bad   = DropSimCore.randomCountInRange({min = 5, max = 3});
        Assert.assertEq(expected = (2, 5), (fixed, bad))

    // ─── 集計 ────────────────────────────────────────────────────────

    /// roomCount=3（対象2部屋）・itemsPerRoom{2,2}・items 単一 "a"・chests なし。
    /// 1 回回すと床ドロップは必ず 2部屋×2個=4 個すべて "a"。集計が一致する。
    @Test
    def testSimulateFloorDemand(): Unit \ {Assert, Math.Random} =
        let floor = floorJson(3, 2, 2, Vector#{entryJson("a", 100)}, Vector#{});
        let r = DropSimCore.simulate(floor, None, 1, 1);
        let aCount = Map.get("a", r#floorFreq) |> Option.getWithDefault(0);
        Assert.assertEq(
            expected = (4, 4, 1),
            (r#floorTotal, aCount, List.length(r#samples)))

    /// 相対重み（percent 合計≠100）が反映される: a:b = 1:9 なら b の出現が a を上回る。
    /// 大 N（targetRooms=1, itemsPerRoom{1,1}）で頻度の大小だけを緩く検証（flaky 回避）。
    @Test
    def testSimulateRelativeWeight(): Unit \ {Assert, Math.Random} =
        let floor = floorJson(2, 1, 1, Vector#{entryJson("a", 1), entryJson("b", 9)}, Vector#{});
        let r = DropSimCore.simulate(floor, None, 2000, 0);
        let a = Map.get("a", r#floorFreq) |> Option.getWithDefault(0);
        let b = Map.get("b", r#floorFreq) |> Option.getWithDefault(0);
        Assert.assertEq(expected = true, b > a)

    /// chests 非空フロアで、大 N の宝箱出現率が 0.33 の近傍（0.28〜0.38）。
    @Test
    def testSimulateChestSpawnRate(): Unit \ {Assert, Math.Random} =
        let floor = floorJson(3, 1, 1, Vector#{entryJson("a", 100)}, Vector#{entryJson("wooden", 100)});
        // chests.json が無くても種別抽選は floor#chests から、中身は空プール→中身なしだが
        // 「出現したか(chestSpawned)」は 0.33 判定だけで決まるので出現率は測れる。
        let r = DropSimCore.simulate(floor, None, 3000, 0);
        let rate = Int32.toFloat64(r#chestHits) / 3000.0;
        Assert.assertEq(expected = true, rate > 0.28 and rate < 0.38)

    /// idLabels はカタログ JSON の id→name を引く（`{weapons:{id:{name}}}`）。
    @Test
    def testIdLabels(): Unit \ Assert =
        let cat = JObject(Map#{"weapons" => JObject(Map#{
            "iron_lance" => JObject(Map#{"name" => JString("てつのやり")})})});
        let m = DropSimCore.idLabels(Some(cat), "weapons", "name");
        Assert.assertEq(expected = Some("てつのやり"), Map.get("iron_lance", m))

    /// formatResult はフロア id 見出しと主要セクションを含む（クラッシュせず整形できる）。
    @Test
    def testFormatResultStructure(): Unit \ {Assert, Math.Random} =
        let floor = floorJson(3, 2, 2, Vector#{entryJson("a", 100)}, Vector#{});
        let r = DropSimCore.simulate(floor, None, 10, 3);
        let text = DropSimCore.formatResult("f03", r, id -> id);
        Assert.assertEq(
            expected = (true, true),
            (String.contains(substr = "ドロップ試算: f03", text),
             String.contains(substr = "床アイテム別頻度", text)))
}
