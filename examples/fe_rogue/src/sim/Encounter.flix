/// Encounter — 現フレームの「盤面 + 盤上ユニット」を結合したスナップショット
///
/// `Board`(座標 + Piece) を `units: List[UnitView]`(HP・武器・ステータスを id で結合済み) と
/// 束ねた純粋値。「位置 × ステータスの join」をこの 1 箇所（`fromScene`）に集約し、
/// EnemyAI / ActionMenu / BattlePanel が散らばって id 結合していたのを置き換える。
///
/// `Encounter` は `Board` を **包含** するので、幾何（bfsPath / reachable）は `enc#board` 経由で
/// そのまま使え、ステータス絡みの判定は `enc#units` から取れる。
///
/// snapshot / live の 2 つの読み口は同じ `fromScene` を通る:
///   - live    : driver が手元の（mid-frame mutation 済み）scene に適用
///   - snapshot: effect handler が `Ref.get(sceneRef)`（フレーム頭）に適用
///
/// hidden（しゅうごう退避中 / 階段退場）の味方は盤面から外れているので units からも除外する
/// （`BoardSnapshot.fromScene` と同じフィルタ）。
pub type alias Encounter = {
    board = Board,
    units = List[UnitView]
}

// scene → Encounter を組み立てる `fromScene` ビルダーは scene を読むため scenes/BoardSnapshot.flix
// と同層の scenes/EncounterBuilder.flix（mod Encounter）へ置く。ここ(game/)は型と純クエリのみ。

mod Encounter {

    /// AI の攻撃対象列挙・ActionMenu の選択肢絞り込みなど、faction を軸に敵味方を問い合わせる共通起点。
    /// faction が異なるユニットだけを返すので、呼び手は自分の faction を渡すだけでよい。
    pub def enemiesOf(faction: Faction, enc: Encounter): List[UnitView] =
        List.filter(u -> u#faction != faction, enc#units)

    /// 回復・支援対象の列挙など、同 faction のユニットを一覧したい場面で使う共通クエリ。
    /// `enemiesOf` と対称に設計されており、faction を渡すだけで味方全員を得られる。
    pub def alliesOf(faction: Faction, enc: Encounter): List[UnitView] =
        List.filter(u -> u#faction == faction, enc#units)

    /// 移動先の占有確認・攻撃対象の特定など、座標からユニットを引く共通起点（先頭一致）。
    /// 同セル 2 体は想定外のため Option で返す。
    pub def unitAt(pos: {x = Int32, y = Int32}, enc: Encounter): Option[UnitView] =
        List.find(u -> u#pos#x == pos#x and u#pos#y == pos#y, enc#units)

    /// `self` のセルに自分以外の同 faction 味方が重なっているか（たいき可否の判定に使う）。
    pub def sameCellAlly(self: UnitView, enc: Encounter): Bool =
        List.exists(u ->
            u#id != self#id and u#faction == self#faction
                and u#pos#x == self#pos#x and u#pos#y == self#pos#y,
            enc#units)
}
