// TestTerrainDoc — *.terrain.json の橋渡し(fromJson / defaults / fail-open)を固定する。
// 方針どおり 1 Doc 最大3本: 壊れたJSON→既定値 / 1フィールド上書き / 複合破損サンプル1本で
// decode 契約(char 先勝ち・未知 preset 除去・edge の uniform 先勝ち)。
// 期待値はリテラルで書かず defaults() から導く。描画の導出(16ケースの形・持ち上げ・粒)は
// テストしない —スナップショットと目視の仕事。
mod TestTerrainDoc {

    @Test
    def testTerrainBrokenJsonFallsBackToDefaults(): Unit \ Assert =
        // 壊れた JSON は既定の表へ倒れる(ゲームは必ず起動する)。
        let doc = TerrainDoc.fromJson("{ broken") |> Option.getWithDefault(TerrainDoc.defaults());
        Assert.assertEq(
            expected = (TerrainDoc.defaults()#styleMix#round,
                        List.length(TerrainDoc.defaults()#entries)),
            (doc#styleMix#round, List.length(doc#entries)))

    @Test
    def testTerrainOverridesOneField(): Unit \ Assert =
        // styleMix.round だけ書いた JSON はそこだけ効き、残りは既定のまま。
        // 上書き値は let で1回だけ持ち、JSON 断片と期待値の両方をそこから導く(リテラルの二重書きをしない)。
        let round = 0.9;
        let doc = TerrainDoc.fromJson("{\"version\":1, \"styleMix\": {\"round\": ${round}}}")
            |> Option.getWithDefault(TerrainDoc.defaults());
        Assert.assertEq(
            expected = (round, TerrainDoc.defaults()#styleMix#square),
            (doc#styleMix#round, doc#styleMix#square))

    @Test
    def testTerrainDecodeRulesInOneSample(): Unit \ Assert =
        // 複合破損サンプル1本で decode 契約を3つ固定する(壊れ扱いにせず静かに受け入れる = fail-open):
        //   (a) 同じ char の二重宣言は先勝ち(Studio 契約)
        //   (b) 未知の preset 名は decode 時に除去され surface が空になる
        //   (c) edge に uniform と top が混在したら uniform 先勝ち
        let text = "{\"version\":1, \"entries\":["
            + "{\"char\":\"#\",\"name\":\"first\",\"fill\":\"#334455\","
            +   "\"edge\":{\"uniform\":\"#101010\",\"top\":\"#fefefe\"},"
            +   "\"surface\":[{\"preset\":\"nosuch\",\"color\":\"#ffffff\"}]},"
            + "{\"char\":\"#\",\"name\":\"second\",\"fill\":\"#667788\"}]}";
        let doc = TerrainDoc.fromJson(text) |> Option.getWithDefault(TerrainDoc.defaults());
        let isUniform = e -> match e#edge {
            case TerrainDoc.EdgeRef.Uniform(_) => true
            case _                             => false
        };
        Assert.assertEq(
            expected = ("first" :: Nil, Some(0), Some(true)),
            (doc#entries |> List.map(e -> e#name),                              // (a) 先勝ち
             List.head(doc#entries) |> Option.map(e -> List.length(e#surface)), // (b) 未知 preset 除去
             List.head(doc#entries) |> Option.map(isUniform)))                  // (c) uniform 先勝ち
}
