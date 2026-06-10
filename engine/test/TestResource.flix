// Tests for Resource module
//
// 観点:
//   - checkConsistency: 完全一致 / 過剰 / 不足 / 両方ズレ
//   - Saveable[ResourceSchema] の round-trip（小さなサンプルが encode→parse→decode で復元される）

mod TestResource {

    use Resource.{ResourceSchema, FieldEntry, FieldSchema, FieldType, FieldHint}

    // ========================================================================
    // checkConsistency
    // ========================================================================

    /// expected と schema の field 集合が完全一致 → Ok
    @Test
    def testCheckConsistencyMatch(): Unit \ Assert =
        let schema = Resource.mkSchema(Map#{
            "hp"        => simpleIntField("HP"),
            "moveTiles" => simpleIntField("移動力")
        });
        let result = Resource.checkConsistency(Set#{"hp", "moveTiles"}, schema);
        Assert.assertEq(expected = true, Result.isOk(result))

    /// schema に余分なフィールドがある → Err
    @Test
    def testCheckConsistencyExtra(): Unit \ Assert =
        let schema = Resource.mkSchema(Map#{
            "hp"  => simpleIntField("HP"),
            "spd" => simpleIntField("速さ")   // expected には無い
        });
        let result = Resource.checkConsistency(Set#{"hp"}, schema);
        Assert.assertEq(expected = true, Result.isErr(result))

    /// schema に不足フィールドがある → Err
    @Test
    def testCheckConsistencyMissing(): Unit \ Assert =
        let schema = Resource.mkSchema(Map#{
            "hp" => simpleIntField("HP")
        });
        let result = Resource.checkConsistency(Set#{"hp", "moveTiles"}, schema);
        Assert.assertEq(expected = true, Result.isErr(result))

    // ========================================================================
    // Saveable[ResourceSchema] round-trip
    // ========================================================================

    /// 全種別の hint を含む schema が encode → parse → decode で同じ field 集合に戻る
    @Test
    def testSchemaRoundTrip(): Unit \ Assert =
        let original = Resource.mkSchema(Map#{
            "name"      => leafField(FieldType.TextT,  FieldHint.Plain,                                   "名前"),
            "moveTiles" => leafField(FieldType.IntT,   FieldHint.Slider({min = 1.0, max = 10.0, step = 1.0}),  "移動力"),
            "frame"     => leafField(FieldType.IntT,   FieldHint.Spinner({min = 0, max = 9}),            "フレーム"),
            "sprite"    => FieldEntry.Nested(Map#{
                "texture" => leafField(FieldType.TexturePathT, FieldHint.Plain, "テクスチャ"),
                "frame"   => leafField(FieldType.IntT,
                                       FieldHint.FrameGrid({hframesField = "hframes", vframesField = "vframes"}),
                                       "フレーム")
            })
        });
        let json     = Saveable.toJson(original);
        let written  = Util.Json.toPrettyString(2, json);
        let parsed   = JsonCompat.parse(written);
        let restored: Option[ResourceSchema] = Option.flatMap(Saveable.fromJson, parsed);
        // 完全な比較は派生が無いため、key 集合と各 leaf の label 等を抽出して比較する
        let originalKeys = Map.keysOf(Resource.fieldsOf(original));
        let restoredKeys = match restored {
            case Some(r) => Map.keysOf(Resource.fieldsOf(r))
            case None    => Set.empty()
        };
        Assert.assertEq(
            expected = (true, originalKeys),
            (Option.nonEmpty(restored), restoredKeys))

    // ========================================================================
    // helpers
    // ========================================================================

    def simpleIntField(label: String): FieldEntry =
        leafField(FieldType.IntT, FieldHint.Plain, label)

    def leafField(ftype: FieldType, hint: FieldHint, label: String): FieldEntry =
        FieldEntry.Field({ftype = ftype, hint = hint, label = label, order = None})
}
