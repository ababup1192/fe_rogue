// TestPreviewUi — 合成プレビューと data 流し込みの純粋な部分を固定する。
// 描画そのもの (PNG の中身) は目視検品に任せ、ここでは封筒の解釈・spawn の台帳・
// warning の導出だけを見る。

mod TestPreviewUi {
    use Util.Json.Json

    /// テスト用の最小 ui.json を UiSpec.Spec に解く。ここで解けないのはテスト自身の書き間違い。
    def specOf(text: String): UiSpec.Spec =
        match (JsonCompat.parse(text) |> Option.map(UiSpec.parse)) {
            case Some(Ok(spec)) => spec
            case _              => bug!("test ui.json does not parse: ${text}")
        }

    /// root 名と bind key を差し替えられる 1 枚モノの文書 (root の下に bind 付き text が 1 つ)。
    def docJson(rootName: String, bindKey: String): String =
        "{\"defaultFont\": \"default\", \"root\": {\"name\": \"${rootName}\", \"widget\": \"none\", \"visible\": false, " +
        "\"children\": [{\"name\": \"label\", \"widget\": \"text\", \"text\": \"old\", \"bind\": \"${bindKey}\"}]}}"

    def toSpawn(rootName: String, bindKey: String, data: Map[String, String]): PreviewUi.DocToSpawn =
        { path = "assets/${rootName}.ui.json", spec = specOf(docJson(rootName, bindKey)), data = data }

    // ========================================================================
    // 封筒の解釈 (data / compose / sidecar パス)
    // ========================================================================

    /// sidecar は *.ui.json の隣の <同名>.preview.json。ui.json でないパスは対象外。
    @Test
    def testSidecarPathOf(): Unit \ Assert =
        Assert.assertEq(
            expected = (Some("assets/Hud.preview.json"), (None: Option[String])),
            (PreviewUi.sidecarPathOf("assets/Hud.ui.json"), PreviewUi.sidecarPathOf("assets/hitbox.json")))

