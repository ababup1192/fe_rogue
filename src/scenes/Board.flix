/// Board — 盤面状態（マップ + 駒の位置）のスナップショット
///
/// チェスの盤面のメタファー:
///   - map: タイル（壁・床）の地形情報
///   - pieces: 盤上にいる駒（プレイヤー [id 付き] ・敵 [id 付き] ・将来のアイテム）の位置リスト
///
/// BoardLogic / EnemyAI はこの Board を 1 つ受け取れば「次の手」を計算できる。
/// 駒の位置を毎回外から教えてもらう必要がなくなり、責務が「盤面 → 手」に閉じる。
///
/// 取得は BoardQuery effect 経由。Game.start の handler が現フレームの
/// Scene と TileMapLayer から構築してクロージャに包み、フレーム内で固定して返す。
pub enum Piece with Eq {
    case Player(Int32)   // id 付き（パーティ 3 人を区別する）
    case Enemy(Int32)
    // 将来: case Item(...)
}

pub type alias Board = {
    map    = MapSnapshot,
    pieces = List[(Piece, Vec2.Vec2i)]
}

pub eff BoardQuery {
    def board(): Board
}

mod Board {

    /// 盤面上のプレイヤー駒一覧（id, gridPos）。pieces 順を保つ。
    /// パーティ 3 人がそれぞれ id=0/1/2 で並んでいる想定。
    pub def playerPositions(board: Board): List[(Int32, Vec2.Vec2i)] =
        List.filterMap(entry -> match entry {
            case (Piece.Player(id), pos) => Some((id, pos))
            case _                        => None
        }, board#pieces)

    /// 盤面上の敵駒一覧（id, gridPos）。pieces 順を保つ。
    pub def enemyPositions(board: Board): List[(Int32, Vec2.Vec2i)] =
        List.filterMap(entry -> match entry {
            case (Piece.Enemy(id), pos) => Some((id, pos))
            case _                      => None
        }, board#pieces)

    /// 任意の駒（Player / Enemy）が `coord` を占有しているか。
    /// Vec2i は record alias なのでフィールド比較する。
    pub def isOccupied(coord: Vec2.Vec2i, board: Board): Bool =
        List.exists(entry -> {
            let (_, pos) = entry;
            pos#x == coord#x and pos#y == coord#y
        }, board#pieces)

    /// 敵駒だけが `coord` を占有しているか（味方駒や空マスは false）。
    /// プレイヤーの移動判定で「味方をすり抜ける」を実現するために使う。
    pub def isEnemyAt(coord: Vec2.Vec2i, board: Board): Bool =
        List.exists(entry -> match entry {
            case (Piece.Enemy(_), pos) => pos#x == coord#x and pos#y == coord#y
            case _                      => false
        }, board#pieces)

    /// `enemyPos` から最も Manhattan 距離が近いプレイヤー駒を返す。
    /// 同距離の場合は id の小さい方（pieces 順の先頭）を選ぶ。
    /// プレイヤーが居なければ None。EnemyAI が追跡 target を決めるのに使う。
    pub def nearestPlayer(enemyPos: Vec2.Vec2i,
                           board: Board): Option[(Int32, Vec2.Vec2i)] =
        let withDist = List.map(p -> {
            let (id, pos) = p;
            let dx = Int32.abs(pos#x - enemyPos#x);
            let dy = Int32.abs(pos#y - enemyPos#y);
            (dx + dy, id, pos)
        }, playerPositions(board));
        match withDist {
            case Nil       => None
            case x :: rest =>
                let best = List.foldLeft((acc, t) -> {
                    let (d1, _, _) = acc;
                    let (d2, _, _) = t;
                    if (d2 < d1) t else acc
                }, x, rest);
                let (_, id, pos) = best;
                Some((id, pos))
        }

    /// `pos` の上下左右に居る最初のプレイヤー駒の (id, position) を返す。
    /// EnemyAI の Attack 判定で「隣接する誰かを 1 体攻撃」するのに使う。
    pub def adjacentPlayer(pos: Vec2.Vec2i,
                            board: Board): Option[(Int32, Vec2.Vec2i)] =
        playerPositions(board)
            |> List.findMap(p -> {
                let (id, ppos) = p;
                let dx = Int32.abs(ppos#x - pos#x);
                let dy = Int32.abs(ppos#y - pos#y);
                if ((dx == 1 and dy == 0) or (dx == 0 and dy == 1))
                    Some((id, ppos))
                else None
            })
}
