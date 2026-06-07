/// MoveDraft — 移動トランザクション中に scene へ加えた「可逆な副作用」を表す ADT
///
/// PlayerCursor で味方を選んでから（行動確定 or キャンセルするまで）の間に、scene へ
/// 加える「あとで巻き戻せる変更」を 1 件ずつ表す。`SelectedPlayer.Selection.drafts` に
/// **新しい順**（先頭が直近の操作）で積み、
///   - キャンセル（`PlayerScene.cancelSelection`）→ 先頭から順に逆操作
///   - 行動確定（`commitWaitedAndAdvance` の `SelectedPlayer.cleared()`）/ 次の選択開始
///     → スタックごと破棄（＝確定）
/// で扱う。巻き戻しの実体（snapTo / respawn / 在庫取り消し）は `PlayerScene.revertDraftAction`
/// に集約する。
///
/// 拡張: 新しい可逆操作を足すときは
///   (1) `DraftAction` に case 追加
///   (2) `PlayerScene.revertDraftAction` に 1 分岐追加
///   (3) その操作を行う箇所で `drafts` に push
/// の 3 点だけで済む（`cancelSelection` 本体や `SelectedPlayer` のフィールドは触らない）。
mod MoveDraft {

    /// 移動中に加えた可逆な副作用 1 件。巻き戻しは `PlayerScene.revertDraftAction` が
    /// **新しい順**に逆操作する（後勝ちで積んだ操作から戻すので、各 revert は「その操作の
    /// 直後の状態」に対して走る＝末尾前提の取り消しも正しく動く）。
    ///   - `MovedFrom(playerId, fromCell)`        : 移動。巻き戻しは `snapTo(fromCell)`。
    ///   - `PickedUp(playerId, cell, itemKey, kind)`: 床アイテム取得。巻き戻しは
    ///       `ItemScene.respawn`（床へ戻す）+ 在庫末尾の取り消し。
    ///   - `Equipped(playerId, idx)`              : 装備（`weapons` を `moveToHead(idx)`）。
    ///       巻き戻しは先頭を idx 位置へ戻す（`moveHeadTo`）。
    ///   - `Dropped(playerId, kind, item)`        : 捨てる（`removeAt(idx)`）。
    ///       巻き戻しは元 idx に `item` を挿入し直す。
    ///   - `Traded(...)`                          : こうかん（`swapItem`）。巻き戻しは
    ///       相手末尾の付加分を除去し、双方の元 idx へ戻す。
    pub enum DraftAction {
        case MovedFrom(Int32, {x = Int32, y = Int32})
        case PickedUp(Int32, {x = Int32, y = Int32}, String, ItemScene.GroundItemKind)
        case Equipped(Int32, Int32)
        case Dropped(Int32, PlayerScene.ItemKind, ItemScene.GroundItemKind)
        case Traded({ selfId = Int32, selfKind = PlayerScene.ItemKind,
                      selfItem = ItemScene.GroundItemKind,
                      partnerId = Int32, partnerKind = Option[PlayerScene.ItemKind],
                      partnerItem = Option[ItemScene.GroundItemKind] })
    }

}
