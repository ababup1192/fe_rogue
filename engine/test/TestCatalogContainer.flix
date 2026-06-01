/// CatalogContainer の汎用 encode / decode の性質を固定する。
/// `loadWithCheck` は `\ Fs.FileRead` を持つので別フィクスチャが要る (本ファイルでは扱わない)。
///
/// 観点:
///   - decode が containerKey 配下を entries、残りを meta に分離する
///   - decode で containerKey が無いと None
///   - encode / decode の round-trip で entries が戻り、meta 部分の key も保持される
///   - entry decode の 1 つでも失敗すると全体 None
///   - get が境界 (存在 / 不在) で正しく動く
///
/// 注: JsonElement / CatalogContainer は Eq / ToString を持たないので、
/// assertEq には Map / Set 等の比較可能な型に変換した値を渡す。
mod TestCatalogContainer {

    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonString, JsonNumber, JsonArray}

    // ════════════════════════════════════════════════════════
    // containerKey による entries / meta の分離
    // ════════════════════════════════════════════════════════

    /// `{"items": {"a": 10}, "extras": "tag"}` を containerKey="items" で decode すると
    /// entries={a => 10} に、meta は "extras" を含む形で分離される
    @Test
    def testDecodeSeparatesContainerAndMeta(): Unit \ Assert =
        let json = JsonObject(Map#{
            "items"  => JsonObject(Map#{"a" => JsonNumber(JsonCodec.intToBd(10))}),
            "extras" => JsonString("tag")
        });
        match CatalogContainer.decode("items", JsonCodec.expectInt, json) {
            case Some(container) =>
                let entries = CatalogContainer.entriesOf(container);
                let metaKeys = Map.keysOf(CatalogContainer.metaOf(container));
                Assert.assertEq(
                    expected = (Map#{"a" => 10}, Set#{"extras"}),
                    (entries, metaKeys))
            case None => bug!("expected container decode to succeed")
        }

    /// containerKey が JSON 上に無いと decode は None を返す
    @Test
    def testDecodeReturnsNoneWhenContainerKeyMissing(): Unit \ Assert =
        let json = JsonObject(Map#{"other" => JsonObject(Map.empty())});
        let decoded = CatalogContainer.decode("items", JsonCodec.expectInt, json);
        Assert.assertEq(expected = true, Option.isEmpty(decoded))

    // ════════════════════════════════════════════════════════
    // encode → decode round-trip: entries + meta keys が戻る
    // ════════════════════════════════════════════════════════

    /// entries={a=>10, b=>20} + meta={pool => JsonArray} を encode → decode すると
    /// entries は完全一致、meta の key 集合も維持される
    @Test
    def testRoundTripPreservesEntriesAndMetaKeys(): Unit \ Assert =
        let meta = Map#{
            "pool" => JsonArray(Vector#{JsonString("a"), JsonString("b")})
        };
        let original = CatalogContainer.CatalogContainer({
            containerKey = "items",
            entries      = Map#{"a" => 10, "b" => 20},
            meta         = meta
        });
        let encoded = CatalogContainer.encode(
            n -> JsonNumber(JsonCodec.intToBd(n)), original);
        let decoded = CatalogContainer.decode(
            "items", JsonCodec.expectInt, encoded);
        match decoded {
            case Some(container) =>
                let entries = CatalogContainer.entriesOf(container);
                let metaKeys = Map.keysOf(CatalogContainer.metaOf(container));
                Assert.assertEq(
                    expected = (Map#{"a" => 10, "b" => 20}, Set#{"pool"}),
                    (entries, metaKeys))
            case None => bug!("expected round-trip to succeed")
        }

    // ════════════════════════════════════════════════════════
    // entry decode 失敗の伝播
    // ════════════════════════════════════════════════════════

    /// entries の値のいずれかが decode 失敗すると全体 None になる
    /// (schema 不整合を部分成功として隠さないための設計)
    @Test
    def testDecodeFailsWhenAnyEntryFails(): Unit \ Assert =
        let json = JsonObject(Map#{
            "items" => JsonObject(Map#{
                "good" => JsonNumber(JsonCodec.intToBd(10)),
                "bad"  => JsonString("not int")
            })
        });
        let decoded = CatalogContainer.decode("items", JsonCodec.expectInt, json);
        Assert.assertEq(expected = true, Option.isEmpty(decoded))

    // ════════════════════════════════════════════════════════
    // get の境界
    // ════════════════════════════════════════════════════════

    /// 存在する id なら Some、未定義 id なら None
    @Test
    def testGetReturnsSomeForExistingAndNoneForMissing(): Unit \ Assert =
        let container = CatalogContainer.CatalogContainer({
            containerKey = "items",
            entries      = Map#{"existing" => 42},
            meta         = (Map.empty(): Map[String, JsonElement])
        });
        Assert.assertEq(
            expected = (Some(42), None),
            (CatalogContainer.get("existing", container),
             CatalogContainer.get("missing", container)))
}
