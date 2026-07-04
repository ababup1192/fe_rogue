// Level — 古典的な sokoban のテキスト形式で書かれたボードと、文字列を位置の集合
// へ変換する純粋なパーサー:
//
//   #  壁          .  ゴール         @  ロボット
//   $  クレート    *  ゴール上のクレート +  ゴール上のロボット
//   (空白) 床
//
// レベルはデータである: 新しいボードを設計してもゲームのルールには一切触れな
// い。パースは Result を返す純粋な関数である —— 不正な文字列は、クラッシュでは
// なく何が間違っているかを説明する値になる。

mod Level {

    /// 最初のボード: クレート2個、ゴール2個、内部の壁なし。
    pub def one(): String =
        String.unlines(
            "#######" ::
            "#     #" ::
            "# .$  #" ::
            "#     #" ::
            "#  $. #" ::
            "#  @  #" ::
            "#######" :: Nil)

    /// 2番目のボード: 内部の壁が、各プッシュの前に迂回を強いる。
    pub def two(): String =
        String.unlines(
            "########" ::
            "#      #" ::
            "# ## $.#" ::
            "# #    #" ::
            "# $ ## #" ::
            "#. @   #" ::
            "########" :: Nil)

    /// あるボードが語るすべてを、素のデータとして。グリッド座標は (列, 行) で、
    /// テキストの左上から数える。
    pub type alias Parsed = {
        walls = Set[(Int32, Int32)],
        goals = Set[(Int32, Int32)],
        crates = Set[(Int32, Int32)],
        robot = (Int32, Int32),
        cols = Int32,
        rows = Int32
    }

    /// まだ読み込み中のボード: ロボットはまだ現れていないかもしれない。
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
