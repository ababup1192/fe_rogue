/// JsonCodec の汎用ヘルパが、各 catalog の Codec から取り出された後も
/// 同じ性質を満たすことを固定する。
///
/// 観点:
///   - 値の取り出し: 期待型なら Some、それ以外なら None
///   - BigDecimal 変換: 100 を「100」(「100.0」ではなく) として書き出す
///   - Map[String, T] / List[T] の round-trip: 元の値に戻る
///   - decode の全要素 or 全体 None ポリシー: 1 つでも壊れたら全体 None
mod TestJsonCodec {

    use Util.Json.Json
    use Util.Json.Json.{JObject, JString, JNumber, JBool, JArray}

    // ════════════════════════════════════════════════════════
    // 値の取り出し: 期待型なら Some、それ以外なら None
    // ════════════════════════════════════════════════════════

    /// JString に対して expectString は中身を取り出す
    @Test
    def testExpectStringReturnsSomeForJString(): Unit \ Assert =
        Assert.assertEq(expected = Some("hello"),
                          JsonCodec.expectString(JString("hello")))

    /// 整数や真偽値などの非文字列 Json は None を返す
    @Test
    def testExpectStringReturnsNoneForNonString(): Unit \ Assert =
        Assert.assertEq(expected = None,
                          JsonCodec.expectString(JNumber(JsonCodec.intToBd(42))))

    /// expectInt に JString を渡すと None になる (型不一致)。
    /// 仕様メモ: JNumber 100.5 を渡した場合は truncate されて Some(100) になる
    /// (BigDecimal -> Float64 -> Int32 の `Float64.tryToInt32` が truncate するため)。
    @Test
    def testExpectIntReturnsNoneForNonNumber(): Unit \ Assert =
        Assert.assertEq(expected = None,
                          JsonCodec.expectInt(JString("not a number")))

    /// expectInt は整数値 42 を Int32 として取り出す
    @Test
    def testExpectIntReturnsSomeForIntegralNumber(): Unit \ Assert =
        Assert.assertEq(expected = Some(42),
                          JsonCodec.expectInt(JNumber(JsonCodec.intToBd(42))))

    /// expectBool は JBool(true) から true を取り出す
    @Test
    def testExpectBoolReturnsSomeForJBool(): Unit \ Assert =
        Assert.assertEq(expected = Some(true),
                          JsonCodec.expectBool(JBool(true)))

    // ════════════════════════════════════════════════════════
    // BigDecimal 変換: trailing zero を除去して「100」と書き出す
    // ════════════════════════════════════════════════════════

    /// floatToBd(100.0) を文字列化すると "100" になる (小数点が消える)
    @Test
    def testFloatToBdStripsTrailingZero(): Unit \ Assert =
        Assert.assertEq(expected = "100",
                          ToString.toString(JsonCodec.floatToBd(100.0)))

    /// intToBd(100) も "100" として書き出される (Int -> Float -> BigDecimal の経路)
    @Test
    def testIntToBdStripsTrailingZero(): Unit \ Assert =
        Assert.assertEq(expected = "100",
                          ToString.toString(JsonCodec.intToBd(100)))

    // ════════════════════════════════════════════════════════
    // Map[String, T] round-trip: encode → decode で元の値に戻る
    // ════════════════════════════════════════════════════════

    /// {"a"=>10, "b"=>20} を encode → decode すると元の Map に戻る
    @Test
    def testStringMapRoundTrip(): Unit \ Assert =
        let original = Map#{"a" => 10, "b" => 20};
        let encoded = JsonCodec.encodeStringMap(
            n -> JNumber(JsonCodec.intToBd(n)), original);
        let decoded = JsonCodec.decodeStringMap(JsonCodec.expectInt, encoded);
        Assert.assertEq(expected = Some(original), decoded)

