// ChestScene のテスト（P6-1d: World store 権威）
//
// 宝箱の存在/中身は World.chests store（SpawnChest/RemoveChest/ClearChests）が唯一の権威で、
// scene ノードは存在しない（描画は RenderWorld.renderChests の直描き）。
// ランダム配置 (add) は実マップ (LDTK) を要求するためここでは扱わず、Cmd 単位で
// 「spawn → 問い合わせ → 開錠除去 → 全消去」の store 遷移を pin する。

mod TestChestScene {

    /// (2,3) に chestKey="wooden" の宝箱 1 個を spawn した World。中身は適当な武器。
    def worldWithChest(): World =
        let content = ItemData.GroundItemKind.WeaponItem(TestUnitFixtures.testWeapon());
        let data: ChestScene.Data = {gridPos = {x = 2, y = 3}, chestKey = "wooden",
                                     contentId = "test_content", content = content};
        World.applyCmd(World.Cmd.SpawnChest(data), World.empty())

    /// spawn したセルでは chestAtOf が chestKey を返し、別セルでは None。
    @Test
    def testChestAtOfReturnsChestAtCell(): Unit \ Assert =
        let w = worldWithChest();
        Assert.assertEq(
            expected = (Some("wooden"), None),
            (World.chestAtOf({x = 2, y = 3}, w) |> Option.map(d -> d#chestKey),
             World.chestAtOf({x = 9, y = 9}, w) |> Option.map(d -> d#chestKey)))

    /// takeAt は store に宝箱が居るときだけ `Cmd.RemoveChest` を emit し、apply 後は消える
    /// （開錠後の再表示なし）。無いセルへの takeAt は no-op（emit ゼロ）。
    @Test
    def testTakeAtDrivesWorldChestStore(): Unit \ Assert =
        region rc {
            let wref = Ref.fresh(rc, worldWithChest());
            let runTake = cell -> {
                run { discard ChestScene.takeAt(cell, Scene.empty()) }
                    with handler World.Command {
                        def emit(c, k) = { Ref.put(World.applyCmd(c, Ref.get(wref)), wref); k() }
                    }
                    with handler World.WorldQuery {
                        def get(k) = k(Ref.get(wref))
                    }
            };
            runTake({x = 9, y = 9});   // 不在セル: no-op
            let afterMiss = World.chestAtOf({x = 2, y = 3}, Ref.get(wref)) |> Option.map(d -> d#chestKey);
            runTake({x = 2, y = 3});   // 在セル: RemoveChest
            let afterTake = World.chestAtOf({x = 2, y = 3}, Ref.get(wref)) |> Option.map(d -> d#chestKey);
            Assert.assertEq(expected = (Some("wooden"), None), (afterMiss, afterTake))
        }

    /// ClearChests は store を空にする（フロア再構築の掃除。scene 再構築 prune の代替）。
    @Test
    def testClearChestsEmptiesStore(): Unit \ Assert =
        let cleared = World.applyCmd(World.Cmd.ClearChests, worldWithChest());
        Assert.assertEq(expected = 0, Map.size(World.chestsOf(cleared)))

    /// refreshMirror は command 由来の chests を preserve する（scene 非依存＝ノード無しでも消えない）。
    @Test
    def testRefreshMirrorPreservesChests(): Unit \ Assert =
        let after = World.refreshMirror(worldWithChest());
        Assert.assertEq(
            expected = Some("wooden"),
            World.chestAtOf({x = 2, y = 3}, after) |> Option.map(d -> d#chestKey))
}
