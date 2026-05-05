/// Board — 盤面状態（マップ + 駒の位置）のスナップショット
///
/// チェスの盤面のメタファー:
///   - map: タイル（壁・床）の地形情報
///   - pieces: 盤上にいる駒（プレイヤー・将来的に敵・アイテム）の位置リスト
///
/// BoardLogic はこの Board を 1 つ受け取れば「次の手」を計算できる。
/// 駒の位置を毎回外から教えてもらう必要がなくなり、責務が「盤面 → 手」に閉じる。
///
/// 取得は BoardQuery effect 経由。Game.start の handler が現フレームの
/// Scene と TileMapLayer から構築してクロージャに包み、フレーム内で固定して返す。
pub enum Piece with Eq {
    case Player
    // 将来: case Enemy(...), case Item(...)
}

pub type alias Board = {
    map    = MapSnapshot,
    pieces = List[(Piece, Vec2.Vec2i)]
}

pub eff BoardQuery {
    def board(): Board
}

mod Board {

    /// 盤面から Player の位置を取り出す。
    /// 通常は必ず Player が存在するが、Option で返すことで test や将来の
    /// 「Player が一時的に居ないフレーム」にも耐える。
    pub def playerPos(board: Board): Option[Vec2.Vec2i] =
        List.findMap(entry -> match entry {
            case (Piece.Player, pos) => Some(pos)
        }, board#pieces)
}