    /// 要素のひとつでも decode 失敗すると全体が None になる
    /// (schema 不整合を部分成功として隠さないための設計)
    @Test
    def testStringMapDecodeReturnsNoneIfAnyEntryFails(): Unit \ Assert =
        let mixed = JObject(Map#{
            "good" => JNumber(JsonCodec.intToBd(10)),
            "bad"  => JString("not a number")
        });
        Assert.assertEq(expected = None,
                          JsonCodec.decodeStringMap(JsonCodec.expectInt, mixed))

    // ════════════════════════════════════════════════════════
    // List[T] round-trip: 要素 1 つの失敗で全体 None
    // ════════════════════════════════════════════════════════

    /// [10, 20, 30] を encode → decode すると元のリストに戻る
    @Test
    def testListRoundTrip(): Unit \ Assert =
        let original = 10 :: 20 :: 30 :: Nil;
        let encoded = JsonCodec.encodeList(
            n -> JNumber(JsonCodec.intToBd(n)), original);
        let decoded = JsonCodec.decodeList(JsonCodec.expectInt, encoded);
        Assert.assertEq(expected = Some(original), decoded)

    /// 要素のひとつが壊れたリストは全体 None になる
    @Test
    def testListDecodeReturnsNoneIfAnyEntryFails(): Unit \ Assert =
        let mixed = JArray(Vector#{
            JNumber(JsonCodec.intToBd(10)),
            JString("not a number")
        });
        Assert.assertEq(expected = None,
                          JsonCodec.decodeList(JsonCodec.expectInt, mixed))

    // ════════════════════════════════════════════════════════
    // Vec2 round-trip: encode → decode で元の Vec2 に戻る
    // ════════════════════════════════════════════════════════

    /// {x=16.0, y=8.0} を encode → decode すると元の Vec2 (x, y) に戻る
    @Test
    def testVec2RoundTrip(): Unit \ Assert =
        let original: Vec2.Vec2 = {x = 16.0, y = 8.0};
        let decoded = JsonCodec.decodeVec2(JsonCodec.encodeVec2(original));
        Assert.assertEq(expected = Some((16.0, 8.0)),
                          Option.map(v -> (v#x, v#y), decoded))

    /// x が欠落した object は y だけ読み x を 0.0 で補完する
    @Test
    def testDecodeVec2FillsMissingXWithZero(): Unit \ Assert =
        let partial = JObject(Map#{"y" => JNumber(JsonCodec.floatToBd(8.0))});
        Assert.assertEq(expected = Some((0.0, 8.0)),
                          Option.map(v -> (v#x, v#y), JsonCodec.decodeVec2(partial)))

    /// None を渡すと defaultValue (1.0) で埋めた Vec2 を返す
    @Test
    def testDecodeVec2OrDefaultReturnsDefaultForNone(): Unit \ Assert =
        let result = JsonCodec.decodeVec2OrDefault(None, 1.0);
        Assert.assertEq(expected = (1.0, 1.0), (result#x, result#y))

    // ════════════════════════════════════════════════════════
    // fail-open ヘルパ: キーが無い・型が違えば黙って fallback
    // ════════════════════════════════════════════════════════

    /// floatOr: キーがあり数値なら中身、無ければ fallback、型違いでも fallback。
    @Test
    def testFloatOrReadsPresentKey(): Unit \ Assert =
        let obj = Map#{"speed" => JNumber(JsonCodec.floatToBd(2.5))};
        Assert.assertEq(expected = 2.5, JsonCodec.floatOr("speed", 9.0, obj))

    @Test
    def testFloatOrFallsBackWhenKeyMissing(): Unit \ Assert =
        Assert.assertEq(expected = 9.0, JsonCodec.floatOr("speed", 9.0, Map.empty()))

    @Test
    def testFloatOrFallsBackWhenTypeMismatches(): Unit \ Assert =
        let obj = Map#{"speed" => JString("fast")};
        Assert.assertEq(expected = 9.0, JsonCodec.floatOr("speed", 9.0, obj))

    /// intOr: キーがあり整数なら中身、無ければ fallback、型違いでも fallback。
    @Test
    def testIntOrReadsPresentKey(): Unit \ Assert =
        let obj = Map#{"count" => JNumber(JsonCodec.intToBd(3))};
        Assert.assertEq(expected = 3, JsonCodec.intOr("count", 7, obj))

    @Test
    def testIntOrFallsBackWhenKeyMissing(): Unit \ Assert =
        Assert.assertEq(expected = 7, JsonCodec.intOr("count", 7, Map.empty()))

    @Test
    def testIntOrFallsBackWhenTypeMismatches(): Unit \ Assert =
        let obj = Map#{"count" => JBool(true)};
        Assert.assertEq(expected = 7, JsonCodec.intOr("count", 7, obj))

    /// stringOr: キーがあり文字列なら中身、無ければ fallback、型違いでも fallback。
    @Test
    def testStringOrReadsPresentKey(): Unit \ Assert =
        let obj = Map#{"name" => JString("hero")};
        Assert.assertEq(expected = "hero", JsonCodec.stringOr("name", "unknown", obj))

    @Test
    def testStringOrFallsBackWhenKeyMissing(): Unit \ Assert =
        Assert.assertEq(expected = "unknown", JsonCodec.stringOr("name", "unknown", Map.empty()))

    @Test
    def testStringOrFallsBackWhenTypeMismatches(): Unit \ Assert =
        let obj = Map#{"name" => JNumber(JsonCodec.intToBd(1))};
        Assert.assertEq(expected = "unknown", JsonCodec.stringOr("name", "unknown", obj))

    /// boolOr: キーがあり真偽値なら中身、無ければ fallback、型違いでも fallback。
    @Test
    def testBoolOrReadsPresentKey(): Unit \ Assert =
        let obj = Map#{"enabled" => JBool(true)};
        Assert.assertEq(expected = true, JsonCodec.boolOr("enabled", false, obj))

    @Test
    def testBoolOrFallsBackWhenKeyMissing(): Unit \ Assert =
        Assert.assertEq(expected = false, JsonCodec.boolOr("enabled", false, Map.empty()))

    @Test
    def testBoolOrFallsBackWhenTypeMismatches(): Unit \ Assert =
        let obj = Map#{"enabled" => JString("yes")};
        Assert.assertEq(expected = false, JsonCodec.boolOr("enabled", false, obj))
}
