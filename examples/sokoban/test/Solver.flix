// Solver — 同梱レベルが解けることを機械的に証明する自動ソルバーと、レベルの静的
// 検証。fe_rogue で昇格した engine_world の GridSearch を逆輸入し、探索の芯
// （どこまで歩けるか）はすべて GridSearch.reachable に委ねる。
//
// ソルバーはプッシュ空間の幅優先探索: 状態は「クレートの位置の集合 + ロボットの
// 正規化位置」だけで、ロボットの歩きは状態に数えない —— 同じクレート配置でロボ
// ットが同じ部屋にいる盤はすべて同じ状態である。1手 = 1回の押し、なので幅優先の
// 深さがそのまま最小押し数になる。
//
// ここにあるものはすべて純粋: Level.Parsed を渡せば答えが返る。テスト専用であり
// ゲーム本体（src/）には一切触れない。
mod Solver {

    /// グリッド上の1マス、(列, 行)。Level.Parsed と同じ流儀。
    type alias Cell = (Int32, Int32)

    /// 探索中の1状態。crates はクレートの現在地、reach はロボットが（クレートを
    /// 押さずに）歩いて行けるマスの一覧（遷移の合法判定に使う）、norm は到達域の
    /// 座標順最小マス（状態の同一性判定に使う正規化位置）。
    type alias State = { crates = Set[Cell], reach = List[Cell], norm = Cell }

    /// 状態の同一性判定に使う鍵: クレート配置 + ロボット到達域の座標順最小マス。
    /// 到達域のどこにロボットが立っていても同じ鍵になるので、歩きの違いだけの
    /// 状態が1つに畳まれる。
    type alias StateKey = (Set[Cell], Cell)

    // ── ソルバー: プッシュ空間の幅優先探索 ──

