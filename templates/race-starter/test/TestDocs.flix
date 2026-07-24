// JSON 橋渡しのテスト（1 Doc につき最大 3 本まで。同型の重複は書かない）。
// 期待値はリテラルでなく defaults() から導く（バランス調整でテストが壊れないように）。
mod TestDocs {

    // ══════════════════════════════════════════════════════
    // RulesDoc（手触りと収支の数値）
    // ══════════════════════════════════════════════════════

    @Test
    def testRulesBrokenJsonFallsBackToDefaults(): Unit \ Assert =
        // 壊れた JSON は既定へ倒れる（ゲームは必ず起動する）。
        let doc = RulesDoc.fromJson("{ broken") |> Option.getWithDefault(RulesDoc.defaults());
        Assert.assertEq(expected = RulesDoc.defaults()#forwardSpeed, doc#forwardSpeed)

    @Test
    def testRulesOverridesOneField(): Unit \ Assert =
        // 1 フィールドだけ書いた JSON はそこだけ効き、残りは既定のまま。
        let doc = RulesDoc.fromJson("{\"version\":1, \"totalLaps\": 5}")
            |> Option.getWithDefault(RulesDoc.defaults());
        Assert.assertEq(
            expected = (5, RulesDoc.defaults()#forwardSpeed),
            (doc#totalLaps, doc#forwardSpeed))

    // ══════════════════════════════════════════════════════
    // ThemeDoc（色。別型 = 色の Or 読みなので橋渡しを 1 本だけ）
    // ══════════════════════════════════════════════════════

    @Test
    def testThemeOverridesOneColor(): Unit \ Assert =
        // 1 色だけ書いた JSON はその色だけ効き、残りは既定のまま。
        let doc = ThemeDoc.fromJson("{\"version\":1, \"road\": \"#010203\"}")
            |> Option.getWithDefault(ThemeDoc.defaults());
        let d = ThemeDoc.defaults();
        Assert.assertEq(
            expected = (true, d#player#r),
            (doc#road#r != d#road#r, doc#player#r))

    // ══════════════════════════════════════════════════════
    // CourseDoc（コースの格子。壊れ → 既定 / 段数の追随）
    // ══════════════════════════════════════════════════════

    @Test
    def testCourseBrokenJsonFallsBackToDefaults(): Unit \ Assert =
        // 壊れた JSON は既定のコースへ倒れる。
        let doc = CourseDoc.fromJson("{ broken") |> Option.getWithDefault(CourseDoc.defaults());
        Assert.assertEq(expected = CourseDoc.rowCount(CourseDoc.defaults()), CourseDoc.rowCount(doc))

    @Test
    def testCourseRowCountFollowsJson(): Unit \ Assert =
        // rows 配列の長さを変えれば段数も追随する（2 段だけの JSON なら rowCount = 2）。
        let doc = CourseDoc.fromJson("{\"version\":1, \"rows\":[\"##.\", \".##\"]}")
            |> Option.getWithDefault(CourseDoc.defaults());
        Assert.assertEq(expected = 2, CourseDoc.rowCount(doc))
}
