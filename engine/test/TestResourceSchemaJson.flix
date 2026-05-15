// fe_rogue が使う実際の _schema.json と同じ JSON 文字列を Saveable[ResourceSchema]
// で round-trip できるか検証する。本番ロード時の Option None の原因が
// 文字列 JSON 段階で再現するなら、ファイル I/O ではなく decoder のバグ。

mod TestResourceSchemaJson {

    /// fe_rogue/assets/units/_schema.json と同等の JSON 文字列
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

    /// Json.Parse.parse + Saveable.fromJson が成功し、トップレベル fields の
    /// key 集合が {moveTiles, hp, sprite} になる
    @Test
    def testDecodeRealSchemaJson(): Unit \ Assert =
        let parsed: Option[Json.JsonElement] = Json.Parse.parse(schemaJson());
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
}
