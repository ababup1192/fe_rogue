/// `Game.Inventory` の単体テスト。
///
/// 「アイテム列 + 選択スロット」の Ref に対して `add` / `remove` / `setSelected` を
/// 効果越しに発火し、派生クエリ (`has` / `selectedId`) が一貫して動くことを確認する。
/// `Access` effect は本番と同じ Ref ベース実装で handler を仕込み、テスト用に
/// 自前の handler を書かない。
mod TestInventory {

    /// テスト用 handler 装着ヘルパ。本番 (`Game.start`) と同じ
    /// `Game.Inventory.withState` を使い、挙動の乖離を防ぐ。
    def withInventory(thunk: Unit -> a \ ef):
                       a \ (ef - Game.Inventory.Access) =
        region rc {
            Game.Inventory.withState(rc)(thunk)
        }

    // ========================================================================
    // add: 末尾追加と重複時の冪等性
    // ========================================================================

    /// 同じ id を 2 回 add しても items は 1 件のまま（冪等）。
    /// `<<inv add demo_key>>` がループから 2 度呼ばれても OK にする保証。
    @Test
    def testAddIsIdempotentForSameId(): Unit \ Assert =
        let items = withInventory(() -> {
            Game.Inventory.Access.add("demo_key");
            Game.Inventory.Access.add("demo_key");
            Game.Inventory.items()
        });
        Assert.assertEq(expected = "demo_key" :: Nil, items)

    /// 異なる 3 件を順に追加すると、追加順がそのまま items に保たれる
    /// （スロット 0 / 1 / 2 がそれぞれ A / B / C を指す前提のため）。
    @Test
    def testAddPreservesInsertionOrder(): Unit \ Assert =
        let items = withInventory(() -> {
            Game.Inventory.Access.add("a");
            Game.Inventory.Access.add("b");
            Game.Inventory.Access.add("c");
            Game.Inventory.items()
        });
        Assert.assertEq(expected = "a" :: "b" :: "c" :: Nil, items)

    // ========================================================================
    // remove: 残り順序保持と未登録 id への no-op
    // ========================================================================

    /// 真ん中の id を 1 件取り除いても、左右の順序は保たれる。
    /// （後ろのアイテムが前に詰まってスロット番号がズレる挙動を担保）
    @Test
    def testRemoveKeepsOrderOfSurvivors(): Unit \ Assert =
        let items = withInventory(() -> {
            Game.Inventory.Access.add("a");
            Game.Inventory.Access.add("b");
            Game.Inventory.Access.add("c");
            Game.Inventory.Access.remove("b");
            Game.Inventory.items()
        });
        Assert.assertEq(expected = "a" :: "c" :: Nil, items)

    // ========================================================================
    // setSelected: 範囲外は None に丸める
    // ========================================================================

    /// 空のインベントリで slot 0 を選んでも `None` になる
    /// （選べるアイテムが無いので選択不可を強制したい）。
    @Test
    def testSelectInEmptyInventoryYieldsNone(): Unit \ Assert =
        let selected = withInventory(() -> {
            Game.Inventory.Access.setSelected(Some(0));
            Game.Inventory.selectedSlot()
        });
        Assert.assertEq(expected = None, selected)

    /// 1 件追加した状態で slot 0 を選ぶと `Some(0)`、`selectedId()` でその id が返る。
    @Test
    def testSelectExistingSlotExposesItemId(): Unit \ Assert =
        let result = withInventory(() -> {
            Game.Inventory.Access.add("demo_key");
            Game.Inventory.Access.setSelected(Some(0));
            (Game.Inventory.selectedSlot(), Game.Inventory.selectedId())
        });
        Assert.assertEq(expected = (Some(0), "demo_key"), result)

    /// 上限 (5) を超えるスロット番号は受け付けない（None に丸める）。
    /// 6 番目のアイテムが存在しないかどうかではなく、**スロット番号自体が範囲外**で弾かれる。
    @Test
    def testSelectOutOfRangeYieldsNone(): Unit \ Assert =
        let selected = withInventory(() -> {
            Game.Inventory.Access.add("a");
            Game.Inventory.Access.setSelected(Some(7));
            Game.Inventory.selectedSlot()
        });
        Assert.assertEq(expected = None, selected)

    // ========================================================================
    // remove + 選択中: 選択していたアイテムが消えたら自動で選択解除
    // ========================================================================

    /// slot 1 を選んでいる状態で slot 1 のアイテムを remove すると、
    /// items の長さが 1 に縮んで slot 1 が範囲外になり、選択は `None` に戻る。
    /// （プレイヤが「選択中の鍵を使ってアイテム消費」した後にもスロットが指す中身が
    ///   別のアイテムにすり替わると挙動が直感に反する、それを避ける保険）。
    @Test
    def testRemoveSelectedItemClearsSelection(): Unit \ Assert =
        let selected = withInventory(() -> {
            Game.Inventory.Access.add("a");
            Game.Inventory.Access.add("b");
            Game.Inventory.Access.setSelected(Some(1));
            Game.Inventory.Access.remove("b");
            Game.Inventory.selectedSlot()
        });
        Assert.assertEq(expected = None, selected)

    // ========================================================================
    // has: 所持判定
    // ========================================================================

    /// add 後に has は true、remove 後は false に戻る。
    /// `<<if inv_has("key")>>` の真偽が状態に追従することの最低限の確認。
    @Test
    def testHasFollowsAddRemove(): Unit \ Assert =
        let result = withInventory(() -> {
            let before  = Game.Inventory.has("demo_key");
            Game.Inventory.Access.add("demo_key");
            let after   = Game.Inventory.has("demo_key");
            Game.Inventory.Access.remove("demo_key");
            let dropped = Game.Inventory.has("demo_key");
            (before, after, dropped)
        });
        Assert.assertEq(expected = (false, true, false), result)
}
