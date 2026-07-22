// JSON 橋渡しのテスト（1 Doc につき最大 3 本まで。同型の重複は書かない）。
// ThemeDoc は KindDoc と同型（フィールドの Or 読み）なので橋渡しは書かない。
mod TestDocs {

    // ══════════════════════════════════════════════════════
    // StoryDoc（台本: rows）
    // ══════════════════════════════════════════════════════

    @Test
    def testStoryBrokenJsonFallsBackToDefaults(): Unit \ Assert =
        // 壊れた JSON は既定の台本へ倒れる（ゲームは必ず起動する）。
        let doc = StoryDoc.fromJson("{ broken") |> Option.getWithDefault(StoryDoc.defaults());
        Assert.assertEq(expected = StoryDoc.defaults()#start, doc#start)

    @Test
    def testStoryOverridesOneField(): Unit \ Assert =
        // 1 フィールドだけ書いた JSON はそこだけ効き、残りは既定のまま。
        let doc = StoryDoc.fromJson("{\"version\":1, \"lamps\": 5}")
            |> Option.getWithDefault(StoryDoc.defaults());
        Assert.assertEq(expected = (5, StoryDoc.defaults()#start), (doc#lamps, doc#start))

    @Test
    def testStoryRowsLengthFollowsJson(): Unit \ Assert =
        // sections の rows を増やせば節が増える（節の中の beats / options の rows も追随する）。
        let text = "{\"version\":1, \"start\":\"a\", \"sections\":["
            + "{\"id\":\"a\", \"beats\":[{\"text\":\"x\"},{\"text\":\"y\"}],"
            + " \"ask\":{\"text\":\"?\", \"options\":[{\"label\":\"l\",\"goto\":\"b\"}]}},"
            + "{\"id\":\"b\", \"beats\":[]}]}";
        let doc = StoryDoc.fromJson(text) |> Option.getWithDefault(StoryDoc.defaults());
        let beatsInA = StoryDoc.sectionOf("a", doc)
            |> Option.map(section -> List.length(section#beats))
            |> Option.getWithDefault(-1);
        let optionsInA = StoryDoc.sectionOf("a", doc)
            |> Option.flatMap(section -> section#ask)
            |> Option.map(ask -> List.length(ask#options))
            |> Option.getWithDefault(-1);
        Assert.assertEq(expected = (2, 2, 1),
            (List.length(doc#sections), beatsInA, optionsInA))

    // ══════════════════════════════════════════════════════
    // KindDoc（手触りの数値）
    // ══════════════════════════════════════════════════════

    @Test
    def testKindBrokenJsonFallsBackToDefaults(): Unit \ Assert =
        let doc = KindDoc.fromJson("{ broken") |> Option.getWithDefault(KindDoc.defaults());
        Assert.assertEq(expected = KindDoc.defaults()#cps, doc#cps)

    @Test
    def testKindOverridesOneField(): Unit \ Assert =
        let doc = KindDoc.fromJson("{\"version\":1, \"cps\": 99.0}")
            |> Option.getWithDefault(KindDoc.defaults());
        Assert.assertEq(expected = (99.0, KindDoc.defaults()#dim), (doc#cps, doc#dim))
}
