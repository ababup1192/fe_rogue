// JSON 橋渡しのテスト(1 Doc につき最大 3 本まで。同型の重複は書かない)。
// ThemeDoc は KindDoc と同型(フィールドの Or 読み)なので橋渡しは書かない。
mod TestDocs {

    // ══════════════════════════════════════════════════════
    // MapDoc(里の間取り: rows と配置)
    // ══════════════════════════════════════════════════════

    @Test
    def testMapBrokenJsonFallsBackToDefaults(): Unit \ Assert =
        // 壊れた JSON は既定の間取りへ倒れる(ゲームは必ず起動する)。
        let doc = MapDoc.fromJson("{ broken") |> Option.getWithDefault(MapDoc.defaults());
        Assert.assertEq(
            expected = (MapDoc.defaults()#start#x, MapDoc.defaults()#start#y, MapDoc.defaults()#goal),
            (doc#start#x, doc#start#y, doc#goal))

    @Test
    def testMapOverridesOneField(): Unit \ Assert =
        // 1 フィールドだけ書いた JSON はそこだけ効き、残りは既定のまま。
        let doc = MapDoc.fromJson("{\"version\":1, \"hint\": \"Xではじめる\"}")
            |> Option.getWithDefault(MapDoc.defaults());
        Assert.assertEq(expected = ("Xではじめる", MapDoc.defaults()#goal), (doc#hint, doc#goal))

    @Test
    def testMapRowsLengthFollowsJson(): Unit \ Assert =
        // rows・villagers・herbs の行数を増減すれば Doc も追随する。
        let text = "{\"version\":1,"
            + " \"rows\":[\"###\",\"#.#\",\"###\"],"
            + " \"villagers\":[{\"id\":\"a\",\"x\":1,\"y\":1},{\"id\":\"b\",\"x\":1,\"y\":1}],"
            + " \"herbs\":[{\"x\":1,\"y\":1}]}";
        let doc = MapDoc.fromJson(text) |> Option.getWithDefault(MapDoc.defaults());
        Assert.assertEq(expected = (3, 2, 1),
            (List.length(doc#rows), List.length(doc#villagers), List.length(doc#herbs)))

    // ══════════════════════════════════════════════════════
    // KindDoc(手触りの数値)
    // ══════════════════════════════════════════════════════

    @Test
    def testKindBrokenJsonFallsBackToDefaults(): Unit \ Assert =
        let doc = KindDoc.fromJson("{ broken") |> Option.getWithDefault(KindDoc.defaults());
        Assert.assertEq(expected = KindDoc.defaults()#walk, doc#walk)

    @Test
    def testKindOverridesOneField(): Unit \ Assert =
        let doc = KindDoc.fromJson("{\"version\":1, \"walk\": 9.0}")
            |> Option.getWithDefault(KindDoc.defaults());
        Assert.assertEq(expected = (9.0, KindDoc.defaults()#cps), (doc#walk, doc#cps))

    // ══════════════════════════════════════════════════════
    // ThemeDoc resolver（terrain の @参照が使う派生色）
    // TerrainDoc の橋渡し（fromJson / defaults / fail-open）は engine 側
    // TestTerrainDoc で完結 — ここでは繰り返さない。
    // ══════════════════════════════════════════════════════

    @Test
    def testThemeResolverDerivesWallTop(): Unit \ Assert =
        // 派生色はテーマの基準色から導かれる（導出できる値は Doc に置かない）。
        let d = ThemeDoc.defaults();
        let expectedColor = ThemeDoc.lighten(d#wall, 0.18);
        let got = ThemeDoc.resolver(d, "wallTop");
        Assert.assertEq(
            expected = (expectedColor#r, expectedColor#g, expectedColor#b),
            (got#r, got#g, got#b))
}
