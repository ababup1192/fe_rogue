/// BoardSnapshot — 駒（PlayerDriver / EnemyDriver）と地形（MapSnapshot）から `Board` を組み立てる純粋モジュール
///
/// `Board` (Board.flix) は「マップ + 駒の位置リスト」だけを持つ純粋値で、
/// EnemyAI / AutoMove / MoveRange 等の判断ロジックが「World を直接読まずに
/// 次の手を計算する」ための共通インターフェース。
///
/// live の Board 構築は `World.boardOf`（地形＝World.mapSnapshot・駒＝World.pos）が唯一の経路。
/// このモジュールは **駒 Data から Board を組むテスト/検証用 seam** で、地形は呼び出し側が
/// 値（MapSnapshot literal / fixture）で渡す。
///
/// 副作用ハンドラ(Aef)不要で値のみに依存する `fromParts` と、現在の PlayerDriver/EnemyDriver を
/// World から読んで組む `fromWorld` の 2 経路を提供する。
mod BoardSnapshot {

    /// 現在の PlayerDriver / EnemyDriver（World 読み）と地形値から Board を組み立てる。
    /// 順序: players → enemies (Board.playerPositions / enemyPositions の filterMap が
    /// 順序を保つ前提なので、ここでも安定順を維持する)。
    /// 順序が崩れると Board.playerPositions / enemyPositions が id と位置のズレを起こし、
    /// 移動範囲計算や AI の衝突判定が誤った駒を参照する。
    pub def fromWorld(terrain: MapSnapshot): Board \ World.WorldQuery =
        fromParts(terrain, PlayerDriver.getAll(), EnemyDriver.getAll())

    /// `fromWorld` の「取得済みリスト版」。同じ World クエリを二度呼ばないよう、生の(hidden を含む)
    /// players/enemies を渡してこちらを使う。hidden の盤面除外は**ここ 1 箇所**で行う
    /// （Board 経由の全クエリが自動的に hidden を無視する）。
    /// 非対称: players は hidden フィルタをかけるが、enemies にはかけない。
    /// EnemyDriver.Data に hidden 概念がなく、死亡敵は EnemyDriver 側で既に除去されているため。
    pub def fromParts(terrain: MapSnapshot,
                       players: List[PlayerDriver.Data],
                       enemies: List[EnemyDriver.Data]): Board =
        let playerPieces = players
            |> List.filter(d -> not d#hidden)
            |> List.map(d -> (Piece.Player(d#id), d#gridPos));
        let enemyPieces = enemies
            |> List.map(e -> (Piece.Enemy(e#id), e#gridPos));
        {
            map    = terrain,
            pieces = List.append(playerPieces, enemyPieces)
        }
}
