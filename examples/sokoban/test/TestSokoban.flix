// TestSokoban — pins the parser, the push rules and the slide rhythm as plain
// facts. Keys and levels arrive as data, so every case is an ordinary function
// call with concrete values: no window, no keyboard.

mod TestSokoban {

    // ── Helpers ──

    def keys(u: Bool, d: Bool, l: Bool, r: Bool): Sokoban.Input =
        { up = u, down = d, left = l, right = r }

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
            facing = Robot.Direction.Down, walkPhase = 0.0, slide = None })

    def withSlide(s: Sokoban.Slide, w: Sokoban.World): Sokoban.World =
        let Sokoban.World.World(b) = w;
        Sokoban.World.World({ slide = Some(s) | b })

    def slideOf(w: Sokoban.World): Option[((Int32, Int32), Bool, Float64)] =
        let Sokoban.World.World(b) = w;
        Option.map(s -> (s#fromCell, s#pushing, s#t), b#slide)

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
        Assert.assertEq(expected = ((3, 2), "Right", Some(((2, 2), false, 0.0))),
            (b#robot, tagOf(b#facing), slideOf(w)))

    @Test
    def testInputIgnoredWhileSliding(): Unit \ Assert =
        let sliding = withSlide({ fromCell = (2, 2), pushing = false, t = 0.5 },
                                board(Nil, Nil, (3, 2)));
        let w = Sokoban.step(keys(true, false, false, false), dt(), sliding);
        let Sokoban.World.World(b) = w;
        Assert.assertEq(expected = ((3, 2), "Down", Some(((2, 2), false, 0.625))),
            (b#robot, tagOf(b#facing), slideOf(w)))

    @Test
    def testHeldKeyChainsNextHopWhenSlideLands(): Unit \ Assert =
        let sliding = withSlide({ fromCell = (2, 2), pushing = false, t = 0.875 },
                                board(Nil, Nil, (3, 2)));
        let w = Sokoban.step(right(), dt(), sliding);
        let Sokoban.World.World(b) = w;
        Assert.assertEq(expected = ((4, 2), Some(((3, 2), false, 0.0))),
            (b#robot, slideOf(w)))

    @Test
    def testReleaseStopsAtSlideEnd(): Unit \ Assert =
        let sliding = withSlide({ fromCell = (2, 2), pushing = false, t = 0.875 },
                                board(Nil, Nil, (3, 2)));
        let w = Sokoban.step(none(), dt(), sliding);
        let Sokoban.World.World(b) = w;
        Assert.assertEq(expected = ((3, 2), None, 0.03125),
            (b#robot, slideOf(w), b#walkPhase))

    @Test
    def testWalkPhaseStridesWhileSlidingMarchesWhileStanding(): Unit \ Assert =
        let sliding = withSlide({ fromCell = (2, 2), pushing = false, t = 0.5 },
                                board(Nil, Nil, (3, 2)));
        let Sokoban.World.World(b1) = Sokoban.step(none(), dt(), sliding);
        let Sokoban.World.World(b2) = Sokoban.step(none(), dt(), board(Nil, Nil, (2, 2)));
        Assert.assertEq(expected = (0.03125, 0.01171875), (b1#walkPhase, b2#walkPhase))

    @Test
    def testSlideSpeedScalesWithDtNotFrames(): Unit \ Assert =
        let sliding = () -> withSlide({ fromCell = (2, 2), pushing = false, t = 0.5 },
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
        Assert.assertEq(expected = ((3, 2), false, true, Some(((2, 2), true, 0.0))),
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

    // ── Winning ──

    @Test
    def testWonExactlyWhenAllCratesOnGoals(): Unit \ Assert =
        let onGoals = Sokoban.World.World({
            walls = Set.empty(), goals = List.toSet((1, 1) :: (2, 2) :: Nil),
            crates = List.toSet((1, 1) :: Nil), robot = (3, 3), cols = 5, rows = 5,
            facing = Robot.Direction.Down, walkPhase = 0.0, slide = None });
        let strayCrate = Sokoban.World.World({
            walls = Set.empty(), goals = List.toSet((1, 1) :: Nil),
            crates = List.toSet((1, 1) :: (3, 3) :: Nil), robot = (2, 2), cols = 5, rows = 5,
            facing = Robot.Direction.Down, walkPhase = 0.0, slide = None });
        Assert.assertEq(expected = (true, false), (Sokoban.won(onGoals), Sokoban.won(strayCrate)))
}
