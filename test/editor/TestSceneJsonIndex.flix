// Tests for SceneJsonIndex — scene.json 群を走査して「ルート名 → ファイルパス」索引を作る
//
// `rootNamesOf` は純粋なので手作りの JsonElement で直接テストできる。
// `load()` は実在の `src/scenes/*.scene.json` を入力に取り、特定 root 名が
// 期待ファイルパスに紐付くか検証する

mod TestSceneJsonIndex {
    use Json.JsonElement.{JsonObject, JsonArray, JsonString, JsonNumber, JsonNull}

    // ====================================================================
    // rootNamesOf — 手作り JSON で純粋テスト
    // ====================================================================

    /// 単一 JsonObject に "name" があれば 1 件返す
    @Test
    def testRootNamesOfSingleObjectWithName(): Unit \ Assert =
        let json = JsonObject(Map#{"name" => JsonString("hero"), "type" => JsonString("Sprite2D")});
        let names = SceneJsonIndex.rootNamesOf(json);
        Assert.assertEq(expected = "hero" :: Nil, names)

    /// "name" がない JsonObject は空
    @Test
    def testRootNamesOfObjectWithoutName(): Unit \ Assert =
        let json = JsonObject(Map#{"type" => JsonString("Sprite2D")});
        let names = SceneJsonIndex.rootNamesOf(json);
        Assert.assertEq(expected = Nil, names)

    /// JsonArray の各要素から "name" を集める
    @Test
    def testRootNamesOfArrayCollectsAllNames(): Unit \ Assert =
        let elem1 = JsonObject(Map#{"name" => JsonString("a")});
        let elem2 = JsonObject(Map#{"name" => JsonString("b")});
        let elem3 = JsonObject(Map#{"name" => JsonString("c")});
        let json = JsonArray(Vector#{elem1, elem2, elem3});
        let names = SceneJsonIndex.rootNamesOf(json);
        Assert.assertEq(expected = "a" :: "b" :: "c" :: Nil, names)

    /// JsonArray に "name" 欠落要素が混ざっていても、ある分だけ拾う
    @Test
    def testRootNamesOfArraySkipsElementsWithoutName(): Unit \ Assert =
        let elem1 = JsonObject(Map#{"name" => JsonString("a")});
        let elem2 = JsonObject(Map#{"type" => JsonString("Sprite2D")});  // name 無し
        let elem3 = JsonObject(Map#{"name" => JsonString("c")});
        let json = JsonArray(Vector#{elem1, elem2, elem3});
        let names = SceneJsonIndex.rootNamesOf(json);
        Assert.assertEq(expected = "a" :: "c" :: Nil, names)

    /// JsonObject でも JsonArray でもない値は空
    @Test
    def testRootNamesOfNonContainer(): Unit \ Assert =
        Assert.assertEq(
            expected = (Nil, Nil, Nil),
            (SceneJsonIndex.rootNamesOf(JsonString("x")),
             SceneJsonIndex.rootNamesOf(JsonNumber(42.0ff)),
             SceneJsonIndex.rootNamesOf(JsonNull)))

    /// JsonObject の "name" が文字列でなければ無視
    @Test
    def testRootNamesOfNameMustBeString(): Unit \ Assert =
        let json = JsonObject(Map#{"name" => JsonNumber(123.0ff)});
        let names = SceneJsonIndex.rootNamesOf(json);
        Assert.assertEq(expected = Nil, names)

    // ====================================================================
    // load — 実在の scene.json を入力にした統合テスト
    // ====================================================================

    /// 未登録の root は None
    @Test
    def testLoadDoesNotIndexNonExistentRoot(): Unit \ {Assert, Fs.Glob, Fs.FileRead} =
        let index = SceneJsonIndex.load();
        Assert.assertEq(expected = None, Map.get("__never_used_root__", index))
}
