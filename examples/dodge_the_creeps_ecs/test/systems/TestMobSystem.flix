// MobSystem のテスト — move（位置積分）/ despawn（画面外）/ spawn（seeded）
//
// move/despawn は純粋なので直接テスト。spawn は \ Math.Random なので seeded handler を注入する。

mod TestMobSystem {

    def withMockRandom(f: Unit -> a \ ef + Math.Random): a \ ef =
        run f() with handler Math.Random {
            def randomFloat64(k) = k(0.5)
            def randomInt64(k)   = k(42i64)
        }

    def aMob(): SpriteComp = World.mobSprite("fly", "enemyFlyingAlt_1", "enemyFlyingAlt_2")

    /// move: position += velocity * dt
    @Test
    def testMoveIntegrates(): Unit \ Assert =
        let w0 = World.addMob({x = 100.0, y = 100.0}, {x = 10.0, y = 20.0}, aMob(), 30.0, World.empty());
        let after = MobSystem.moveSystem(1.0, w0);
        let World.World(wa) = after;
        let pos = Map.get(0, wa#positions) |> Option.getWithDefault(Vec2.zero());
        Assert.assertEq(expected = true, pos#x == 110.0 and pos#y == 120.0)

    /// despawn: 画面外（x が右端＋margin を超える）の mob は除去
    @Test
    def testDespawnRemovesOffscreen(): Unit \ Assert =
        let w0 = World.addMob({x = 1000.0, y = 100.0}, Vec2.zero(), aMob(), 30.0, World.empty());
        let after = MobSystem.despawnOffscreenSystem(w0);
        let World.World(wa) = after;
        Assert.assertEq(expected = 0, Set.size(wa#mobs))

    /// despawn: 画面内の mob は残る
    @Test
    def testDespawnKeepsOnscreen(): Unit \ Assert =
        let w0 = World.addMob({x = 100.0, y = 100.0}, Vec2.zero(), aMob(), 30.0, World.empty());
        let after = MobSystem.despawnOffscreenSystem(w0);
        let World.World(wa) = after;
        Assert.assertEq(expected = 1, Set.size(wa#mobs))

    /// spawn: Playing かつ startDelay 経過後、interval を超えたら 1 体湧く
    @Test
    def testSpawnAddsMob(): Unit \ Assert =
        let World.World(w0) = World.empty();
        let playing = World.World({phase = GamePhase.Playing,
                                   timers = {mobSpawn = 0.5 | w0#timers} | w0});
        let after = withMockRandom(() -> MobSystem.spawnSystem(0.1, playing));
        let World.World(wa) = after;
        Assert.assertEq(expected = 1, Set.size(wa#mobs))

    /// spawn: Menu 中は湧かない
    @Test
    def testSpawnSkipsInMenu(): Unit \ Assert =
        let World.World(w0) = World.empty();
        let menu = World.World({timers = {mobSpawn = 0.5 | w0#timers} | w0});  // phase=Menu
        let after = withMockRandom(() -> MobSystem.spawnSystem(0.1, menu));
        let World.World(wa) = after;
        Assert.assertEq(expected = 0, Set.size(wa#mobs))

    /// spawn: Get Ready（startDelay>0）中は Playing でも湧かない
    @Test
    def testSpawnSkipsDuringGetReady(): Unit \ Assert =
        let World.World(w0) = World.empty();
        let getReady = World.World({phase = GamePhase.Playing,
                                    timers = {mobSpawn = 0.5, startDelay = 2.0 | w0#timers} | w0});
        let after = withMockRandom(() -> MobSystem.spawnSystem(0.1, getReady));
        let World.World(wa) = after;
        Assert.assertEq(expected = 0, Set.size(wa#mobs))

    /// despawn 境界: 右端＋margin = 480+64 = 544。x=544 は残り、x=545 は消える
    @Test
    def testDespawnBoundaryKeeps(): Unit \ Assert =
        let w0 = World.addMob({x = 544.0, y = 100.0}, Vec2.zero(), aMob(), 30.0, World.empty());
        let World.World(wa) = MobSystem.despawnOffscreenSystem(w0);
        Assert.assertEq(expected = 1, Set.size(wa#mobs))

    @Test
    def testDespawnBoundaryRemoves(): Unit \ Assert =
        let w0 = World.addMob({x = 545.0, y = 100.0}, Vec2.zero(), aMob(), 30.0, World.empty());
        let World.World(wa) = MobSystem.despawnOffscreenSystem(w0);
        Assert.assertEq(expected = 0, Set.size(wa#mobs))

    /// mobFromRandom（純粋）: 速度の大きさが minSpeed..maxSpeed に入る
    @Test
    def testMobFromRandomSpeed(): Unit \ Assert =
        let m = MobSystem.mobFromRandom(0.5, 0.5, 0.5, 0.5);
        let sp = Vec2.length(m#vel);
        Assert.assertEq(expected = true, sp > 149.0 and sp < 251.0)
}
