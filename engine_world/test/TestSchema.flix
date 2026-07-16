/// 新方言スキーマ(Schema)の読み書きを検証する。
///
/// 観点:
///   - フル例(catalog / list / record の 3 セクション・全 type 形)のデコードと主要値の pin
///   - round-trip: toJson |> fromJson で同じ値に戻る(widget は原文保持)
///   - 厳格さ: 未知の type タグ・未知の kind・未知の object 形は Err(位置がわかる文面)
///   - widget は不透明 Json: 文字列 / object / 配列の何でも通り、そのまま保持される
///   - required / default / min / max / step の有無両方と "//" 注釈キーの読み飛ばし
///   - checkSection: 一致 → Ok / 欠け → Err / 余分 → Err
mod TestSchema {

    use Util.Json.Json
    use Util.Json.Json.{JObject, JString, JNumber, JBool, JArray}
    use Schema.SectionKind

    // ════════════════════════════════════════════════════════
    // fixture: 仕様書のフル例(+ "//" 注釈キー)
    // ════════════════════════════════════════════════════════

    /// 3 セクション・全 type 形を含むスキーマ JSON。sections と fields に "//" 注釈キーを混ぜる
    def fullSchemaJson(): String = String.unlines(
        "{" ::
        "  \"version\": 1," ::
        "  \"sections\": {" ::
        "    \"//memo\": \"sections 直下の注釈は読み飛ばされる\"," ::
        "    \"routes\": { \"kind\": \"catalog\", \"fields\": {" ::
        "      \"speed\": { \"type\": \"float\", \"label\": \"速さ\", \"order\": 1," ::
        "                 \"min\": 0, \"max\": 150, \"widget\": \"slider\" }" ::
        "    }}," ::
        "    \"spawns\": { \"kind\": \"list\", \"fields\": {" ::
        "      \"//memo\": \"fields 直下の注釈も読み飛ばされる\"," ::
        "      \"kind\":  { \"type\": {\"enum\": [\"popcorn\",\"turret\",\"dome\"]}, \"widget\": \"segmented\" }," ::
        "      \"route\": { \"type\": {\"ref\": \"routes\"}, \"required\": true }," ::
        "      \"hp\":    { \"type\": \"int\", \"default\": 3 }," ::
        "      \"spells\": { \"type\": {\"list\": {\"ref\": \"spells\"}} }," ::
        "      \"sprite\": { \"type\": {\"record\": { \"texture\": {\"type\": \"texture\"}, \"frame\": {\"type\": \"int\"} }} }," ::
        "      \"special\": { \"type\": {\"custom\": \"weaponProf\"} }" ::
        "    }}," ::
        "    \"meta\": { \"kind\": \"record\", \"fields\": { \"scrollSpeed\": {\"type\": \"float\"} } }" ::
        "  }" ::
        "}" :: Nil)

    /// フル例をデコードした結果
    def decodedFull(): Result[String, Schema.Schema] =
        decodeText(fullSchemaJson())

    /// スキーマ JSON 文字列を parse + fromJson に通す
    def decodeText(text: String): Result[String, Schema.Schema] =
        JsonCompat.parse(text)
            |> Option.toOk("JSON parse failed")
            |> Result.flatMap(Schema.fromJson)

