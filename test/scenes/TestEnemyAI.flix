/// EnemyAI.decideAction の振る舞いを純粋関数として検証する。
///
/// 検証する状態遷移:
///   - dormant かつ別モジュール → Skip、alerted は false のまま
///   - dormant かつ同モジュール → alerted=true に更新、その場で chase（Q3-B）
///   - alerted かつ別モジュール → 引き続き chase（一度起きたら永続）
///   - 隣接 → Attack
///   - 経路無し（壁・他駒で詰まり）→ Wait
///   - BFS が壁を回避して 1 歩目を選ぶ
///   - BFS が他敵駒を障害物として回避（Q7-A）
mod TestEnemyAI {

    use EnemyAI.EnemyAction

    // ════════════════════════════════════════════════════════
    // ヘルパー
    // ════════════════════════════════════════════════════════

    def testTileSize(): Float64 = 16.0

    def testGridToWorld(c: Vec2.Vec2i): Vec2.Vec2 =
        let s = testTileSize();
        let v = Vec2.fromI(c);
        {x = v#x * s + s / 2.0, y = v#y * s + s / 2.0}

    /// 全床 w×h で 2 つの仮想モジュール領域に区切った MapSnapshot を作る。
    /// (0..w/2, 0..h)  → moduleIdx = Some(0)（プレイヤーの部屋）
    /// (w/2..w, 0..h)  → moduleIdx = Some(1)（敵の部屋）
    def twoRoomSnapshot(w: Int32, h: Int32): MapSnapshot =
        let inB = c -> c#x >= 0 and c#x < w and c#y >= 0 and c#y < h;
        let half = w / 2;
        {
            tileSize     = testTileSize(),
            usedRect     = {position = Vec2.zeroI(), size = ({x = w, y = h}: Vec2.Vec2i)},
            isWall       = c -> not inB(c),
            isFloor      = c -> inB(c),
            mapToLocal   = c -> testGridToWorld(c),
            gridToWorld  = c -> testGridToWorld(c),
            moduleOfCell = c ->
                if (not inB(c)) None
                else if (c#x < half) Some(0)
                else Some(1)
        }

    /// 1 部屋だけの snapshot（全マス moduleIdx = 0）。
    def singleRoomSnapshot(w: Int32, h: Int32): MapSnapshot =
        let inB = c -> c#x >= 0 and c#x < w and c#y >= 0 and c#y < h;
        {
            tileSize     = testTileSize(),
            usedRect     = {position = Vec2.zeroI(), size = ({x = w, y = h}: Vec2.Vec2i)},
            isWall       = c -> not inB(c),
            isFloor      = c -> inB(c),
            mapToLocal   = c -> testGridToWorld(c),
            gridToWorld  = c -> testGridToWorld(c),
            moduleOfCell = c -> if (inB(c)) Some(0) else None
        }

    /// 壁マス wall を持つ単一部屋 snapshot（moduleIdx = 0）。
    def singleRoomWithWall(w: Int32, h: Int32, wall: Vec2.Vec2i): MapSnapshot =
        let inB = c -> c#x >= 0 and c#x < w and c#y >= 0 and c#y < h;
        let isW = c -> c#x == wall#x and c#y == wall#y;
        {
            tileSize     = testTileSize(),
            usedRect     = {position = Vec2.zeroI(), size = ({x = w, y = h}: Vec2.Vec2i)},
            isWall       = c -> not inB(c) or isW(c),
            isFloor      = c -> inB(c) and not isW(c),
            mapToLocal   = c -> testGridToWorld(c),
            gridToWorld  = c -> testGridToWorld(c),
            moduleOfCell = c -> if (inB(c) and not isW(c)) Some(0) else None
        }

    /// プレイヤー + 敵 1 体の Board を組む。
    def boardOf(map: MapSnapshot, player: Vec2.Vec2i,
                 enemyId: Int32, enemyPos: Vec2.Vec2i): Board =
        {
            map    = map,
            pieces = (Piece.Player, player)
                  :: (Piece.Enemy(enemyId), enemyPos) :: Nil
        }

    /// 敵 Data を作る。`moveTiles` は引数で指定（テストで挙動を変えるため）。
    def enemyAt(id: Int32, pos: Vec2.Vec2i, alerted: Bool,
                 home: Int32, moveTiles: Int32): EnemyScene.Data =
        { id = id, gridPos = pos, alerted = alerted,
          homeModuleIdx = home, moveTiles = moveTiles }

    /// EnemyAction を tag だけのタプルに圧縮（id 付き）。Eq が無いので比較しやすくする。
    def tagOf(a: EnemyAction): String =
        match a {
            case EnemyAction.Move(_, _) => "Move"
            case EnemyAction.Attack(_)  => "Attack"
            case EnemyAction.Wait(_)    => "Wait"
            case EnemyAction.Skip(_)    => "Skip"
        }

    def moveTarget(a: EnemyAction): Option[Vec2.Vec2i] =
        match a {
            case EnemyAction.Move(_, t) => Some(t)
            case _                      => None
        }

    /// Option[Vec2.Vec2i] が Some か（isSome の代わり）。
    def isSome(o: Option[Vec2.Vec2i]): Bool =
        match o {
            case Some(_) => true
            case None    => false
        }

    // ════════════════════════════════════════════════════════
    // dormant ↔ alerted の遷移
    // ════════════════════════════════════════════════════════

    /// dormant + 別モジュール → Skip、alerted は false のまま。
    @Test
    def testDecideDormantDifferentModuleSkips(): Unit \ Assert =
        let map     = twoRoomSnapshot(10, 5);
        let player  = ({x = 1, y = 2}: Vec2.Vec2i);   // module 0
        let enemyP  = ({x = 7, y = 2}: Vec2.Vec2i);   // module 1
        let board   = boardOf(map, player, 0, enemyP);
        let enemy   = enemyAt(0, enemyP, false, 1, 3);
        let (a, d)  = EnemyAI.decideAction(board, enemy);
        Assert.assertEq(expected = ("Skip", false), (tagOf(a), d#alerted))

    /// dormant + 同モジュール → alerted=true、Move（Q3-B: 検出フレームに動く）。
    @Test
    def testDecideDormantSameModuleAlertsAndMoves(): Unit \ Assert =
        let map     = singleRoomSnapshot(10, 10);
        let player  = ({x = 1, y = 1}: Vec2.Vec2i);
        let enemyP  = ({x = 5, y = 5}: Vec2.Vec2i);
        let board   = boardOf(map, player, 0, enemyP);
        let enemy   = enemyAt(0, enemyP, false, 0, 3);
        let (a, d)  = EnemyAI.decideAction(board, enemy);
        Assert.assertEq(expected = ("Move", true), (tagOf(a), d#alerted))

    /// 一度 alerted なら別モジュールでも chase 継続。
    @Test
    def testDecideAlertedDifferentModuleStillChases(): Unit \ Assert =
        let map     = twoRoomSnapshot(10, 5);
        let player  = ({x = 1, y = 2}: Vec2.Vec2i);
        let enemyP  = ({x = 7, y = 2}: Vec2.Vec2i);
        let board   = boardOf(map, player, 0, enemyP);
        let enemy   = enemyAt(0, enemyP, true, 1, 3);    // 既に alerted
        let (a, d)  = EnemyAI.decideAction(board, enemy);
        Assert.assertEq(expected = ("Move", true), (tagOf(a), d#alerted))

    // ════════════════════════════════════════════════════════
    // 隣接 → Attack
    // ════════════════════════════════════════════════════════

    @Test
    def testDecideAdjacentAttacks(): Unit \ Assert =
        let map     = singleRoomSnapshot(10, 10);
        let player  = ({x = 5, y = 5}: Vec2.Vec2i);
        let enemyP  = ({x = 6, y = 5}: Vec2.Vec2i);
        let board   = boardOf(map, player, 0, enemyP);
        let enemy   = enemyAt(0, enemyP, true, 0, 3);
        let (a, _)  = EnemyAI.decideAction(board, enemy);
        Assert.assertEq(expected = "Attack", tagOf(a))

    @Test
    def testIsAdjacentManhattanOne(): Unit \ Assert =
        let a = ({x = 5, y = 5}: Vec2.Vec2i);
        let b = ({x = 5, y = 6}: Vec2.Vec2i);   // 真下
        let c = ({x = 6, y = 6}: Vec2.Vec2i);   // 斜め
        let d = ({x = 5, y = 5}: Vec2.Vec2i);   // 同位置
        Assert.assertEq(
            expected = (true, false, false),
            (EnemyAI.isAdjacent(a, b),
             EnemyAI.isAdjacent(a, c),
             EnemyAI.isAdjacent(a, d)))

    // ════════════════════════════════════════════════════════
    // BFS の経路選択
    // ════════════════════════════════════════════════════════

    /// 何も無い部屋で敵 (5,5) → プレイヤー (1,5)、moveTiles=1 なら 1 歩目は (4,5)。
    @Test
    def testBfsStraightLineOneStep(): Unit \ Assert =
        let map     = singleRoomSnapshot(10, 10);
        let player  = ({x = 1, y = 5}: Vec2.Vec2i);
        let enemyP  = ({x = 5, y = 5}: Vec2.Vec2i);
        let board   = boardOf(map, player, 0, enemyP);
        let enemy   = enemyAt(0, enemyP, true, 0, 1);
        let (a, _)  = EnemyAI.decideAction(board, enemy);
        let target  = moveTarget(a);
        Assert.assertEq(
            expected = ("Move", true, 4, 5),
            (tagOf(a),
             isSome(target),
             Option.map(t -> t#x, target) |> Option.getWithDefault(-1),
             Option.map(t -> t#y, target) |> Option.getWithDefault(-1)))

    /// `decideAction` は常に「最短経路の 1 歩目」だけを返す（複数マス分は呼び出し側
    /// の EnemyTurn.Queue が step を積んで処理する）。距離 2 のケースで 1 歩目 (2,5) を
    /// 返し、プレイヤーセル (1,5) を踏み越えないことを確認。
    @Test
    def testBfsStopsBeforePlayer(): Unit \ Assert =
        let map     = singleRoomSnapshot(10, 10);
        let player  = ({x = 1, y = 5}: Vec2.Vec2i);
        let enemyP  = ({x = 3, y = 5}: Vec2.Vec2i);
        let board   = boardOf(map, player, 0, enemyP);
        let enemy   = enemyAt(0, enemyP, true, 0, 3);
        let (a, _)  = EnemyAI.decideAction(board, enemy);
        let target  = moveTarget(a);
        Assert.assertEq(
            expected = ("Move", true, 2, 5),
            (tagOf(a),
             isSome(target),
             Option.map(t -> t#x, target) |> Option.getWithDefault(-1),
             Option.map(t -> t#y, target) |> Option.getWithDefault(-1)))

    /// 壁を迂回するケース。
    /// 配置:
    ///   . . . . .
    ///   P # . . E
    ///   . . . . .
    /// 敵 (4,1) → プレイヤー (0,1)。直線は (1,1) が壁で塞がれているので、
    /// 上下どちらかから迂回する。1 歩目は (3,1) または (4,0) または (4,2)。
    /// ここでは「最短経路の 1 歩目」が取れること（None でない）と Move であることを検証。
    @Test
    def testBfsWallDetour(): Unit \ Assert =
        let map     = singleRoomWithWall(5, 3, ({x = 1, y = 1}: Vec2.Vec2i));
        let player  = ({x = 0, y = 1}: Vec2.Vec2i);
        let enemyP  = ({x = 4, y = 1}: Vec2.Vec2i);
        let board   = boardOf(map, player, 0, enemyP);
        let enemy   = enemyAt(0, enemyP, true, 0, 3);
        let (a, _)  = EnemyAI.decideAction(board, enemy);
        Assert.assertEq(expected = ("Move", true),
                         (tagOf(a), isSome(moveTarget(a))))

    /// 経路無し → Wait。1×1 の独房に敵を閉じ込めて、周囲全部壁にする。
    /// 4×3 で wall 列 x=1 全部 → (0,*) は (2,*) に到達不能。
    @Test
    def testBfsNoPathWaits(): Unit \ Assert =
        // 全床 5×3 だが、x=2 列を全部壁にして敵側 (3+) と Player 側 (0,1) を分離する。
        let inB = c -> c#x >= 0 and c#x < 5 and c#y >= 0 and c#y < 3;
        let isW = c -> c#x == 2;
        let map: MapSnapshot = {
            tileSize     = testTileSize(),
            usedRect     = {position = Vec2.zeroI(), size = ({x = 5, y = 3}: Vec2.Vec2i)},
            isWall       = c -> not inB(c) or isW(c),
            isFloor      = c -> inB(c) and not isW(c),
            mapToLocal   = c -> testGridToWorld(c),
            gridToWorld  = c -> testGridToWorld(c),
            moduleOfCell = c -> if (inB(c) and not isW(c)) Some(0) else None
        };
        let player  = ({x = 0, y = 1}: Vec2.Vec2i);
        let enemyP  = ({x = 4, y = 1}: Vec2.Vec2i);
        let board   = boardOf(map, player, 0, enemyP);
        let enemy   = enemyAt(0, enemyP, true, 0, 3);
        let (a, _)  = EnemyAI.decideAction(board, enemy);
        Assert.assertEq(expected = "Wait", tagOf(a))

    /// 他敵駒は障害物。Q7-A を確認する。
    /// 配置（5×3 全床、敵 0 が (4,1)、プレイヤー (0,1)、別の敵 (3,1) で直線が塞がれる）:
    ///   . . . . .
    ///   P . . X E0
    ///   . . . . .
    /// moveTiles=3 で迂回する。経路は (4,0) や (4,2) を通って 3 歩進む。target はそれぞれ
    /// (2,0) もしくは (2,2)。BFS の方向タイブレークに依存するので「(3,1) を通っていない」
    /// 「manhattan 距離 3 以内」「(3,1) でない」の 3 条件で受け入れる。
    @Test
    def testBfsAvoidsOtherEnemy(): Unit \ Assert =
        let map = singleRoomSnapshot(5, 3);
        let board: Board = {
            map    = map,
            pieces = (Piece.Player, ({x = 0, y = 1}: Vec2.Vec2i))
                  :: (Piece.Enemy(0), ({x = 4, y = 1}: Vec2.Vec2i))
                  :: (Piece.Enemy(1), ({x = 3, y = 1}: Vec2.Vec2i)) :: Nil
        };
        let enemy   = enemyAt(0, ({x = 4, y = 1}: Vec2.Vec2i), true, 0, 3);
        let (a, _)  = EnemyAI.decideAction(board, enemy);
        let target  = moveTarget(a);
        let okTarget = match target {
            case Some(t) =>
                let manhattan = Int32.abs(t#x - 4) + Int32.abs(t#y - 1);
                let notOtherEnemy = not (t#x == 3 and t#y == 1);
                manhattan >= 1 and manhattan <= 3 and notOtherEnemy
            case None    => false
        };
        Assert.assertEq(expected = ("Move", true), (tagOf(a), okTarget))
}
