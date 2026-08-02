/// UiSpec の parse（テンプレ上書き合成・pad 展開・bind/meta・不正入力）と、
/// spawn 後の names/parents/order/metas/styles、respawn での selection 生存を固定する。
mod TestUiSpec {

    // ════════════════════════════════════════════════════════
    // フィクスチャ
    // ════════════════════════════════════════════════════════

    /// テスト用 ui.json。
    ///   Menu (box, #ff00ff, alpha0.5, column, gap1.5, pad[3,2,3,2], abs[58,40])
    ///     ├─ item0  (use menuItem, text A, meta goddess, fontSize 6.0 で上書き)
    ///     ├─ item1  (use menuItem, text B, meta floor, fontSize は template の 5.0)
    ///     └─ hint   (text, bind gameOverHint, fontSize 4.0)
    /// テンプレ menuItem は widget=text / font=ui / fontSize=5.0 / tint=#e8e8e8 / zIndex=120。
    def sampleJson(): String =
        "{"
        + "\"templates\": { \"menuItem\": {\"widget\":\"text\",\"font\":\"ui\",\"fontSize\":5.0,\"tint\":\"#e8e8e8\",\"zIndex\":120} },"
        + "\"root\": {"
        + "\"name\":\"Menu\",\"widget\":\"box\",\"color\":\"#ff00ff\",\"alpha\":0.5,\"dir\":\"column\",\"gap\":1.5,\"pad\":[3,2,3,2],\"abs\":[58,40],\"zIndex\":110,"
        + "\"children\":["
        + "{\"use\":\"menuItem\",\"name\":\"item0\",\"text\":\"A\",\"meta\":\"goddess\",\"fontSize\":6.0},"
        + "{\"use\":\"menuItem\",\"name\":\"item1\",\"text\":\"B\",\"meta\":\"floor\"},"
        + "{\"name\":\"hint\",\"widget\":\"text\",\"bind\":\"gameOverHint\",\"font\":\"ui\",\"fontSize\":4.0}"
        + "]}}"

    /// JSON テキストを parse して spawn した UiWorld（失敗時 None）。
    def spawnFrom(jsonText: String): Option[UiStore.UiWorld] =
        specAndWorld(jsonText) |> Option.map(snd)

    /// JSON テキストを parse し、Spec と spawn 済み UiWorld の組を返す（失敗時 None）。
    def specAndWorld(jsonText: String): Option[(UiSpec.Spec, UiStore.UiWorld)] =
        DocJson.parse(jsonText)
            |> Option.flatMap(json -> UiSpec.parse(json) |> Result.toOption)
            |> Option.map(spawnPair)

    /// Spec を空 UiWorld へ spawnRoot し、Spec と結果 UiWorld の組にする。
    def spawnPair(spec: UiSpec.Spec): (UiSpec.Spec, UiStore.UiWorld) =
        let (_, ui) = UiSpec.spawnRoot(spec, UiStore.empty());
        (spec, ui)

    /// 名前パス → その entity の描画/属性 map 値を引くルックアップ。
    def lookup(path: String, m: UiStore.UiWorld -> Map[EntityId, v], ui: UiStore.UiWorld): Option[v] =
        UiStore.idOf(path, ui) |> Option.flatMap(id -> Map.get(id, m(ui)))

    def snd(pair: (a, b)): b = let (_, y) = pair; y

    // ════════════════════════════════════════════════════════
    // parse + spawn: 名前パス採番（DFS 前順で root=1, item0=2, item1=3, hint=4）
    // ════════════════════════════════════════════════════════

    /// idOf で 4 パスが順に 1,2,3,4 に解決される。
    @Test
    def testSpawnRegistersNamePaths(): Unit \ Assert =
        let ids = spawnFrom(sampleJson()) |> Option.map(ui ->
            (UiStore.idOf("Menu", ui), UiStore.idOf("Menu/item0", ui),
             UiStore.idOf("Menu/item1", ui), UiStore.idOf("Menu/hint", ui)));
        Assert.assertEq(expected = Some((Some(1), Some(2), Some(3), Some(4))), ids)

