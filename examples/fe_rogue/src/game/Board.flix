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
///   (E) 駒視点ヘルパー: reachableForUnit / stoppableForUnit
///   (F) 射程計算: manhattanOffsets / computeThreatCells
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

    /// 全プレイヤー駒の位置だけを並べたリスト（id は捨てる）。
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

    /// `cell`(ロード位置) が生存敵に検知されるか（ローグ移動モードの敵検知）。
    /// 次のいずれかなら true:
    ///   (a) **同じ部屋**: `cell` と生存敵が同じモジュール(部屋)に居る
    ///       (`moduleOf` は `MapSnapshot#moduleOfCell` 相当。通路等は None で部屋扱いしない)
    ///   (b) **索敵範囲内**: `cell` がいずれかの生存敵の移動到達範囲(赤マス = `reachableCells`)に入る
    /// 死亡演出中(isDying)の敵は数えない。(a) は `EnemyAI.sameModuleAsAnyPlayer` と同じ部屋モデル、
    /// (b) は EnemyRangeScene と同じ reachableCells 計算。
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

    /// 味方マスは通過可能、敵マスは NG、壁・範囲外も NG な BFS。
    /// `allyCells` には source 以外の全味方位置を渡す（source が含まれていてもよい）。
    /// AutoMove のロード合流 / テストから経路全体を確認したい場合に使う。
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

    /// `bfsPathIsOpen` の派生: 味方マスは「通過可能」として true を返す。
    /// 敵駒は引き続き NG（`isOccupied` で他駒検出後、味方リストに含まれるかでフィルタ）。
    def bfsPathIsOpenSkipAllies(board: Board, c: {x = Int32, y = Int32},
                                 source: {x = Int32, y = Int32},
                                 goal: {x = Int32, y = Int32},
                                 allyCells: List[{x = Int32, y = Int32}]): Bool =
        if (not isWalkable(board, c)) false
        else if (samePosition(c, source) or samePosition(c, goal)) true
        else if (isInList(c, allyCells)) true   // 味方は通過 OK
        else not isOccupied(c, board)            // 残り = 敵駒 / その他なら NG

    // ════════════════════════════════════════════════════════
    // (E) 駒視点ヘルパー — 「壁・敵だけ通行不可、味方マスは通過可。停止は味方マス NG」
    //     という FE 流の動きモデルを公開する。MoveRangeScene の青マス表示はこのレイヤ
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

    // ════════════════════════════════════════════════════════
    // 内部ヘルパー
    // ════════════════════════════════════════════════════════

    def samePosition(a: {x = Int32, y = Int32}, b: {x = Int32, y = Int32}): Bool =
        a#x == b#x and a#y == b#y

    def isInList(c: {x = Int32, y = Int32}, list: List[{x = Int32, y = Int32}]): Bool =
        List.exists(v -> samePosition(v, c), list)
}
