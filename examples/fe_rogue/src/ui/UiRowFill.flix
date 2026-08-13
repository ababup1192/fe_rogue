/// UiRowFill — 固定数の行スロットへ項目列を表示範囲（offset）付きで流し込む骨格。
/// アイテム/交換/武器メニューが共有する「項目のある行は meta を設定して可視、表示範囲外の行は
/// meta を消して不可視（display:none でパネルが縮む＋選択対象から外れる）」の規約を一手に引き受け、
/// 各メニューは行の飾り（アイコン/サブライン/色）だけを applyRow で与える。
mod UiRowFill {

    /// 行スロットの配置規約。`rowPath` = i 行目の行コンテナの名前パス、`maxSlots` = 行数、
    /// `offset` = 表示範囲の先頭 index（スクロールの無いメニューは 0）。
    pub type alias Spec = { rowPath = Int32 -> String, maxSlots = Int32, offset = Int32 }

    /// items[offset+i] を行 0..maxSlots-1 へ流し込む。項目のある行は applyRow（行の飾り書き。
    /// (行 index, 項目) を受ける）の後に meta を設定して可視化し、表示範囲外の行は meta を消して不可視にする。
    pub def fill(spec: Spec, items: List[ItemEntry],
                 applyRow: (Int32, ItemEntry, UiStore.UiWorld) -> UiStore.UiWorld,
                 ui: UiStore.UiWorld): UiStore.UiWorld =
        List.range(0, spec#maxSlots) |> List.foldLeft((acc, i) ->
            match List.nth(spec#offset + i, items) {
                case Some(entry) =>
                    applyRow(i, entry, acc)
                        |> UiStore.setMeta(spec#rowPath(i), Option.getWithDefault("", entry#metadata))
                        |> UiStore.setVisible(spec#rowPath(i), true)
                case None =>
                    acc
                        |> UiStore.clearMeta(spec#rowPath(i))
                        |> UiStore.setVisible(spec#rowPath(i), false)
            }, ui)

    /// 全行を隠して meta も消す（非表示フェーズ用）。
    pub def hideAll(spec: Spec, ui: UiStore.UiWorld): UiStore.UiWorld =
        fill(spec, Nil, (_i, _entry, acc) -> acc, ui)
}
