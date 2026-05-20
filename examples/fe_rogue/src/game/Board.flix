/// Board — 盤面状態（マップ + 駒の位置）と、その上での動き・経路探索を一元的に扱う
///
/// チェスの盤面のメタファー:
///   - map: タイル（壁・床）の地形情報
///   - pieces: 盤上にいる駒（プレイヤー [id 付き] / 敵 [id 付き] / 将来のアイテム）の位置リスト
///
/// 章立て:
///   (A) 型 + effect: Piece / Board / BoardQuery
///   (B) 駒クエリ: playerPositions / enemyPositions / isOccupied / isEnemyAt /
///                 nearestPlayer / adjacentPlayer
///   (C) 動きルール: isWalkable / stepTarget / tryMove / tryMoveWithRange
///   (D) 経路探索: reachableCells / bfsPath
///
/// EnemyAI / AutoMove / MoveRangeScene / EnemyRangeScene / PlayerScene などはこの
/// Board を 1 つ受け取れば「次の手」を計算できる。Scene[NodeTag] には依存しない。
///
/// `BoardQuery` は「現フレームの盤面」を effect 経由で取り回すための窓口。
/// Game.start の handler が現フレームの Scene と TileMapLayer から構築してクロージャに
/// 包み、フレーム内で固定して返す。
pub enum Piece with Eq {
    case Player(Int32)   // id 付き（パーティ 3 人を区別する）
    case Enemy(Int32)
    // 将来: case Item(...)
}

pub type alias Board = {
    map    = MapSnapshot,
    pieces = List[(Piece, {x = Int32, y = Int32})]
}

pub eff BoardQuery {
    def board(): Board
}

mod Board {

    // ════════════════════════════════════════════════════════
    // (B) 駒クエリ
    // ════════════════════════════════════════════════════════

