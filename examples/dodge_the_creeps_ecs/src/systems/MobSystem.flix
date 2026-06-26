// MobSystem — モブの spawn / move / despawn
//
// 旧 node 版の RigidBody2D 物理積分・Timer ノード・VisibleOnScreenNotifier2D を
// 3 つの小さな System に畳む。spawn の幾何（端サンプリング＋速度）は純粋関数
// mobFromRandom に切り出してテスト可能にし、乱数は spawnSystem 側で引いて渡す。

mod MobSystem {

    // ── 定数 ──
    def spawnInterval(): Float64 = 0.5     // 秒ごとに 1 体
    def minSpeed(): Float64 = 150.0
    def maxSpeed(): Float64 = 250.0
    def mobRadius(): Float64 = 30.0
    def despawnMargin(): Float64 = 64.0

    def toF(i: Int32): Float64 = Int32.toFloat64(i)
    def halfPi(): Float64 = Vec2.pi() / 2.0

    // ── 移動（純粋）: position を持つ全 entity（mob＋player）を velocity で一律に積分する ──
    // positions には mob と player しか入らない（HUD は huds 側で position 無し）ので、
    // 「両方持つものを更新する」Query.updateWith2 がそのまま正しい。player の velocity は
    // 直前の playerInputSystem が入力から設定済み。画面端クランプは clampPlayerSystem が担う。
    // 不変条件: phase ガードを持たないが、GameOver 時は collisionSystem が player を despawn
    // 済み（positions から除去）なので、死後に player が積分でドリフトすることはない。

    pub def moveSystem(dt: Float64, world: World): World =
        let World.World(w) = world;
        let newPos = Query.updateWith2(w#positions, w#velocities,
            (p, v) -> Vec2.add(p, Vec2.mul(v, dt)));
        World.World({positions = newPos | w})

    // ── 画面外破棄（純粋）──

    pub def despawnOffscreenSystem(world: World): World =
        let World.World(w) = world;
        let dead = Set.toList(w#mobs)
            |> List.filter(id -> isOffscreen(Map.get(id, w#positions)));
        List.foldLeft((acc, id) -> World.removeEntity(id, acc), world, dead)

    def isOffscreen(posOpt: Option[Vec2.Vec2]): Bool =
        let m = despawnMargin();
        let w = toF(World.designWi());
        let h = toF(World.designHi());
        match posOpt {
            case None    => true
            case Some(p) => p#x < (0.0 - m) or p#x > (w + m) or
                            p#y < (0.0 - m) or p#y > (h + m)
        }

    // ── spawn の幾何（純粋）: 4 つの乱数 [0,1) から 1 体分のデータを作る ──

    pub def mobFromRandom(tEdge: Float64, speedR: Float64,
                          jitterR: Float64, typeR: Float64):
            {pos = Vec2.Vec2, vel = Vec2.Vec2, sprite = SpriteComp, radius = Float64} =
        let edge = edgePoint(tEdge);
        let speed = minSpeed() + speedR * (maxSpeed() - minSpeed());
        let jitter = (jitterR - 0.5) * halfPi();   // ±π/4
        let dir = edge#inward + jitter;
        let vel = {x = Vec2.cos(dir) * speed, y = Vec2.sin(dir) * speed};
        let (anim, t1, t2) = pickType(typeR);
        {pos = edge#pos, vel = vel,
         sprite = World.mobSprite(anim, t1, t2), radius = mobRadius()}

    /// 周長パラメータ t∈[0,1) を矩形の縁の点＋内向き角に写す。
    def edgePoint(t: Float64): {pos = Vec2.Vec2, inward = Float64} =
        let w = toF(World.designWi());
        let h = toF(World.designHi());
        if (t < 0.25)
            {pos = {x = w * (t / 0.25), y = 0.0}, inward = halfPi()}            // top → 下
        else if (t < 0.5)
            {pos = {x = w, y = h * ((t - 0.25) / 0.25)}, inward = Vec2.pi()}    // right → 左
        else if (t < 0.75)
            {pos = {x = w * ((t - 0.5) / 0.25), y = h}, inward = 0.0 - halfPi()} // bottom → 上
        else
            {pos = {x = 0.0, y = h * ((t - 0.75) / 0.25)}, inward = 0.0}        // left → 右

    def pickType(r: Float64): (String, String, String) =
        if (r < 0.3333)      ("fly",  "enemyFlyingAlt_1", "enemyFlyingAlt_2")
        else if (r < 0.6666) ("walk", "enemyWalking_1",   "enemyWalking_2")
        else                 ("swim", "enemySwimming_1",  "enemySwimming_2")

    // ── spawn System（\ Math.Random）: timer-gated でモブを湧かせる ──

    pub def spawnSystem(dt: Float64, world: World): World \ Math.Random =
        let World.World(w) = world;
        if (w#phase != GamePhase.Playing or w#timers#startDelay > 0.0)
            world
        else {
            let acc = w#timers#mobSpawn + dt;
            if (acc < spawnInterval())
                World.World({timers = {mobSpawn = acc | w#timers} | w})
            else
                doSpawn(acc - spawnInterval(), world)
        }

    def doSpawn(accLeft: Float64, world: World): World \ Math.Random =
        let tEdge   = Math.Random.randomFloat64();
        let speedR  = Math.Random.randomFloat64();
        let jitterR = Math.Random.randomFloat64();
        let typeR   = Math.Random.randomFloat64();
        let m = mobFromRandom(tEdge, speedR, jitterR, typeR);
        let World.World(w) = world;
        let withTimer = World.World({timers = {mobSpawn = accLeft | w#timers} | w});
        World.addMob(m#pos, m#vel, m#sprite, m#radius, withTimer)
}
