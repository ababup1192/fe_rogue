// WorldCodec のテスト — World → JSON → World の round-trip（不変 World はただの値＝保存可能）
// size だけでなく、各 component の中身（clips / shape / layer/mask / timers / velocity）まで照合する。

mod TestWorldCodec {

    // ── ヘルパ ──
    def roundTrip(world: World): World =
        WorldCodec.encodeWorld(world) |> WorldCodec.decodeWorld |> Option.getWithDefault(World.empty())

    def posOf(id: EntityId, world: World): Vec2.Vec2 =
        let World.World(w) = world; Map.get(id, w#positions) |> Option.getWithDefault({x = -1.0, y = -1.0})
    def velOf(id: EntityId, world: World): Vec2.Vec2 =
        let World.World(w) = world; Map.get(id, w#velocities) |> Option.getWithDefault({x = -1.0, y = -1.0})
    def colliderOf(id: EntityId, world: World): Option[Collision.Collider] =
        let World.World(w) = world; Map.get(id, w#colliders)
    def spriteOf(id: EntityId, world: World): Option[SpriteComp] =
        let World.World(w) = world; Map.get(id, w#sprites)

    def sampleWorld(): World =
        let World.World(w0) = World.empty();
        let playing = World.World({phase = GamePhase.Playing, score = 7,
                                   timers = {mobSpawn = 0.3, startDelay = 0.0,
                                             score = 0.5, gameOverMsg = 0.0, title = 0.0} | w0});
        let withPlayer = World.spawnPlayer({x = 240.0, y = 450.0}, 30.0, playing);   // id 0
        let m1 = World.addMob({x = 100.0, y = 50.0}, {x = 0.0, y = 120.0},
                              World.mobSprite("fly", "enemyFlyingAlt_1", "enemyFlyingAlt_2"), 30.0, withPlayer); // id 1
        World.addMob({x = 300.0, y = 80.0}, {x = -40.0, y = 90.0},
                     World.mobSprite("walk", "enemyWalking_1", "enemyWalking_2"), 30.0, m1)  // id 2

    // ── 主要フィールド＋resource ──
    @Test
    def testWorldRoundTripFields(): Unit \ Assert =
        let original = sampleWorld();
        let restored = roundTrip(original);
        let World.World(o) = original;
        let World.World(r) = restored;
        let ok =
            Map.size(r#positions) == Map.size(o#positions) and
            Map.size(r#velocities) == Map.size(o#velocities) and
            Set.size(r#mobs) == Set.size(o#mobs) and
            r#player == o#player and r#score == 7 and r#phase == GamePhase.Playing and r#nextId == o#nextId and
            posOf(0, restored)#x == 240.0 and posOf(0, restored)#y == 450.0 and
            velOf(1, restored)#y == 120.0 and velOf(2, restored)#x == -40.0;
        Assert.assertEq(expected = true, ok)

    // ── timers 全5フィールド ──
    @Test
    def testTimersRoundTrip(): Unit \ Assert =
        let World.World(r) = roundTrip(sampleWorld());
        let t = r#timers;
        Assert.assertEq(expected = true,
            t#mobSpawn == 0.3 and t#score == 0.5 and t#startDelay == 0.0 and
            t#gameOverMsg == 0.0 and t#title == 0.0)

    // ── sprite の clips（ネスト Map）中身 ──
    @Test
    def testSpriteClipsRoundTrip(): Unit \ Assert =
        let restored = roundTrip(sampleWorld());
        let ok = match spriteOf(1, restored) {
            case Some(sc) => sc#current == "fly" and
                             World.currentTexture(sc) == "enemyFlyingAlt_1" and
                             (Map.get("fly", sc#clips) |> Option.map(List.length) |> Option.getWithDefault(0)) == 2
            case None     => false
        };
        Assert.assertEq(expected = true, ok)

    // ── collider の circle radius / layer / mask ──
    @Test
    def testColliderCircleRoundTrip(): Unit \ Assert =
        let restored = roundTrip(sampleWorld());
        let ok = match colliderOf(0, restored) {
            case Some(c) => c#layer == World.playerLayer() and c#mask == World.mobLayer() and circleRadiusIs(c, 30.0)
            case None    => false
        };
        Assert.assertEq(expected = true, ok)

    def circleRadiusIs(c: Collision.Collider, r: Float64): Bool = match c#shape {
        case CollisionShape2D.CircleShape2D(s) => s#radius == r
        case _                                 => false
    }

    // ── rect / capsule shape の codec パス（dodge 本編は circle のみなので明示テスト）──
    def worldWithCollider(col: Collision.Collider): World =
        let World.World(w) = World.empty();
        World.World({ positions = Map#{ 5 => {x = 10.0, y = 10.0} }, colliders = Map#{ 5 => col } | w })

    @Test
    def testRectColliderRoundTrip(): Unit \ Assert =
        let rect: Collision.Collider =
            {shape = CollisionShape2D.RectShape2D({width = 40.0, height = 20.0}), layer = 1i32, mask = 2i32};
        let restored = roundTrip(worldWithCollider(rect));
        let ok = match colliderOf(5, restored) {
            case Some(c) => rectIs(c, 40.0, 20.0)
            case None    => false
        };
        Assert.assertEq(expected = true, ok)

    def rectIs(c: Collision.Collider, w: Float64, h: Float64): Bool = match c#shape {
        case CollisionShape2D.RectShape2D(s) => s#width == w and s#height == h
        case _                               => false
    }

    @Test
    def testCapsuleColliderRoundTrip(): Unit \ Assert =
        let cap: Collision.Collider =
            {shape = CollisionShape2D.CapsuleShape2D({radius = 8.0, height = 30.0, vertical = true}),
             layer = 1i32, mask = 0i32};
        let restored = roundTrip(worldWithCollider(cap));
        let ok = match colliderOf(5, restored) {
            case Some(c) => capsuleIs(c, 8.0, 30.0, true)
            case None    => false
        };
        Assert.assertEq(expected = true, ok)

    def capsuleIs(c: Collision.Collider, r: Float64, h: Float64, v: Bool): Bool = match c#shape {
        case CollisionShape2D.CapsuleShape2D(s) => s#radius == r and s#height == h and s#vertical == v
        case _                                  => false
    }

    // ── 空 World 境界 ──
    @Test
    def testEmptyWorldRoundTrip(): Unit \ Assert =
        let restored = WorldCodec.encodeWorld(World.empty()) |> WorldCodec.decodeWorld;
        let ok = match restored {
            case Some(World.World(r)) => Map.isEmpty(r#positions) and r#score == 0 and r#phase == GamePhase.Menu
            case None                 => false
        };
        Assert.assertEq(expected = true, ok)
}
