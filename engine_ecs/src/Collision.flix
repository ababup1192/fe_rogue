// Collision — 再利用可能な ECS 衝突モジュール（Bevy の物理プラグイン相当の最小版）
//
// 各ゲームが衝突判定を手書きする代わりに、Collider component を付けて detectCollisions の
// 返すペアを読む。narrowphase は engine の純粋関数 CollisionShape2D.checkOverlap を再利用し、
// layer/mask は engine と同じビットマスク（Int32.bitwiseAnd）。engine に無い broadphase
// （一様空間グリッド）だけを新規実装して O(n²) を避ける。
// 共有パッケージ flix_engine_ecs の一部。どの ECS ゲームも import して Collider を付け、
// detectCollisions のペアを読むだけ（Bevy の物理プラグインと同じ使い心地）。

mod Collision {

    /// 衝突の形（engine の CollisionShape2D を再利用）＋ layer/mask（engine と同じ意味論）。
    pub type alias Collider = {
        shape = CollisionShape2D,
        layer = Int32,   // 自分が属するレイヤー
        mask  = Int32    // 観測するレイヤー（mask & 相手 layer != 0 で判定対象）
    }

    // ── 公開 API ──

    /// position と collider を両方持つ entity から、衝突しているペアを列挙する。
    /// 同じペアは (idA < idB) で1回だけ。layer/mask で除外されたペアは含めない。
    /// 注: layer/mask 判定は無方向（どちらかが相手を観測していれば検出）。engine の
    /// monitoring/monitorable に当たる概念は持たない。
    pub def detectCollisions(positions: Map[EntityId, Vec2.Vec2],
                             colliders: Map[EntityId, Collider]): List[(EntityId, EntityId)] =
        let bodies = Query.with2(positions, colliders);   // Map[EntityId, (Vec2, Collider)]
        let cs = cellSize(colliders);
        let grid = buildGrid(cs, bodies);
        Map.foldLeftWithKey((acc, id, body) ->
            let (pos, col) = body;
            let pairs = neighborhoodIds(cellOf(cs, pos), grid)
                |> List.filter(other -> id < other)            // dedup＋自己ペア除外
                |> List.filterMap(other -> tryPair(id, pos, col, other, bodies));
            List.append(pairs, acc), Nil, bodies)

    // ── broadphase（一様空間グリッド）──
    // セル幅は「衝突しうる最大の中心間距離 = 2×最大 extent」以上にすると、重なるペアは
    // 必ず同一/隣接セルに入り、3×3 近傍探索で取りこぼさない。固定値ではなく collider から
    // 導出するので、どんな形状サイズのゲームでも正しい（再利用 lib の不変条件をコードで満たす）。

    def cellSize(colliders: Map[EntityId, Collider]): Float64 =
        let maxExtent = Map.foldLeftWithKey((acc, _id, c) -> Float64.max(acc, extentOf(c)), 0.0, colliders);
        Float64.max(1.0, 2.0 * maxExtent)

    /// 形状の境界半径（中心から最遠点までの距離）。
    def extentOf(c: Collider): Float64 =
        match c#shape {
            case CollisionShape2D.CircleShape2D(s)  => s#radius
            case CollisionShape2D.RectShape2D(s)    => Vec2.length({x = s#width / 2.0, y = s#height / 2.0})
            case CollisionShape2D.CapsuleShape2D(s) => s#height / 2.0
        }

    def buildGrid(cs: Float64, bodies: Map[EntityId, (Vec2.Vec2, Collider)]):
            Map[(Int32, Int32), List[EntityId]] =
        Map.foldLeftWithKey((g, id, body) -> let (pos, _) = body; addToGrid(cs, id, pos, g),
                             Map.empty(), bodies)

    def toCell(cs: Float64, v: Float64): Int32 =
        Float64.floor(v / cs) |> Float64.tryToInt32 |> Option.getWithDefault(0)

    def cellOf(cs: Float64, p: Vec2.Vec2): (Int32, Int32) = (toCell(cs, p#x), toCell(cs, p#y))

    def addToGrid(cs: Float64, id: EntityId, pos: Vec2.Vec2,
                  grid: Map[(Int32, Int32), List[EntityId]]): Map[(Int32, Int32), List[EntityId]] =
        let c = cellOf(cs, pos);
        let cur = Map.get(c, grid) |> Option.getWithDefault(Nil);
        Map.insert(c, id :: cur, grid)

    /// セル自身＋8 近傍に居る entity id を集める。
    def neighborhoodIds(c: (Int32, Int32), grid: Map[(Int32, Int32), List[EntityId]]): List[EntityId] =
        let (cx, cy) = c;
        let offs = -1 :: 0 :: 1 :: Nil;
        List.flatMap(dx ->
            List.flatMap(dy ->
                Map.get((cx + dx, cy + dy), grid) |> Option.getWithDefault(Nil), offs),
            offs)

    // ── narrowphase（engine の純粋関数を再利用）──

    def tryPair(idA: EntityId, posA: Vec2.Vec2, colA: Collider, idB: EntityId,
                bodies: Map[EntityId, (Vec2.Vec2, Collider)]): Option[(EntityId, EntityId)] =
        match Map.get(idB, bodies) {
            case Some((posB, colB)) =>
                if (masksMatch(colA, colB) and
                    CollisionShape2D.checkOverlap(posA, colA#shape, posB, colB#shape))
                    Some((idA, idB))
                else None
            case None => None
        }

    /// どちらか一方が相手を観測していれば判定対象（engine の (mask & layer) と同じ）。
    def masksMatch(a: Collider, b: Collider): Bool =
        Int32.bitwiseAnd(a#mask, b#layer) != 0i32 or Int32.bitwiseAnd(b#mask, a#layer) != 0i32
}
