/// `InventoryScene` の純粋判定ロジック (`hitSlot` / `nextSelectionFor`) と
/// 選択切替フロー (`onClick`) の単体テスト。
///
/// process (snapshot → scene tree 同期) は I/O 寄りで scene tree が必要なので、
/// ここでは入力 → `Inventory.Access.setSelected` の挙動だけを確認する。
/// scene 描画の挙動は実機 + 開発者目視で確認する想定。
mod TestInventoryScene {

    /// テスト用 RoomState は不要。Inventory.Access だけ装着するヘルパ。
    def withInventory(thunk: Unit -> a \ ef):
                       a \ (ef - Game.Inventory.Access) =
        region rc {
            Game.Inventory.withState(rc)(thunk)
        }

    // ========================================================================
    // (A) hitSlot — 純粋関数
    // ========================================================================

    /// 各スロットの中心座標で hitSlot するとそのスロット index が返る。
    /// scene.json の配置 (slot 0 中心 (168,20)、以降 36 px 間隔) と整合する。
    @Test
    def testHitSlotAtSlotCenters(): Unit \ Assert =
        let result = (
            InventoryScene.hitSlot(({x = 168.0, y = 20.0}: Vec2.Vec2)),
            InventoryScene.hitSlot(({x = 204.0, y = 20.0}: Vec2.Vec2)),
            InventoryScene.hitSlot(({x = 240.0, y = 20.0}: Vec2.Vec2)),
            InventoryScene.hitSlot(({x = 276.0, y = 20.0}: Vec2.Vec2)),
            InventoryScene.hitSlot(({x = 312.0, y = 20.0}: Vec2.Vec2))
        );
        Assert.assertEq(expected = (Some(0), Some(1), Some(2), Some(3), Some(4)), result)

    /// バー領域外 (y >= 40) のクリックは hitSlot で None。
    /// 部屋の hotspot 領域や対話パネル位置をクリックしてもスロット選択は起きない保証。
    @Test
    def testHitSlotOutsideBarReturnsNone(): Unit \ Assert =
        let result = (
            InventoryScene.hitSlot(({x = 168.0, y = 100.0}: Vec2.Vec2)),
            InventoryScene.hitSlot(({x = 168.0, y = 250.0}: Vec2.Vec2))
        );
        Assert.assertEq(expected = (None, None), result)

    /// バー領域内でもスロット間ギャップ (x=184〜188) は None。
    /// 余白クリックは「選択解除」用入力として扱う方針 (nextSelectionFor 側で None 返す)。
    @Test
    def testHitSlotInGapReturnsNone(): Unit \ Assert =
        Assert.assertEq(expected = None,
            InventoryScene.hitSlot(({x = 186.0, y = 20.0}: Vec2.Vec2)))

    // ========================================================================
    // (B) nextSelectionFor — トグル動作
    // ========================================================================

    /// 未選択状態でスロット 0 中心をクリックすると Some(0) になる。
    @Test
    def testClickEmptySelectsSlot(): Unit \ Assert =
        let next = InventoryScene.nextSelectionFor(
            ({x = 168.0, y = 20.0}: Vec2.Vec2), None);
        Assert.assertEq(expected = Some(0), next)

    /// スロット 0 を既に選択中で再びスロット 0 中心をクリックすると None (解除)。
    @Test
    def testClickSameSlotDeselects(): Unit \ Assert =
        let next = InventoryScene.nextSelectionFor(
            ({x = 168.0, y = 20.0}: Vec2.Vec2), Some(0));
        Assert.assertEq(expected = None, next)

    /// スロット 0 選択中で別スロット (1) をクリックすると Some(1) に切替。
    @Test
    def testClickDifferentSlotSwitches(): Unit \ Assert =
        let next = InventoryScene.nextSelectionFor(
            ({x = 204.0, y = 20.0}: Vec2.Vec2), Some(0));
        Assert.assertEq(expected = Some(1), next)

    /// スロット 0 選択中でバー内ギャップをクリックすると None (解除)。
    /// 「ぼんやり選択を解除したいときバーの空白を押せばいい」UX。
    @Test
    def testClickGapDeselects(): Unit \ Assert =
        let next = InventoryScene.nextSelectionFor(
            ({x = 186.0, y = 20.0}: Vec2.Vec2), Some(0));
        Assert.assertEq(expected = None, next)

    // ========================================================================
    // (C) onClick — Inventory.Access への副作用
    // ========================================================================

    /// `onClick` を呼ぶと Inventory.Access.setSelected が呼ばれて snapshot に反映する。
    /// アイテム 1 件 ("demo_key") を持つ状態でスロット 0 をクリック → 選択 Some(0)。
    @Test
    def testOnClickCallsSetSelected(): Unit \ Assert =
        let selected = withInventory(() -> {
            Game.Inventory.Access.add("demo_key");
            discard InventoryScene.onClick(
                ({x = 168.0, y = 20.0}: Vec2.Vec2),
                Scene.empty());
            Game.Inventory.selectedSlot()
        });
        Assert.assertEq(expected = Some(0), selected)

    /// 選択中スロットに空きアイテム (slot 1 はアイテムなし) を選ぶと、
    /// Inventory.setSelected の正規化ロジック (Phase 1) によって None になる。
    /// 「持っていないスロットは選べない」UX。
    @Test
    def testOnClickEmptySlotYieldsNone(): Unit \ Assert =
        let selected = withInventory(() -> {
            Game.Inventory.Access.add("demo_key");  // slot 0 に 1 件だけ
            discard InventoryScene.onClick(
                ({x = 204.0, y = 20.0}: Vec2.Vec2),  // slot 1 中心
                Scene.empty());
            Game.Inventory.selectedSlot()
        });
        Assert.assertEq(expected = None, selected)
}
