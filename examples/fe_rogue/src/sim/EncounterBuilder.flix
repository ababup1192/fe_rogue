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
    /// EnemyAI 入力の Encounter を **board・units とも World 由来**で組む（S4.3 reader-flip）。
    /// board は `BoardQuery`、units は `World.unitViewFromWorld`（S4.1 で構築・S4.4b 完了後 run 検証で
    /// scene unitView と bit 一致を実証＝挙動同一）。aiType だけ resource 残置(hybrid-A)。
    /// **唯一の Encounter 構築口**（D0 で退役 `fromScene` 撤去）。hidden（階段退場）の味方は scene d#hidden で
    /// 除外し units からも外す。駒順は players → enemies（`Board.nearestPlayer` の id 小タイブレーク用）。
    /// `unitViewFromWorld` は Option（core W field 欠落で None）ゆえ filterMap で落とす（live は常に Some）。
    pub def fromBoardQuery(scene: Scene[NodeTag]): Encounter \ {BoardQuery, World.WorldQuery} =
        let board   = BoardQuery.board();
        let world   = World.WorldQuery.get();
        let players = PlayerScene.getAll(scene)
            |> List.filter(d -> not d#hidden)
            |> List.filterMap(d -> World.unitViewFromWorld(World.EntityRef.Player(d#id), world, scene));
        let enemies = EnemyScene.getAll(scene)
            |> List.filterMap(d -> World.unitViewFromWorld(World.EntityRef.Enemy(d#id), world, scene));
        {board = board, units = List.append(players, enemies)}
}
