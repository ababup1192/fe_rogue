// TestSokoban — pins the parser, the push rules and the slide rhythm as plain
// facts. Keys and levels arrive as data, so every case is an ordinary function
// call with concrete values: no window, no keyboard.

mod TestSokoban {

    // ── Helpers ──

    def keys(u: Bool, d: Bool, l: Bool, r: Bool): Sokoban.Input =
        { up = u, down = d, left = l, right = r, undo = false }

    def zKey(): Sokoban.Input =
        { up = false, down = false, left = false, right = false, undo = true }

    def none(): Sokoban.Input = keys(false, false, false, false)

    def right(): Sokoban.Input = keys(false, false, false, true)

    /// The frame time every case steps by: 1/64 s, a dyadic value so every
    /// pinned t and phase below is exact.
    def dt(): Float64 = 1.0 / 64.0

    /// A 5x5 open floor with the given contents, at rest.
    def board(walls: List[(Int32, Int32)], crates: List[(Int32, Int32)],
              robot: (Int32, Int32)): Sokoban.World =
        Sokoban.World.World({
            walls = List.toSet(walls), goals = Set.empty(), crates = List.toSet(crates),
            robot = robot, cols = 5, rows = 5,
            facing = Robot.Direction.Down, walkPhase = 0.0, slide = None, undoFx = None })

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
    def testClearThenUndoUnclears(): Unit \ Assert =
        let goalAt42 = Sokoban.World.World({
            walls = Set.empty(), goals = Set#{(4, 2)}, crates = Set#{(3, 2)},
            robot = (2, 2), cols = 5, rows = 5,
            facing = Robot.Direction.Down, walkPhase = 0.0, slide = None, undoFx = None });
        let pushed = Sokoban.tick(right(), dt(), fresh(goalAt42));
        let undone = undoNow(land(pushed));
        Assert.assertEq(expected = (true, false),
            (Sokoban.won(Worldline.current(pushed)), Sokoban.won(Worldline.current(undone))))

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

    // ── Winning ──

    @Test
    def testWonExactlyWhenAllCratesOnGoals(): Unit \ Assert =
        let onGoals = Sokoban.World.World({
            walls = Set.empty(), goals = List.toSet((1, 1) :: (2, 2) :: Nil),
            crates = List.toSet((1, 1) :: Nil), robot = (3, 3), cols = 5, rows = 5,
            facing = Robot.Direction.Down, walkPhase = 0.0, slide = None, undoFx = None });
        let strayCrate = Sokoban.World.World({
            walls = Set.empty(), goals = List.toSet((1, 1) :: Nil),
            crates = List.toSet((1, 1) :: (3, 3) :: Nil), robot = (2, 2), cols = 5, rows = 5,
            facing = Robot.Direction.Down, walkPhase = 0.0, slide = None, undoFx = None });
        Assert.assertEq(expected = (true, false), (Sokoban.won(onGoals), Sokoban.won(strayCrate)))
}
