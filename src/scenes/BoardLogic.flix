/// BoardLogic — グリッド盤面上の純粋ロジック
///
/// チェスの盤面の駒の動きを計算するイメージで、
/// 「ここから右に1マス進めるか？」「攻撃範囲内のセルはどれか？」など、
/// マップの形状や駒の位置に基づくルール判定を集約する。
///
/// 引数で受ける `Board` には地形（map）と駒の位置（pieces）が同梱されているので、
/// 「コマの位置を毎回外から教えてもらう」必要がなくなり、責務が「盤面 → 手」に閉じる。
/// Scene の構造や PlayerScene の Data には依存しない（テストは Board を直接合成可能）。
mod BoardLogic {

    /// 指定セルが歩行可能か（マップ範囲内 かつ 壁ではない）
    pub def isWalkable(board: Board, coord: Vec2.Vec2i): Bool =
        board#map#isFloor(coord)

    /// origin から dir 方向に 1 マス進む候補座標
    pub def stepTarget(origin: Vec2.Vec2i, dir: Vec2.Vec2i): Vec2.Vec2i =
        Vec2.addI(origin, dir)

    /// Player を dir 方向に 1 マス進めるか試みる。
    /// 進めるなら Some(目標座標)、壁・範囲外、または盤上に Player がいなければ None。
    pub def tryMove(board: Board, dir: Vec2.Vec2i): Option[Vec2.Vec2i] =
        Board.playerPos(board) |> Option.flatMap(player ->
            let target = stepTarget(player, dir);
            if (isWalkable(board, target)) Some(target) else None)
}