    /// デコード結果からフィールド宣言 1 個を引く
    def fieldOf(sectionKey: String, fieldKey: String, decoded: Result[String, Schema.Schema]):
            Option[Schema.Field] =
        decoded
            |> Result.toOption
            |> Option.flatMap(schema -> Map.get(sectionKey, schema#sections))
            |> Option.flatMap(section -> Map.get(fieldKey, section#fields))

    /// Err の文面を取り出す(Ok のときは空文字。テストは文面の部分一致で判定する)
    def errText(decoded: Result[String, Schema.Schema]): String =
        match decoded {
            case Err(message) => message
            case Ok(_)        => ""
        }

    // ════════════════════════════════════════════════════════
    // フル例のデコード: セクション構成と主要値の pin
    // ════════════════════════════════════════════════════════

    /// フル例が Ok になり、version と 3 セクションのキー・kind が仕様どおり
    /// ("//memo" は sections から読み飛ばされる)
    @Test
    def testFullExampleSectionsAndKinds(): Unit \ Assert =
        let got = decodedFull() |> Result.toOption |> Option.map(schema -> (
            schema#version,
            Map.keysOf(schema#sections),
            Map.get("routes", schema#sections) |> Option.map(section -> section#kind),
            Map.get("spawns", schema#sections) |> Option.map(section -> section#kind),
            Map.get("meta", schema#sections)   |> Option.map(section -> section#kind)));
        Assert.assertEq(
            expected = Some((
                1,
                Set#{"routes", "spawns", "meta"},
                Some(SectionKind.Catalog),
                Some(SectionKind.RecordList),
                Some(SectionKind.Record))),
            got)

    /// routes.speed の表示メタと制約: label / order / min / max が入り、required は既定 false、
    /// widget は文字列 "slider" が原文のまま保持される
    @Test
    def testSpeedFieldMetaAndConstraints(): Unit \ Assert =
        let got = fieldOf("routes", "speed", decodedFull()) |> Option.map(field ->
            (field#label, field#order, field#min, field#max, field#required, field#widget));
        Assert.assertEq(
            expected = Some((Some("速さ"), Some(1), Some(0.0), Some(150.0), false,
                             Some(JString("slider")))),
            got)

    /// spawns の各フィールドの type が全 object 形(enum / ref / list / record / custom)と
    /// 文字列タグ(int)に正しく読める(typeToJson で JSON 表現に戻して比較)
    @Test
    def testSpawnsFieldTypes(): Unit \ Assert =
        let typeJsonOf = key ->
            fieldOf("spawns", key, decodedFull())
                |> Option.map(field -> Schema.typeToJson(field#fieldType));
        let got = List.map(typeJsonOf, "kind" :: "route" :: "hp" :: "spells" :: "special" :: Nil);
        Assert.assertEq(
            expected =
                Some(JObject(Map#{"enum" => JArray(Vector#{
                    JString("popcorn"), JString("turret"), JString("dome")})})) ::
                Some(JObject(Map#{"ref" => JString("routes")})) ::
                Some(JString("int")) ::
                Some(JObject(Map#{"list" => JObject(Map#{"ref" => JString("spells")})})) ::
                Some(JObject(Map#{"custom" => JString("weaponProf")})) :: Nil,
            got)

    /// spawns.sprite の入れ子 record type: 中の texture / frame まで宣言として読める
    @Test
    def testSpriteRecordType(): Unit \ Assert =
        let got = fieldOf("spawns", "sprite", decodedFull())
            |> Option.map(field -> Schema.typeToJson(field#fieldType));
        Assert.assertEq(
            expected = Some(JObject(Map#{"record" => JObject(Map#{
                "texture" => JObject(Map#{"type" => JString("texture")}),
                "frame"   => JObject(Map#{"type" => JString("int")})})})),
            got)

    /// required / default の有無両方: hp は required 省略 → false・default 3 保持、
    /// route は required true・default なし
    @Test
    def testRequiredAndDefaultPresence(): Unit \ Assert =
        let pick = key -> fieldOf("spawns", key, decodedFull())
            |> Option.map(field -> (field#required, field#default));
        Assert.assertEq(
            expected = (Some((false, Some(JNumber(JsonCodec.intToBd(3))))),
                        Some((true, None))),
            (pick("hp"), pick("route")))

    /// 制約なしのフィールド(meta.scrollSpeed)は min / max / step / label / order が全部 None
    @Test
    def testConstraintsAbsentAreNone(): Unit \ Assert =
        let got = fieldOf("meta", "scrollSpeed", decodedFull()) |> Option.map(field ->
            (field#min, field#max, field#step, field#label, field#order));
        Assert.assertEq(
            expected = Some((None, None, None, None, None)),
            got)

    /// fields 内の "//" キーは注釈として読み飛ばされ、フィールドにならない
    @Test
    def testNoteKeysAreSkippedInFields(): Unit \ Assert =
        let got = decodedFull()
            |> Result.toOption
            |> Option.flatMap(schema -> Map.get("spawns", schema#sections))
            |> Option.map(section -> Map.keysOf(section#fields));
        Assert.assertEq(
            expected = Some(Set#{"kind", "route", "hp", "spells", "sprite", "special"}),
            got)

    // ════════════════════════════════════════════════════════
    // round-trip: toJson |> fromJson で同じ値に戻る
    // ════════════════════════════════════════════════════════

    /// フル例(全 type 形 + widget + 制約)が toJson |> fromJson で同じ JSON に戻る
    @Test
    def testRoundTripFullExample(): Unit \ Assert =
        let once  = decodedFull();
        let twice = once |> Result.map(Schema.toJson) |> Result.flatMap(Schema.fromJson);
        Assert.assertEq(
            expected = (true, prettyOf(once)),
            (Result.isOk(twice), prettyOf(twice)))

    /// object の widget(エディタ独自の入れ子設定)も round-trip で原文どおり残る
    @Test
    def testRoundTripKeepsOpaqueObjectWidget(): Unit \ Assert =
        let once  = decodeText(objectWidgetSchemaJson());
        let twice = once |> Result.map(Schema.toJson) |> Result.flatMap(Schema.fromJson);
        let widget = fieldOf("stats", "hp", twice) |> Option.flatMap(field -> field#widget);
        Assert.assertEq(
            expected = (prettyOf(once),
                        Some(JObject(Map#{
                            "slider" => JObject(Map#{
                                "min" => JNumber(JsonCodec.intToBd(0)),
                                "max" => JNumber(JsonCodec.intToBd(10))}),
                            "unit"   => JString("px")}))),
            (prettyOf(twice), widget))

    /// デコード結果を整形 JSON にする(round-trip の比較用。Err のときは文面)
    def prettyOf(decoded: Result[String, Schema.Schema]): String =
        decoded
            |> Result.map(schema -> Util.Json.toPrettyString(2, Schema.toJson(schema)))
            |> Result.getWithDefault("(decode failed: ${errText(decoded)})")

    /// widget に object を入れた 1 セクションのスキーマ JSON
    def objectWidgetSchemaJson(): String = String.unlines(
        "{ \"sections\": { \"stats\": { \"kind\": \"record\", \"fields\": {" ::
        "  \"hp\": { \"type\": \"int\", \"widget\": { \"slider\": { \"min\": 0, \"max\": 10 }, \"unit\": \"px\" } }" ::
        "}}}}" :: Nil)

    // ════════════════════════════════════════════════════════
    // widget は不透明 Json: 何でも通ってそのまま保持される
    // ════════════════════════════════════════════════════════

    /// widget は文字列・object・配列のどれでも通り、そのままの Json で保持される
    @Test
    def testWidgetAcceptsAnyJsonShape(): Unit \ Assert =
        let decoded = decodeText(String.unlines(
            "{ \"sections\": { \"s\": { \"kind\": \"record\", \"fields\": {" ::
            "  \"a\": { \"type\": \"int\", \"widget\": \"plain\" }," ::
            "  \"b\": { \"type\": \"int\", \"widget\": { \"kind\": \"dial\" } }," ::
            "  \"c\": { \"type\": \"int\", \"widget\": [\"red\", \"blue\"] }" ::
            "}}}}" :: Nil));
        let widgetOf = key -> fieldOf("s", key, decoded) |> Option.flatMap(field -> field#widget);
        Assert.assertEq(
            expected = (Some(JString("plain")),
                        Some(JObject(Map#{"kind" => JString("dial")})),
                        Some(JArray(Vector#{JString("red"), JString("blue")}))),
            (widgetOf("a"), widgetOf("b"), widgetOf("c")))

    // ════════════════════════════════════════════════════════
    // 厳格さ: 未知の綴り・形は位置つきの Err
    // ════════════════════════════════════════════════════════

    /// 未知の type タグ("flaot")は Err になり、文面にフィールドの位置と綴りが入る
    @Test
    def testUnknownTypeTagIsErrWithFieldName(): Unit \ Assert =
        let decoded = decodeText(String.unlines(
            "{ \"sections\": { \"stats\": { \"kind\": \"record\", \"fields\": {" ::
            "  \"hp\": { \"type\": \"flaot\" }" ::
            "}}}}" :: Nil));
        let message = errText(decoded);
        Assert.assertEq(
            expected = (true, true, true),
            (Result.isErr(decoded),
             String.contains(substr = "stats.hp", message),
             String.contains(substr = "flaot", message)))

    /// 未知の object 形の type({"reff": ...})も Err になり、文面に位置と綴りが入る
    @Test
    def testUnknownTypeShapeIsErr(): Unit \ Assert =
        let decoded = decodeText(String.unlines(
            "{ \"sections\": { \"spawns\": { \"kind\": \"list\", \"fields\": {" ::
            "  \"route\": { \"type\": { \"reff\": \"routes\" } }" ::
            "}}}}" :: Nil));
        let message = errText(decoded);
        Assert.assertEq(
            expected = (true, true, true),
            (Result.isErr(decoded),
             String.contains(substr = "spawns.route", message),
             String.contains(substr = "reff", message)))

    /// 未知の kind("catalogue")は Err になり、文面にセクション名と綴りが入る
    @Test
    def testUnknownKindIsErr(): Unit \ Assert =
        let decoded = decodeText(String.unlines(
            "{ \"sections\": { \"routes\": { \"kind\": \"catalogue\", \"fields\": {} } } }" :: Nil));
        let message = errText(decoded);
        Assert.assertEq(
            expected = (true, true, true),
            (Result.isErr(decoded),
             String.contains(substr = "routes", message),
             String.contains(substr = "catalogue", message)))

    // ════════════════════════════════════════════════════════
    // checkSection: ゲームの期待フィールド集合との突き合わせ
    // ════════════════════════════════════════════════════════

    /// checkSection をフル例に対して呼ぶ
    def checkFull(sectionKey: String, expected: Set[String]): Result[String, Unit] =
        decodedFull() |> Result.flatMap(schema ->
            Schema.checkSection(sectionKey, expected, schema))

    /// 期待とスキーマが一致すれば Ok
    @Test
    def testCheckSectionMatchIsOk(): Unit \ Assert =
        Assert.assertEq(
            expected = Ok(()),
            checkFull("spawns", Set#{"kind", "route", "hp", "spells", "sprite", "special"}))

    /// ゲームが期待するのにスキーマに無いフィールドは Err(「無い」と名前が文面に入る)
    @Test
    def testCheckSectionMissingIsErr(): Unit \ Assert =
        let result = checkFull("routes", Set#{"speed", "power"});
        let message = match result { case Err(m) => m case Ok(_) => "" };
        Assert.assertEq(
            expected = (true, true, true),
            (Result.isErr(result),
             String.contains(substr = "無い", message),
             String.contains(substr = "power", message)))

    /// スキーマにあるのにゲームが期待しないフィールドは Err(「余分」と名前が文面に入る)
    @Test
    def testCheckSectionExtraIsErr(): Unit \ Assert =
        let result = checkFull("routes", Set.empty());
        let message = match result { case Err(m) => m case Ok(_) => "" };
        Assert.assertEq(
            expected = (true, true, true),
            (Result.isErr(result),
             String.contains(substr = "余分", message),
             String.contains(substr = "speed", message)))

    /// 無いセクション名を聞くと Err(セクション名が文面に入る)
    @Test
    def testCheckSectionUnknownSectionIsErr(): Unit \ Assert =
        let result = checkFull("enemies", Set#{"hp"});
        let message = match result { case Err(m) => m case Ok(_) => "" };
        Assert.assertEq(
            expected = (true, true),
            (Result.isErr(result), String.contains(substr = "enemies", message)))
}
