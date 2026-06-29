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
    /// EnemyAI 入力の Encounter を **board(位置幾何)は World 由来(`BoardQuery`)・units(stats)は scene の
    /// read-model** で組むハイブリッド版（**唯一の Encounter 構築口**。D0 で退役 `fromScene` を撤去）。
    /// §A 採用戦略（位置は World 権威・combat/weapon 等の stats は read-model）に沿う。
    /// dual-write で World pos == scene gridPos ゆえ board と units の位置は一致（挙動不変）。
    /// hidden（階段退場）の味方は盤面・units の双方から除外。駒順は players → enemies
    /// （`Board.nearestPlayer` の id 小タイブレーク用）。EnemyAI 駆動の mid-frame 消費者がこれを使う。
    pub def fromBoardQuery(scene: Scene[NodeTag]): Encounter \ BoardQuery =
        let board   = BoardQuery.board();
        let players = PlayerScene.getAll(scene)
            |> List.filter(d -> not d#hidden)
            |> List.map(PlayerScene.unitView);
        let enemies = EnemyScene.getAll(scene)
            |> List.map(EnemyScene.unitView);
        {board = board, units = List.append(players, enemies)}
}
