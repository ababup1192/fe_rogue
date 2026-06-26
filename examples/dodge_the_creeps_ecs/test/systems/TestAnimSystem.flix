// AnimSystem のテスト（純粋）— フレーム送り / プレイヤーのクリップ・flip 選択

mod TestAnimSystem {

    def aMob(): SpriteComp = World.mobSprite("fly", "enemyFlyingAlt_1", "enemyFlyingAlt_2")

    def spriteOf(id: EntityId, world: World): Option[SpriteComp] =
        let World.World(w) = world;
        Map.get(id, w#sprites)

    /// fps=5（interval 0.2）の 2 フレーム clip を 0.25 秒進めると frame=1 に送られる
    @Test
    def testFrameAdvances(): Unit \ Assert =
        let w0 = World.addMob({x = 100.0, y = 100.0}, Vec2.zero(), aMob(), 30.0, World.empty());
        let after = AnimSystem.animSystem(0.25, w0);
        let frame = spriteOf(0, after) |> Option.map(s -> s#frame) |> Option.getWithDefault(-1);
        Assert.assertEq(expected = 1, frame)

    /// interval 未満（0.1 < 0.2）ではフレームは進まない
    @Test
    def testFrameHoldsUnderInterval(): Unit \ Assert =
        let w0 = World.addMob({x = 100.0, y = 100.0}, Vec2.zero(), aMob(), 30.0, World.empty());
        let after = AnimSystem.animSystem(0.1, w0);
        let frame = spriteOf(0, after) |> Option.map(s -> s#frame) |> Option.getWithDefault(-1);
        Assert.assertEq(expected = 0, frame)

    /// player が左移動(vx<0)なら clip=walk・flipH=true
    @Test
    def testPlayerWalkLeftFlips(): Unit \ Assert =
        let withPlayer = World.spawnPlayer({x = 200.0, y = 200.0}, 30.0, World.empty());
        let World.World(w) = withPlayer;
        let moving = World.World({velocities = Map.insert(0, {x = -100.0, y = 0.0}, w#velocities) | w});
        let after = AnimSystem.animSystem(0.0, moving);   // dt=0 でクリップ選択だけを見る
        let sc = spriteOf(0, after) |> Option.getWithDefault(World.playerSprite());
        Assert.assertEq(expected = true, sc#current == "walk" and sc#flipH == true)

    /// player が下移動(vx=0, vy>0)なら clip=up・flipV=true
    @Test
    def testPlayerUpDown(): Unit \ Assert =
        let withPlayer = World.spawnPlayer({x = 200.0, y = 200.0}, 30.0, World.empty());
        let World.World(w) = withPlayer;
        let moving = World.World({velocities = Map.insert(0, {x = 0.0, y = 80.0}, w#velocities) | w});
        let after = AnimSystem.animSystem(0.0, moving);
        let sc = spriteOf(0, after) |> Option.getWithDefault(World.playerSprite());
        Assert.assertEq(expected = true, sc#current == "up" and sc#flipV == true)
}
