// TestSokoban — pins step's rules as plain facts. Keys arrive as data, so every
// case is an ordinary function call with concrete values: no window, no keyboard.

mod TestSokoban {

    def keys(u: Bool, d: Bool, l: Bool, r: Bool): Sokoban.Input =
        { up = u, down = d, left = l, right = r }

    def at(x: Float64, y: Float64, facing: Robot.Direction, phase: Float64): Sokoban.World =
        Sokoban.World.World({ robotX = x, robotY = y, facing = facing, walkPhase = phase })

    def tagOf(d: Robot.Direction): String = match d {
        case Robot.Direction.Up    => "Up"
        case Robot.Direction.Down  => "Down"
        case Robot.Direction.Left  => "Left"
        case Robot.Direction.Right => "Right"
    }

    @Test
    def testIdleSnapsToRestPoseAndKeepsFacing(): Unit \ Assert =
        let Sokoban.World.World(r) =
            Sokoban.step(keys(false, false, false, false),
                         at(100.0, 90.0, Robot.Direction.Left, 0.5));
        Assert.assertEq(expected = (100.0, 90.0, "Left", 0.0),
            (r#robotX, r#robotY, tagOf(r#facing), r#walkPhase))

    @Test
    def testRightMovesFacesAndWalks(): Unit \ Assert =
        let Sokoban.World.World(r) =
            Sokoban.step(keys(false, false, false, true),
                         at(160.0, 120.0, Robot.Direction.Down, 0.0));
        Assert.assertEq(expected = (161.5, 120.0, "Right", 0.03125),
            (r#robotX, r#robotY, tagOf(r#facing), r#walkPhase))

    @Test
    def testDiagonalMovesBothAxesHorizontalWinsFacing(): Unit \ Assert =
        let Sokoban.World.World(r) =
            Sokoban.step(keys(true, false, false, true),
                         at(160.0, 120.0, Robot.Direction.Down, 0.0));
        Assert.assertEq(expected = (161.5, 118.5, "Right"),
            (r#robotX, r#robotY, tagOf(r#facing)))

    @Test
    def testOpposedKeysCancelToRest(): Unit \ Assert =
        let Sokoban.World.World(r) =
            Sokoban.step(keys(false, false, true, true),
                         at(160.0, 120.0, Robot.Direction.Up, 0.25));
        Assert.assertEq(expected = (160.0, "Up", 0.0),
            (r#robotX, tagOf(r#facing), r#walkPhase))

    @Test
    def testClampStopsAtScreenEdge(): Unit \ Assert =
        let Sokoban.World.World(r) =
            Sokoban.step(keys(false, false, false, true),
                         at(272.0, 120.0, Robot.Direction.Right, 0.0));
        Assert.assertEq(expected = 272.0, r#robotX)

    @Test
    def testWalkPhaseWrapsPastOne(): Unit \ Assert =
        let Sokoban.World.World(r) =
            Sokoban.step(keys(false, true, false, false),
                         at(160.0, 120.0, Robot.Direction.Down, 0.984375));
        Assert.assertEq(expected = 0.015625, r#walkPhase)
}
