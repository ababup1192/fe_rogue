/// MoveDraft — 移動トランザクション中に scene へ加えた「可逆な副作用」を表す ADT
///
/// PlayerCursor で味方を選んでから（行動確定 or キャンセルするまで）の間に、scene へ
/// 加える「あとで巻き戻せる変更」を 1 件ずつ表す。`SelectedPlayer.Selection.drafts` に
/// **新しい順**（先頭が直近の操作）で積み、
///   - キャンセル（`PlayerDriver.cancelSelection`）→ 先頭から順に逆操作
///   - 行動確定 / 次の選択開始 → drafts スタックごと破棄（revert 不要）
/// で扱う。巻き戻しの実体（snapTo / respawn / 在庫取り消し）は `PlayerDriver.revertDraftAction`
/// に集約する。
///
/// 拡張: 新しい可逆操作を足すときは
///   (1) `DraftAction` に case 追加
///   (2) `PlayerDriver.revertDraftAction` に 1 分岐追加
///   (3) その操作を行う箇所で `drafts` に push
/// の 3 点だけで済む。cancelSelection 本体や SelectedPlayer のフィールドには触らずに済むのは、
/// 巻き戻し責務をこの 3 箇所に局所化しているため（open/closed 的なローカリティ）。
mod MoveDraft {

    /// 移動中に加えた可逆な副作用 1 件。巻き戻しは `PlayerDriver.revertDraftAction` が
    /// **新しい順**に逆操作する（後勝ちで積んだ操作から戻すので、各 revert は「その操作の
    /// 直後の状態」に対して走る＝末尾前提の取り消しも正しく動く）。
    ///
    /// 各 case で非自明な巻き戻し契約のみ記す:
    ///   - `Equipped`: 装備時に先頭へ移動した武器を、元の idx 位置へ戻す必要がある
    ///     （先頭以外の順序は `moveHeadTo` で復元できるが、idx がズレると別の武器を指す）。
    ///   - `Traded`: 相手側に末尾付加した分を除去してから双方の元 idx へ戻す
    ///     （除去を先に行わないと idx がズレる）。
    pub enum DraftAction {
        case MovedFrom(Int32, {x = Int32, y = Int32})
        case PickedUp(Int32, {x = Int32, y = Int32}, String, ItemData.GroundItemKind)
        case Equipped(Int32, Int32)
        case Dropped(Int32, PlayerData.ItemKind, ItemData.GroundItemKind)
        case Traded({ selfId = Int32, selfKind = PlayerData.ItemKind,
                      selfItem = ItemData.GroundItemKind,
                      partnerId = Int32, partnerKind = Option[PlayerData.ItemKind],
                      partnerItem = Option[ItemData.GroundItemKind] })
        /// 集合（行軍）中に移動距離を使い切って非アクティブ(waited)化した味方 id。
        /// キャンセルで集合をなかったことにするとき、これを巻き戻して再アクティブにする。
        case GatherWaited(Int32)
    }

    /// drafts から id 一致の `MovedFrom` 起点（このターンの移動開始位置）を返す。無ければ None。
    /// drafts は新しい順スタック。個別移動は 1 件、集合移動は全味方ぶん積まれるため id で絞る
    /// （`findMap` は先頭一致＝最新を返すが、1 ターンに id あたり 1 件しか積まれない）。
    /// フォグ／ミニマップが「移動中も部屋点灯を origin 基準に保つ」ために参照する。
    pub def originOf(id: Int32, drafts: List[DraftAction]): Option[{x = Int32, y = Int32}] =
        List.findMap(a -> match a {
            case DraftAction.MovedFrom(i, c) => if (i == id) Some(c) else None
            case _                           => None
        }, drafts)

    /// この移動ドラフトで「いずれかのユニットが開始位置(origin)から動いたか」。
    /// `MovedFrom` を持たないユニット（このターン未選択）は寄与しない。ターン頭（0歩）の
    /// 「敵に見つかったら強制たいき」誤発火を防ぐガードとして `EnemyTurnDriver` が使う。
    pub def anyMovedFromOrigin(units: List[{id = Int32, gridPos = {x = Int32, y = Int32} | r}],
                                drafts: List[DraftAction]): Bool =
        List.exists(d -> match originOf(d#id, drafts) {
            case Some(o) => o#x != d#gridPos#x or o#y != d#gridPos#y
            case None    => false
        }, units)

}
