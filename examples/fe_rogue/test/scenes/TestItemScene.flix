/// ItemScene の純粋ロジックテスト。
///
/// `floorCellsInBounds`: 「offset + 半開 bbox」内で床述語を満たすセルを列挙する純粋関数
/// （床ドロップ/敵スポーンの候補セル）。床判定を引数で注入するので scene/engine 非依存で検証できる。
/// `isTaken`: 同セル二重ドロップ防止の述語。
/// 守るバグ: アイテムが部屋 bbox 外（通路・壁）に湧いて取得不能 / 同セルに二重ドロップ。
mod TestItemScene {

    /// bbox 内の床セルを列挙し、maxEx は排他（半開区間）。
    /// offset(0,0)・min(0,0)・maxEx(2,2)・全床 → (0,0)(1,0)(0,1)(1,1) の 4 セル。(2,0) は範囲外。
    @Test
    def testFloorCellsRespectsBoundsHalfOpen(): Unit \ Assert =
        let cells = ItemScene.floorCellsInBounds(_ -> true,
                        {x = 0, y = 0}, {x = 0, y = 0}, {x = 2, y = 2})
                    |> List.map(c -> (c#x, c#y));
        Assert.assertEq(
            expected = (4, true, false),
            (List.length(cells),
             List.memberOf((1, 1), cells),     // 範囲内
             List.memberOf((2, 0), cells)))    // maxEx 排他で範囲外

    /// 床述語が false のセルは候補に入らない（通路床がアイテム候補に混ざらない）。
    /// x=0 列だけ床 → (0,0)(0,1) のみ。(1,0) は非床で除外。
    @Test
    def testFloorCellsFiltersNonFloor(): Unit \ Assert =
        let cells = ItemScene.floorCellsInBounds(c -> c#x == 0,
                        {x = 0, y = 0}, {x = 0, y = 0}, {x = 2, y = 2})
                    |> List.map(c -> (c#x, c#y));
        Assert.assertEq(
            expected = (2, false),
            (List.length(cells), List.memberOf((1, 0), cells)))

    /// offset が bbox に加算される（モジュールのワールド配置）。
    /// offset(10,20)・min(0,0)・maxEx(1,1) → (10,20) のみ。
    @Test
    def testFloorCellsAppliesOffset(): Unit \ Assert =
        let cells = ItemScene.floorCellsInBounds(_ -> true,
                        {x = 10, y = 20}, {x = 0, y = 0}, {x = 1, y = 1})
                    |> List.map(c -> (c#x, c#y));
        Assert.assertEq(expected = (10, 20) :: Nil, cells)

    /// 既取得セルは座標一致で検出する（二重ドロップ防止）。
    @Test
    def testIsTakenMatchByCoord(): Unit \ Assert =
        let taken = {x = 0, y = 0} :: {x = 1, y = 1} :: Nil;
        Assert.assertEq(
            expected = (true, false),
            (ItemScene.isTaken({x = 1, y = 1}, taken),
             ItemScene.isTaken({x = 2, y = 2}, taken)))

    /// (4,5) に武器アイテム 1 個を置いた最小シーン（World/Items/Item_0 を直接構築）。
    def sceneWithItem(): Scene[NodeTag] =
        let item = ItemData.GroundItemKind.WeaponItem(TestUnitFixtures.testWeapon());
        let body = EngineNode.Sprite2DWithState(
            Sprite2D.make("item_icons", Vec2.zero(), Vec2.one()),
            NodeTag.GroundItem(({gridPos = {x = 4, y = 5}, itemKey = "test_weapon",
                                  item = item, elapsed = Duration.seconds(0.0)}: ItemScene.Data)));
        let marker = () -> EngineNode.Marker2DWithState(Marker2D.make(Vec2.zero()), NodeTag.NoTag);
        Scene.empty()
            |> Scene.addNode(MapScene.worldName(), marker())
            |> Scene.addChildAt(MapScene.worldPath(), "Items", marker())
            |> Scene.addChildAt(ItemScene.parentPath(), "Item_0", body)

    /// P3-c: World store 権威の証跡。scene から seed した World は床アイテムを groundItemAtOf で返し、
    /// takeAt の emit した `Cmd.RemoveItem` を applyCmd すると Map から消える。
    @Test
    def testTakeAtDrivesWorldItemStore(): Unit \ Assert =
        region rc {
            let scene = sceneWithItem();
            let wref = Ref.fresh(rc, World.syncFromScene(scene, World.empty()));
            let before = World.groundItemAtOf({x = 4, y = 5}, Ref.get(wref)) |> Option.map(d -> d#itemKey);
            run { discard ItemScene.takeAt({x = 4, y = 5}, scene) }
                with handler World.Command {
                    def emit(c, k) = { Ref.put(World.applyCmd(c, Ref.get(wref)), wref); k() }
                };
            let after = World.groundItemAtOf({x = 4, y = 5}, Ref.get(wref)) |> Option.map(d -> d#itemKey);
            Assert.assertEq(expected = (Some("test_weapon"), None), (before, after))
        }
}
