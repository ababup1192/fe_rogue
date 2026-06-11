/// BoardSnapshot — Scene[NodeTag] から `Board` を組み立てる純粋寄りモジュール
///
/// `Board` (Board.flix) は「マップ + 駒の位置リスト」だけを持つ純粋値で、
/// EnemyAI / AutoMove / MoveRangeScene 等の判断ロジックが「scene を知らずに
/// 次の手を計算する」ための共通インターフェース。
///
/// このモジュールは scene を読み取って Board を返す **1 関数のみ** を持つ。
/// `BoardQuery` handler の中身、敵 step 内の盤面更新後の再構築、AutoMove の
/// step 判定など、scene → Board の変換が必要な全箇所がここを呼ぶ。
///
/// Aef を持たない (scene の値だけで決まる) ため、Board 系のテストから直接呼べる。
mod BoardSnapshot {

    /// 現フレームの scene から Board (MapSnapshot + 駒一覧) を組み立てる。
    /// 駒は PlayerScene / EnemyScene の Data から (Piece, gridPos) を作る。
    /// 順序: players → enemies (Board.playerPositions / enemyPositions の filterMap が
    /// 順序を保つ前提なので、ここでも安定順を維持する)。
    pub def fromScene(scene: Scene[NodeTag]): Board =
        fromParts(scene, PlayerScene.getAll(scene), EnemyScene.getAll(scene))

    /// `fromScene` の「取得済みリスト版」。`Encounter.fromScene` が同じ scene を二度歩かない
    /// よう、生の(hidden を含む) players/enemies を渡してこちらを使う。hidden の盤面除外は
    /// 従来どおり**ここ 1 箇所**で行う（Board 経由の全クエリが自動的に hidden を無視する）。
    pub def fromParts(scene: Scene[NodeTag],
                       players: List[PlayerScene.Data],
                       enemies: List[EnemyScene.Data]): Board =
        let layer       = MapScene.getMapLayer(scene);
        let mapGlobal   = Scene.globalPositionAt(MapScene.mapPath(), scene);
        let placements  = MapScene.getPlacements(scene);
        // engine 値 → 純粋データの MapSnapshot へ射影（唯一の変換点）。
        let map = MapScene.snapshotOf(layer, mapGlobal, placements);
        let playerPieces = players
            |> List.filter(d -> not d#hidden)
            |> List.map(d -> (Piece.Player(d#id), d#gridPos));
        let enemyPieces = enemies
            |> List.map(e -> (Piece.Enemy(e#id), e#gridPos));
        {
            map    = map,
            pieces = List.append(playerPieces, enemyPieces)
        }
}
