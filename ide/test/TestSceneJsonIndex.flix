// Tests for SceneJsonIndex — scene.json 群を走査して「ルート名 → ファイルパス」索引を作る
//
// `rootNamesOf` は純粋なので手作りの Json.JsonElement で直接テストできる。
// `load()` は実在の `src/scenes/*.scene.json` を入力に取り、特定 root 名が
// 期待ファイルパスに紐付くか検証する

mod TestSceneJsonIndex {

    /// editor 単独テスト用の最小 tag enum (NodeTag は consumer 側で定義される型)
    pub enum Tag { case NoTag }

    // ====================================================================
    // rootNamesOf — 手作り JSON で純粋テスト
    // ====================================================================

    /// 単一 Json.JsonElement.JsonObject に "name" があれば 1 件返す
    @Test
    def testRootNamesOfSingleObjectWithName(): Unit \ Assert =
        let json = Json.JsonElement.JsonObject(Map#{"name" => Json.JsonElement.JsonString("hero"), "type" => Json.JsonElement.JsonString("Sprite2D")});
        let names = SceneJsonIndex.rootNamesOf(json);
        Assert.assertEq(expected = "hero" :: Nil, names)

    /// "name" がない Json.JsonElement.JsonObject は空
    @Test
    def testRootNamesOfObjectWithoutName(): Unit \ Assert =
        let json = Json.JsonElement.JsonObject(Map#{"type" => Json.JsonElement.JsonString("Sprite2D")});
        let names = SceneJsonIndex.rootNamesOf(json);
        Assert.assertEq(expected = Nil, names)

    /// Json.JsonElement.JsonArray の各要素から "name" を集める
    @Test
    def testRootNamesOfArrayCollectsAllNames(): Unit \ Assert =
        let elem1 = Json.JsonElement.JsonObject(Map#{"name" => Json.JsonElement.JsonString("a")});
        let elem2 = Json.JsonElement.JsonObject(Map#{"name" => Json.JsonElement.JsonString("b")});
        let elem3 = Json.JsonElement.JsonObject(Map#{"name" => Json.JsonElement.JsonString("c")});
        let json = Json.JsonElement.JsonArray(Vector#{elem1, elem2, elem3});
        let names = SceneJsonIndex.rootNamesOf(json);
        Assert.assertEq(expected = "a" :: "b" :: "c" :: Nil, names)

    /// Json.JsonElement.JsonArray に "name" 欠落要素が混ざっていても、ある分だけ拾う
    @Test
    def testRootNamesOfArraySkipsElementsWithoutName(): Unit \ Assert =
        let elem1 = Json.JsonElement.JsonObject(Map#{"name" => Json.JsonElement.JsonString("a")});
        let elem2 = Json.JsonElement.JsonObject(Map#{"type" => Json.JsonElement.JsonString("Sprite2D")});  // name 無し
        let elem3 = Json.JsonElement.JsonObject(Map#{"name" => Json.JsonElement.JsonString("c")});
        let json = Json.JsonElement.JsonArray(Vector#{elem1, elem2, elem3});
        let names = SceneJsonIndex.rootNamesOf(json);
        Assert.assertEq(expected = "a" :: "c" :: Nil, names)

    /// Json.JsonElement.JsonObject でも Json.JsonElement.JsonArray でもない値は空
    @Test
    def testRootNamesOfNonContainer(): Unit \ Assert =
        Assert.assertEq(
            expected = (Nil, Nil, Nil),
            (SceneJsonIndex.rootNamesOf(Json.JsonElement.JsonString("x")),
             SceneJsonIndex.rootNamesOf(Json.JsonElement.JsonNumber(42.0ff)),
             SceneJsonIndex.rootNamesOf(Json.JsonElement.JsonNull)))

    /// Json.JsonElement.JsonObject の "name" が文字列でなければ無視
    @Test
    def testRootNamesOfNameMustBeString(): Unit \ Assert =
        let json = Json.JsonElement.JsonObject(Map#{"name" => Json.JsonElement.JsonNumber(123.0ff)});
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
