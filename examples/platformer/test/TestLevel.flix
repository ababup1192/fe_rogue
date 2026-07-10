// TestLevel — テキストグリッドの run 融合パーサと敵・坂の抽出が正しく組み上がることを pin する。
// 期待値はグリッド定義（208×30）から手で数えた実測値。グリッドを編集したらここも更新する。

mod TestLevel {

    // グリッドの run 融合数。行優先の走査で数えた実測値を pin。
    // Track F のレベル: 硬い床 37（地面 4 行 × 4 分割 + 段差・台地・浮き床・階段）・一方通行 6。
    @Test
    def testRunCounts(): Unit \ Assert =
        Assert.assertEq(expected = (37, 6),
            (List.length(Level.solidRuns()), List.length(Level.oneWayRuns())))

    // 最初の硬い床 run（id 200・行16 列190-191 = 階段の最上段）の矩形を厳密に pin。
    @Test
    def testFirstSolidRunRect(): Unit \ Assert =
        let firstSolid = Level.solidRuns() |> List.head;
        let asTuple = firstSolid |> Option.map(p -> (p#id, p#pos#x, p#pos#y, p#size#x, p#size#y));
        Assert.assertEq(expected = Some((200, 3056.0, 264.0, 32.0, 16.0)), asTuple)

    // 出発点 'P' セル（列3・行24）の中心座標を厳密に pin。地面（上面 416）のすぐ上の空中。
    @Test
    def testSpawnOf(): Unit \ Assert =
        let startPos = Level.spawnOf();
        Assert.assertEq(expected = (56.0, 392.0), (startPos#x, startPos#y))

    // レベル寸法と旗: 3328×480px・ゴールは列 204 の中心（x=3272）・中間地点は列 105（x=1688）。
    @Test
    def testLevelDimsAndGoal(): Unit \ Assert =
        Assert.assertEq(expected = (3328.0, 480.0, 3272.0, 1688.0, 392.0),
            (Level.levelWidth(), Level.levelHeight(), Level.goalX(),
             Level.checkpointPos()#x, Level.checkpointPos()#y))

    // id 帯: 硬い床は [200,300)・一方通行は [300,400)・フェリーは 400・坂は 500 番台 3 枚。
    // 見えない境界壁は硬い床帯の手前の 198・199。
    @Test
    def testIdBands(): Unit \ Assert =
        let solidIdsOk = Level.solidRuns() |> List.forAll(p -> p#id >= 200 and p#id < 300);
        let oneWayIdsOk = Level.oneWayRuns() |> List.forAll(p -> p#id >= 300 and p#id < 400);
        let moverIds = Level.movingPlatforms() |> List.map(p -> p#id);
        let slopeIds = Level.slopePlatforms() |> List.map(p -> p#id);
        let wallIds = Level.boundaryWalls() |> List.map(p -> p#id);
        Assert.assertEq(expected = (true, true, 400 :: Nil, 500 :: 501 :: 502 :: Nil, 198 :: 199 :: Nil),
            (solidIdsOk, oneWayIdsOk, moverIds, slopeIds, wallIds))

    // レベル幅は 3328px。グリッド由来と坂はその範囲に収まり、境界壁 2 枚だけが
    // 意図的に範囲の外（カメラに決して映らない位置）に立つ。
    @Test
    def testLevelWidthBounds(): Unit \ Assert =
        let inside = List.append(Level.gridPlatforms(),
            List.append(Level.slopePlatforms(), Level.movingPlatforms()));
        let rightOk = inside |> List.forAll(p -> p#pos#x + p#size#x / 2.0 <= Level.levelWidth());
        let leftOk = inside |> List.forAll(p -> p#pos#x - p#size#x / 2.0 >= 0.0);
        let wallsOutside = Level.boundaryWalls()
            |> List.forAll(p -> p#pos#x + p#size#x / 2.0 <= 0.0 or p#pos#x - p#size#x / 2.0 >= Level.levelWidth());
        Assert.assertEq(expected = (3328.0, true, true, true),
            (Level.levelWidth(), rightOk, leftOk, wallsOutside))

    // 画面 1 枚ぶん（320px）の帯すべてに硬い床のどこかが掛かる — 徒歩で進める保証の粗い網。
    @Test
    def testGroundInEveryScreenBand(): Unit \ Assert =
        let solids = Level.solidRuns();
        let overlapsBand = (lo, hi) -> solids |> List.exists(p ->
            p#pos#x + p#size#x / 2.0 > lo and p#pos#x - p#size#x / 2.0 < hi);
        let bands = List.range(0, 10) |> List.map(i -> Int32.toFloat64(i) * 320.0);
        Assert.assertEq(expected = true,
            bands |> List.forAll(lo -> overlapsBand(lo, lo + 320.0)))

    // 敵の抽出: 8 体（歩く敵 4・パタパタ 3・トゲ 1）が行優先で id 600 から並ぶ。
    // 最初の歩く敵（id 603・列40）は地面の上面に立つ（y = 416 − 敵半径10 = 406）。
    @Test
    def testEnemyExtraction(): Unit \ Assert =
        let foes = Level.enemies();
        let countOf = kind -> foes |> List.filter(e -> e#kind == kind) |> List.length;
        let ids = foes |> List.map(e -> e#id);
        let firstWalker = foes |> List.findLeft(e -> e#kind == Field.EnemyKind.WalkerKind);
        let walkerPos = firstWalker |> Option.map(e -> (e#id, e#base#x, e#base#y));
        Assert.assertEq(expected =
            (4, 3, 1,
             600 :: 601 :: 602 :: 603 :: 604 :: 605 :: 606 :: 607 :: Nil,
             Some((603, 648.0, 406.0))),
            (countOf(Field.EnemyKind.WalkerKind),
             countOf(Field.EnemyKind.FlyerKind),
             countOf(Field.EnemyKind.SpikyKind),
             ids, walkerPos))
}
