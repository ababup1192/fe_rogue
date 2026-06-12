/// Board — 盤面状態（マップ + 駒の位置）と、その上での動き・経路探索を一元的に扱う
///
/// チェスの盤面のメタファー:
///   - map: タイル（壁・床）の地形情報
///   - pieces: 盤上にいる駒（プレイヤー [id 付き] / 敵 [id 付き] / 将来のアイテム）の位置リスト
///
/// 章立て:
///   (A) 型 + effect: Piece / Board / BoardQuery
///   (B) 駒クエリ: playerPositions / enemyPositions / allPlayerCells /
///                 isOccupied / isEnemyAt / nearestPlayer / adjacentPlayer /
///                 containsCell
///   (C) 動きルール: isWalkable / stepTarget / tryMove / tryMoveWithRange
///   (D) 経路探索: reachableCells / bfsPath / bfsPathSkipAllies
///   (D') 距離フィールド: distanceField / fieldDist / stepDownhill
///   (E) 駒視点ヘルパー: reachableForUnit / stoppableForUnit
///   (F) 射程計算: manhattanOffsets / computeThreatCells
///   (G) 直線射出: rayCast / knockbackPath / dedupCells / padCells
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

/// 杖の直線射出の結果。`rayCast` が返す。
///   - `HitPlayer(id, cell)`: 味方に当たって停止。`cell` は当たった味方のセル
///   - `HitEnemy(id, cell)` : 敵に当たって停止。`cell` は当たった敵のセル
///   - `HitWall(cell)`      : 壁に当たって停止。`cell` は壁の **直前** （= 進めた最後のセル）
///   - `OutOfRange(cell)`   : 何にも当たらず射程切れ。`cell` は到達した最遠セル
///
/// `Eq` / `ToString` は付けない。`cell` の `{x, y}` record に Eq/ToString が無く
/// derive できないため。比較が必要なテストはタプル `(tag, id, x, y)` に変換して扱う。
pub enum RayHit {
    case HitPlayer(Int32, {x = Int32, y = Int32})
    case HitEnemy(Int32, {x = Int32, y = Int32})
    case HitWall({x = Int32, y = Int32})
    case OutOfRange({x = Int32, y = Int32})
}

mod Board {

    // ════════════════════════════════════════════════════════
    // (B) 駒クエリ
    // ════════════════════════════════════════════════════════

    /// 盤面上のプレイヤー駒一覧（id, gridPos）。pieces 順を保つ。
    /// id の連続性（0/1/2）は呼び出し側（PlayerScene）が保証する前提。
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

    /// AutoMove / MoveRange など「味方マスのリスト」だけ要る用途で使う。
    pub def allPlayerCells(board: Board): List[{x = Int32, y = Int32}] =
        playerPositions(board)
            |> List.map(pair -> { let (_, pos) = pair; pos })

    /// `cell` が `cells` に含まれるか（Vec2i フィールド比較版の `List.memberOf`）。
    /// 「味方マスに含まれるか」「reachable に含まれるか」等の判定で多用する。
    pub def containsCell(cell: {x = Int32, y = Int32},
                          cells: List[{x = Int32, y = Int32}]): Bool =
        isInList(cell, cells)

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

