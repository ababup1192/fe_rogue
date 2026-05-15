// UnitCatalog の Saveable[UnitCatalog] が実 units.json と同じ JSON 文字列を
// パース→デコードできるか検証するテスト。ファイル I/O は介さず、文字列リテラル
// を直接 Json.Parse.parse → Saveable.fromJson するだけ。

mod TestUnitCatalog {

    /// units.json と同じ構造の JSON 文字列リテラル
    def sampleJson(): String = String.unlines(
        "{" ::
        "  \"units\": {" ::
        "    \"knight\": {" ::
        "      \"moveTiles\": 4," ::
        "      \"hp\": 14," ::
        "      \"attack\":  6," ::
        "      \"defense\": 5," ::
        "      \"speed\":   2," ::
        "      \"sprite\": { \"texture\": \"character_sheet\", \"hframes\": 5, \"vframes\": 2, \"frame\": 0 }" ::
        "    }," ::
        "    \"goblin\": {" ::
        "      \"moveTiles\": 3," ::
        "      \"hp\": 3," ::
        "      \"attack\":  3," ::
        "      \"defense\": 1," ::
        "      \"speed\":   4," ::
        "      \"sprite\": { \"texture\": \"character_sheet\", \"hframes\": 5, \"vframes\": 2, \"frame\": 4 }" ::
        "    }" ::
        "  }," ::
        "  \"pools\": {" ::
        "    \"party\": [\"knight\"]," ::
        "    \"enemyTier1\": [\"goblin\"]" ::
        "  }" ::
        "}" :: Nil)

    /// パース→デコード成功 + units / pools の key 集合が期待通り
    @Test
    def testDecodeSampleCatalog(): Unit \ Assert =
        let parsed: Option[Json.JsonElement] = Json.Parse.parse(sampleJson());
        let decoded: Option[UnitCatalog.UnitCatalog] =
            Option.flatMap(Saveable.fromJson, parsed);
        let unitKeys = match decoded {
            case Some(c) => Map.keysOf(UnitCatalog.unitsOf(c))
            case None    => Set.empty()
        };
        let poolKeys = match decoded {
            case Some(c) => Map.keysOf(UnitCatalog.poolsOf(c))
            case None    => Set.empty()
        };
        Assert.assertEq(
            expected = (true, Set#{"knight", "goblin"}, Set#{"party", "enemyTier1"}),
            (Option.nonEmpty(decoded), unitKeys, poolKeys))

    /// pool 取得が期待通りに UnitResource を返す
    @Test
    def testPoolLookup(): Unit \ Assert =
        let parsed: Option[Json.JsonElement] = Json.Parse.parse(sampleJson());
        let decoded: Option[UnitCatalog.UnitCatalog] =
            Option.flatMap(Saveable.fromJson, parsed);
        match decoded {
            case None    => Assert.assertEq(expected = "decoded", "none")
            case Some(c) =>
                let party = UnitCatalog.pool("party", c);
                let knight = List.head(party);
                let hp = match knight {
                    case Some(u) => u#hp
                    case None    => -1
                };
                Assert.assertEq(expected = (1, 14), (List.length(party), hp))
        }
}
