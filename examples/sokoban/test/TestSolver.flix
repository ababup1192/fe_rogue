// TestSolver — 同梱レベルが解けることの機械証明と、レベル静的検証の pin。
//
// TestSokoban の testReplaySolves… は「同梱の解答 Trace を再生すると勝つ」という
// 証明で、こちらは「ソルバーが自力で解を見つける」という独立の証明 —— 手書きの
// 解答に依存しないので、レベルを差し替えたときに解答 Trace の更新忘れとレベル
// 自体の破綻を別々に検出できる。
mod TestSolver {

    /// レベル文字列を Option[Parsed] へ（パース失敗はテスト側で None として現れる）。
    def parsed(text: String): Option[Level.Parsed] =
        Level.parse(text) |> Result.toOption

    /// 角に据えられたクレートの小盤: クレート (1,1) は上も左も壁なので、どの方向
    /// にも押せない。ゴール (3,2) は永遠に空のまま —— 解けない盤の負例。
    ///
    ///   #####
    ///   #$  #
    ///   #@ .#
    ///   #####
    def cornerLockedBoard(): String =
        String.unlines(
            "#####" ::
            "#$  #" ::
            "#@ .#" ::
            "#####" :: Nil)

    /// 壁で仕切られた床 (3,1) を持つ小盤: ロボットからは決して歩いて行けない
    /// 孤立領域の負例（クレートなし・検証専用の盤なのでゴールも要らない）。
    ///
    ///   #####
    ///   #@# #
    ///   #####
    def isolatedPocketBoard(): String =
        String.unlines(
            "#####" ::
            "#@# #" ::
            "#####" :: Nil)

    // ── ソルバー: 同梱レベルが解けることの機械証明 ──

    @Test
    def testSolverProvesLevelOneInTwoPushes(): Unit \ Assert =
        // レベル1はクレート2個がそれぞれ隣のゴールへ1押しずつ: 最小押し数 2。
        Assert.assertEq(expected = Some(Some(2)),
            parsed(Level.one()) |> Option.map(Solver.minPushes))

    @Test
    def testSolverProvesLevelTwoInThreePushes(): Unit \ Assert =
        // レベル2は上のクレートが1押し、下のクレートが左→下の2押し: 最小押し数
        // 3。同梱の解答 Trace は21手（歩き込み）だが、押しだけ数えれば3手である。
        Assert.assertEq(expected = Some(Some(3)),
            parsed(Level.two()) |> Option.map(Solver.minPushes))

    @Test
    def testSolverRejectsCornerLockedBoard(): Unit \ Assert =
        // 角のクレートはどの方向にも押せないので、探索は1状態で尽きて解なし。
        Assert.assertEq(expected = Some(None),
            parsed(cornerLockedBoard()) |> Option.map(Solver.minPushes))

    // ── レベル静的検証: 出荷ゲート ──

    @Test
    def testShippedLevelsPassStaticChecks(): Unit \ Assert =
        // 出荷している両レベルが「床がすべて繋がっている」「角に据えられたゴール
        // 外のクレートがない」の両検査を通ること。レベルを追加・変更したときの
        // 自動ガード。
        let checks = text -> parsed(text) |> Option.map(p ->
            (Solver.floorConnected(p), Solver.noCornerDeadlock(p)));
        Assert.assertEq(expected = (Some((true, true)), Some((true, true))),
            (checks(Level.one()), checks(Level.two())))

    @Test
    def testCornerDetectorNamesTheLockedCrate(): Unit \ Assert =
        // 負例の盤では角検査がちゃんと鳴き、詰んでいるクレートの位置を名指しする。
        Assert.assertEq(expected = Some((1, 1) :: Nil),
            parsed(cornerLockedBoard()) |> Option.map(Solver.cornerDeadlocks))

    @Test
    def testConnectivityDetectorNamesTheIsolatedFloor(): Unit \ Assert =
        // 負例の盤では連結性検査がちゃんと鳴き、孤立した床の位置を名指しする。
        Assert.assertEq(expected = Some((false, (3, 1) :: Nil)),
            parsed(isolatedPocketBoard()) |> Option.map(p ->
                (Solver.floorConnected(p), Solver.isolatedFloors(p))))
}
