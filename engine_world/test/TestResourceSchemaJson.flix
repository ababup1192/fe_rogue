// 実際の _schema.json と同じ JSON 文字列を Saveable[ResourceSchema]
// で round-trip できるか検証する。本番ロード時の Option None の原因が
// 文字列 JSON 段階で再現するなら、ファイル I/O ではなく decoder のバグ。

mod TestResourceSchemaJson {

    /// units.schema.json と同等の JSON 文字列
    def schemaJson(): String = String.unlines(
        "{" ::
        "  \"fields\": {" ::
        "    \"moveTiles\": {" ::
        "      \"field\": {" ::
        "        \"ftype\": \"int\"," ::
        "        \"hint\":  { \"slider\": { \"min\": 1, \"max\": 10, \"step\": 1 } }," ::
        "        \"label\": \"移動力\"" ::
        "      }" ::
        "    }," ::
        "    \"hp\": {" ::
        "      \"field\": {" ::
        "        \"ftype\": \"int\"," ::
        "        \"hint\":  { \"slider\": { \"min\": 1, \"max\": 100, \"step\": 5 } }," ::
        "        \"label\": \"HP\"" ::
        "      }" ::
        "    }," ::
        "    \"sprite\": {" ::
        "      \"nested\": {" ::
        "        \"texture\": {" ::
        "          \"field\": {" ::
        "            \"ftype\": \"texturePath\"," ::
        "            \"hint\":  \"plain\"," ::
        "            \"label\": \"テクスチャ\"" ::
        "          }" ::
        "        }," ::
        "        \"hframes\": {" ::
        "          \"field\": {" ::
        "            \"ftype\": \"int\"," ::
        "            \"hint\":  { \"spinner\": { \"min\": 1, \"max\": 16 } }," ::
        "            \"label\": \"横分割\"" ::
        "          }" ::
        "        }," ::
        "        \"vframes\": {" ::
        "          \"field\": {" ::
        "            \"ftype\": \"int\"," ::
        "            \"hint\":  { \"spinner\": { \"min\": 1, \"max\": 16 } }," ::
        "            \"label\": \"縦分割\"" ::
        "          }" ::
        "        }," ::
        "        \"frame\": {" ::
        "          \"field\": {" ::
        "            \"ftype\": \"int\"," ::
        "            \"hint\":  { \"frameGrid\": { \"hframesField\": \"hframes\", \"vframesField\": \"vframes\" } }," ::
        "            \"label\": \"フレーム\"" ::
        "          }" ::
        "        }" ::
        "      }" ::
        "    }" ::
        "  }" ::
        "}" :: Nil)

    /// DocJson.parse + Saveable.fromJson が成功し、トップレベル fields の
    /// key 集合が {moveTiles, hp, sprite} になる
    @Test
    def testDecodeRealSchemaJson(): Unit \ Assert =
        let parsed: Option[Util.Json.Json] = DocJson.parse(schemaJson());
        let decoded: Option[Resource.ResourceSchema] =
            Option.flatMap(Saveable.fromJson, parsed);
        let parsedOk = Option.nonEmpty(parsed);
        let decodedOk = Option.nonEmpty(decoded);
        let topKeys = match decoded {
            case Some(s) => Map.keysOf(Resource.fieldsOf(s))
            case None    => Set.empty()
        };
        Assert.assertEq(
            expected = (true, true, Set#{"moveTiles", "hp", "sprite"}),
            (parsedOk, decodedOk, topKeys))

    /// metaHints セクションを含む schema JSON。
    /// players は units を参照する array、tags は自由文字列 array として明示する。
    def schemaJsonWithMeta(): String = String.unlines(
        "{" ::
        "  \"fields\": {" ::
        "    \"hp\": {" ::
        "      \"field\": {" ::
        "        \"ftype\": \"int\"," ::
        "        \"hint\":  { \"slider\": { \"min\": 1, \"max\": 100, \"step\": 5 } }," ::
        "        \"label\": \"HP\"" ::
        "      }" ::
        "    }" ::
        "  }," ::
        "  \"metaHints\": {" ::
        "    \"players\": { \"type\": \"ref\", \"to\": \"units\" }," ::
        "    \"tags\":    { \"type\": \"text\" }" ::
        "  }" ::
        "}" :: Nil)

    /// metaHints あり: fields に hp、metaHints に players/tags が decode される。
    @Test
    def testDecodeSchemaWithMetaHints(): Unit \ Assert =
        let parsed: Option[Util.Json.Json] = DocJson.parse(schemaJsonWithMeta());
        let decoded: Option[Resource.ResourceSchema] =
            Option.flatMap(Saveable.fromJson, parsed);
        let metaKeys = match decoded {
            case Some(s) => Map.keysOf(Resource.metaHintsOf(s))
            case None    => Set.empty()
        };
        let playersHint = match decoded {
            case Some(s) => Map.get("players", Resource.metaHintsOf(s))
            case None    => None
        };
        Assert.assertEq(
            expected = (true, Set#{"players", "tags"}, Some(Resource.MetaHint.Ref("units"))),
            (Option.nonEmpty(decoded), metaKeys, playersHint))

    /// round-trip: encode → parse → decode で同じ schema に戻る。
    @Test
    def testMetaHintsRoundTrip(): Unit \ Assert =
        let original = Resource.mkSchemaWithMeta(
            Map#{},
            Map#{
                "players" => Resource.MetaHint.Ref("units"),
                "tags"    => Resource.MetaHint.Text
            });
        let json = Saveable.toJson(original);
        let pretty = Util.Json.toPrettyString(2, json);
        let reparsed: Option[Resource.ResourceSchema] =
            DocJson.parse(pretty) |> Option.flatMap(Saveable.fromJson);
        let metaHints = match reparsed {
            case Some(s) => Resource.metaHintsOf(s)
            case None    => Map.empty()
        };
        Assert.assertEq(
            expected = Map#{
                "players" => Resource.MetaHint.Ref("units"),
                "tags"    => Resource.MetaHint.Text
            },
            metaHints)
}
