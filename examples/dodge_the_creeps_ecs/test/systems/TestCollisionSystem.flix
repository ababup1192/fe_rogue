// CollisionSystem のテスト（純粋）— 接触で GameOver＋player despawn、非接触で不変

mod TestCollisionSystem {

    def aMob(): SpriteComp = World.mobSprite("fly", "enemyFlyingAlt_1", "enemyFlyingAlt_2")

    /// player(100,100,r30) と mob(110,100,r30): 距離10 < 60 → 接触
    @Test
    def testHitTriggersGameOver(): Unit \ Assert =
        let withPlayer = World.spawnPlayer({x = 100.0, y = 100.0}, 30.0, World.empty());
        let World.World(wp) = withPlayer;
        let playing = World.World({phase = GamePhase.Playing | wp});
        let w = World.addMob({x = 110.0, y = 100.0}, Vec2.zero(), aMob(), 30.0, playing);
        let after = CollisionSystem.collisionSystem(w);
        let World.World(wa) = after;
        Assert.assertEq(expected = true,
            wa#phase == GamePhase.GameOver and wa#player == None)

    /// player(100,100) と mob(400,400): 遠い → 不変（Playing 維持・player 健在）
    @Test
    def testNoHitKeepsPlaying(): Unit \ Assert =
        let withPlayer = World.spawnPlayer({x = 100.0, y = 100.0}, 30.0, World.empty());
        let World.World(wp) = withPlayer;
        let playing = World.World({phase = GamePhase.Playing | wp});
        let w = World.addMob({x = 400.0, y = 400.0}, Vec2.zero(), aMob(), 30.0, playing);
        let after = CollisionSystem.collisionSystem(w);
        let World.World(wa) = after;
        Assert.assertEq(expected = true,
            wa#phase == GamePhase.Playing and wa#player != None)
}
