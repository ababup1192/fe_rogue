// Level — boards written in the classic sokoban text form, and the pure parser
// that turns a string into sets of positions:
//
//   #  wall        .  goal          @  robot
//   $  crate       *  crate on goal +  robot on goal
//   (space) floor
//
// A level is data: designing a new board never touches the game's rules.
// Parsing is a pure function returning Result — a bad string is a value
// describing what is wrong, not a crash.

mod Level {

    /// The first board: two crates, two goals, no interior walls.
    pub def one(): String =
        String.unlines(
            "#######" ::
            "#     #" ::
            "# .$  #" ::
            "#     #" ::
            "#  $. #" ::
            "#  @  #" ::
            "#######" :: Nil)

    /// The second board: interior walls force a detour before each push.
    pub def two(): String =
        String.unlines(
            "########" ::
            "#      #" ::
            "# ## $.#" ::
            "# #    #" ::
            "# $ ## #" ::
            "#. @   #" ::
            "########" :: Nil)

    /// Everything a board says, as plain data. Grid positions are (column, row),
    /// counted from the top-left of the text.
    pub type alias Parsed = {
        walls = Set[(Int32, Int32)],
        goals = Set[(Int32, Int32)],
        crates = Set[(Int32, Int32)],
        robot = (Int32, Int32),
        cols = Int32,
        rows = Int32
    }

    /// A board still being read: the robot may not have appeared yet.
    type alias Draft = {
        walls = Set[(Int32, Int32)],
        goals = Set[(Int32, Int32)],
        crates = Set[(Int32, Int32)],
        robot = Option[(Int32, Int32)],
        cols = Int32
    }

    pub def parse(text: String): Result[String, Parsed] =
        let lines = String.lines(text);
        forM (d <- parseRows(0, lines, emptyDraft());
              robot <- requireRobot(d#robot))
        yield { walls = d#walls, goals = d#goals, crates = d#crates,
                robot = robot, cols = d#cols, rows = List.length(lines) }

    def emptyDraft(): Draft =
        { walls = Set.empty(), goals = Set.empty(), crates = Set.empty(),
          robot = None, cols = 0 }

    def requireRobot(o: Option[(Int32, Int32)]): Result[String, (Int32, Int32)] =
        match o {
            case Some(p) => Result.Ok(p)
            case None    => Result.Err("the level has no robot '@'")
        }

    def parseRows(y: Int32, lines: List[String], d: Draft): Result[String, Draft] =
        match lines {
            case Nil => Result.Ok(d)
            case line :: rest =>
                forM (d1 <- parseCells(0, y, String.toList(line), d);
                      d2 <- parseRows(y + 1, rest, d1))
                yield d2
        }

    def parseCells(x: Int32, y: Int32, cells: List[Char], d: Draft): Result[String, Draft] =
        match cells {
            case Nil => Result.Ok({ cols = Int32.max(x, d#cols) | d })
            case c :: rest =>
                forM (d1 <- cell(x, y, c, d);
                      d2 <- parseCells(x + 1, y, rest, d1))
                yield d2
        }

    def cell(x: Int32, y: Int32, c: Char, d: Draft): Result[String, Draft] =
        let p = (x, y);
        match c {
            case '#' => Result.Ok({ walls = Set.insert(p, d#walls) | d })
            case ' ' => Result.Ok(d)
            case '.' => Result.Ok({ goals = Set.insert(p, d#goals) | d })
            case '$' => Result.Ok({ crates = Set.insert(p, d#crates) | d })
            case '*' => Result.Ok({ crates = Set.insert(p, d#crates),
                                    goals = Set.insert(p, d#goals) | d })
            case '@' => placeRobot(p, d)
            case '+' => forM (d1 <- placeRobot(p, d))
                        yield { goals = Set.insert(p, d1#goals) | d1 }
            case _   => Result.Err("unknown tile '${c}' at column ${x}, row ${y}")
        }

    def placeRobot(p: (Int32, Int32), d: Draft): Result[String, Draft] =
        if (Option.isEmpty(d#robot)) Result.Ok({ robot = Some(p) | d })
        else Result.Err("more than one robot in the level")
}
