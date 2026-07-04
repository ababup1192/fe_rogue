// TestSokoban — pins the parser, the push rules and the slide rhythm as plain
// facts. Keys and levels arrive as data, so every case is an ordinary function
// call with concrete values: no window, no keyboard.

mod TestSokoban {

    // ── Helpers ──

    def keys(u: Bool, d: Bool, l: Bool, r: Bool): Sokoban.Input =
        { up = u, down = d, left = l, right = r,
          undo = false, enter = false, back = false, esc = false }

    def none(): Sokoban.Input = keys(false, false, false, false)

    def zKey(): Sokoban.Input = { undo = true | none() }

    def enterKey(): Sokoban.Input = { enter = true | none() }

    def backKey(): Sokoban.Input = { back = true | none() }

    def escKey(): Sokoban.Input = { esc = true | none() }

    def right(): Sokoban.Input = keys(false, false, false, true)

    /// The frame time every case steps by: 1/64 s, a dyadic value so every
    /// pinned t and phase below is exact.
    def dt(): Float64 = 1.0 / 64.0

    /// A 5x5 open floor with the given contents, at rest, mid-play on level 1.
    def board(walls: List[(Int32, Int32)], crates: List[(Int32, Int32)],
              robot: (Int32, Int32)): Sokoban.World =
        Sokoban.World.World({
            walls = List.toSet(walls), goals = Set.empty(), crates = List.toSet(crates),
            robot = robot, cols = 5, rows = 5,
            facing = Robot.Direction.Down, walkPhase = 0.0, slide = None, undoFx = None,
            screen = Sokoban.Screen.Playing, level = 1, clearElapsed = 0.0 })

