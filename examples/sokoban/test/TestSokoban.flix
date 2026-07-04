// TestSokoban — パーサー、押しのルール、スライドのリズムを平文の事実として固定
// する。キーとレベルはデータとして渡されるので、どのケースも具体的な値を伴う普
// 通の関数呼び出しになる: ウィンドウもキーボードもない。

mod TestSokoban {

    // ── ヘルパー ──

    def keys(u: Bool, d: Bool, l: Bool, r: Bool): Board.Input =
        { up = u, down = d, left = l, right = r,
          undo = false, enter = false, back = false, esc = false }

    def none(): Board.Input = keys(false, false, false, false)

    def zKey(): Board.Input = { undo = true | none() }

    def enterKey(): Board.Input = { enter = true | none() }

    def backKey(): Board.Input = { back = true | none() }

    def escKey(): Board.Input = { esc = true | none() }

    def right(): Board.Input = keys(false, false, false, true)

    /// どのケースも刻む1フレームの時間: 1/64秒、2進小数として正確な値なので、
    /// 以下で固定するすべての t と phase は誤差なく正確である。
    def dt(): Float64 = 1.0 / 64.0

    /// 与えられた中身を持つ、5x5の開けた床、静止状態、レベル1のプレイ中。
    def board(walls: List[(Int32, Int32)], crates: List[(Int32, Int32)],
              robot: (Int32, Int32)): Board.World =
        Board.World.World({
            walls = List.toSet(walls), goals = Set.empty(), crates = List.toSet(crates),
            robot = robot, cols = 5, rows = 5,
            facing = Dir4.Down, walkPhase = 0.0, slide = None, undoFx = None,
            screen = Board.Screen.Playing, level = 1, clearElapsed = 0.0 })

