// Tests for SceneSerializer の JsonOrdered 経由書き戻し
//
// 防御テスト: editor の save → JSON 書き戻し時に
//   - キー出現順が保持される
//   - 配列 inline スタイルが保持される
//   - 末尾改行が付与される
//   - ノード名集合が変わらない
// を保証する

mod TestSceneSerializer {

    // ====================================================================
    // JsonOrdered.parse → writePretty の round-trip 性
    // ====================================================================

    /// 単純な object の parse → writePretty で同じ出力（末尾改行付き）
    @Test
    def testRoundTripSimpleObject(): Unit \ Assert =
        let original = "{\"type\": \"Sprite2D\", \"name\": \"hero\"}";
        let result = JsonOrdered.parse(original) |> Result.map(j ->
            JsonOrdered.writePretty(2, j));
        Assert.assertEq(
            expected = Ok("{\n  \"type\": \"Sprite2D\",\n  \"name\": \"hero\"\n}\n"),
            result)

    /// inline 配列 ([0, 0]) は parse → write 後も 1 行のまま
    @Test
    def testRoundTripInlineArray(): Unit \ Assert =
        let original = "{\"pos\": [0, 0]}";
        let result = JsonOrdered.parse(original) |> Result.map(j ->
            JsonOrdered.writePretty(2, j));
        Assert.assertEq(
            expected = Ok("{\n  \"pos\": [0, 0]\n}\n"),
            result)

    /// block 配列（改行入り）は parse → write 後も block のまま
    @Test
    def testRoundTripBlockArray(): Unit \ Assert =
        let original = "{\"pos\": [\n  0,\n  0\n]}";
        let result = JsonOrdered.parse(original) |> Result.map(j ->
            JsonOrdered.writePretty(2, j));
        Assert.assertEq(
            expected = Ok("{\n  \"pos\": [\n    0,\n    0\n  ]\n}\n"),
            result)

    /// 末尾は必ず改行で終わる
    @Test
    def testWriteAddsTrailingNewline(): Unit \ Assert =
        let original = "{\"x\": 1}";
        let result = JsonOrdered.parse(original)
            |> Result.map(JsonOrdered.writePretty(2));
        let endsWithNewline = match result {
            case Ok(s) => String.endsWith(suffix = "\n", s)
            case Err(_) => false
        };
        Assert.assertEq(expected = Ok("{\n  \"x\": 1\n}\n"), result);
        Assert.assertEq(expected = true, endsWithNewline)

    // ====================================================================
    // キー順保持
    // ====================================================================

    /// type → name → pos の意味順が parse → write でも維持される
    /// （alphabetical sort されない）
    @Test
    def testKeyOrderPreserved(): Unit \ Assert =
        let original = "{\"type\": \"Sprite2D\", \"name\": \"x\", \"pos\": [0, 0]}";
        let result = JsonOrdered.parse(original) |> Result.map(j ->
            JsonOrdered.writePretty(2, j));
        Assert.assertEq(
            expected = Ok("{\n  \"type\": \"Sprite2D\",\n  \"name\": \"x\",\n  \"pos\": [0, 0]\n}\n"),
            result)

    /// ネストした children 配列内のキー順も維持
    @Test
    def testNestedKeyOrderPreserved(): Unit \ Assert =
        let original = "{\"name\": \"a\", \"children\": [{\"type\": \"Sprite2D\", \"name\": \"b\"}]}";
        let result = JsonOrdered.parse(original) |> Result.map(j ->
            JsonOrdered.writePretty(2, j));
        // type は b ノード内で先頭に来るはず
        let containsTypeBeforeName = match result {
            case Ok(s) =>
                let typeIdx = String.indexOf(substr = "\"type\"", s);
                let nameIdx = String.indexOf(substr = "\"name\": \"b\"", s);
                match (typeIdx, nameIdx) {
                    case (Some(t), Some(n)) => t < n
                    case _                  => false
                }
            case _ => false
        };
        Assert.assertEq(expected = true, containsTypeBeforeName)
}
