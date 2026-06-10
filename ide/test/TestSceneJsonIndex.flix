// Tests for SceneJsonIndex — scene.json 群を走査して「ルート名 → ファイルパス」索引を作る
//
// `rootNamesOf` は純粋なので手作りの Util.Json.Json で直接テストできる。
// `load()` は実在の `src/scenes/*.scene.json` を入力に取り、特定 root 名が
// 期待ファイルパスに紐付くか検証する

mod TestSceneJsonIndex {

    /// editor 単独テスト用の最小 tag enum (NodeTag は consumer 側で定義される型)
    pub enum Tag { case NoTag }

    // ====================================================================
    // rootNamesOf — 手作り JSON で純粋テスト
    // ====================================================================

    /// 単一 Util.Json.Json.JObject に "name" があれば 1 件返す
    @Test
    def testRootNamesOfSingleObjectWithName(): Unit \ Assert =
        let json = Util.Json.Json.JObject(Map#{"name" => Util.Json.Json.JString("hero"), "type" => Util.Json.Json.JString("Sprite2D")});
        let names = SceneJsonIndex.rootNamesOf(json);
        Assert.assertEq(expected = "hero" :: Nil, names)

    /// "name" がない Util.Json.Json.JObject は空
    @Test
    def testRootNamesOfObjectWithoutName(): Unit \ Assert =
        let json = Util.Json.Json.JObject(Map#{"type" => Util.Json.Json.JString("Sprite2D")});
        let names = SceneJsonIndex.rootNamesOf(json);
        Assert.assertEq(expected = Nil, names)

    /// Util.Json.Json.JArray の各要素から "name" を集める
    @Test
    def testRootNamesOfArrayCollectsAllNames(): Unit \ Assert =
        let elem1 = Util.Json.Json.JObject(Map#{"name" => Util.Json.Json.JString("a")});
        let elem2 = Util.Json.Json.JObject(Map#{"name" => Util.Json.Json.JString("b")});
        let elem3 = Util.Json.Json.JObject(Map#{"name" => Util.Json.Json.JString("c")});
        let json = Util.Json.Json.JArray(Vector#{elem1, elem2, elem3});
        let names = SceneJsonIndex.rootNamesOf(json);
        Assert.assertEq(expected = "a" :: "b" :: "c" :: Nil, names)

    /// Util.Json.Json.JArray に "name" 欠落要素が混ざっていても、ある分だけ拾う
    @Test
    def testRootNamesOfArraySkipsElementsWithoutName(): Unit \ Assert =
        let elem1 = Util.Json.Json.JObject(Map#{"name" => Util.Json.Json.JString("a")});
        let elem2 = Util.Json.Json.JObject(Map#{"type" => Util.Json.Json.JString("Sprite2D")});  // name 無し
        let elem3 = Util.Json.Json.JObject(Map#{"name" => Util.Json.Json.JString("c")});
        let json = Util.Json.Json.JArray(Vector#{elem1, elem2, elem3});
        let names = SceneJsonIndex.rootNamesOf(json);
        Assert.assertEq(expected = "a" :: "c" :: Nil, names)

    /// Util.Json.Json.JObject でも Util.Json.Json.JArray でもない値は空
    @Test
    def testRootNamesOfNonContainer(): Unit \ Assert =
        Assert.assertEq(
            expected = (Nil, Nil, Nil),
            (SceneJsonIndex.rootNamesOf(Util.Json.Json.JString("x")),
             SceneJsonIndex.rootNamesOf(Util.Json.Json.JNumber(42.0ff)),
             SceneJsonIndex.rootNamesOf(Util.Json.Json.JNull)))

    /// Util.Json.Json.JObject の "name" が文字列でなければ無視
    @Test
    def testRootNamesOfNameMustBeString(): Unit \ Assert =
        let json = Util.Json.Json.JObject(Map#{"name" => Util.Json.Json.JNumber(123.0ff)});
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