    /// すでに解決済みのボード（1つのクレートが1つのゴールに乗っている）、指定
    /// されたレベルで。
    def wonBoard(level: Int32): Board.World =
        let Board.World.World(b) = board(Nil, (1, 1) :: Nil, (2, 2));
        Board.World.World({ goals = Set#{(1, 1)}, level = level | b })

    def withSlide(s: Board.Slide, w: Board.World): Board.World =
        let Board.World.World(b) = w;
        Board.World.World({ slide = Some(s) | b })

    def slideOf(w: Board.World): Option[((Int32, Int32), Bool, Bool, Float64)] =
        let Board.World.World(b) = w;
        Option.map(s -> (s#fromCell, s#pushing, s#reverse, s#t), b#slide)

    def tagOf(d: Dir4.Dir4): String = match d {
        case Dir4.Up    => "Up"
        case Dir4.Down  => "Down"
        case Dir4.Left  => "Left"
        case Dir4.Right => "Right"
    }

    // ── パーサー ──

    @Test
    def testParseTinyLevel(): Unit \ Assert =
        let text = String.unlines("#####" :: "#@$.#" :: "#####" :: Nil);
        let actual = Result.map(p ->
            (p#cols, p#rows, p#robot,
             Set.memberOf((2, 1), p#crates), Set.memberOf((3, 1), p#goals), Set.size(p#walls)),
            Level.parse(text));
        Assert.assertEq(expected = Result.Ok((5, 3, (1, 1), true, true, 12)), actual)

    @Test
    def testParseStarAndPlusOverlays(): Unit \ Assert =
        let text = String.unlines("####" :: "#+*#" :: "####" :: Nil);
        let actual = Result.map(p ->
            (p#robot, Set.memberOf((2, 1), p#crates),
             Set.memberOf((1, 1), p#goals), Set.memberOf((2, 1), p#goals)),
            Level.parse(text));
        Assert.assertEq(expected = Result.Ok(((1, 1), true, true, true)), actual)

    @Test
    def testParseRejectsUnknownTile(): Unit \ Assert =
        let actual = Result.map(p -> p#cols, Level.parse("#X@#"));
        Assert.assertEq(expected = Result.Err("unknown tile 'X' at column 1, row 0"), actual)

    @Test
    def testParseRejectsTwoRobots(): Unit \ Assert =
        let actual = Result.map(p -> p#cols, Level.parse("#@@#"));
        Assert.assertEq(expected = Result.Err("more than one robot in the level"), actual)

    @Test
    def testParseRejectsRobotlessLevel(): Unit \ Assert =
        let actual = Result.map(p -> p#cols, Level.parse("#$.#"));
        Assert.assertEq(expected = Result.Err("the level has no robot '@'"), actual)

    @Test
    def testShippedLevelsParse(): Unit \ Assert =
        Assert.assertEq(expected = (true, true),
            (Result.isOk(Level.parse(Level.one())), Result.isOk(Level.parse(Level.two()))))

    // ── 移動: ホップ、スライド、入力ゲート ──

    @Test
    def testPressHopsCellAndStartsSlide(): Unit \ Assert =
        let w = Sokoban.step(right(), dt(), board(Nil, Nil, (2, 2)));
        let Board.World.World(b) = w;
        Assert.assertEq(expected = ((3, 2), "Right", Some(((2, 2), false, false, 0.0))),
            (b#robot, tagOf(b#facing), slideOf(w)))

    @Test
    def testInputIgnoredWhileSliding(): Unit \ Assert =
        let sliding = withSlide({ fromCell = (2, 2), pushing = false, reverse = false, t = 0.5 },
                                board(Nil, Nil, (3, 2)));
        let w = Sokoban.step(keys(true, false, false, false), dt(), sliding);
        let Board.World.World(b) = w;
        Assert.assertEq(expected = ((3, 2), "Down", Some(((2, 2), false, false, 0.625))),
            (b#robot, tagOf(b#facing), slideOf(w)))

    @Test
    def testHeldKeyChainsNextHopWhenSlideLands(): Unit \ Assert =
        let sliding = withSlide({ fromCell = (2, 2), pushing = false, reverse = false, t = 0.875 },
                                board(Nil, Nil, (3, 2)));
        let w = Sokoban.step(right(), dt(), sliding);
        let Board.World.World(b) = w;
        Assert.assertEq(expected = ((4, 2), Some(((3, 2), false, false, 0.0))),
            (b#robot, slideOf(w)))

    @Test
    def testReleaseStopsAtSlideEnd(): Unit \ Assert =
        let sliding = withSlide({ fromCell = (2, 2), pushing = false, reverse = false, t = 0.875 },
                                board(Nil, Nil, (3, 2)));
        let w = Sokoban.step(none(), dt(), sliding);
        let Board.World.World(b) = w;
        Assert.assertEq(expected = ((3, 2), None, 0.03125),
            (b#robot, slideOf(w), b#walkPhase))

    @Test
    def testWalkPhaseStridesWhileSlidingMarchesWhileStanding(): Unit \ Assert =
        let sliding = withSlide({ fromCell = (2, 2), pushing = false, reverse = false, t = 0.5 },
                                board(Nil, Nil, (3, 2)));
        let Board.World.World(b1) = Sokoban.step(none(), dt(), sliding);
        let Board.World.World(b2) = Sokoban.step(none(), dt(), board(Nil, Nil, (2, 2)));
        Assert.assertEq(expected = (0.03125, 0.01171875), (b1#walkPhase, b2#walkPhase))

    @Test
    def testSlideSpeedScalesWithDtNotFrames(): Unit \ Assert =
        let sliding = () -> withSlide({ fromCell = (2, 2), pushing = false, reverse = false, t = 0.5 },
                                      board(Nil, Nil, (3, 2)));
        let atDt = d -> {
            let Board.World.World(b) = Sokoban.step(none(), d, sliding());
            Option.map(s -> s#t, b#slide)
        };
        Assert.assertEq(expected = (Some(0.625), Some(0.75)),
            (atDt(1.0 / 64.0), atDt(1.0 / 32.0)))

    @Test
    def testWallBlocksButRobotTurns(): Unit \ Assert =
        let w = Sokoban.step(right(), dt(), board((3, 2) :: Nil, Nil, (2, 2)));
        let Board.World.World(b) = w;
        Assert.assertEq(expected = ((2, 2), "Right", None),
            (b#robot, tagOf(b#facing), slideOf(w)))

    // ── 押すこと ──

    @Test
    def testPushMovesCrateAndSlidesInSync(): Unit \ Assert =
        let w = Sokoban.step(right(), dt(), board(Nil, (3, 2) :: Nil, (2, 2)));
        let Board.World.World(b) = w;
        Assert.assertEq(expected = ((3, 2), false, true, Some(((2, 2), true, false, 0.0))),
            (b#robot, Set.memberOf((3, 2), b#crates), Set.memberOf((4, 2), b#crates), slideOf(w)))

    @Test
    def testCrateAgainstWallDoesNotBudge(): Unit \ Assert =
        let Board.World.World(b) =
            Sokoban.step(right(), dt(), board((4, 2) :: Nil, (3, 2) :: Nil, (2, 2)));
        Assert.assertEq(expected = ((2, 2), true),
            (b#robot, Set.memberOf((3, 2), b#crates)))

    @Test
    def testTwoCratesInARowDoNotBudge(): Unit \ Assert =
        let Board.World.World(b) =
            Sokoban.step(right(), dt(), board(Nil, (3, 2) :: (4, 2) :: Nil, (2, 2)));
        Assert.assertEq(expected = ((2, 2), true, true),
            (b#robot, Set.memberOf((3, 2), b#crates), Set.memberOf((4, 2), b#crates)))

    // ── Worldline: 手が確定すれば記録し、Z で巻き戻す ──

    def robotOf(w: Board.World): (Int32, Int32) =
        let Board.World.World(b) = w;
        b#robot

    def cratesOf(w: Board.World): Set[(Int32, Int32)] =
        let Board.World.World(b) = w;
        b#crates

    /// 1フレームが見うる両方の向き: 絵がまとうもの（drawnFacing）と、Board に
    /// 保存されているもの。
    def facingsOf(w: Board.World): (String, String) =
        let Board.World.World(b) = w;
        (tagOf(View.drawnFacing(b)), tagOf(b#facing))

    def fresh(w: Board.World): Worldline[Board.World] =
        Worldline.make(w, Sokoban.historyCap())

    /// 進行中のスライドを何であれ着地させる（完全な前方スライドの1ティック）。
    def land(line: Worldline[Board.World]): Worldline[Board.World] =
        Sokoban.tick(none(), 0.125, line)

    /// 右へ着地済みの1手、巻き戻される準備ができている。
    def movedAndLanded(w: Board.World): Worldline[Board.World] =
        land(Sokoban.tick(right(), dt(), fresh(w)))

    /// Z が押された状態での tick；何も滑っていなければ即座に発動する。
    def undoNow(line: Worldline[Board.World]): Worldline[Board.World] =
        Sokoban.tick(zKey(), dt(), line)

    @Test
    def testUndoRestoresStoresAtOnceAndStartsReverseSlide(): Unit \ Assert =
        let back = Worldline.current(undoNow(movedAndLanded(board(Nil, Nil, (2, 2)))));
        // セルはすでに戻っている；絵はまだ (3,2) に外れていて、逆再生中。
        Assert.assertEq(expected = ((2, 2), Some(((3, 2), false, true, 0.0))),
            (robotOf(back), slideOf(back)))

    @Test
    def testUndoRestoresPushedCrateWithReverseSlide(): Unit \ Assert =
        let back = Worldline.current(undoNow(movedAndLanded(board(Nil, (3, 2) :: Nil, (2, 2)))));
        // Store は即座に戻る；スライドはクレートも一緒に戻ってくることを知って
        // いる。
        Assert.assertEq(expected = ((2, 2), Set#{(3, 2)}, Some(((3, 2), true, true, 0.0))),
            (robotOf(back), cratesOf(back), slideOf(back)))

    @Test
    def testMoveKeysIgnoredWhileRewindSliding(): Unit \ Assert =
        let rewinding = undoNow(movedAndLanded(board(Nil, Nil, (2, 2))));
        let w = Worldline.current(Sokoban.tick(right(), dt(), rewinding));
        // 右キーは何も変えなかった；逆スライドがただ進んだだけ。
        Assert.assertEq(expected = ((2, 2), Some(((3, 2), false, true, 0.0625))),
            (robotOf(w), slideOf(w)))

    @Test
    def testHeldZChainsUndosAtReverseSlideRhythm(): Unit \ Assert =
        // 右へ着地済みの2手...
        let m2 = land(Sokoban.tick(right(), dt(), movedAndLanded(board(Nil, Nil, (2, 2)))));
        let u1 = undoNow(m2);
        // ...それから Z を押し続けたまま undoDuration まるまる1回分: 最初の逆
        // スライドが着地し、次の巻き戻しが同じ呼吸の中で始まる。
        let u2 = Sokoban.tick(zKey(), 0.25, u1);
        Assert.assertEq(expected = ((4, 2), (3, 2), (2, 2)),
            (robotOf(Worldline.current(m2)), robotOf(Worldline.current(u1)),
             robotOf(Worldline.current(u2))))

    @Test
    def testRewindSlideWearsEachUndoneMovesFacing(): Unit \ Assert =
        // 右へ歩き、それから上へ。各巻き戻しは、それが取り消す手の方向へ滑って
        // 進み、スナップショットの向きで着地する: 最初は移動中は Up、静止すると
        // Right；2回目は移動中は Right、（開始ポーズである）Down で静止 —— 巻き
        // 戻し直前に行った向き転換は、決してその滑りには漏れ出さない。
        let m2 = land(Sokoban.tick(keys(true, false, false, false), dt(),
                                   movedAndLanded(board(Nil, Nil, (2, 2)))));
        let u1 = undoNow(m2);
        let u1landed = Sokoban.tick(none(), 0.25, u1);
        let u2 = undoNow(u1landed);
        let u2landed = Sokoban.tick(none(), 0.25, u2);
        Assert.assertEq(
            expected = (("Up", "Right"), ("Right", "Right"), ("Right", "Down"), ("Down", "Down")),
            (facingsOf(Worldline.current(u1)), facingsOf(Worldline.current(u1landed)),
             facingsOf(Worldline.current(u2)), facingsOf(Worldline.current(u2landed))))

    @Test
    def testUndoAtInitialBoardIsSafe(): Unit \ Assert =
        let back = Worldline.current(undoNow(fresh(board(Nil, Nil, (2, 2)))));
        // 巻き戻すものは何もない: スライドなし、時計なし、誰も動かない。
        Assert.assertEq(expected = ((2, 2), None, None),
            (robotOf(back), slideOf(back), fxOf(back)))

    @Test
    def testClearIgnoresUndo(): Unit \ Assert =
        // CLEAR はモーダル: すべてのクレートがゴールに乗った後は Enter と
        // Escape しか聞こえない —— Z は勝利の一押しを巻き戻せない。
        let goalAt42 = Board.World.World({
            walls = Set.empty(), goals = Set#{(4, 2)}, crates = Set#{(3, 2)},
            robot = (2, 2), cols = 5, rows = 5,
            facing = Dir4.Down, walkPhase = 0.0, slide = None, undoFx = None,
            screen = Board.Screen.Playing, level = 1, clearElapsed = 0.0 });
        let pushed = land(Sokoban.tick(right(), dt(), fresh(goalAt42)));
        let afterZ = Sokoban.tick(zKey(), dt(), pushed);
        Assert.assertEq(expected = (true, true, (3, 2), None),
            (Board.won(Worldline.current(pushed)), Board.won(Worldline.current(afterZ)),
             robotOf(Worldline.current(afterZ)), slideOf(Worldline.current(afterZ))))

    @Test
    def testIdleMarchBreathesAcrossUndo(): Unit \ Assert =
        let Board.World.World(b) =
            Worldline.current(undoNow(movedAndLanded(board(Nil, Nil, (2, 2)))));
        // 移動フレームでの行進 + 着地中のフルストライド + 巻き戻しフレームでの
        // 行進、すべてジャンプをまたいで引き継がれる。
        Assert.assertEq(expected = 0.2734375, b#walkPhase)

    // ── 巻き戻し時計 ──

    def fxOf(w: Board.World): Option[(Float64, Float64)] =
        let Board.World.World(b) = w;
        Option.map(f -> (f#spin, f#linger), b#undoFx)

    @Test
    def testUndoRaisesTheClock(): Unit \ Assert =
        let moved = movedAndLanded(board(Nil, Nil, (2, 2)));
        Assert.assertEq(expected = (None, Some((0.0, 0.0))),
            (fxOf(Worldline.current(moved)), fxOf(Worldline.current(undoNow(moved)))))

    @Test
    def testNeedleTurnsWithTheReverseSlide(): Unit \ Assert =
        let rewinding = undoNow(movedAndLanded(board(Nil, Nil, (2, 2))));
        let w = Worldline.current(Sokoban.tick(zKey(), dt(), rewinding));
        // 逆スライドの1フレーム分 = 針の回転の同じ割合。
        Assert.assertEq(expected = Some((0.0625, 0.0)), fxOf(w))

    @Test
    def testClockAgesAndFadesOut(): Unit \ Assert =
        let withFx = f -> {
            let Board.World.World(b) = board(Nil, Nil, (2, 2));
            Board.World.World({ undoFx = Some(f) | b })
        };
        let aged = Sokoban.step(none(), dt(), withFx({ spin = 0.125, linger = 0.34375 }));
        let gone = Sokoban.step(none(), dt(), withFx({ spin = 0.125, linger = 0.390625 }));
        Assert.assertEq(expected = (Some((0.125, 0.359375)), None),
            (fxOf(aged), fxOf(gone)))

    @Test
    def testNeedleAngleIsDerivedFromSpin(): Unit \ Assert =
        // 巻き戻された1手につき反時計回りに1回転: 半分の手数は半分の回転。
        Assert.assertEq(expected = (0.0, 3.141592653589793),
            (View.needleAngle(0.0), View.needleAngle(0.5)))

    // ── 画面: Title、Playing、そしてレベルの間のページたち ──

    def screenTag(w: Board.World): String =
        let Board.World.World(b) = w;
        match b#screen {
            case Board.Screen.Title   => "Title"
            case Board.Screen.Playing => "Playing"
        }

    def levelOf(w: Board.World): Int32 =
        let Board.World.World(b) = w;
        b#level

    def colsOf(w: Board.World): Int32 =
        let Board.World.World(b) = w;
        b#cols

    @Test
    def testTitleEnterStartsLevelOne(): Unit \ Assert =
        let w = Worldline.current(Sokoban.tick(enterKey(), dt(), fresh(Board.titleWorld())));
        Assert.assertEq(expected = ("Playing", 1, (3, 5)),
            (screenTag(w), levelOf(w), robotOf(w)))

    @Test
    def testTitleIgnoresWalkAndUndoKeys(): Unit \ Assert =
        let l1 = Sokoban.tick(right(), dt(), fresh(Board.titleWorld()));
        let w = Worldline.current(Sokoban.tick(zKey(), dt(), l1));
        Assert.assertEq(expected = ("Title", (3, 5)), (screenTag(w), robotOf(w)))

    @Test
    def testEnterMidLevelDoesNothing(): Unit \ Assert =
        // ゴールから外れたままのクレートが1つでもあればボードは未解決のままなの
        // で、Enter はただの静かなフレームになる。
        let unsolved = board(Nil, (3, 3) :: Nil, (2, 2));
        let w = Worldline.current(Sokoban.tick(enterKey(), dt(), fresh(unsolved)));
        Assert.assertEq(expected = ("Playing", (2, 2)), (screenTag(w), robotOf(w)))

    @Test
    def testClearEnterAdvancesToLevelTwo(): Unit \ Assert =
        // レベル2は8列幅、レベル1は7列幅である: 新しいボードが、ページが本当に
        // めくれたことを証明する。
        let w = Worldline.current(Sokoban.tick(enterKey(), dt(), fresh(wonBoard(1))));
        Assert.assertEq(expected = ("Playing", 2, 8),
            (screenTag(w), levelOf(w), colsOf(w)))

    @Test
    def testLastLevelClearEnterReturnsToTitle(): Unit \ Assert =
        let w = Worldline.current(Sokoban.tick(enterKey(), dt(), fresh(wonBoard(2))));
        Assert.assertEq(expected = "Title", screenTag(w))

    @Test
    def testBackAbandonsToTitle(): Unit \ Assert =
        let w = Worldline.current(Sokoban.tick(backKey(), dt(), fresh(board(Nil, Nil, (2, 2)))));
        Assert.assertEq(expected = "Title", screenTag(w))

    @Test
    def testClearEscReturnsToTitle(): Unit \ Assert =
        // CLEAR パネルでは Escape はゲームではなくパネルを閉じる。
        let w = Worldline.current(Sokoban.tick(escKey(), dt(), fresh(wonBoard(1))));
        Assert.assertEq(expected = "Title", screenTag(w))

    @Test
    def testClearIgnoresWalkKeys(): Unit \ Assert =
        // CLEAR はモーダル: 方向キーは何も動かさず、履歴も何も書かない。
        let l = Sokoban.tick(right(), dt(), fresh(wonBoard(1)));
        let w = Worldline.current(l);
        Assert.assertEq(expected = ("Playing", (2, 2), Set#{(1, 1)}, 0),
            (screenTag(w), robotOf(w), cratesOf(w), Worldline.pastLength(l)))

    @Test
    def testScreenTransitionStartsFreshHistory(): Unit \ Assert =
        // 着地済みの1手のあと、タイトルへ離脱: 新しい履歴には過去がない —— 履歴
        // は「あるボードへの一回の挑戦」に属する。
        let played = movedAndLanded(board(Nil, Nil, (2, 2)));
        let l = Sokoban.tick(backKey(), dt(), played);
        Assert.assertEq(expected = (1, 0),
            (Worldline.pastLength(played), Worldline.pastLength(l)))

    // ── 手数は過去の長さである: 履歴はすでに数えていた ──

    @Test
    def testMoveCountIsThePastLength(): Unit \ Assert =
        let m1 = movedAndLanded(board(Nil, Nil, (2, 2)));
        let m2 = land(Sokoban.tick(right(), dt(), m1));
        let u1 = undoNow(m2);
        Assert.assertEq(expected = (1, 2, 1),
            (Worldline.pastLength(m1), Worldline.pastLength(m2), Worldline.pastLength(u1)))

    // ── リプレイ: Trace はデータであり、その結末は事実である ──

    @Test
    def testReplaySolvesLevelOne(): Unit \ Assert =
        // 同梱の解答を、固定 dt で純粋な tick に流し込んで駆動する。同じ
        // Trace、同じ Worldline、常に同じ結果: 勝利、手数、最終位置は素の値と
        // して固定される。
        let end = Replay.play(Sokoban.tick, Trace.dt(), Trace.solveLevelOne(), fresh(Board.playingWorld(1)));
        let w = Worldline.current(end);
        Assert.assertEq(expected = (true, 7, (3, 2), Set#{(2, 2), (4, 4)}),
            (Board.won(w), Worldline.pastLength(end), robotOf(w), cratesOf(w)))

    @Test
    def testReplaySolvesLevelTwo(): Unit \ Assert =
        // この固定によって、同梱の両レベルが解けることが証明される —— 第4章で
        // 手作業で確認していたことが、今や機械の仕事になった。
        let end = Replay.play(Sokoban.tick, Trace.dt(), Trace.solveLevelTwo(), fresh(Board.playingWorld(2)));
        let w = Worldline.current(end);
        Assert.assertEq(expected = (true, 21, (5, 2), Set#{(1, 5), (6, 2)}),
            (Board.won(w), Worldline.pastLength(end), robotOf(w), cratesOf(w)))

    @Test
    def testReplayRewindReturnsToTheStart(): Unit \ Assert =
        // 3手進んでから、それらすべてを巻き戻すのに十分な長さ Z を押し続ける:
        // Store はちょうど0手目まで戻ってくる。
        let out = List.flatten(
            Trace.walk(Dir4.Left) ::
            Trace.walk(Dir4.Up) ::
            Trace.walk(Dir4.Right) :: Nil);
        let back = Replay.play(Sokoban.tick, Trace.dt(), Trace.rewind(56) :: Nil,
                              Replay.play(Sokoban.tick, Trace.dt(), out, fresh(Board.playingWorld(1))));
        let w = Worldline.current(back);
        let Board.World.World(start) = Board.playingWorld(1);
        Assert.assertEq(expected = ((3, 5), start#crates, 0),
            (robotOf(w), cratesOf(w), Worldline.pastLength(back)))

    // ── 演出: パーティの時計、紙吹雪、押しの手応え、耳 ──

    def clearElapsedOf(w: Board.World): Float64 =
        let Board.World.World(b) = w;
        b#clearElapsed

    /// 右へ一押しすれば勝利という位置。
    def aboutToWin(): Board.World =
        let Board.World.World(b) = board(Nil, (3, 2) :: Nil, (2, 2));
        Board.World.World({ goals = Set#{(4, 2)} | b })

    @Test
    def testPartyClockRunsOnlyWhileCleared(): Unit \ Assert =
        let cleared = Sokoban.tick(none(), dt(), fresh(wonBoard(1)));
        let playing = Sokoban.tick(none(), dt(), fresh(board(Nil, (3, 3) :: Nil, (2, 2))));
        Assert.assertEq(expected = (dt(), 0.0),
            (clearElapsedOf(Worldline.current(cleared)),
             clearElapsedOf(Worldline.current(playing))))

    @Test
    def testConfettiIsAClosedFormOfTheClock(): Unit \ Assert =
        // 粒子は何も保存されない: 時刻 t における雨は t だけから丸ごと導出され
        // る —— 2回尋ねても同じ絵が返る。
        let atTime = t -> {
            let Board.World.World(b) = wonBoard(1);
            View.confettiQuads({ clearElapsed = t | b })
        };
        let corners = quads -> List.map(q -> List.map(v -> (v#x, v#y), q#vertices), quads);
        let rain = atTime(1.0);
        Assert.assertEq(expected = (0, 48, true, true),
            (List.length(atTime(0.0)), List.length(rain),
             corners(rain) == corners(atTime(1.0)),
             List.forAll(q -> List.length(q#vertices) == 4, rain)))

    @Test
    def testCrateSettleOvershootsOnlyAtTheEnd(): Unit \ Assert =
        // 押されているクレートは 0.8 まで線形スライドに乗り、最後の区間で目標を
        // 飛び越え、着地時にちょうど自宅にいる。
        Assert.assertEq(expected = (0.5, 0.8, true, 1.0),
            (View.settle(0.5), View.settle(0.8),
             View.settle(0.9) > 0.9, View.settle(1.0)))

    @Test
    def testSfxEventNamesTheFrame(): Unit \ Assert =
        let pushStart = fresh(board(Nil, (3, 2) :: Nil, (2, 2)));
        let pushed = Sokoban.tick(right(), dt(), pushStart);
        let walkStart = fresh(board(Nil, Nil, (2, 2)));
        let walked = Sokoban.tick(right(), dt(), walkStart);
        let landed = land(walked);
        let undone = undoNow(landed);
        Assert.assertEq(expected = (Some("push"), Some("move"), Some("undo"), None),
            (Sokoban.sfxEvent(pushStart, pushed), Sokoban.sfxEvent(walkStart, walked),
             Sokoban.sfxEvent(landed, undone), Sokoban.sfxEvent(landed, landed)))

    @Test
    def testSfxClearTrumpsPushAndTransitionsStaySilent(): Unit \ Assert =
        // 勝利の一押しはドンではなくファンファーレ；そしてページをめくる操作
        // （タイトルからボードへ）は一切音を立てない。
        let winStart = fresh(aboutToWin());
        let winPush = Sokoban.tick(right(), dt(), winStart);
        let title = fresh(Board.titleWorld());
        let opened = Sokoban.tick(enterKey(), dt(), title);
        Assert.assertEq(expected = (Some("clear"), None),
            (Sokoban.sfxEvent(winStart, winPush), Sokoban.sfxEvent(title, opened)))

    // ── UI Spec: assets/*.ui.json に宣言されたページたち ──

    /// 同梱の両ページ Spec を1つの UiWorld へ生成する、ランチャーと同じように。
    def spawnedUi(): Option[UiStore.UiWorld] \ IO = Harness.ui()

    def has(path: String, ui: UiStore.UiWorld): Bool =
        not Option.isEmpty(UiStore.idOf(path, ui))

    def textOf(path: String, ui: UiStore.UiWorld): Option[String] =
        UiStore.textOf(path, ui)

    def pageVisible(page: String, ui: UiStore.UiWorld): Option[Bool] =
        UiStore.visibleOf(page, ui)

    @Test
    def testShippedUiSpecsCarryTheAddressedNodes(): Unit \ {Assert, IO} =
        // コードがアドレスするノード名は、同梱の Spec に存在していなければなら
        // ない。
        let found = spawnedUi() |> Option.map(ui ->
            (has("Title", ui), has("Title/prompt", ui),
             has("Clear/panel/headline", ui), has("Clear/panel/moves", ui)));
        Assert.assertEq(expected = Some((true, true, true, true)), found)

    @Test
    def testProjectUiTurnsThePages(): Unit \ {Assert, IO} =
        let pages = w -> spawnedUi() |> Option.map(ui -> {
            let u = GameUi.projectUi(0, w, ui);
            (pageVisible("Title", u), pageVisible("Clear", u))
        });
        Assert.assertEq(
            expected = (Some((Some(true), Some(false))),
                        (Some((Some(false), Some(true))))),
            (pages(Board.titleWorld()), pages(wonBoard(1))))

    @Test
    def testProjectUiWritesTheMoveCount(): Unit \ {Assert, IO} =
        let text = spawnedUi() |> Option.flatMap(ui ->
            textOf("Clear/panel/moves", GameUi.projectUi(3, wonBoard(1), ui)));
        Assert.assertEq(expected = Some("Moves: 3"), text)

    // ── 勝利 ──

    @Test
    def testWonExactlyWhenAllCratesOnGoals(): Unit \ Assert =
        let onGoals = Board.World.World({
            walls = Set.empty(), goals = List.toSet((1, 1) :: (2, 2) :: Nil),
            crates = List.toSet((1, 1) :: Nil), robot = (3, 3), cols = 5, rows = 5,
            facing = Dir4.Down, walkPhase = 0.0, slide = None, undoFx = None,
            screen = Board.Screen.Playing, level = 1, clearElapsed = 0.0 });
        let strayCrate = Board.World.World({
            walls = Set.empty(), goals = List.toSet((1, 1) :: Nil),
            crates = List.toSet((1, 1) :: (3, 3) :: Nil), robot = (2, 2), cols = 5, rows = 5,
            facing = Dir4.Down, walkPhase = 0.0, slide = None, undoFx = None,
            screen = Board.Screen.Playing, level = 1, clearElapsed = 0.0 });
        // クレートのないボードはパズルにならず、決してクリア扱いにはならない。
        let crateless = board(Nil, Nil, (2, 2));
        Assert.assertEq(expected = (true, false, false),
            (Board.won(onGoals), Board.won(strayCrate), Board.won(crateless)))
}
