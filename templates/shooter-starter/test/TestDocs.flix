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
        Assert.assertEq(expected = RulesDoc.defaults()#bulletSpeed, doc#bulletSpeed)

    @Test
    def testRulesOverridesOneField(): Unit \ Assert =
        // 1 フィールドだけ書いた JSON はそこだけ効き、残りは既定のまま。
        let doc = RulesDoc.fromJson("{\"version\":1, \"fireInterval\": 0.1}")
            |> Option.getWithDefault(RulesDoc.defaults());
        Assert.assertEq(
            expected = (0.1, RulesDoc.defaults()#bulletSpeed),
            (doc#fireInterval, doc#bulletSpeed))

    // ══════════════════════════════════════════════════════
    // ThemeDoc（色。RulesDoc と別型 = 色の Or 読みなので橋渡しを 1 本だけ）
    // ══════════════════════════════════════════════════════

    @Test
    def testThemeOverridesOneColor(): Unit \ Assert =
        // 1 色だけ書いた JSON はその色だけ効き、残りは既定のまま。
        let doc = ThemeDoc.fromJson("{\"version\":1, \"enemy\": \"#010203\"}")
            |> Option.getWithDefault(ThemeDoc.defaults());
        let d = ThemeDoc.defaults();
        Assert.assertEq(
            expected = (true, d#player#r),
            (doc#enemy#r != d#enemy#r, doc#player#r))

    // ══════════════════════════════════════════════════════
    // WavesDoc（敵の波 = 格子の配列。壊れ → 既定 / 波数の追随）
    // ══════════════════════════════════════════════════════

    @Test
    def testWavesBrokenJsonFallsBackToDefaults(): Unit \ Assert =
        // 壊れた JSON は既定の波へ倒れる。
        let doc = WavesDoc.fromJson("{ broken") |> Option.getWithDefault(WavesDoc.defaults());
        Assert.assertEq(expected = WavesDoc.waveCount(WavesDoc.defaults()), WavesDoc.waveCount(doc))

    @Test
    def testWavesCountFollowsJson(): Unit \ Assert =
        // waves 配列の長さを変えれば波数も追随する（1 波だけの JSON なら waveCount = 1）。
        let doc = WavesDoc.fromJson("{\"version\":1, \"waves\":[[\"X.X\"]]}")
            |> Option.getWithDefault(WavesDoc.defaults());
        Assert.assertEq(expected = 1, WavesDoc.waveCount(doc))
}
