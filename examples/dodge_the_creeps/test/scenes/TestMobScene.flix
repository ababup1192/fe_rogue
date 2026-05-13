// Tests for MobScene — モブのスポーンと画面外削除

mod TestMobScene {

    // ── 共通ヘルパー ──

    /// Math.Random のモックハンドラ
    def withMockRandom(f: Unit -> a \ ef + Math.Random): a \ ef =
        run f() with handler Math.Random {
            def randomFloat64(k) = k(0.5)
            def randomInt64(k)   = k(42i64)
        }

    /// 空シーンに mob_path だけ追加した最小シーン
    def baseScene(): Scene[NodeTag] =
        let path = Path2D.screenEdgePath(Game.designWi(), Game.designHi());
        Scene.empty()
            |> Scene.addNode("mob_path",
                EngineNode.Path2DWithState(path, NodeTag.NoTag))

    // ── テスト ──

    /// spawnMob で新しいモブが追加される
    @Test
    def testSpawnMobAddsNode(): Unit \ Assert =
        let before = baseScene();
        let after = withMockRandom(() ->
            MobScene.spawnMob(0, {x = 100.0, y = 0.0}, 1.57, before));
        let mobPresent = Option.nonEmpty(Scene.getEngineNode(MobScene.mobName(0) :: Nil, after));
        Assert.assertEq(expected = true, mobPresent)

    /// spawnMob で追加されたモブは mobGroup に登録される
    @Test
    def testSpawnMobJoinsGroup(): Unit \ Assert =
        let before = baseScene();
        let after = withMockRandom(() ->
            MobScene.spawnMob(0, {x = 100.0, y = 0.0}, 1.57, before));
        let inGroup = Scene.getNodesInGroup(MobScene.mobGroup(), after);
        Assert.assertEq(expected = 1, List.length(inGroup))

    /// spawnFromPath は path からサンプリングして 1 体追加する
    @Test
    def testSpawnFromPathAddsOne(): Unit \ Assert =
        let before = baseScene();
        let after = withMockRandom(() -> MobScene.spawnFromPath(7, before));
        Assert.assertEq(expected = true,
            Option.nonEmpty(Scene.getEngineNode(MobScene.mobName(7) :: Nil, after)))

    /// onScreenExit はノードを削除する
    @Test
    def testOnScreenExitRemovesNode(): Unit \ Assert =
        let scene = withMockRandom(() ->
            MobScene.spawnMob(3, {x = 100.0, y = 0.0}, 1.57, baseScene()));
        let mobPath = MobScene.mobName(3) :: Nil;
        let afterRemove = MobScene.onScreenExit(mobPath, scene);
        Assert.assertEq(expected = false,
            Option.nonEmpty(Scene.getEngineNode(mobPath, afterRemove)))
}
