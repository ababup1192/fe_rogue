// ChestScene のテスト
//
// 宝箱は World/Chests 配下に Sprite2D として複数並ぶ。ランダム配置 (add) は実マップ
// (LDTK) を要求するためここでは扱わず、セル固定で組んだシーンに対する問い合わせ
// (findAt / getAllPositions) と取得 (takeAt) の論理だけを検証する。
// いずれも Option チェーン + assertEq で「期待ケースだけ」を比較し、分岐を持たない。

mod TestChestScene {

    /// (2,3) に chestKey="wooden" の宝箱 1 個だけを置いた最小シーン
    /// （JSON ロードを介さず World/Chests/Chest_0 を直接構築）。中身は適当な武器。
    def sceneWithChest(): Scene[NodeTag] =
        let content = ItemData.GroundItemKind.WeaponItem(TestUnitFixtures.testWeapon());
        let chest = EngineNode.Sprite2DWithState(
            Sprite2D.make("item_icons", Vec2.zero(), Vec2.one()),
            NodeTag.Chest(({gridPos = {x = 2, y = 3}, chestKey = "wooden",
                             contentId = "test_content", content = content}: ChestScene.Data)));
        let marker = () -> EngineNode.Marker2DWithState(Marker2D.make(Vec2.zero()), NodeTag.NoTag);
        Scene.empty()
            |> Scene.addNode(MapScene.worldName(), marker())
            |> Scene.addChildAt(MapScene.worldPath(), "Chests", marker())
            |> Scene.addChildAt(ChestScene.parentPath(), "Chest_0", chest)

    /// 宝箱を置いたセルでは findAt が chestKey を返し、別セルでは None。
    @Test
    def testFindAtReturnsChestAtCell(): Unit \ Assert =
        let scene = sceneWithChest();
        Assert.assertEq(
            expected = (Some("wooden"), None),
            (ChestScene.findAt({x = 2, y = 3}, scene) |> Option.map(d -> d#chestKey),
             ChestScene.findAt({x = 9, y = 9}, scene) |> Option.map(d -> d#chestKey)))

    /// takeAt するとその宝箱は消え、再度 findAt しても見つからない（開錠後の再表示なし）。
    /// P3-b: takeAt は `Cmd.RemoveChest` を emit する。scene ノード除去だけを検証するので World.Command は no-op で捨てる。
    @Test
    def testTakeAtRemovesChest(): Unit \ Assert =
        let scene = sceneWithChest();
        let after = run { ChestScene.takeAt({x = 2, y = 3}, scene) }
                    with handler World.Command { def emit(_, k) = k() };
        Assert.assertEq(
            expected = (true, false),
            (Option.nonEmpty(ChestScene.findAt({x = 2, y = 3}, scene)),
             Option.nonEmpty(ChestScene.findAt({x = 2, y = 3}, after))))

    /// P3-b: World store 権威の証跡。scene から seed した World は宝箱を chestAtOf で返し、
    /// takeAt の emit した `Cmd.RemoveChest` を applyCmd すると Map から消える。
    @Test
    def testTakeAtDrivesWorldChestStore(): Unit \ Assert =
        region rc {
            let scene = sceneWithChest();
            let wref = Ref.fresh(rc, World.syncFromScene(scene, World.empty()));
            let before = World.chestAtOf({x = 2, y = 3}, Ref.get(wref)) |> Option.map(d -> d#chestKey);
            run { discard ChestScene.takeAt({x = 2, y = 3}, scene) }
                with handler World.Command {
                    def emit(c, k) = { Ref.put(World.applyCmd(c, Ref.get(wref)), wref); k() }
                };
            let after = World.chestAtOf({x = 2, y = 3}, Ref.get(wref)) |> Option.map(d -> d#chestKey);
            Assert.assertEq(expected = (Some("wooden"), None), (before, after))
        }

    /// getAllPositions は配置済み宝箱のセルを返す（占有判定・ミニマップ用）。
    @Test
    def testGetAllPositionsReturnsChestCell(): Unit \ Assert =
        let scene = sceneWithChest();
        Assert.assertEq(
            expected = (2, 3) :: Nil,
            ChestScene.getAllPositions(scene) |> List.map(c -> (c#x, c#y)))
}
