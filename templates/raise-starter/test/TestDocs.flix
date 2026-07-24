// JSON 橋渡しのテスト（1 Doc につき最大 3 本まで。同型の重複は書かない）。
// 期待値はリテラルでなく defaults() から導く（バランス調整でテストが壊れないように）。
mod TestDocs {

    // ══════════════════════════════════════════════════════
    // RulesDoc（進行と収支の数値）
    // ══════════════════════════════════════════════════════

    @Test
    def testRulesBrokenJsonFallsBackToDefaults(): Unit \ Assert =
        // 壊れた JSON は既定へ倒れる（ゲームは必ず起動する）。
        let doc = RulesDoc.fromJson("{ broken") |> Option.getWithDefault(RulesDoc.defaults());
        Assert.assertEq(expected = RulesDoc.defaults()#dayCount, doc#dayCount)

    @Test
    def testRulesOverridesOneField(): Unit \ Assert =
        // 1 フィールドだけ書いた JSON はそこだけ効き、残りは既定のまま。
        let doc = RulesDoc.fromJson("{\"version\":1, \"dayCount\": 3}")
            |> Option.getWithDefault(RulesDoc.defaults());
        Assert.assertEq(
            expected = (3, RulesDoc.defaults()#eventChance),
            (doc#dayCount, doc#eventChance))

    // ══════════════════════════════════════════════════════
    // ThemeDoc（色。RulesDoc と別型 = 色の Or 読みなので橋渡しを 1 本だけ）
    // ══════════════════════════════════════════════════════

    @Test
    def testThemeOverridesOneColor(): Unit \ Assert =
        // 1 色だけ書いた JSON はその色だけ効き、残りは既定のまま。
        let doc = ThemeDoc.fromJson("{\"version\":1, \"bar1\": \"#010203\"}")
            |> Option.getWithDefault(ThemeDoc.defaults());
        let d = ThemeDoc.defaults();
        Assert.assertEq(
            expected = (true, d#text#r),
            (doc#bar1#r != d#bar1#r, doc#text#r))

    // ══════════════════════════════════════════════════════
    // PlanDoc（行動・イベント・結末の表。壊れ → 既定 / 行数の追随）
    // ══════════════════════════════════════════════════════

    @Test
    def testPlanBrokenJsonFallsBackToDefaults(): Unit \ Assert =
        // 壊れた JSON は既定の表へ倒れる（行動数が既定と同じ）。
        let doc = PlanDoc.fromJson("{ broken") |> Option.getWithDefault(PlanDoc.defaults());
        Assert.assertEq(expected = PlanDoc.actionCount(PlanDoc.defaults()), PlanDoc.actionCount(doc))

    @Test
    def testPlanActionCountFollowsJson(): Unit \ Assert =
        // actions 配列の長さを変えれば選択肢の数も追随する（1 行だけの JSON なら actionCount = 1）。
        let doc = PlanDoc.fromJson(
                "{\"version\":1, \"stats\":[], \"events\":[], \"endings\":[], "
              + "\"actions\":[{\"label\":\"a\",\"power\":1,\"spirit\":0,\"skill\":0}]}")
            |> Option.getWithDefault(PlanDoc.defaults());
        Assert.assertEq(expected = 1, PlanDoc.actionCount(doc))
}
