// Doc と JSON の橋渡しだけをテストする。1種類につき最大3本に絞る。
mod TestDocs {

    // ========================================================================
    // TuningDoc: 手触りと収支
    // ========================================================================

    /// 壊れた JSON は既定値へ倒れ、ゲームが起動できる。
    @Test
    def testTuningBrokenJsonFallsBackToDefaults(): Unit \ Assert =
        let doc = TuningDoc.fromJson("{ broken") |> Option.getWithDefault(TuningDoc.defaults());
        Assert.assertEq(expected = TuningDoc.defaults()#maxSpeed, doc#maxSpeed)

    /// 1項目だけ上書きすると、その値だけが反映される。
    @Test
    def testTuningOverridesOneField(): Unit \ Assert =
        let doc = TuningDoc.fromJson("{\"version\":1,\"totalLaps\":5}")
            |> Option.getWithDefault(TuningDoc.defaults());
        Assert.assertEq(
            expected = (5, TuningDoc.defaults()#maxSpeed),
            (doc#totalLaps, doc#maxSpeed))

    /// 型が正しくても0周は遊べないため、その欄だけ既定値へ戻す。
    @Test
    def testTuningRejectsUnsafeLapCount(): Unit \ Assert =
        let doc = TuningDoc.fromJson("{\"version\":1,\"totalLaps\":0}")
            |> Option.getWithDefault(TuningDoc.defaults());
        Assert.assertEq(expected = TuningDoc.defaults()#totalLaps, doc#totalLaps)

    // ========================================================================
    // SceneryDoc: 背景と速度表現
    // ========================================================================

    /// 壊れた JSON は既定の背景調整へ倒れ、描画を続けられる。
    @Test
    def testSceneryBrokenJsonFallsBackToDefaults(): Unit \ Assert =
        let doc = SceneryDoc.fromJson("{ broken")
            |> Option.getWithDefault(SceneryDoc.defaults());
        Assert.assertEq(
            expected = SceneryDoc.defaults()#panoramaStrength,
            doc#panoramaStrength)

    /// 背景の振れ幅だけ変えても、回路密度は既定のまま残る。
    @Test
    def testSceneryOverridesOneField(): Unit \ Assert =
        let doc = SceneryDoc.fromJson(
            "{\"version\":1,\"panoramaStrength\":150.0}")
            |> Option.getWithDefault(SceneryDoc.defaults());
        Assert.assertEq(
            expected = (150.0, SceneryDoc.defaults()#circuitStride),
            (doc#panoramaStrength, doc#circuitStride))

    // ========================================================================
    // CourseDoc: 増減できるコース行
    // ========================================================================

    /// 壊れた JSON は既定コースへ倒れる。
    @Test
    def testCourseBrokenJsonFallsBackToDefaults(): Unit \ Assert =
        let doc = CourseDoc.fromJson("{ broken") |> Option.getWithDefault(CourseDoc.defaults());
        Assert.assertEq(expected = List.length(CourseDoc.defaults()#rows), List.length(doc#rows))

    /// rows の増減はコースの区間数へそのまま反映される。
    @Test
    def testCourseRowCountFollowsJson(): Unit \ Assert =
        let doc = CourseDoc.fromJson("{\"version\":1,\"rows\":[\"###\",\".##\",\"##.\"]}")
            |> Option.getWithDefault(CourseDoc.defaults());
        Assert.assertEq(expected = 3, List.length(doc#rows))

    /// 1行だけでは閉じたコースを作れないため、既定コースへ戻す。
    @Test
    def testCourseRejectsSingleRow(): Unit \ Assert =
        let doc = CourseDoc.fromJson("{\"version\":1,\"rows\":[\"###\"]}")
            |> Option.getWithDefault(CourseDoc.defaults());
        Assert.assertEq(expected = List.length(CourseDoc.defaults()#rows), List.length(doc#rows))

    // ========================================================================
    // ThemeDoc / CopyDoc: 別型の1項目上書き
    // ========================================================================

    /// 1色だけ書き換えても、他の役割色は既定のまま残る。
    @Test
    def testThemeOverridesOneColor(): Unit \ Assert =
        let doc = ThemeDoc.fromJson("{\"version\":1,\"player\":\"#010203\"}")
            |> Option.getWithDefault(ThemeDoc.defaults());
        Assert.assertEq(
            expected = (true, ThemeDoc.defaults()#road#r),
            (doc#player#r != ThemeDoc.defaults()#player#r, doc#road#r))

    /// 表紙の題だけ書き換えても、操作案内は既定のまま残る。
    @Test
    def testCopyOverridesOneLine(): Unit \ Assert =
        let doc = CopyDoc.fromJson("{\"version\":1,\"titleMain\":\"NIGHT RUN\"}")
            |> Option.getWithDefault(CopyDoc.defaults());
        Assert.assertEq(
            expected = ("NIGHT RUN", CopyDoc.defaults()#startHint),
            (doc#titleMain, doc#startHint))
}
