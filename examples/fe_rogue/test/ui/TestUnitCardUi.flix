/// UnitCardUi の純関数と、別名 spawn（spawnAssetAs）の names/sources を固定する:
///   - fitText: 収まれば原文 / あふれれば "…" 省略（収まる最大 prefix + …、1 文字も無理なら "…"）
///   - barFillWidth: value/max 比を 0..1 にクランプして size に掛ける
///   - spawnAssetAs: 1 枚のアセットを別名 root（EnemyCard）として組み、sources を root 名で登録する
///   - reloadAll: 別名 root は登録キー名のままリロードされる（アセット自身の root 名 UnitCard へは戻らない）
mod TestUnitCardUi {

    // ════════════════════════════════════════════════════════
    // フィクスチャ
    // ════════════════════════════════════════════════════════

    /// 等幅 advance=10 のサンプルアトラス（'A' のみ登録・fontSize=16）。
    /// 未登録グリフ（"…" 含む）は advance=0 として測られる。TestText の sampleAtlas と同流儀。
    def monoAtlas(): FontAtlas =
        let metrics: TextLayout.GlyphMetrics = {
            xOff = 0.0, yOff = 0.0, glyphW = 10.0, glyphH = 10.0,
            advance = 10.0, s0 = 0.0, t0 = 0.0, s1 = 1.0, t1 = 1.0
        };
        ({
            textureName = "atlas", fontSize = 16.0, textureSize = 256.0,
            ascent = 8.0, descent = 2.0, lineGap = 0.0,
            glyphs = Map.insert(65, metrics, Map.empty())   // 'A' = 65
        }: FontAtlas)

    def snd(pair: (a, b)): b = let (_, y) = pair; y

    // ════════════════════════════════════════════════════════
    // fitText: 省略規則
    // ════════════════════════════════════════════════════════

    /// 収まる文字列はそのまま返す（"AAA" 幅 30 ≤ 100）。
    @Test
    def testFitTextFits(): Unit \ Assert =
        Assert.assertEq(expected = "AAA", UnitCardUi.fitText("AAA", monoAtlas(), 16.0, 100.0))

    /// あふれる文字列は収まる最大 prefix + "…"。"AAAAA"(幅50) を maxWidth 25 に詰めると
    /// "AA…"（幅 20 ≤ 25、"AAA…"=30 は超過）になる（"…" は幅 0）。
    @Test
    def testFitTextTruncates(): Unit \ Assert =
        Assert.assertEq(expected = "AA…", UnitCardUi.fitText("AAAAA", monoAtlas(), 16.0, 25.0))

    /// 1 文字 + "…" すら入らない極小幅は "…" だけを返す（"A…"=10 > 5）。
    @Test
    def testFitTextEllipsisOnly(): Unit \ Assert =
        Assert.assertEq(expected = "…", UnitCardUi.fitText("AAA", monoAtlas(), 16.0, 5.0))

    // ════════════════════════════════════════════════════════
    // barFillWidth: 比率クランプ
    // ════════════════════════════════════════════════════════

    /// HP 5/10 は幅 26 の半分 = 13.0。
    @Test
    def testBarFillHalf(): Unit \ Assert =
        Assert.assertEq(expected = 13.0, UnitCardUi.barFillWidth(26.0, 5, 10))

    /// HP 0/10 は塗りなし = 0.0。
    @Test
    def testBarFillZero(): Unit \ Assert =
        Assert.assertEq(expected = 0.0, UnitCardUi.barFillWidth(26.0, 0, 10))

    /// value>max は 1.0 にクランプ（満タン幅 = size）。
    @Test
    def testBarFillClampsAtFull(): Unit \ Assert =
        Assert.assertEq(expected = 26.0, UnitCardUi.barFillWidth(26.0, 20, 10))

    /// max<=0 は 0/0 を避けて 0.0（未 seed の敵などの防御）。
    @Test
    def testBarFillMaxZero(): Unit \ Assert =
        Assert.assertEq(expected = 0.0, UnitCardUi.barFillWidth(16.0, 5, 0))

    // ════════════════════════════════════════════════════════
    // spawnAssetAs: 別名 root の names / sources
    // ════════════════════════════════════════════════════════

    /// 別名 spawn した UiWorld（EnemyCard として組む。失敗時 None）。
    def spawnAsEnemy(): Option[UiStore.UiWorld] \ Fs.FileRead =
        UiSpec.spawnAssetAs(UnitCardUi.specPath(), UnitCardUi.enemyRootName(), UiStore.empty())
            |> Result.toOption |> Option.map(snd)

    /// EnemyCard root と panel が名前パスで引け、アセット自身の "UnitCard" 名は登録されない。
    @Test
    def testSpawnAsRegistersRenamedNamePaths(): Unit \ {Assert, Fs.FileRead} =
        let present = spawnAsEnemy() |> Option.map(ui ->
            (not Option.isEmpty(UiStore.idOf("EnemyCard", ui)),
             not Option.isEmpty(UiStore.idOf("EnemyCard/panel", ui)),
             Option.isEmpty(UiStore.idOf("UnitCard", ui))));
        Assert.assertEq(expected = Some((true, true, true)), present)

    /// sources 台帳は別名 root（EnemyCard）をキーにアセットパスを登録する。
    @Test
    def testSpawnAsRegistersSourceUnderRootName(): Unit \ {Assert, Fs.FileRead} =
        let src = spawnAsEnemy() |> Option.map(ui -> Map.get("EnemyCard", ui#sources));
        Assert.assertEq(expected = Some(Some(UnitCardUi.specPath())), src)

    /// reloadAll は登録キー（EnemyCard）名でツリーを組み直す（アセット自身の root 名へは戻らない・孤児なし）。
    @Test
    def testReloadKeepsAliasRootName(): Unit \ {Assert, Fs.FileRead} =
        let present = spawnAsEnemy()
            |> Option.map(UiSpec.reloadAll)
            |> Option.map(ui ->
                (not Option.isEmpty(UiStore.idOf("EnemyCard", ui)),
                 Option.isEmpty(UiStore.idOf("UnitCard", ui))));
        Assert.assertEq(expected = Some((true, true)), present)
}
