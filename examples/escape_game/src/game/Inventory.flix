/// プレイヤー所持品の状態管理。
///
/// 設計意図:
///   - 状態は `Game.Inventory.Access` effect 経由で読み書きする。実体（region 内
///     `MutList[ItemId, r]` + `Ref[Option[SlotIndex], r]`）は `Game.start` の handler
///     が握り、ゲーム本体は内部構造を見ない（`Game.ShakeState` と同じ流儀）
///   - Yarn 側は副作用コマンド `<<inv add/remove>>` でアイテムを増減し、ビルトイン
///     `inv_has(id)` `inv_selected()` で問い合わせる
///   - 「持ち物」は **MutList** で順序保持。重複追加は indexOf チェックで弾く
///   - 「選択中スロット」は `Option[SlotIndex]` を `Ref` 1 つで持つ
///   - 外部に渡す `Snapshot` は immutable List を含む値型で、save/load や view が
///     mutable の中身を直接触らないように `MutList.toList` で 1 段コピーする
mod Game.Inventory {

    /// アイテム id（`<<inv add demo_key>>` の `demo_key` のような短い識別子）。
    pub type alias ItemId = String

    /// スロット番号（0 始まり、`slotCount()` 未満）。
    pub type alias SlotIndex = Int32

    /// 外部に渡すインベントリの瞬時値。view / save 用の immutable コピー。
    pub type alias Snapshot = { items = List[ItemId], selected = Option[SlotIndex] }

    /// スロット数の上限。プランで「固定 5」と決めた値。
    pub def slotCount(): Int32 = 5

    /// インベントリ操作。実体は `Game.start` の handler で region 内 mutable に
    /// 閉じ込めて注入する。
    pub eff Access {
        /// 現在のスナップショットを取得する（テスト・ビルトインからも利用）。
        /// 内部 MutList の即時コピーを返すので、後続の add/remove で値が変化しても影響しない。
        def snapshot(): Snapshot

        /// アイテムを末尾に追加する。同じ id が既にあれば何もしない（冪等）。
        def add(id: ItemId): Unit

        /// アイテムを取り除く。存在しなければ何もしない。
        /// 取り除いた結果、選択中スロットが範囲外になったら選択解除する。
        def remove(id: ItemId): Unit

        /// 選択中スロットを更新する。`None` で解除。範囲外（負・上限以上・空スロット）は `None` 扱い。
        def setSelected(slot: Option[SlotIndex]): Unit
    }

    /// `Game.ShakeState.withState` と同じ流儀の handler 注入。
    /// `itemsRef` (MutList) と `selectedRef` (Ref) は内部 closure に閉じ込められ、
    /// 呼び出し側からは見えない。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - Access) + r =
        thunk -> {
            let itemsRef: MutList[ItemId, r] = MutList.empty(rc);
            let selectedRef: Ref[Option[SlotIndex], r] = Ref.fresh(rc, None);
            run thunk() with handler Access {
                def snapshot(k)       = k(snapshotOf(itemsRef, selectedRef))
                def add(id, k)        = { addMut(id, itemsRef); k() }
                def remove(id, k)     = { removeMut(id, itemsRef, selectedRef); k() }
                def setSelected(s, k) = { setSelectedMut(s, itemsRef, selectedRef); k() }
            }
        }

    /// 内部 mutable 状態から immutable Snapshot を作る。
    /// `MutList.toList` で items を 1 度コピーする。
    def snapshotOf(itemsRef: MutList[ItemId, r],
                    selectedRef: Ref[Option[SlotIndex], r]):
                    Snapshot \ r =
        ({items = MutList.toList(itemsRef), selected = Ref.get(selectedRef)}: Snapshot)

    /// 末尾追加。重複は indexOf で弾く（O(n) だが n <= slotCount で十分）。
    def addMut(id: ItemId, itemsRef: MutList[ItemId, r]): Unit \ r =
        if (MutList.memberOf(id, itemsRef)) ()
        else MutList.push(id, itemsRef)

    /// 削除。`indexOf` で位置を引いて `MutList.remove` で取り出し、
    /// 選択中スロットが新しい長さの範囲外になったら自動で None に戻す。
    def removeMut(id: ItemId,
                   itemsRef: MutList[ItemId, r],
                   selectedRef: Ref[Option[SlotIndex], r]): Unit \ r =
        match MutList.indexOf(id, itemsRef) {
            case None     => ()
            case Some(ix) =>
                MutList.remove(ix, itemsRef);
                clampSelectedAfterShrink(itemsRef, selectedRef)
        }

    /// 選択スロットの正規化。範囲内なら `Some`、範囲外なら `None` に丸める。
    def setSelectedMut(slot: Option[SlotIndex],
                        itemsRef: MutList[ItemId, r],
                        selectedRef: Ref[Option[SlotIndex], r]): Unit \ r =
        let len = MutList.length(itemsRef);
        let normalized = Option.flatMap(s -> normalizeSlot(s, len), slot);
        Ref.put(normalized, selectedRef)

    /// 縮小後に選択中スロットが範囲外なら `None` にリセットする。
    def clampSelectedAfterShrink(itemsRef: MutList[ItemId, r],
                                  selectedRef: Ref[Option[SlotIndex], r]): Unit \ r =
        let len = MutList.length(itemsRef);
        let next = Option.flatMap(s -> normalizeSlot(s, len), Ref.get(selectedRef));
        Ref.put(next, selectedRef)

    /// スロット番号を範囲内なら `Some` に、範囲外なら `None` に丸める。
    /// 範囲: `0 <= s < min(slotCount, itemCount)`。
    def normalizeSlot(s: SlotIndex, itemCount: Int32): Option[SlotIndex] =
        if (s >= 0 and s < slotCount() and s < itemCount) Some(s) else None

    // ════════════════════════════════════════════════════════════════════════
    // 公開ヘルパー（Snapshot を読む派生クエリ）
    // ════════════════════════════════════════════════════════════════════════

    /// `id` を所持しているか。
    pub def has(id: ItemId): Bool \ Access =
        List.memberOf(id, Access.snapshot()#items)

    /// 現在選択中のスロットに入っているアイテム id。未選択時は空文字 `""`。
    pub def selectedId(): ItemId \ Access =
        let snap = Access.snapshot();
        snap#selected
            |> Option.flatMap(s -> List.nth(s, snap#items))
            |> Option.getWithDefault("")

    /// 所持品の id 列。
    pub def items(): List[ItemId] \ Access =
        Access.snapshot()#items

    /// 選択中スロット番号。
    pub def selectedSlot(): Option[SlotIndex] \ Access =
        Access.snapshot()#selected
}
