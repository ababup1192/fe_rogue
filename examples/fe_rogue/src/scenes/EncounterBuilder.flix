/// EncounterBuilder — scene → Encounter の変換器（mod Encounter の scene 読み部分）。
///
/// Encounter 型と純クエリ(enemiesOf 等)は game/Encounter.flix に置き、scene を読む `fromScene` だけ
/// この scenes/ 層に分離する（game/ から scenes/ を読まないようにするため）。
/// Flix は同名 mod の複数ファイル分割を許さないので、builder は別 mod 名 `EncounterBuilder` にする。
mod EncounterBuilder {

    /// scene から Encounter を組み立てる唯一のビルダー（join はすべてここ）。
    /// 駒順は `BoardSnapshot.fromScene` と同じ players → enemies を保つ
    /// （`Board.nearestPlayer` の id 小タイブレークに効くため）。
    /// hidden（しゅうごう退避中 / 階段退場）の味方は盤面・units の双方から除外する。
    pub def fromScene(scene: Scene[NodeTag]): Encounter =
        // getAll を players/enemies 各1回だけ歩き、その結果で UnitView と Board の両方を作る
        // （`BoardSnapshot.fromParts` が hidden 除外と pieces 化を担当）。
        let allPlayers = PlayerScene.getAll(scene);
        let allEnemies = EnemyScene.getAll(scene);
        let board = BoardSnapshot.fromParts(scene, allPlayers, allEnemies);
        let players = allPlayers
            |> List.filter(d -> not d#hidden)
            |> List.map(PlayerScene.unitView);
        let enemies = allEnemies
            |> List.map(EnemyScene.unitView);
        {board = board, units = List.append(players, enemies)}
}
