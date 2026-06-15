/// EncounterBuilder — scene → Encounter の変換器（mod Encounter の scene 読み部分）。
///
/// Encounter 型と純クエリ(enemiesOf 等)は game/Encounter.flix に置き、scene を読む `fromScene` だけ
/// この scenes/ 層に分離する（game/ から scenes/ を読まないようにするため）。
/// Flix は同名 mod の複数ファイル分割を許さないので、builder は別 mod 名 `EncounterBuilder` にする。
mod EncounterBuilder {

    /// scene から Encounter を組み立てる唯一のビルダー
    /// （players と enemies の UnitView 合成はすべてここで行う）。
    /// 唯一にしている理由: hidden 除外・駒順不変条件を一箇所に集約し、
    /// 他の場所で組み立てると hidden 漏れや順序崩れが起きるのを防ぐため。
    /// 駒順は `BoardSnapshot.fromScene` と同じ players → enemies を保つ
    /// （`Board.nearestPlayer` の id 小タイブレークに効くため）。
    /// hidden（階段退場）の味方は盤面・units の双方から除外する。
    pub def fromScene(scene: Scene[NodeTag]): Encounter =
        // getAll を players/enemies 各1回だけ歩き、その結果で UnitView と Board の両方を作る。
        // `BoardSnapshot.fromParts` に hidden 除外と pieces 化を委譲することで、
        // hidden 判定を一箇所に集め、getAll の走査結果を Board/UnitView で使い回す。
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