    // ════════════════════════════════════════════════════════
    // parse + spawn: parents（子は全て Menu=1 が親・root は親なし）
    // ════════════════════════════════════════════════════════

    /// item0/item1/hint の親は 1、Menu 自身は parents 非在。
    @Test
    def testSpawnRegistersParents(): Unit \ Assert =
        let parentOf = (path, ui) -> UiStore.idOf(path, ui) |> Option.flatMap(id -> Map.get(id, ui#parents));
        let ps = spawnFrom(sampleJson()) |> Option.map(ui ->
            (parentOf("Menu/item0", ui), parentOf("Menu/item1", ui),
             parentOf("Menu/hint", ui), parentOf("Menu", ui)));
        Assert.assertEq(expected = Some((Some(1), Some(1), Some(1), None)), ps)

    // ════════════════════════════════════════════════════════
    // parse + spawn: order（宣言順に 0,1,2）
    // ════════════════════════════════════════════════════════

    /// item0=0, item1=1, hint=2 の順序が付く。
    @Test
    def testSpawnRegistersOrder(): Unit \ Assert =
        let orders = spawnFrom(sampleJson()) |> Option.map(ui ->
            (Map.get(2, ui#order), Map.get(3, ui#order), Map.get(4, ui#order)));
        Assert.assertEq(expected = Some((Some(0), Some(1), Some(2))), orders)

    // ════════════════════════════════════════════════════════
    // parse + spawn: metas（item0=goddess, item1=floor, hint は無し）
    // ════════════════════════════════════════════════════════

    /// meta 宣言が entity へ登録され、宣言の無い hint は非在。
    @Test
    def testSpawnRegistersMetas(): Unit \ Assert =
        let metas = spawnFrom(sampleJson()) |> Option.map(ui ->
            (lookup("Menu/item0", u -> u#metas, ui),
             lookup("Menu/item1", u -> u#metas, ui),
             lookup("Menu/hint", u -> u#metas, ui)));
        Assert.assertEq(expected = Some((Some("goddess"), Some("floor"), None)), metas)

    // ════════════════════════════════════════════════════════
    // parse: bind 宣言の登録（hint のみ・item0 は非在）
    // ════════════════════════════════════════════════════════

    /// bind は bindings store に入り、宣言の無いノードは非在。
    @Test
    def testParseRegistersBindings(): Unit \ Assert =
        let binds = spawnFrom(sampleJson()) |> Option.map(ui ->
            (lookup("Menu/hint", u -> u#bindings, ui), lookup("Menu/item0", u -> u#bindings, ui)));
        Assert.assertEq(expected = Some((Some("gameOverHint"), None)), binds)

    // ════════════════════════════════════════════════════════
    // parse: テンプレ値の上書き合成
    // ════════════════════════════════════════════════════════

    /// item0 は fontSize をノード側 6.0 で上書きしつつ、font はテンプレの "ui" を継ぐ。
    @Test
    def testTemplateOverrideMerge(): Unit \ Assert =
        let textFields = spawnFrom(sampleJson()) |> Option.flatMap(ui ->
            lookup("Menu/item0", u -> u#texts, ui) |> Option.map(comp -> (comp#fontSize, comp#font)));
        Assert.assertEq(expected = Some((6.0, "ui")), textFields)

    /// item1 は fontSize を上書きしないのでテンプレの 5.0 のまま。
    @Test
    def testTemplateDefaultInherited(): Unit \ Assert =
        let fontSize = spawnFrom(sampleJson()) |> Option.flatMap(ui ->
            lookup("Menu/item1", u -> u#texts, ui) |> Option.map(comp -> comp#fontSize));
        Assert.assertEq(expected = Some(5.0), fontSize)

    // ════════════════════════════════════════════════════════
    // parse + spawn: style（pad 展開・gap・abs）
    // ════════════════════════════════════════════════════════

    /// pad [3,2,3,2] が padLeft/Top/Right/Bottom へ展開され、gap も反映される。
    @Test
    def testSpawnRegistersStylePadAndGap(): Unit \ Assert =
        let pads = spawnFrom(sampleJson()) |> Option.flatMap(ui ->
            lookup("Menu", u -> u#styles, ui)
                |> Option.map(style -> (style#padLeft, style#padTop, style#padRight, style#padBottom, style#gap)));
        Assert.assertEq(expected = Some((3.0, 2.0, 3.0, 2.0, 1.5)), pads)

    /// abs [58,40] がフロー外オフセット Some((58,40)) になる（記録は Vec2、比較は成分タプル）。
    @Test
    def testSpawnRegistersStyleAbs(): Unit \ Assert =
        let abs = spawnFrom(sampleJson()) |> Option.flatMap(ui ->
            lookup("Menu", u -> u#styles, ui)
                |> Option.map(style -> style#abs |> Option.map(offset -> (offset#x, offset#y))));
        Assert.assertEq(expected = Some(Some((58.0, 40.0))), abs)

    // ════════════════════════════════════════════════════════
    // parse: 色（"#rrggbb" → Color）と box の alpha
    // ════════════════════════════════════════════════════════

    /// "#ff00ff" が (r=1, g=0, b=1) に、alpha 0.5 が 0.5f32 になる（色は成分タプルで比較）。
    @Test
    def testParseBoxColorAndAlpha(): Unit \ Assert =
        let box = spawnFrom(sampleJson()) |> Option.flatMap(ui ->
            lookup("Menu", u -> u#boxes, ui)
                |> Option.map(comp -> ((comp#color#r, comp#color#g, comp#color#b), comp#alpha)));
        Assert.assertEq(expected = Some(((1.0f32, 0.0f32, 1.0f32), 0.5f32)), box)

    // ════════════════════════════════════════════════════════
    // parse: box の cornerRadius/borderWidth/borderColor
    // ════════════════════════════════════════════════════════

    /// 未指定なら cornerRadius=0.0, borderWidth=0.0, borderColor=白 の既定値になる（sampleJson の Menu）。
    @Test
    def testParseBoxBorderDefaults(): Unit \ Assert =
        let border = spawnFrom(sampleJson()) |> Option.flatMap(ui ->
            lookup("Menu", u -> u#boxes, ui)
                |> Option.map(comp -> (comp#cornerRadius, comp#borderWidth,
                                       (comp#borderColor#r, comp#borderColor#g, comp#borderColor#b))));
        Assert.assertEq(expected = Some((0.0, 0.0, (1.0f32, 1.0f32, 1.0f32))), border)

    /// "cornerRadius"/"borderWidth"/"borderColor" を指定した box は各値が反映される。
    @Test
    def testParseBoxBorderExplicit(): Unit \ Assert =
        let json =
            "{\"root\":{\"name\":\"Panel\",\"widget\":\"box\",\"color\":\"#0d0d26\","
            + "\"cornerRadius\":2.5,\"borderWidth\":1.0,\"borderColor\":\"#ffffff\"}}";
        let border = spawnFrom(json) |> Option.flatMap(ui ->
            lookup("Panel", u -> u#boxes, ui)
                |> Option.map(comp -> (comp#cornerRadius, comp#borderWidth,
                                       (comp#borderColor#r, comp#borderColor#g, comp#borderColor#b))));
        Assert.assertEq(expected = Some((2.5, 1.0, (1.0f32, 1.0f32, 1.0f32))), border)

    // ════════════════════════════════════════════════════════
    // parse + spawn: poly（points/color/alpha を polys store へ登録）
    // ════════════════════════════════════════════════════════

    /// poly の points([[0,0],[0,2.6],[2.3,1.3]])/color(#00ff00=(0,1,0))/alpha(未指定=1.0)を
    /// parse し polys store に登録する。宣言 poly はサブポリ 1 個で、頂点は成分タプル列、
    /// color は成分タプルで比較する。
    @Test
    def testParsePolyPointsColorAlpha(): Unit \ Assert =
        let json =
            "{\"root\":{\"name\":\"Mark\",\"widget\":\"poly\","
            + "\"points\":[[0,0],[0,2.6],[2.3,1.3]],\"color\":\"#00ff00\"}}";
        let poly = spawnFrom(json) |> Option.flatMap(ui ->
            lookup("Mark", u -> u#polys, ui)
                |> Option.map(comp -> (
                    comp#polys |> List.map(sub -> sub |> List.map(p -> (p#x, p#y))),
                    (comp#color#r, comp#color#g, comp#color#b),
                    comp#alpha)));
        Assert.assertEq(
            expected = Some((
                ((0.0, 0.0) :: (0.0, 2.6) :: (2.3, 1.3) :: Nil) :: Nil,
                (0.0f32, 1.0f32, 0.0f32),
                1.0f32)),
            poly)

    /// points が 2 点以下の poly は Err（塗り潰しに 3 頂点必要）。points キー欠落も Err。
    @Test
    def testParseRejectsPolyWithBadPoints(): Unit \ Assert =
        let isErr = jsonText -> DocJson.parse(jsonText) |> Option.map(json -> Result.isErr(UiSpec.parse(json)));
        let twoPoints = isErr("{\"root\":{\"name\":\"m\",\"widget\":\"poly\",\"points\":[[0,0],[1,1]],\"color\":\"#ffffff\"}}");
        let noPoints  = isErr("{\"root\":{\"name\":\"m\",\"widget\":\"poly\",\"color\":\"#ffffff\"}}");
        Assert.assertEq(expected = (Some(true), Some(true)), (twoPoints, noPoints))

    // ════════════════════════════════════════════════════════
    // parse: 不正入力は Err
    // ════════════════════════════════════════════════════════

    /// 未知 widget "blob" は Err。name 欠落も Err。兄弟 name 重複も Err。
    @Test
    def testParseRejectsInvalidInput(): Unit \ Assert =
        let isErr = jsonText -> DocJson.parse(jsonText) |> Option.map(json -> Result.isErr(UiSpec.parse(json)));
        let unknownWidget = isErr("{\"root\":{\"name\":\"x\",\"widget\":\"blob\"}}");
        let missingName   = isErr("{\"root\":{\"widget\":\"box\",\"color\":\"#ffffff\"}}");
        let dupSibling    = isErr("{\"root\":{\"name\":\"r\",\"children\":[{\"name\":\"a\",\"widget\":\"none\"},{\"name\":\"a\",\"widget\":\"none\"}]}}");
        Assert.assertEq(expected = (Some(true), Some(true), Some(true)), (unknownWidget, missingName, dupSibling))

    // ════════════════════════════════════════════════════════
    // parse + spawn: layer（root のみ登録・既定 0・非 root は無視）
    // ════════════════════════════════════════════════════════

    /// "layer" 未指定の root（sampleJson の Menu）は既定値 0 で layers store に登録される。
    @Test
    def testSpawnRegistersDefaultLayer(): Unit \ Assert =
        let layer = spawnFrom(sampleJson()) |> Option.flatMap(ui -> lookup("Menu", u -> u#layers, ui));
        Assert.assertEq(expected = Some(0), layer)

    /// root の "layer": 3 は layers store に 3 として登録され、非 root の子の "layer": 9 は無視される。
    @Test
    def testSpawnRegistersExplicitRootLayerAndIgnoresChildLayer(): Unit \ Assert =
        let json =
            "{\"root\":{\"name\":\"Root\",\"widget\":\"none\",\"layer\":3,"
            + "\"children\":[{\"name\":\"child\",\"widget\":\"none\",\"layer\":9}]}}";
        let layers = spawnFrom(json) |> Option.map(ui ->
            (lookup("Root", u -> u#layers, ui), lookup("Root/child", u -> u#layers, ui)));
        Assert.assertEq(expected = Some((Some(3), None)), layers)

    // ════════════════════════════════════════════════════════
    // respawn: selection が String キーゆえ生存する
    // ════════════════════════════════════════════════════════

    /// putSelection("Menu", 2) してから respawn しても selection は残る。
    @Test
    def testRespawnKeepsSelection(): Unit \ Assert =
        let survived = specAndWorld(sampleJson()) |> Option.map(selectionAfterRespawn);
        Assert.assertEq(expected = Some(2), survived)

    /// selection を 2 に設定してから respawn し、残った selection を返す。
    def selectionAfterRespawn(pair: (UiSpec.Spec, UiStore.UiWorld)): Int32 =
        let (spec, ui) = pair;
        let (_, ui2) = UiSpec.respawn(spec, UiStore.putSelection("Menu", 2, ui));
        UiStore.selectionOf("Menu", ui2)

    /// respawn 後も名前パスは再登録される（Menu が解決できる）。
    @Test
    def testRespawnReregistersNames(): Unit \ Assert =
        let hasRoot = specAndWorld(sampleJson()) |> Option.map(rootResolvableAfterRespawn);
        Assert.assertEq(expected = Some(true), hasRoot)

    /// respawn 後に root 名パスが解決できるかを返す。
    def rootResolvableAfterRespawn(pair: (UiSpec.Spec, UiStore.UiWorld)): Bool =
        let (spec, ui) = pair;
        let (_, ui2) = UiSpec.respawn(spec, ui);
        not Option.isEmpty(UiStore.idOf("Menu", ui2))

    // ════════════════════════════════════════════════════════
    // respawn: 動的に切り替えた可視状態が同じ名前パスへ引き継がれる
    // ════════════════════════════════════════════════════════

    /// item0 を setVisible(false) してから respawn すると、item0 は visible=false を引き継ぐ
    /// （spec 既定の true に戻らない）。ゲームが動的に隠した状態がリロードを生き延びる。
    @Test
    def testRespawnKeepsVisible(): Unit \ Assert =
        let survived = specAndWorld(sampleJson()) |> Option.flatMap(visibleAfterRespawn);
        Assert.assertEq(expected = Some(false), survived)

    /// item0 を不可視にしてから respawn し、残った visible 値を返す。
    def visibleAfterRespawn(pair: (UiSpec.Spec, UiStore.UiWorld)): Option[Bool] =
        let (spec, ui) = pair;
        let hidden = UiStore.setVisible("Menu/item0", false, ui);
        let (_, ui2) = UiSpec.respawn(spec, hidden);
        UiStore.visibleOf("Menu/item0", ui2)

    // ════════════════════════════════════════════════════════
    // parse: name バリデーション（空文字・"/" 含みは Err）
    // ════════════════════════════════════════════════════════

    /// name が空文字の root は Err（名前パス機構の破壊を防ぐ）。
    @Test
    def testParseRejectsEmptyName(): Unit \ Assert =
        let isErr = DocJson.parse("{\"root\":{\"name\":\"\",\"widget\":\"none\"}}")
            |> Option.map(json -> Result.isErr(UiSpec.parse(json)));
        Assert.assertEq(expected = Some(true), isErr)

    /// name に区切り文字 "/" を含む root は Err（"a/b" は名前パスを曖昧にする）。
    @Test
    def testParseRejectsSlashInName(): Unit \ Assert =
        let isErr = DocJson.parse("{\"root\":{\"name\":\"a/b\",\"widget\":\"none\"}}")
            |> Option.map(json -> Result.isErr(UiSpec.parse(json)));
        Assert.assertEq(expected = Some(true), isErr)
}
