// ルールと進行・収支だけをテストする（方針どおり）。演出（閃光・スクロールの見た目）や座標の写経はしない。
// 期待値はリテラルでなく Doc（RulesDoc.defaults / CourseDoc.defaults）から導く — バランス調整で壊れないように。
//
// World を直接組んで規則関数を当てる。座標は px（y は下ほど大きい）。
mod TestRules {

    /// 既定の Doc から Title の World を作る土台。
    def base(): World.World =
        World.initial({ rules = RulesDoc.defaults(), theme = ThemeDoc.defaults(),
                        course = CourseDoc.defaults(), shader = ShaderDoc.demoSurface() })

    /// Racing にした World（進行・当たり・収支のテスト用）。
    def racing(w: World.World): World.World =
        { phase = World.Phase.Racing | w }

    /// ライバル 1 台（progress・レーン x・速さ・抜いたか）。
    def rivalAt(progress: Float64, passed: Bool): World.Rival =
        { progress = progress, laneX = 100.0, speed = 0.0, passed = passed }

    // ══════════════════════════════════════════════════════
    // ハンドル（←→ で左右に寄る・画面の縁で止まる = ルール）
    // ══════════════════════════════════════════════════════

    @Test
    def testSteerRightMovesPlayer(): Unit \ Assert =
        // → を入れると playerX が steerSpeed * dt ぶん右へ動く。
        let d = RulesDoc.defaults();
        let w = racing(base());
        let dt = 0.1;
        let after = World.step(1.0, dt, w);
        Assert.assertEq(expected = w#playerX + d#steerSpeed * dt, after#playerX)

    @Test
    def testSteerClampsAtEdge(): Unit \ Assert =
        // ずっと右へ寄せても画面の外（designW を越えて）へは出ない。
        let w = { playerX = World.designW() | racing(base()) };
        let after = World.step(1.0, 1.0, w);
        Assert.assertEq(expected = true, after#playerX <= World.designW())

    // ══════════════════════════════════════════════════════
    // はみ出し減速（草に出ると前進が offRoadSlow ぶん遅くなる = ルール）
    // ══════════════════════════════════════════════════════

    @Test
    def testOnRoadAdvancesAtFullSpeed(): Unit \ Assert =
        // 路面の上（既定コースの先頭段の '#' の列）にいれば前進速度は forwardSpeed のまま。
        let d = RulesDoc.defaults();
        // 既定コース先頭段 "...#####...." の路面の中央あたりへ playerX を置く。
        let cols = CourseDoc.colCount(CourseDoc.defaults());
        let cellW = World.designW() / Int32.toFloat64(cols);
        let onRoadX = 5.5 * cellW;                                   // 6 列目（'#' の帯の中）
        let w = { playerX = onRoadX, distance = 0.0 | racing(base()) };
        let after = World.step(0.0, 0.1, w);
        Assert.assertEq(expected = d#forwardSpeed, after#speed)

    @Test
    def testOffRoadSlowsDown(): Unit \ Assert =
        // 草の上（先頭段の '.' の列 = 左端）にいれば前進速度は forwardSpeed * offRoadSlow に落ちる。
        let d = RulesDoc.defaults();
        let w = { playerX = 0.0, distance = 0.0 | racing(base()) };  // 左端 = 草
        let after = World.step(0.0, 0.1, w);
        Assert.assertEq(expected = d#forwardSpeed * d#offRoadSlow, after#speed)

    // ══════════════════════════════════════════════════════
    // 追い抜き（distance がライバルの progress を越えたら抜く → 加点・順位が上がる）
    // ══════════════════════════════════════════════════════

    @Test
    def testPassingRivalScoresAndRanksUp(): Unit \ Assert =
        // まだ抜いていない前方ライバルを、自機の distance が追い越すと 1 台抜き、
        // scorePerPass が入り、順位（rank）が 1 つ上がる。
        let d = RulesDoc.defaults();
        // 自機がちょうどライバルの手前。1 フレームで progress を越えるだけ前進する。
        let rivalProgress = 50.0;
        let w = { distance = rivalProgress - 1.0, score = 0,
                  rivals = rivalAt(rivalProgress, false) :: Nil | racing(base()) };
        let dt = 5.0 / d#forwardSpeed;                              // 5px 前進 = ライバルを越える
        let after = World.step(0.0, dt, w);
        let passedNow = after#rivals |> List.forAll(r -> r#passed);
        Assert.assertEq(
            expected = (d#scorePerPass, 1, true),
            (after#score, after#rank, passedNow))

    @Test
    def testRivalPassedOnceDoesNotScoreTwice(): Unit \ Assert =
        // 既に抜いた（passed = true）ライバルは、また加点しない（掛け金で 1 回だけ）。
        let w = { distance = 100.0, score = 0,
                  rivals = rivalAt(50.0, true) :: Nil | racing(base()) };
        let after = World.step(0.0, 0.1, w);
        Assert.assertEq(expected = 0, after#score)

    // ══════════════════════════════════════════════════════
    // 周回とゴール（distance / lapLength で lap・totalLaps 周で WIN。ボーナスは Doc 由来）
    // ══════════════════════════════════════════════════════

    @Test
    def testLapCountFollowsDistance(): Unit \ Assert =
        // 1 周ぶん（lapLength）少し越えて走ると lap が 1 になる（まだ totalLaps 未満なら Racing のまま）。
        let d = RulesDoc.defaults();
        let w = { distance = d#lapLength + 10.0 | racing(base()) };
        let after = World.step(0.0, 0.001, w);
        Assert.assertEq(
            expected = (1, World.Phase.Racing),
            (after#lap, after#phase))

    @Test
    def testReachingTotalLapsWins(): Unit \ Assert =
        // totalLaps 周ぶんの距離に達すると FINISH（WIN）になり、finishBonus が入る。
        let d = RulesDoc.defaults();
        let dist = d#lapLength * Int32.toFloat64(d#totalLaps) + 10.0;
        // ライバルを外して、加点がゴールボーナスだけになるようにする（追い抜き分を混ぜない）。
        let w = { distance = dist, score = 0, rivals = Nil | racing(base()) };
        let after = World.step(0.0, 0.001, w);
        Assert.assertEq(
            expected = (World.Phase.Finish, d#finishBonus),
            (after#phase, after#score))

    // ══════════════════════════════════════════════════════
    // 順位の計算（自機より前にいるライバルの数 + 1）
    // ══════════════════════════════════════════════════════

    @Test
    def testRankCountsRivalsAhead(): Unit \ Assert =
        // 前に 1 台・後ろに 1 台いれば順位は 2 位（前の 1 台 + 自分）。
        let w = { distance = 100.0,
                  rivals = rivalAt(150.0, false) :: rivalAt(50.0, true) :: Nil | racing(base()) };
        Assert.assertEq(expected = 2, World.rankOf(w))

    // ══════════════════════════════════════════════════════
    // 場面の決定（Title→Racing・Finish→Title）
    // ══════════════════════════════════════════════════════

    @Test
    def testConfirmFromTitleStartsRace(): Unit \ Assert =
        // Title で決定すると Racing になり、ライバルが前方（自機より先）に涌く。
        let after = World.confirm(base());
        let allAhead = after#rivals |> List.forAll(r -> r#progress > after#distance);
        Assert.assertEq(
            expected = (World.Phase.Racing, true),
            (after#phase, allAhead))

    @Test
    def testConfirmFromFinishReturnsToTitle(): Unit \ Assert =
        // FINISH で決定すると Title に戻る（必ず仕切り直せる）。
        let w = { phase = World.Phase.Finish | base() };
        Assert.assertEq(expected = World.Phase.Title, World.confirm(w)#phase)

    // ══════════════════════════════════════════════════════
    // コース読み（格子の文字 → 路面かどうか）
    // ══════════════════════════════════════════════════════

    @Test
    def testCourseIsRoadOnlyForNonEmptyCells(): Unit \ Assert =
        // '#' は路面、'.'/空白は草。判断は CourseDoc.isRoad 1 か所だけ。
        Assert.assertEq(
            expected = (true, false, false),
            (CourseDoc.isRoad('#'), CourseDoc.isRoad('.'), CourseDoc.isRoad(' ')))
}