    /// 盤面上のプレイヤー駒一覧（id, gridPos）。pieces 順を保つ。
    /// パーティ 3 人がそれぞれ id=0/1/2 で並んでいる想定。
    pub def playerPositions(board: Board): List[(Int32, {x = Int32, y = Int32})] =
        List.filterMap(entry -> match entry {
            case (Piece.Player(id), pos) => Some((id, pos))
            case _                        => None
        }, board#pieces)

    /// 盤面上の敵駒一覧（id, gridPos）。pieces 順を保つ。
    pub def enemyPositions(board: Board): List[(Int32, {x = Int32, y = Int32})] =
        List.filterMap(entry -> match entry {
            case (Piece.Enemy(id), pos) => Some((id, pos))
            case _                      => None
        }, board#pieces)

    /// 任意の駒（Player / Enemy）が `coord` を占有しているか。
    /// Vec2i は record alias なのでフィールド比較する。
    pub def isOccupied(coord: {x = Int32, y = Int32}, board: Board): Bool =
        List.exists(entry -> {
            let (_, pos) = entry;
            samePosition(pos, coord)
        }, board#pieces)

    /// `playerId` が居るセルに、自分以外の味方が居るか（= 味方と重なっているか）。
    /// 移動で味方マスをすり抜ける挙動を許す代わりに「重なっている間は何も決定できない」
    /// (= PlayerMoving + Z で ActionMenu を開かない) ガードに使う純粋関数。
    pub def isOverlappingAlly(playerId: Int32, board: Board): Bool =
        let positions = playerPositions(board);
        match List.find(p -> { let (id, _) = p; id == playerId }, positions) {
            case None         => false
            case Some(myPair) =>
                let (_, myPos) = myPair;
                List.exists(p -> {
                    let (id, pos) = p;
                    id != playerId and samePosition(pos, myPos)
                }, positions)
        }

    /// 敵駒だけが `coord` を占有しているか（味方駒や空マスは false）。
    /// プレイヤーの移動判定で「味方をすり抜ける」を実現するために使う。
    pub def isEnemyAt(coord: {x = Int32, y = Int32}, board: Board): Bool =
        List.exists(entry -> match entry {
            case (Piece.Enemy(_), pos) => samePosition(pos, coord)
            case _                      => false
        }, board#pieces)

    /// `enemyPos` から最も Manhattan 距離が近いプレイヤー駒を返す。
    /// 同距離の場合は id の小さい方（pieces 順の先頭）を選ぶ。
    /// プレイヤーが居なければ None。EnemyAI が追跡 target を決めるのに使う。
    pub def nearestPlayer(enemyPos: {x = Int32, y = Int32},
                           board: Board): Option[(Int32, {x = Int32, y = Int32})] =
        let manhattan = entry -> {
            let (_, pos) = entry;
            Int32.abs(pos#x - enemyPos#x) + Int32.abs(pos#y - enemyPos#y)
        };
        playerPositions(board)
            |> List.minimumBy((a, b) -> Order.compare(manhattan(a), manhattan(b)))

    /// `pos` の上下左右に居る最初のプレイヤー駒の (id, position) を返す。
    /// EnemyAI の Attack 判定で「隣接する誰かを 1 体攻撃」するのに使う。
    pub def adjacentPlayer(pos: {x = Int32, y = Int32},
                            board: Board): Option[(Int32, {x = Int32, y = Int32})] =
        playerPositions(board)
            |> List.findMap(p -> {
                let (id, ppos) = p;
                let dx = Int32.abs(ppos#x - pos#x);
                let dy = Int32.abs(ppos#y - pos#y);
                if ((dx == 1 and dy == 0) or (dx == 0 and dy == 1))
                    Some((id, ppos))
                else None
            })

    // ════════════════════════════════════════════════════════
    // (C) 動きルール
    // ════════════════════════════════════════════════════════

    /// 指定セルが歩行可能か（マップ範囲内 かつ 壁ではない）。
    /// 駒の占有は別途 `isOccupied` でチェックする（自分自身が source にいる
    /// ケースを呼び出し側が制御できるよう、ここでは地形のみ見る）。
    pub def isWalkable(board: Board, coord: {x = Int32, y = Int32}): Bool =
        board#map#isFloor(coord)

    /// origin から dir 方向に 1 マス進む候補座標
    pub def stepTarget(origin: {x = Int32, y = Int32}, dir: {x = Int32, y = Int32}): {x = Int32, y = Int32} =
        Vec2i.add(origin, dir)

    /// `source` から dir 方向に 1 マス進めるか試みる。
    /// 進めるなら Some(目標座標)、壁・範囲外なら None。
    /// **マルチプレイヤー対応**: source は呼び出し側が「いま動かしたい駒」の位置を渡す。
    pub def tryMove(board: Board, source: {x = Int32, y = Int32},
                     dir: {x = Int32, y = Int32}): Option[{x = Int32, y = Int32}] =
        tryMoveWithRange(board, source, dir, _ -> true)

    /// `tryMove` に「移動可能セル」述語による追加制約を加える版。
    /// 範囲表示（move_tile）の外には踏み込めないようにする用途で `MoveRangeScene.isInRange`
    /// 等を渡す。`allowed` が常に true なら `tryMove` と同じ挙動。
    /// **味方駒は通過可能**（`isEnemyAt` で敵だけブロックする）。
    pub def tryMoveWithRange(board: Board, source: {x = Int32, y = Int32},
                              dir: {x = Int32, y = Int32},
                              allowed: {x = Int32, y = Int32} -> Bool): Option[{x = Int32, y = Int32}] =
        let target = stepTarget(source, dir);
        // 床 + 範囲内 + 敵駒に占有されていない（味方駒は通過可）
        if (isWalkable(board, target)
            and allowed(target)
            and not isEnemyAt(target, board)) Some(target) else None

    // ════════════════════════════════════════════════════════
    // (D) 経路探索 — 4 方向 BFS
    // ════════════════════════════════════════════════════════

    /// 4 方向 BFS で `origin` から最大 `maxSteps` ステップ以内に到達できる床セルの一覧を返す。
    /// `origin` 自身も結果に含む（距離 0）。
    /// `isFloor` は「そのセルが歩行可能か（床か）」を判定する述語。
    /// `MapSnapshot` を直接受け取らないことで、テストや別経路でも合成しやすくする。
    pub def reachableCells(isFloor: {x = Int32, y = Int32} -> Bool,
                            origin: {x = Int32, y = Int32},
                            maxSteps: Int32): List[{x = Int32, y = Int32}] =
        let initVisited = origin :: Nil;
        let initQueue   = (origin, 0i32) :: Nil;
        bfsReachable(isFloor, maxSteps, initVisited, initQueue)

    /// `reachableCells` の BFS。`visited` は到達済みセル（順序保持）。
    /// 深さ `maxSteps` に達した節点はそれ以上展開しない。
    def bfsReachable(isFloor: {x = Int32, y = Int32} -> Bool,
                      maxSteps: Int32,
                      visited: List[{x = Int32, y = Int32}],
                      queue: List[({x = Int32, y = Int32}, Int32)]): List[{x = Int32, y = Int32}] =
        match queue {
            case Nil => visited
            case (cur, depth) :: rest =>
                if (depth >= maxSteps) bfsReachable(isFloor, maxSteps, visited, rest)
                else
                    let dirs = Vec2i.up() :: Vec2i.down()
                                :: Vec2i.left() :: Vec2i.right() :: Nil;
                    let candidates = List.map(d -> Vec2i.add(cur, d), dirs);
                    let fresh = List.filter(c ->
                        isFloor(c) and not isInList(c, visited),
                        candidates);
                    let newVisited = List.append(visited, fresh);
                    let newQueue   = List.append(rest,
                        List.map(c -> (c, depth + 1), fresh));
                    bfsReachable(isFloor, maxSteps, newVisited, newQueue)
        }

    /// `source` から `goal` への最短経路を返す。経路無しなら None。
    /// 戻り値は **source を含まない** 順序付きリスト（先頭 = 1 歩目、末尾 = goal）。
    /// 障害物 = 壁 + 他駒（自分・goal のセルは通行可）。
    /// 隣接判定は呼び出し側が済ませている前提（source == goal は使用想定外）。
    /// EnemyAI の chase / AutoMove の旗追跡が共通で使う。
    pub def bfsPath(board: Board, source: {x = Int32, y = Int32},
                     goal: {x = Int32, y = Int32}): Option[List[{x = Int32, y = Int32}]] =
        let isOpen = c -> bfsPathIsOpen(board, c, source, goal);
        let initVisited = source :: Nil;
        // queue: (current, pathReversedFromSource) — source から current までの経路を
        //   末尾 cons で積んだもの（reverse すれば 1 歩目 → goal）。
        let initQueue: List[({x = Int32, y = Int32}, List[{x = Int32, y = Int32}])] = (source, Nil) :: Nil;
        bfsPathLoop(isOpen, goal, initVisited, initQueue)

    def bfsPathLoop(isOpen: {x = Int32, y = Int32} -> Bool,
                     goal: {x = Int32, y = Int32},
                     visited: List[{x = Int32, y = Int32}],
                     queue: List[({x = Int32, y = Int32}, List[{x = Int32, y = Int32}])]):
                    Option[List[{x = Int32, y = Int32}]] =
        match queue {
            case Nil => None
            case (cur, pathRev) :: rest =>
                if (samePosition(cur, goal)) Some(List.reverse(pathRev))
                else
                    let dirs = Vec2i.up() :: Vec2i.down()
                                :: Vec2i.left() :: Vec2i.right() :: Nil;
                    let neighbors = List.map(d -> Vec2i.add(cur, d), dirs);
                    let fresh = List.filter(c ->
                        isOpen(c) and not isInList(c, visited),
                        neighbors);
                    let withPath = List.map(c -> (c, c :: pathRev), fresh);
                    let newVisited = List.append(visited, fresh);
                    let newQueue   = List.append(rest, withPath);
                    bfsPathLoop(isOpen, goal, newVisited, newQueue)
        }

    /// BFS で「踏める」と判定するセルの述語。
    /// - 床でなければ NG
    /// - source（自分） / goal（プレイヤー）は通行可
    /// - 他駒（他の敵 or 別の駒）が居れば NG
    def bfsPathIsOpen(board: Board, c: {x = Int32, y = Int32},
                       source: {x = Int32, y = Int32}, goal: {x = Int32, y = Int32}): Bool =
        if (not isWalkable(board, c)) false
        else if (samePosition(c, source) or samePosition(c, goal)) true
        else not isOccupied(c, board)

    // ════════════════════════════════════════════════════════
    // 内部ヘルパー
    // ════════════════════════════════════════════════════════

    def samePosition(a: {x = Int32, y = Int32}, b: {x = Int32, y = Int32}): Bool =
        a#x == b#x and a#y == b#y

    def isInList(c: {x = Int32, y = Int32}, list: List[{x = Int32, y = Int32}]): Bool =
        List.exists(v -> samePosition(v, c), list)
}