    /// data は「文字列→文字列」の object のみ。数値が混ざったら丸ごと None (黙って捨てない)。
    @Test
    def testDataFromJson(): Unit \ Assert =
        Assert.assertEq(
            expected = (Some(Map#{"hp" => "12", "name" => "アレン"}), (None: Option[Map[String, String]])),
            (JsonCompat.parse("{\"hp\": \"12\", \"name\": \"アレン\"}") |> Option.flatMap(PreviewUi.dataFromJson),
             JsonCompat.parse("{\"hp\": 12}") |> Option.flatMap(PreviewUi.dataFromJson)))

    /// compose は [{path, data?}] の列。data 省略は空 Map、path 欠けの要素があれば丸ごと None。
    @Test
    def testComposeFromJson(): Unit \ Assert =
        let parsed = JsonCompat.parse("[{\"path\": \"a.ui.json\"}, {\"path\": \"b.ui.json\", \"data\": {\"k\": \"v\"}}]")
            |> Option.flatMap(PreviewUi.composeFromJson)
            |> Option.map(entries -> entries |> List.map(entry -> (entry#path, entry#data)));
        let broken = JsonCompat.parse("[{\"data\": {\"k\": \"v\"}}]")
            |> Option.flatMap(PreviewUi.composeFromJson)
            |> Option.map(entries -> List.length(entries));
        Assert.assertEq(
            expected = (Some(("a.ui.json", (Map.empty(): Map[String, String])) :: ("b.ui.json", Map#{"k" => "v"}) :: Nil),
                        (None: Option[Int32])),
            (parsed, broken))

    /// composable 判定 (GET /files): 木のどこか (入れ子・配列の中) に rotation/pivot が
    /// あれば true。無ければ false ("rotation" という文字列の値には反応しない)。
    @Test
    def testContainsRotation(): Unit \ Assert =
        let deepRotation = "{\"root\": {\"name\": \"g\", \"children\": [{\"name\": \"p\", \"widget\": \"poly\", \"rotation\": 0.1}]}}";
        let pivotOnly    = "{\"root\": {\"name\": \"g\", \"widget\": \"poly\", \"pivot\": [1, 2]}}";
        let plain        = "{\"root\": {\"name\": \"g\", \"widget\": \"text\", \"text\": \"rotation\"}}";
        let check = text -> JsonCompat.parse(text) |> Option.map(PreviewUi.containsRotation);
        Assert.assertEq(
            expected = (Some(true), Some(true), Some(false)),
            (check(deepRotation), check(pivotOnly), check(plain)))

    // ========================================================================
    // パレット表 (応答の palette フィールド)
    // ========================================================================

    /// 文字列をトップレベルの Map[String, Json] に解く (テスト入力用)。
    def topOf(text: String): Map[String, Json] =
        match (JsonCompat.parse(text) |> Option.flatMap(JsonCodec.expectObject)) {
            case Some(m) => m
            case None    => bug!("test json does not parse: ${text}")
        }

    /// 合成順: 外部パレットの上に inline "palette" が勝つ (UiDoc.load と同じ)。
    /// 外部だけの名前・inline だけの名前はそのまま残る。
    @Test
    def testPaletteTableInlineWins(): Unit \ Assert =
        Assert.assertEq(
            expected = Map#{"base" => "#111111", "main" => "#ff0000", "extra" => "#00ff00"},
            PreviewUi.paletteTable(
                topOf("{\"base\": \"#111111\", \"main\": \"#0000ff\"}"),
                topOf("{\"palette\": {\"main\": \"#ff0000\", \"extra\": \"#00ff00\"}}")))

    /// 色 3 表記の解決: "#RRGGBB" は小文字へ正規化、{"rgb"} と {"hsv"} は hex へ変換
    /// (hsv 0/0/1 = 白・0/1/1 = 赤)。解決できない値 ("@参照"・形違い) は表から落ちる。
    @Test
    def testPaletteTableResolvesColorForms(): Unit \ Assert =
        Assert.assertEq(
            expected = Map#{"hexUp" => "#a0b1c2", "red" => "#ff0000", "white" => "#ffffff"},
            PreviewUi.paletteTable(Map.empty(), topOf(
                "{\"palette\": {" +
                "\"hexUp\": \"#A0B1C2\", " +
                "\"white\": {\"hsv\": [0, 0, 1]}, " +
                "\"red\": {\"rgb\": [1, 0, 0]}, " +
                "\"broken\": \"@white\", " +
                "\"weird\": 12}}")))

    /// palette キーが無いドキュメントは空の表 (paletteFile 側も無ければ何も出ない)。
    @Test
    def testPaletteTableEmpty(): Unit \ Assert =
        Assert.assertEq(
            expected = (Map.empty(): Map[String, String]),
            PreviewUi.paletteTable(Map.empty(), topOf("{\"root\": {\"name\": \"g\"}}")))

    /// paletteFile 参照の逆引き: トップレベルの文字列だけ拾う (数値などの形違いは None)。
    @Test
    def testPaletteRefOf(): Unit \ Assert =
        let refOf = text -> JsonCompat.parse(text) |> Option.flatMap(PreviewUi.paletteRefOf);
        Assert.assertEq(
            expected = (Some("assets/palette.json"), (None: Option[String]), (None: Option[String])),
            (refOf("{\"paletteFile\": \"assets/palette.json\", \"root\": {}}"),
             refOf("{\"root\": {\"name\": \"g\"}}"),
             refOf("{\"paletteFile\": 3}")))

    // ========================================================================
    // 合成 spawn (spawnDocs)
    // ========================================================================

    /// data はその文書の bind だけに入る: 同じ bind key "greeting" を持つ 2 文書を重ね、
    /// 後ろ (B) にだけ data を渡す → A の text は据え置き・B だけ差し替わる。
    @Test
    def testSpawnDocsScopesDataPerDoc(): Unit \ Assert =
        let spawned = PreviewUi.spawnDocs(
            toSpawn("A", "greeting", Map.empty()) :: toSpawn("B", "greeting", Map#{"greeting" => "hello"}) :: Nil,
            true);
        Assert.assertEq(
            expected = (Some("old"), Some("hello")),
            (UiStore.textOf("A/label", spawned#ui), UiStore.textOf("B/label", spawned#ui)))

    /// roots は spawn 順 (奥→手前) の台帳になり、layer は配列位置で付け直される
    /// (合成の前後関係は文書側の layer でなく配列順が契約)。bind key は全文書ぶん集まる。
    @Test
    def testSpawnDocsRootsAndLayers(): Unit \ Assert =
        let spawned = PreviewUi.spawnDocs(
            toSpawn("A", "hp", Map.empty()) :: toSpawn("B", "mp", Map.empty()) :: Nil,
            true);
        let rootsWithLayer = spawned#roots
            |> List.map(root -> (root#root, Map.get(root#id, spawned#ui#layers)));
        Assert.assertEq(
            expected = (("A", Some(0)) :: ("B", Some(1)) :: Nil, Set#{"hp", "mp"}),
            (rootsWithLayer, spawned#bindKeys))

    /// overrideLayers = false (単体プレビュー) は文書が宣言した layer をそのまま使う。
    @Test
    def testSpawnDocsKeepsDeclaredLayerWhenAlone(): Unit \ Assert =
        let text = "{\"defaultFont\": \"default\", \"root\": {\"name\": \"A\", \"widget\": \"none\", \"layer\": 5}}";
        let spawned = PreviewUi.spawnDocs(
            ({ path = "", spec = specOf(text), data = Map.empty() }: PreviewUi.DocToSpawn) :: Nil,
            false);
        let layerOfRoot = spawned#roots |> List.head
            |> Option.flatMap(root -> Map.get(root#id, spawned#ui#layers));
        Assert.assertEq(expected = Some(5), layerOfRoot)

    /// root は visible:false 宣言でも強制表示される (子孫の hidden は尊重 = ここでは root だけ見る)。
    @Test
    def testSpawnDocsForcesRootVisible(): Unit \ Assert =
        let spawned = PreviewUi.spawnDocs(toSpawn("A", "hp", Map.empty()) :: Nil, false);
        Assert.assertEq(expected = Some(true), UiStore.visibleOf("A", spawned#ui))

    // ========================================================================
    // warning の導出
    // ========================================================================

    /// 同じ root 名が 2 回現れたら 1 行 (重複名ごとに 1 行)。重複が無ければ何も言わない。
    @Test
    def testDuplicateRootWarnings(): Unit \ Assert =
        Assert.assertEq(
            expected = (1, (Nil: List[String])),
            (List.length(PreviewUi.duplicateRootWarnings("Hud" :: "Memo" :: "Hud" :: Nil)),
             PreviewUi.duplicateRootWarnings("Hud" :: "Memo" :: Nil)))

    /// どの文書の bind にも当たらない data キーだけが warning になる (タイポ検知)。
    @Test
    def testUnmatchedDataWarnings(): Unit \ Assert =
        Assert.assertEq(
            expected = "data key 'nane' does not match any bind" :: Nil,
            PreviewUi.unmatchedDataWarnings(
                Map#{"hp" => "1", "nane" => "x"} :: Nil,
                Set#{"hp", "name"}))
}