    /// このボードを解く最小押し数。解けなければ None。
    /// 幅優先なので、最初に勝利へ届いた深さがそのまま最小押し数である。
    pub def minPushes(parsed: Level.Parsed): Option[Int32] =
        let start = stateOf(parsed, parsed#crates, parsed#robot);
        bfs(parsed, 0, start :: Nil, Set#{keyOf(start)})

    /// このボードは解けるか（minPushes が答えを持つか）。
    pub def solvable(parsed: Level.Parsed): Bool =
        not Option.isEmpty(minPushes(parsed))

    /// 深さ `depth` の状態たち `frontier` に勝利があればその深さを返し、なければ
    /// 全状態を1押しずつ広げて次の深さへ。広げるものが尽きたら解なし。
    def bfs(parsed: Level.Parsed, depth: Int32, frontier: List[State],
            visited: Set[StateKey]): Option[Int32] =
        if (List.isEmpty(frontier)) None
        else if (List.exists(state -> won(parsed#goals, state#crates), frontier)) Some(depth)
        else {
            let (nextFrontier, nextVisited) = expand(parsed, frontier, visited);
            bfs(parsed, depth + 1, nextFrontier, nextVisited)
        }

    /// frontier の全状態の後続をまとめ、未訪問のものだけを次の frontier に積む。
    def expand(parsed: Level.Parsed, frontier: List[State],
               visited: Set[StateKey]): (List[State], Set[StateKey]) =
        List.foldLeft((acc, state) ->
            List.foldLeft((acc2, next) -> {
                let (frontier2, visited2) = acc2;
                let key = keyOf(next);
                if (Set.memberOf(key, visited2)) acc2
                else (next :: frontier2, Set.insert(key, visited2))
            }, acc, successors(parsed, state)),
            (Nil, visited), frontier)

    /// この状態から1押しで行けるすべての状態: 各クレート × 各方向。
    def successors(parsed: Level.Parsed, state: State): List[State] =
        Set.toList(state#crates) |> List.flatMap(crate ->
            Dir4.all() |> List.filterMap(d -> pushOf(parsed, state, crate, d)))

    /// クレート `crate` を方向 `d` へ1マス押す手。合法なのは、押し位置（クレート
    /// の逆方向隣）にロボットが歩いて行けて、押し先が床でクレートも無いとき。
    /// 押した後、ロボットはクレートが居たマスに立つ。
    def pushOf(parsed: Level.Parsed, state: State, crate: Cell, d: Dir4.Dir4): Option[State] =
        let standAt = Grid.neighbor(crate, Dir4.opposite(d));
        let dest = Grid.neighbor(crate, d);
        let legal = List.memberOf(standAt, state#reach)
            and isFloor(parsed, dest)
            and not Set.memberOf(dest, state#crates);
        if (legal)
            Some(stateOf(parsed, Set.insert(dest, Set.remove(crate, state#crates)), crate))
        else None

    /// クレート配置とロボット位置から状態を組む。ロボットの到達域（床かつクレー
    /// ト無しのマスだけを通る）は GridSearch.reachable にそのまま委ねる。
    /// 到達域は必ずロボット自身を含むので、robot を種にした fold で座標順最小の
    /// マスが決定的に求まる —— これが正規化位置になる。
    def stateOf(parsed: Level.Parsed, crates: Set[Cell], robot: Cell): State =
        let canWalk = c -> isFloor(parsed, c) and not Set.memberOf(c, crates);
        let reach = GridSearch.reachable(canWalk, robot, stepBudget(parsed));
        { crates = crates, reach = reach, norm = List.foldLeft(Order.min, robot, reach) }

    /// 状態の鍵: クレート配置 + 正規化位置。
    def keyOf(state: State): StateKey =
        (state#crates, state#norm)

    /// 盤内の全マス数。到達探索の歩数上限としていつでも十分。
    def stepBudget(parsed: Level.Parsed): Int32 =
        parsed#cols * parsed#rows

    /// 勝利判定: Board.won と同じ約束 —— クレートが1つもないボードはパズルに
    /// ならないので、決してクリア扱いにしない。
    def won(goals: Set[Cell], crates: Set[Cell]): Bool =
        not Set.isEmpty(crates) and Set.isSubsetOf(crates, goals)

    /// 盤内かつ壁でないマス（クレートは床の上に乗っているだけなので床扱い）。
    def isFloor(parsed: Level.Parsed, cell: Cell): Bool =
        Grid.inRect(cell, parsed#cols, parsed#rows) and not Set.memberOf(cell, parsed#walls)

    // ── レベル静的検証: レベル追加時の自動ガード ──

    /// 床の連結性: すべての床マスへ、ロボットの初期位置から（クレートを無視して）
    /// 歩いて行けるか。false なら、決して使われない孤立領域が盤に混ざっている。
    pub def floorConnected(parsed: Level.Parsed): Bool =
        List.isEmpty(isolatedFloors(parsed))

    /// ロボットの初期位置から到達できない床マスの一覧（孤立領域の中身）。
    pub def isolatedFloors(parsed: Level.Parsed): List[Cell] =
        let reached = GridSearch.reachable(c -> isFloor(parsed, c), parsed#robot, stepBudget(parsed));
        floorCells(parsed) |> List.filter(c -> not List.memberOf(c, reached))

    /// コーナーデッドロック: 初期配置に「角に据えられたゴール外のクレート」が
    /// ないか。角のクレートはどの方向にも押せないので、そのレベルは開始時点で
    /// 詰んでいる。
    pub def noCornerDeadlock(parsed: Level.Parsed): Bool =
        List.isEmpty(cornerDeadlocks(parsed))

    /// 角（直交2方向が壁）に居るゴール外のクレートの一覧。
    pub def cornerDeadlocks(parsed: Level.Parsed): List[Cell] =
        Set.toList(parsed#crates) |> List.filter(crate ->
            not Set.memberOf(crate, parsed#goals) and inCorner(parsed#walls, crate))

    /// 上下いずれかが壁、かつ左右いずれかが壁 —— 押す隙間のない角。
    def inCorner(walls: Set[Cell], cell: Cell): Bool =
        let wallAt = d -> Set.memberOf(Grid.neighbor(cell, d), walls);
        (wallAt(Dir4.Up) or wallAt(Dir4.Down)) and (wallAt(Dir4.Left) or wallAt(Dir4.Right))

    /// 盤内の全床マス（列優先で決定的な順）。
    def floorCells(parsed: Level.Parsed): List[Cell] =
        List.range(0, parsed#cols) |> List.flatMap(x ->
            List.range(0, parsed#rows) |> List.filterMap(y ->
                if (isFloor(parsed, (x, y))) Some((x, y)) else None))
}