    /// `pos` から見て武器射程 `lo..hi`（マンハッタン距離, inclusive）に入る
    /// 最初のプレイヤー駒の (id, position) を返す。該当が無ければ None。
    /// EnemyAI の Attack 判定で「武器射程内の誰かを 1 体狙う」のに使う。
    /// `adjacentPlayer`（距離 1 固定）の一般化版で、`lo..hi` は呼び出し側の武器射程に従う。
    pub def playerInRange(pos: {x = Int32, y = Int32}, lo: Int32, hi: Int32,
                           board: Board): Option[(Int32, {x = Int32, y = Int32})] =
        playerPositions(board)
            |> List.findMap(p -> {
                let (id, ppos) = p;
                let d = Int32.abs(ppos#x - pos#x) + Int32.abs(ppos#y - pos#y);
                if (d >= lo and d <= hi) Some((id, ppos))
                else None
            })

    // ════════════════════════════════════════════════════════
    // (C) 動きルール
    // ════════════════════════════════════════════════════════

    /// 指定セルが歩行可能か（マップ範囲内 かつ 壁ではない）。
    /// 駒の占有は別途 `isOccupied` でチェックする（自分自身が source にいる
    /// ケースを呼び出し側が制御できるよう、ここでは地形のみ見る）。
    pub def isWalkable(board: Board, coord: {x = Int32, y = Int32}): Bool =
        MapSnapshot.isFloor(coord, board#map)

    /// 座標計算のみ行う。地形・駒の占有はチェックしない。
    /// 呼び出し側が `isWalkable` / `isOccupied` を組み合わせて制御できるよう、
    /// 責務を分離している（source にいる駒を透過するかどうかは文脈依存のため）。
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
    /// 再訪問による無限ループを防ぐため、展開済みセルを `visited` に保持して持ち回る。
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

    /// `cell`(ロード位置) が生存敵に検知されるか（ローグ移動モードの敵検知）。
    /// 次のいずれかなら true:
    ///   (a) **同じ部屋**: `cell` と生存敵が同じモジュール(部屋)に居る
    ///   (b) **索敵範囲内**: `cell` がいずれかの生存敵の移動到達範囲(赤マス = `reachableCells`)に入る
    /// 死亡演出中(isDying)の敵は数えない。
    /// `moduleOf`: グリッドセルの部屋IDを返す述語。通路等は None（部屋扱いしない）。
    pub def cellDetectedByEnemy(moduleOf: {x = Int32, y = Int32} -> Option[Int32],
                                 isFloor: {x = Int32, y = Int32} -> Bool,
                                 enemies: List[{gridPos = {x = Int32, y = Int32},
                                                moveTiles = Int32, isDying = Bool}],
                                 cell: {x = Int32, y = Int32}): Bool =
        let alive = enemies |> List.filter(e -> not e#isDying);
        let sameRoom = match moduleOf(cell) {
            case None    => false
            case Some(m) => List.exists(e -> moduleOf(e#gridPos) == Some(m), alive)
        };
        let inRange = List.exists(e ->
            containsCell(cell, reachableCells(isFloor, e#gridPos, e#moveTiles)), alive);
        sameRoom or inRange

    /// `source` から `goal` への最短経路を返す。経路無しなら None。
    /// 戻り値は **source を含まない** 順序付きリスト（先頭 = 1 歩目、末尾 = goal）。
    /// 障害物 = 壁 + 他駒（自分・goal のセルは通行可）。
    /// 隣接判定は呼び出し側が済ませている前提（source == goal は使用想定外）。
    /// EnemyAI の chase / AutoMove のロード合流が共通で使う。
    pub def bfsPath(board: Board, source: {x = Int32, y = Int32},
                     goal: {x = Int32, y = Int32}): Option[List[{x = Int32, y = Int32}]] =
        let isOpen = c -> bfsPathIsOpen(board, c, source, goal);
        let initVisited = source :: Nil;
        // queue: (current, pathReversedFromSource) — source から current までの経路を
        //   先頭 cons で逆順に積む。Flix のリスト先頭追加が O(1) のため逆順蓄積し、
        //   goal 到達時に一度だけ reverse して返す（末尾追加を毎ステップ行うより効率的）。
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

    /// 味方マスは通過可能、敵マスは NG、壁・範囲外も NG な BFS。
    /// `bfsPath` は敵も味方もブロックするのに対し、こちらは味方だけを透過扱いにする違いがある。
    /// `allyCells` に source を含んでいても安全（source は常に通行可として扱う）。
    /// AutoMove のロード合流（味方マスを経由しながらゴールへ向かう）に使う。
    /// テストから経路全体を確認したい場合にも利用できる。
    /// 経路の途中マスは味方占有でも可（通過可能）。停止可否は呼び出し側が
    /// `stoppableForUnit` 等で別途担保する。
    pub def bfsPathSkipAllies(board: Board,
                               allyCells: List[{x = Int32, y = Int32}],
                               source: {x = Int32, y = Int32},
                               goal: {x = Int32, y = Int32}):
            Option[List[{x = Int32, y = Int32}]] =
        let allySet = allyCells;
        let isOpen = c -> bfsPathIsOpenSkipAllies(board, c, source, goal, allySet);
        let initVisited = source :: Nil;
        let initQueue: List[({x = Int32, y = Int32}, List[{x = Int32, y = Int32}])] = (source, Nil) :: Nil;
        bfsPathLoop(isOpen, goal, initVisited, initQueue)

    /// `bfsPathIsOpen` の派生: 敵駒のみブロック、味方駒は透過扱いにする。
    /// `bfsPathLoop` を共通で再利用しつつ open 述語だけをこちらに差し替えることで、
    /// 同一 BFS ロジックを重複させずに味方透過の挙動を実現している。
    def bfsPathIsOpenSkipAllies(board: Board, c: {x = Int32, y = Int32},
                                 source: {x = Int32, y = Int32},
                                 goal: {x = Int32, y = Int32},
                                 allyCells: List[{x = Int32, y = Int32}]): Bool =
        if (not isWalkable(board, c)) false
        else if (samePosition(c, source) or samePosition(c, goal)) true
        else if (isInList(c, allyCells)) true   // 味方は通過 OK
        else not isOccupied(c, board)            // 残り = 敵駒 / その他なら NG

    // ════════════════════════════════════════════════════════
    // (D') ダイクストラ距離フィールド（多始点 BFS。均一コスト = BFS）
    //     ゴール（プレイヤー等）始点でマップを塗り、各セルに「真の経路距離」を持たせる。
    //     敵は値の小さい隣マスへ降下するだけで局所最小に陥らず迷路でも詰まらない。
    // ════════════════════════════════════════════════════════

    /// 到達不能を表す番兵値。距離フィールドの未到達セルに使う。
    /// Int32 最大値 (2^31 - 1 ≈ 2.1e9) の約半分にしており、
    /// この値同士を加算しても Int32 オーバーフローしない余裕を持たせている。
    pub def infDist(): Int32 = 1000000000

    /// `sources` を距離 0 とする多始点 BFS で、各セルの最短ステップ数を Map で返す。
    /// `passable` が通行可否（床か・ユニット透過か等）を決める述語。到達不能セルは Map に
    /// 含めない（= ∞）。均一コストなので BFS = ダイクストラ（優先度キュー不要）。
    /// frontier をレベル毎リストで広げ、距離は Map に積む（list + isInList の O(n²) を回避）。
    pub def distanceField(passable: {x = Int32, y = Int32} -> Bool,
                           sources: List[{x = Int32, y = Int32}],
                           maxSteps: Int32): Map[(Int32, Int32), Int32] =
        let seeds = List.filter(passable, sources);
        let dist0 = List.foldLeft((m, c) -> Map.insert((c#x, c#y), 0, m), Map.empty(), seeds);
        floodField(passable, maxSteps, 0, seeds, dist0)

    /// `frontier`（距離 `depth` のセル群）の 4 近傍を距離 `depth+1` で登録し、次レベルへ進む。
    /// 既登録セルは Map メンバ判定で弾く（同レベル内の重複も threading した Map で防ぐ）。
    def floodField(passable: {x = Int32, y = Int32} -> Bool,
                    maxSteps: Int32, depth: Int32,
                    frontier: List[{x = Int32, y = Int32}],
                    dist: Map[(Int32, Int32), Int32]): Map[(Int32, Int32), Int32] =
        if (List.isEmpty(frontier) or depth >= maxSteps) dist
        else
            let dirs = Vec2i.up() :: Vec2i.down() :: Vec2i.left() :: Vec2i.right() :: Nil;
            let (nextFrontier, nextDist) =
                List.foldLeft((acc, cur) ->
                    List.foldLeft((acc2, d) -> {
                        let (f2, m2) = acc2;
                        let n   = Vec2i.add(cur, d);
                        let key = (n#x, n#y);
                        if (passable(n) and not Map.memberOf(key, m2))
                            (n :: f2, Map.insert(key, depth + 1, m2))
                        else acc2
                    }, acc, dirs),
                    (Nil, dist), frontier);
            floodField(passable, maxSteps, depth + 1, nextFrontier, nextDist)

    /// 距離フィールドのセル値。未到達は番兵 `infDist`（実質 ∞）。順位付け・降下判定に使う。
    pub def fieldDist(field: Map[(Int32, Int32), Int32], cell: {x = Int32, y = Int32}): Int32 =
        Map.get((cell#x, cell#y), field) |> Option.getWithDefault(infDist())

    /// `field` 上で `pos` から「値がより小さい」隣接セルのうち `ok` を満たす最小値セルを返す。
    /// 降下できる隣接が無ければ None。同値は up→down→left→right の決定的順序で先勝ち。
    /// 壁/未到達セルは ∞ なので「`< here`」で自動的に除外される。
    pub def stepDownhill(field: Map[(Int32, Int32), Int32],
                          pos: {x = Int32, y = Int32},
                          ok: {x = Int32, y = Int32} -> Bool): Option[{x = Int32, y = Int32}] =
        let here = fieldDist(field, pos);
        let dirs = Vec2i.up() :: Vec2i.down() :: Vec2i.left() :: Vec2i.right() :: Nil;
        dirs
            |> List.map(d -> Vec2i.add(pos, d))
            |> List.filter(c -> ok(c) and fieldDist(field, c) < here)
            |> List.minimumBy((a, b) ->
                Order.compare(fieldDist(field, a), fieldDist(field, b)))

    // ════════════════════════════════════════════════════════
    // (E) 駒視点ヘルパー — 「壁・敵だけ通行不可、味方マスは通過可。停止は味方マス NG」
    //     という動きモデルを公開する。MoveRangeScene の青マス表示はこのレイヤ
    //     経由で計算する。AutoMove は同じモデルを `bfsPathSkipAllies` 直叩きで使う。
    // ════════════════════════════════════════════════════════

    /// 味方マスを通過可、敵 / 壁は不可で `origin` から `maxSteps` 以内に到達できるセル一覧。
    /// `origin` 自身も含む（距離 0）。MoveRangeScene の到達範囲のベース。
    pub def reachableForUnit(board: Board, origin: {x = Int32, y = Int32},
                              maxSteps: Int32): List[{x = Int32, y = Int32}] =
        let enemyCells = enemyPositions(board)
            |> List.map(pair -> { let (_, pos) = pair; pos });
        let isPassable = c ->
            isWalkable(board, c) and not isInList(c, enemyCells);
        reachableCells(isPassable, origin, maxSteps)

    /// `reachableForUnit` から「味方マス（自分 + 他味方）」を除いた、
    /// 「移動を完了して停止できる」マスの一覧。MoveRangeScene の青マスに使う。
    pub def stoppableForUnit(board: Board, origin: {x = Int32, y = Int32},
                              maxSteps: Int32): List[{x = Int32, y = Int32}] =
        let playerCells = playerPositions(board)
            |> List.map(pair -> { let (_, pos) = pair; pos });
        reachableForUnit(board, origin, maxSteps)
            |> List.filter(c -> not isInList(c, playerCells))

    // ════════════════════════════════════════════════════════
    // (F) 射程計算 — 武器の `min..max` マンハッタン距離に基づくセル列挙
    //     RangeScenes の Player/MoveAttack/EnemyRange 表示はここを再利用する。
    //     Scene 非依存・engine API 非依存の純粋関数。
    // ════════════════════════════════════════════════════════

    /// `lo..hi` のマンハッタン距離内にあるオフセット (dx, dy) を全列挙する。
    /// `lo > hi` のときは空リスト。`lo == 0` を許可するか否かは呼び出し側が判断する
    /// （AttackRange 系は `Int32.max(1, range#min)` で 0 を除外している）。
    pub def manhattanOffsets(lo: Int32, hi: Int32): List[{x = Int32, y = Int32}] =
        let coords = List.range(-hi, hi + 1);
        List.flatMap(dx ->
            List.foldRight(dy -> acc -> {
                let d = Int32.abs(dx) + Int32.abs(dy);
                if (d >= lo and d <= hi)
                    ({x = dx, y = dy}: {x = Int32, y = Int32}) :: acc
                else acc
            }, Nil, coords),
            coords)

    /// `reachable` の各セルから武器射程 (`min..max` マンハッタン) で届くセル集合を作り、
    /// reachable 自身は除外して返す。同一セルは 1 つにまとめる（先に出たものを残す）。
    /// MoveAttackRange の赤マス計算に使う。`hi < lo` または `reachable` が空なら Nil。
    pub def computeThreatCells(reachable: List[{x = Int32, y = Int32}],
                                lo: Int32, hi: Int32):
                               List[{x = Int32, y = Int32}] =
        if (hi < lo or List.isEmpty(reachable)) Nil
        else
            let offsets = manhattanOffsets(lo, hi);
            let raw = List.flatMap(c ->
                List.map(o ->
                    ({x = c#x + o#x, y = c#y + o#y}: {x = Int32, y = Int32}),
                    offsets),
                reachable);
            let init: {seen = List[{x = Int32, y = Int32}], out = List[{x = Int32, y = Int32}]} =
                {seen = reachable, out = Nil};
            let folded = List.foldLeft(acc -> cell -> {
                if (containsCell(cell, acc#seen)) acc
                else {seen = cell :: acc#seen, out = cell :: acc#out}
            }, init, raw);
            List.reverse(folded#out)

    // ════════════════════════════════════════════════════════
    // (G) 直線射出 — 杖の発射用
    //     origin から dir 方向に 1 マスずつ進めて、最初に当たった
    //     壁 / プレイヤー / 敵 / 射程切れ を `RayHit` で返す。
    //     origin にいる駒（杖の使い手）は origin から踏み出すので
    //     当たり判定から自然に外れる（self を別途渡す必要なし）。
    // ════════════════════════════════════════════════════════

    /// `origin` から `dir` 方向に最大 `range` マスまで進み、最初に当たった対象を `RayHit` で返す。
    /// `range == 0` のときは `OutOfRange(origin)` を即返す。
    /// `dir` は {±1, 0} か {0, ±1} の単位ベクトルを想定（縦横 4 方向）。
    /// 斜め方向は呼び出し側が分解して 2 回 cast する想定だが、cast 自体は dir に依存しない。
    pub def rayCast(origin: {x = Int32, y = Int32},
                     dir: {x = Int32, y = Int32},
                     range: Int32,
                     board: Board): RayHit =
        rayCastLoop(origin, dir, range, board, origin)

    /// `current` から 1 マス進めて、`stepsLeft` を 1 減らしながら再帰する。
    /// `lastValid` は前ステップまでに「実際に進めた」最後のセル。
    /// 壁・射程切れのとき `lastValid` を結果に積む（壁の直前 / 到達最遠）。
    def rayCastLoop(current: {x = Int32, y = Int32},
                     dir: {x = Int32, y = Int32},
                     stepsLeft: Int32,
                     board: Board,
                     lastValid: {x = Int32, y = Int32}): RayHit =
        if (stepsLeft <= 0) RayHit.OutOfRange(lastValid)
        else {
            let next = stepTarget(current, dir);
            if (not isWalkable(board, next)) RayHit.HitWall(lastValid)
            else match findUnitAt(next, board) {
                case Some(Piece.Player(id)) => RayHit.HitPlayer(id, next)
                case Some(Piece.Enemy(id))  => RayHit.HitEnemy(id, next)
                case None                    =>
                    rayCastLoop(next, dir, stepsLeft - 1, board, next)
            }
        }

    /// `coord` を占有している駒を 1 つ返す（無ければ None）。
    /// 同セル 2 駒は想定外なので最初のヒットを返す。
    pub def findUnitAt(coord: {x = Int32, y = Int32}, board: Board): Option[Piece] =
        List.findMap(entry -> {
            let (piece, pos) = entry;
            if (samePosition(pos, coord)) Some(piece) else None
        }, board#pieces)

    /// ふきとばし用: `hitCell` に居る駒が `dir` 方向に押される経路を返す。
    /// 戻り値は順序付きセル列（先頭 = 1 マス目、末尾 = 最終着地）。
    /// 動けないなら Nil。
    /// 押される駒は `hitCell` から動き始めるため、`hitCell` のエントリは
    /// 障害物判定から除外する。
    /// 停止条件: 次のセルが壁 / 範囲外、または他駒（hitCell の駒以外）が居る。
    pub def knockbackPath(hitCell: {x = Int32, y = Int32},
                           dir: {x = Int32, y = Int32},
                           board: Board): List[{x = Int32, y = Int32}] =
        let prunedPieces = List.filter(entry -> {
            let (_, pos) = entry;
            not samePosition(pos, hitCell)
        }, board#pieces);
        let prunedBoard: Board = {pieces = prunedPieces | board};
        knockbackLoop(hitCell, dir, prunedBoard, Nil)

    def knockbackLoop(current: {x = Int32, y = Int32},
                       dir: {x = Int32, y = Int32},
                       board: Board,
                       acc: List[{x = Int32, y = Int32}]):
                      List[{x = Int32, y = Int32}] =
        let next = stepTarget(current, dir);
        if (not isWalkable(board, next)) List.reverse(acc)
        else if (isOccupied(next, board)) List.reverse(acc)
        else knockbackLoop(next, dir, board, next :: acc)

    /// `knockbackPath` を最大 `maxTiles` マスに制限する版。如意棒（2 マス）など距離上限つき用。
    /// `None` または 0 以下なら無制限（突風の書）。壁/駒での停止は `knockbackPath` 同様に効く。
    pub def knockbackPathCapped(hitCell: {x = Int32, y = Int32},
                                 dir: {x = Int32, y = Int32},
                                 board: Board, maxTiles: Option[Int32]):
            List[{x = Int32, y = Int32}] =
        let full = knockbackPath(hitCell, dir, board);
        match maxTiles {
            case Some(n) => if (n <= 0) full else List.take(n, full)
            case None    => full
        }

    /// セル一覧から重複 (x,y 一致) を除く。先に出たものを残す（順序保持・先勝ち）。
    /// spawn 配置・再配置・危険域表示など、座標集合を作る各所で共有する。
    /// 先勝ちにする理由: spawn 等では先に列挙された（優先度が高い）配置を維持し、
    /// 後から追加された重複候補を自動的に無視したいため。
    pub def dedupCells(cells: List[{x = Int32, y = Int32}]): List[{x = Int32, y = Int32}] =
        List.foldLeft((acc, c) ->
            if (isInList(c, acc)) acc else List.append(acc, c :: Nil),
            (Nil: List[{x = Int32, y = Int32}]), cells)

    /// `cells` が `n` 個に満たない場合、不足分を `fallback` で埋めて長さ `n` に揃える。
    /// `len >= n` のときは先頭 `n` 個に切り詰める（`cells` の先頭が優先配置の意味を持つ）。
    /// 狭所で候補が足りない場合の配置保険として使う。
    pub def padCells(cells: List[{x = Int32, y = Int32}],
                      fallback: {x = Int32, y = Int32}, n: Int32):
            List[{x = Int32, y = Int32}] =
        let len = List.length(cells);
        if (len >= n) List.take(n, cells)
        else List.append(cells, List.repeat(n - len, fallback))

    // ════════════════════════════════════════════════════════
    // 内部ヘルパー
    // ════════════════════════════════════════════════════════

    /// `{x, y}` record alias には Flix の `Eq` derive が無いため `==` 比較ができない。
    /// そのため独自のフィールド比較関数を用意している（Flix の落とし穴）。
    def samePosition(a: {x = Int32, y = Int32}, b: {x = Int32, y = Int32}): Bool =
        a#x == b#x and a#y == b#y

    /// `samePosition` を使ったリスト線形探索。`List.memberOf` が使えない理由は `samePosition` と同じ。
    def isInList(c: {x = Int32, y = Int32}, list: List[{x = Int32, y = Int32}]): Bool =
        List.exists(v -> samePosition(v, c), list)
}
