// MobSystem — モブの spawn / move / despawn
//
// 旧 node 版がエンジンに任せていた処理は共有 lib flix_engine_ecs に寄せた:
//   移動（RigidBody2D 積分）        → Motion.integrate
//   画面外検出（VisibleOnScreenNotifier2D）→ Viewport.offscreenEntities
// この System 群は「lib のクエリを呼んでゲーム固有の応答（mob を despawn 等）をする」だけ。
// spawn の幾何（端サンプリング＋速度）は純粋関数 mobFromRandom に切り出してテスト可能にする。

mod MobSystem {

    // ── 定数 ──
    def spawnInterval(): Float64 = 0.5     // 秒ごとに 1 体
    def minSpeed(): Float64 = 150.0
    def maxSpeed(): Float64 = 250.0
    def mobRadius(): Float64 = 30.0
    def despawnMargin(): Float64 = 64.0

    def toF(i: Int32): Float64 = Int32.toFloat64(i)
    def halfPi(): Float64 = Vec2.pi() / 2.0

    def screenBounds(): Viewport.Bounds =
        Viewport.bounds(toF(World.designWi()), toF(World.designHi()))

    // ── 移動: position を velocity で積分（lib の Motion に委譲）──
    // player の velocity は直前の playerInputSystem が設定済み。画面端クランプは clampPlayerSystem。
    // 不変条件: GameOver 時は collisionSystem が player を despawn 済みなのでドリフトしない。

    pub def moveSystem(dt: Float64, world: World): World =
        let World.World(w) = world;
        World.World({positions = Motion.integrate(w#positions, w#velocities, dt) | w})

    // ── 画面外破棄: lib の Viewport で画面外 id を取り、mob だけ despawn する ──
    // （player は clampPlayerSystem で画面内に留まるので実際には対象にならないが、念のため絞る）

    pub def despawnOffscreenSystem(world: World): World =
        let World.World(w) = world;
        // 旧 isOffscreen の「positions に居ない mob も画面外扱い」防御は外した。
        // addMob/removeEntity が positions と mobs を同時更新し mobs ⊆ keys(positions) が常に成立するため。
        let dead = Viewport.offscreenEntities(w#positions, screenBounds(), despawnMargin())
            |> List.filter(id -> Set.memberOf(id, w#mobs));
        List.foldLeft((acc, id) -> World.removeEntity(id, acc), world, dead)

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
            let r = Clock.tick(w#timers#mobSpawn, dt, spawnInterval());
            if (r#fired) doSpawn(r#rest, world)
            else World.World({timers = {mobSpawn = r#rest | w#timers} | w})
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