    /// An already-solved board (one crate on one goal) on the given level.
    def wonBoard(level: Int32): Sokoban.World =
        let Sokoban.World.World(b) = board(Nil, (1, 1) :: Nil, (2, 2));
        Sokoban.World.World({ goals = Set#{(1, 1)}, level = level | b })

    def withSlide(s: Sokoban.Slide, w: Sokoban.World): Sokoban.World =
        let Sokoban.World.World(b) = w;
        Sokoban.World.World({ slide = Some(s) | b })

    def slideOf(w: Sokoban.World): Option[((Int32, Int32), Bool, Bool, Float64)] =
        let Sokoban.World.World(b) = w;
        Option.map(s -> (s#fromCell, s#pushing, s#reverse, s#t), b#slide)

    def tagOf(d: Robot.Direction): String = match d {
        case Robot.Direction.Up    => "Up"
        case Robot.Direction.Down  => "Down"
        case Robot.Direction.Left  => "Left"
        case Robot.Direction.Right => "Right"
    }

    // ── Parser ──

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

    // ── Movement: hops, slides and the input gate ──

    @Test
    def testPressHopsCellAndStartsSlide(): Unit \ Assert =
        let w = Sokoban.step(right(), dt(), board(Nil, Nil, (2, 2)));
        let Sokoban.World.World(b) = w;
        Assert.assertEq(expected = ((3, 2), "Right", Some(((2, 2), false, false, 0.0))),
            (b#robot, tagOf(b#facing), slideOf(w)))

    @Test
    def testInputIgnoredWhileSliding(): Unit \ Assert =
        let sliding = withSlide({ fromCell = (2, 2), pushing = false, reverse = false, t = 0.5 },
                                board(Nil, Nil, (3, 2)));
        let w = Sokoban.step(keys(true, false, false, false), dt(), sliding);
        let Sokoban.World.World(b) = w;
        Assert.assertEq(expected = ((3, 2), "Down", Some(((2, 2), false, false, 0.625))),
            (b#robot, tagOf(b#facing), slideOf(w)))

    @Test
    def testHeldKeyChainsNextHopWhenSlideLands(): Unit \ Assert =
        let sliding = withSlide({ fromCell = (2, 2), pushing = false, reverse = false, t = 0.875 },
                                board(Nil, Nil, (3, 2)));
        let w = Sokoban.step(right(), dt(), sliding);
        let Sokoban.World.World(b) = w;
        Assert.assertEq(expected = ((4, 2), Some(((3, 2), false, false, 0.0))),
            (b#robot, slideOf(w)))

    @Test
    def testReleaseStopsAtSlideEnd(): Unit \ Assert =
        let sliding = withSlide({ fromCell = (2, 2), pushing = false, reverse = false, t = 0.875 },
                                board(Nil, Nil, (3, 2)));
        let w = Sokoban.step(none(), dt(), sliding);
        let Sokoban.World.World(b) = w;
        Assert.assertEq(expected = ((3, 2), None, 0.03125),
            (b#robot, slideOf(w), b#walkPhase))

    @Test
    def testWalkPhaseStridesWhileSlidingMarchesWhileStanding(): Unit \ Assert =
        let sliding = withSlide({ fromCell = (2, 2), pushing = false, reverse = false, t = 0.5 },
                                board(Nil, Nil, (3, 2)));
        let Sokoban.World.World(b1) = Sokoban.step(none(), dt(), sliding);
        let Sokoban.World.World(b2) = Sokoban.step(none(), dt(), board(Nil, Nil, (2, 2)));
        Assert.assertEq(expected = (0.03125, 0.01171875), (b1#walkPhase, b2#walkPhase))

    @Test
    def testSlideSpeedScalesWithDtNotFrames(): Unit \ Assert =
        let sliding = () -> withSlide({ fromCell = (2, 2), pushing = false, reverse = false, t = 0.5 },
                                      board(Nil, Nil, (3, 2)));
        let atDt = d -> {
            let Sokoban.World.World(b) = Sokoban.step(none(), d, sliding());
            Option.map(s -> s#t, b#slide)
        };
        Assert.assertEq(expected = (Some(0.625), Some(0.75)),
            (atDt(1.0 / 64.0), atDt(1.0 / 32.0)))

    @Test
    def testWallBlocksButRobotTurns(): Unit \ Assert =
        let w = Sokoban.step(right(), dt(), board((3, 2) :: Nil, Nil, (2, 2)));
        let Sokoban.World.World(b) = w;
        Assert.assertEq(expected = ((2, 2), "Right", None),
            (b#robot, tagOf(b#facing), slideOf(w)))

    // ── Pushing ──

    @Test
    def testPushMovesCrateAndSlidesInSync(): Unit \ Assert =
        let w = Sokoban.step(right(), dt(), board(Nil, (3, 2) :: Nil, (2, 2)));
        let Sokoban.World.World(b) = w;
        Assert.assertEq(expected = ((3, 2), false, true, Some(((2, 2), true, false, 0.0))),
            (b#robot, Set.memberOf((3, 2), b#crates), Set.memberOf((4, 2), b#crates), slideOf(w)))

    @Test
    def testCrateAgainstWallDoesNotBudge(): Unit \ Assert =
        let Sokoban.World.World(b) =
            Sokoban.step(right(), dt(), board((4, 2) :: Nil, (3, 2) :: Nil, (2, 2)));
        Assert.assertEq(expected = ((2, 2), true),
            (b#robot, Set.memberOf((3, 2), b#crates)))

    @Test
    def testTwoCratesInARowDoNotBudge(): Unit \ Assert =
        let Sokoban.World.World(b) =
            Sokoban.step(right(), dt(), board(Nil, (3, 2) :: (4, 2) :: Nil, (2, 2)));
        Assert.assertEq(expected = ((2, 2), true, true),
            (b#robot, Set.memberOf((3, 2), b#crates), Set.memberOf((4, 2), b#crates)))

    // ── The Worldline: record on moves, rewind on Z ──

    def robotOf(w: Sokoban.World): (Int32, Int32) =
        let Sokoban.World.World(b) = w;
        b#robot

    def cratesOf(w: Sokoban.World): Set[(Int32, Int32)] =
        let Sokoban.World.World(b) = w;
        b#crates

    /// Both facings a frame can see: the one the picture wears (drawnFacing)
    /// and the one stored in the Board.
    def facingsOf(w: Sokoban.World): (String, String) =
        let Sokoban.World.World(b) = w;
        (tagOf(Sokoban.drawnFacing(b)), tagOf(b#facing))

    def fresh(w: Sokoban.World): Worldline[Sokoban.World] =
        Worldline.make(w, Sokoban.historyCap())

    /// Land whatever slide is in flight (one tick of a full forward slide).
    def land(line: Worldline[Sokoban.World]): Worldline[Sokoban.World] =
        Sokoban.tick(none(), 0.125, line)

    /// One landed move to the right, ready to be taken back.
    def movedAndLanded(w: Sokoban.World): Worldline[Sokoban.World] =
        land(Sokoban.tick(right(), dt(), fresh(w)))

    /// tick with Z down; fires at once when nothing is sliding.
    def undoNow(line: Worldline[Sokoban.World]): Worldline[Sokoban.World] =
        Sokoban.tick(zKey(), dt(), line)

    @Test
    def testUndoRestoresStoresAtOnceAndStartsReverseSlide(): Unit \ Assert =
        let back = Worldline.current(undoNow(movedAndLanded(board(Nil, Nil, (2, 2)))));
        // The cell is already home; the picture is still out at (3,2), reversed.
        Assert.assertEq(expected = ((2, 2), Some(((3, 2), false, true, 0.0))),
            (robotOf(back), slideOf(back)))

    @Test
    def testUndoRestoresPushedCrateWithReverseSlide(): Unit \ Assert =
        let back = Worldline.current(undoNow(movedAndLanded(board(Nil, (3, 2) :: Nil, (2, 2)))));
        // Stores at once; the slide knows a crate is riding home too.
        Assert.assertEq(expected = ((2, 2), Set#{(3, 2)}, Some(((3, 2), true, true, 0.0))),
            (robotOf(back), cratesOf(back), slideOf(back)))

    @Test
    def testMoveKeysIgnoredWhileRewindSliding(): Unit \ Assert =
        let rewinding = undoNow(movedAndLanded(board(Nil, Nil, (2, 2))));
        let w = Worldline.current(Sokoban.tick(right(), dt(), rewinding));
        // The right key changed nothing; the reverse slide just advanced.
        Assert.assertEq(expected = ((2, 2), Some(((3, 2), false, true, 0.0625))),
            (robotOf(w), slideOf(w)))

    @Test
    def testHeldZChainsUndosAtReverseSlideRhythm(): Unit \ Assert =
        // Two landed moves right...
        let m2 = land(Sokoban.tick(right(), dt(), movedAndLanded(board(Nil, Nil, (2, 2)))));
        let u1 = undoNow(m2);
        // ...then one full undoDuration with Z held: the first reverse slide
        // lands and the next rewind starts in the same breath.
        let u2 = Sokoban.tick(zKey(), 0.25, u1);
        Assert.assertEq(expected = ((4, 2), (3, 2), (2, 2)),
            (robotOf(Worldline.current(m2)), robotOf(Worldline.current(u1)),
             robotOf(Worldline.current(u2))))

    @Test
    def testRewindSlideWearsEachUndoneMovesFacing(): Unit \ Assert =
        // Walk right, then up. Each rewind glides in the direction of the
        // move it takes back and lands in the snapshot's facing: Up in
        // flight then Right at rest for the first, Right in flight then
        // Down (the starting pose) for the second — the turn made just
        // before undoing never leaks into the glide.
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
        // Nothing to rewind: no slide, no clock, nobody moves.
        Assert.assertEq(expected = ((2, 2), None, None),
            (robotOf(back), slideOf(back), fxOf(back)))

    @Test
    def testClearIgnoresUndo(): Unit \ Assert =
        // CLEAR is modal: once every crate rests on a goal, only Enter and
        // Escape are heard — Z cannot rewind the winning push.
        let goalAt42 = Sokoban.World.World({
            walls = Set.empty(), goals = Set#{(4, 2)}, crates = Set#{(3, 2)},
            robot = (2, 2), cols = 5, rows = 5,
            facing = Robot.Direction.Down, walkPhase = 0.0, slide = None, undoFx = None,
            screen = Sokoban.Screen.Playing, level = 1, clearElapsed = 0.0 });
        let pushed = land(Sokoban.tick(right(), dt(), fresh(goalAt42)));
        let afterZ = Sokoban.tick(zKey(), dt(), pushed);
        Assert.assertEq(expected = (true, true, (3, 2), None),
            (Sokoban.won(Worldline.current(pushed)), Sokoban.won(Worldline.current(afterZ)),
             robotOf(Worldline.current(afterZ)), slideOf(Worldline.current(afterZ))))

    @Test
    def testIdleMarchBreathesAcrossUndo(): Unit \ Assert =
        let Sokoban.World.World(b) =
            Worldline.current(undoNow(movedAndLanded(board(Nil, Nil, (2, 2)))));
        // march on the move frame + a full stride while landing + march on the
        // rewind frame, all carried across the jump.
        Assert.assertEq(expected = 0.2734375, b#walkPhase)

    // ── The rewind clock ──

    def fxOf(w: Sokoban.World): Option[(Float64, Float64)] =
        let Sokoban.World.World(b) = w;
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
        // One frame of reverse slide = the same fraction of a needle turn.
        Assert.assertEq(expected = Some((0.0625, 0.0)), fxOf(w))

    @Test
    def testClockAgesAndFadesOut(): Unit \ Assert =
        let withFx = f -> {
            let Sokoban.World.World(b) = board(Nil, Nil, (2, 2));
            Sokoban.World.World({ undoFx = Some(f) | b })
        };
        let aged = Sokoban.step(none(), dt(), withFx({ spin = 0.125, linger = 0.34375 }));
        let gone = Sokoban.step(none(), dt(), withFx({ spin = 0.125, linger = 0.390625 }));
        Assert.assertEq(expected = (Some((0.125, 0.359375)), None),
            (fxOf(aged), fxOf(gone)))

    @Test
    def testNeedleAngleIsDerivedFromSpin(): Unit \ Assert =
        // One counterclockwise turn per rewound move: half a move, half a turn.
        Assert.assertEq(expected = (0.0, 3.141592653589793),
            (Sokoban.needleAngle(0.0), Sokoban.needleAngle(0.5)))

    // ── Screens: Title, Playing, and the pages between levels ──

    def screenTag(w: Sokoban.World): String =
        let Sokoban.World.World(b) = w;
        match b#screen {
            case Sokoban.Screen.Title   => "Title"
            case Sokoban.Screen.Playing => "Playing"
        }

    def levelOf(w: Sokoban.World): Int32 =
        let Sokoban.World.World(b) = w;
        b#level

    def colsOf(w: Sokoban.World): Int32 =
        let Sokoban.World.World(b) = w;
        b#cols

    @Test
    def testTitleEnterStartsLevelOne(): Unit \ Assert =
        let w = Worldline.current(Sokoban.tick(enterKey(), dt(), fresh(Sokoban.titleWorld())));
        Assert.assertEq(expected = ("Playing", 1, (3, 5)),
            (screenTag(w), levelOf(w), robotOf(w)))

    @Test
    def testTitleIgnoresWalkAndUndoKeys(): Unit \ Assert =
        let l1 = Sokoban.tick(right(), dt(), fresh(Sokoban.titleWorld()));
        let w = Worldline.current(Sokoban.tick(zKey(), dt(), l1));
        Assert.assertEq(expected = ("Title", (3, 5)), (screenTag(w), robotOf(w)))

    @Test
    def testEnterMidLevelDoesNothing(): Unit \ Assert =
        // A crate still off its goal keeps the board unsolved, so Enter is
        // just a quiet frame.
        let unsolved = board(Nil, (3, 3) :: Nil, (2, 2));
        let w = Worldline.current(Sokoban.tick(enterKey(), dt(), fresh(unsolved)));
        Assert.assertEq(expected = ("Playing", (2, 2)), (screenTag(w), robotOf(w)))

    @Test
    def testClearEnterAdvancesToLevelTwo(): Unit \ Assert =
        // Level 2 is eight columns wide where level 1 is seven: the fresh
        // board proves the page really turned.
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
        // On the CLEAR panel Escape closes the panel, not the game.
        let w = Worldline.current(Sokoban.tick(escKey(), dt(), fresh(wonBoard(1))));
        Assert.assertEq(expected = "Title", screenTag(w))

    @Test
    def testClearIgnoresWalkKeys(): Unit \ Assert =
        // CLEAR is modal: a direction key moves nothing and writes no history.
        let l = Sokoban.tick(right(), dt(), fresh(wonBoard(1)));
        let w = Worldline.current(l);
        Assert.assertEq(expected = ("Playing", (2, 2), Set#{(1, 1)}, 0),
            (screenTag(w), robotOf(w), cratesOf(w), Worldline.pastLength(l)))

    @Test
    def testScreenTransitionStartsFreshHistory(): Unit \ Assert =
        // One landed move, then abandon to the title: the new line has no
        // past — history belongs to one attempt at one board.
        let played = movedAndLanded(board(Nil, Nil, (2, 2)));
        let l = Sokoban.tick(backKey(), dt(), played);
        Assert.assertEq(expected = (1, 0),
            (Worldline.pastLength(played), Worldline.pastLength(l)))

    // ── Moves are the past's length: the history was already counting ──

    @Test
    def testMoveCountIsThePastLength(): Unit \ Assert =
        let m1 = movedAndLanded(board(Nil, Nil, (2, 2)));
        let m2 = land(Sokoban.tick(right(), dt(), m1));
        let u1 = undoNow(m2);
        Assert.assertEq(expected = (1, 2, 1),
            (Worldline.pastLength(m1), Worldline.pastLength(m2), Worldline.pastLength(u1)))

    // ── Replay: a Trace is data, and its outcome is a fact ──

    @Test
    def testReplaySolvesLevelOne(): Unit \ Assert =
        // The shipped solution, driven through the pure tick at a fixed dt.
        // Same Trace, same Worldline, always: the win, the move count and
        // the final positions are pinned as plain values.
        let end = Replay.play(Replay.solveLevelOne(), fresh(Sokoban.playingWorld(1)));
        let w = Worldline.current(end);
        Assert.assertEq(expected = (true, 7, (3, 2), Set#{(2, 2), (4, 4)}),
            (Sokoban.won(w), Worldline.pastLength(end), robotOf(w), cratesOf(w)))

    @Test
    def testReplaySolvesLevelTwo(): Unit \ Assert =
        // With this pin, both shipped levels are provably solvable — what
        // chapter 4 checked by hand is now a machine's job.
        let end = Replay.play(Replay.solveLevelTwo(), fresh(Sokoban.playingWorld(2)));
        let w = Worldline.current(end);
        Assert.assertEq(expected = (true, 21, (5, 2), Set#{(1, 5), (6, 2)}),
            (Sokoban.won(w), Worldline.pastLength(end), robotOf(w), cratesOf(w)))

    @Test
    def testReplayRewindReturnsToTheStart(): Unit \ Assert =
        // Three moves out, then Z held long enough to rewind them all: the
        // Stores come back exactly to move zero.
        let out = List.flatten(
            Replay.walk(Robot.Direction.Left) ::
            Replay.walk(Robot.Direction.Up) ::
            Replay.walk(Robot.Direction.Right) :: Nil);
        let back = Replay.play(Replay.rewind(56) :: Nil,
                              Replay.play(out, fresh(Sokoban.playingWorld(1))));
        let w = Worldline.current(back);
        let Sokoban.World.World(start) = Sokoban.playingWorld(1);
        Assert.assertEq(expected = ((3, 5), start#crates, 0),
            (robotOf(w), cratesOf(w), Worldline.pastLength(back)))

    // ── Juice: the party clock, the confetti, the push feel, the ear ──

    def clearElapsedOf(w: Sokoban.World): Float64 =
        let Sokoban.World.World(b) = w;
        b#clearElapsed

    /// One push to the right away from winning.
    def aboutToWin(): Sokoban.World =
        let Sokoban.World.World(b) = board(Nil, (3, 2) :: Nil, (2, 2));
        Sokoban.World.World({ goals = Set#{(4, 2)} | b })

    @Test
    def testPartyClockRunsOnlyWhileCleared(): Unit \ Assert =
        let cleared = Sokoban.tick(none(), dt(), fresh(wonBoard(1)));
        let playing = Sokoban.tick(none(), dt(), fresh(board(Nil, (3, 3) :: Nil, (2, 2))));
        Assert.assertEq(expected = (dt(), 0.0),
            (clearElapsedOf(Worldline.current(cleared)),
             clearElapsedOf(Worldline.current(playing))))

    @Test
    def testConfettiIsAClosedFormOfTheClock(): Unit \ Assert =
        // No particles are stored: the rain at time t is derived, whole,
        // from t alone — asking twice gives the identical picture.
        let atTime = t -> {
            let Sokoban.World.World(b) = wonBoard(1);
            Sokoban.confettiQuads({ clearElapsed = t | b })
        };
        let corners = quads -> List.map(q -> List.map(v -> (v#x, v#y), q#vertices), quads);
        let rain = atTime(1.0);
        Assert.assertEq(expected = (0, 48, true, true),
            (List.length(atTime(0.0)), List.length(rain),
             corners(rain) == corners(atTime(1.0)),
             List.forAll(q -> List.length(q#vertices) == 4, rain)))

    @Test
    def testCrateSettleOvershootsOnlyAtTheEnd(): Unit \ Assert =
        // The pushed crate rides the linear slide until 0.8, pops past the
        // target in the last stretch, and is exactly home at landing.
        Assert.assertEq(expected = (0.5, 0.8, true, 1.0),
            (Sokoban.settle(0.5), Sokoban.settle(0.8),
             Sokoban.settle(0.9) > 0.9, Sokoban.settle(1.0)))

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
        // The winning push is a fanfare, not a thud; and turning a page
        // (title to board) makes no sound at all.
        let winStart = fresh(aboutToWin());
        let winPush = Sokoban.tick(right(), dt(), winStart);
        let title = fresh(Sokoban.titleWorld());
        let opened = Sokoban.tick(enterKey(), dt(), title);
        Assert.assertEq(expected = (Some("clear"), None),
            (Sokoban.sfxEvent(winStart, winPush), Sokoban.sfxEvent(title, opened)))

    // ── The UI Specs: pages declared in assets/*.ui.json ──

    /// Spawn both shipped page Specs into one UiWorld, as the launcher does.
    def spawnedUi(): Option[UiStore.UiWorld] \ IO = Harness.ui()

    def has(path: String, ui: UiStore.UiWorld): Bool =
        not Option.isEmpty(UiStore.idOf(path, ui))

    def textOf(path: String, ui: UiStore.UiWorld): Option[String] =
        UiStore.idOf(path, ui)
            |> Option.flatMap(id -> Map.get(id, ui#texts))
            |> Option.map(t -> t#text)

    def pageVisible(page: String, ui: UiStore.UiWorld): Option[Bool] =
        Map.get(page, UiStore.visibleByPath(page, ui))

    @Test
    def testShippedUiSpecsCarryTheAddressedNodes(): Unit \ {Assert, IO} =
        // The names the code addresses must exist in the shipped Specs.
        let found = spawnedUi() |> Option.map(ui ->
            (has("Title", ui), has("Title/prompt", ui),
             has("Clear/panel/headline", ui), has("Clear/panel/moves", ui)));
        Assert.assertEq(expected = Some((true, true, true, true)), found)

    @Test
    def testProjectUiTurnsThePages(): Unit \ {Assert, IO} =
        let pages = w -> spawnedUi() |> Option.map(ui -> {
            let u = Sokoban.projectUi(0, w, ui);
            (pageVisible("Title", u), pageVisible("Clear", u))
        });
        Assert.assertEq(
            expected = (Some((Some(true), Some(false))),
                        (Some((Some(false), Some(true))))),
            (pages(Sokoban.titleWorld()), pages(wonBoard(1))))

    @Test
    def testProjectUiWritesTheMoveCount(): Unit \ {Assert, IO} =
        let text = spawnedUi() |> Option.flatMap(ui ->
            textOf("Clear/panel/moves", Sokoban.projectUi(3, wonBoard(1), ui)));
        Assert.assertEq(expected = Some("Moves: 3"), text)

    // ── Winning ──

    @Test
    def testWonExactlyWhenAllCratesOnGoals(): Unit \ Assert =
        let onGoals = Sokoban.World.World({
            walls = Set.empty(), goals = List.toSet((1, 1) :: (2, 2) :: Nil),
            crates = List.toSet((1, 1) :: Nil), robot = (3, 3), cols = 5, rows = 5,
            facing = Robot.Direction.Down, walkPhase = 0.0, slide = None, undoFx = None,
            screen = Sokoban.Screen.Playing, level = 1, clearElapsed = 0.0 });
        let strayCrate = Sokoban.World.World({
            walls = Set.empty(), goals = List.toSet((1, 1) :: Nil),
            crates = List.toSet((1, 1) :: (3, 3) :: Nil), robot = (2, 2), cols = 5, rows = 5,
            facing = Robot.Direction.Down, walkPhase = 0.0, slide = None, undoFx = None,
            screen = Sokoban.Screen.Playing, level = 1, clearElapsed = 0.0 });
        // A crateless board poses no puzzle and never counts as solved.
        let crateless = board(Nil, Nil, (2, 2));
        Assert.assertEq(expected = (true, false, false),
            (Sokoban.won(onGoals), Sokoban.won(strayCrate), Sokoban.won(crateless)))
}
