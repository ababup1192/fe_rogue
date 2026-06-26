// PlayerSystem — 入力でプレイヤーの velocity を設定し、別途 position をクランプする
//
// 「意図→積分→制約」の分解:
//   playerInputSystem … 入力(WASD/矢印)を velocity[player] に書くだけ（\ GameEngine.Game）
//   moveSystem        … position を velocity で一律積分（MobSystem 側・Query.updateWith2）
//   clampPlayerSystem … player の position だけ画面内へクランプ（mob は対象外＝画面外で despawn）
// 描画クリップ（walk/up＋flip）は velocity を見て AnimSystem 側が選ぶ。

mod PlayerSystem {

    def speed(): Float64 = 400.0
    def playerRadius(): Float64 = 30.0
    def toF(i: Int32): Float64 = Int32.toFloat64(i)

    /// 入力 → velocity[player]。位置は触らない（積分は moveSystem）。
    pub def playerInputSystem(world: World): World \ GameEngine.Game =
        let World.World(w) = world;
        if (w#phase != GamePhase.Playing) world
        else match w#player {
            case None      => world
            case Some(pid) => setPlayerVelocity(pid, world)
        }

    def setPlayerVelocity(pid: EntityId, world: World): World \ GameEngine.Game =
        let World.World(w) = world;
        let dir = readInputDirection();
        let vel = Vec2.mul(normalizeDir(dir), speed());
        World.World({velocities = Map.insert(pid, vel, w#velocities) | w})

    /// player の position だけ画面内へクランプする（mob は対象外）。
    pub def clampPlayerSystem(world: World): World =
        let World.World(w) = world;
        match w#player {
            case None      => world
            case Some(pid) => clampPlayerPos(pid, world)
        }

    def clampPlayerPos(pid: EntityId, world: World): World =
        let World.World(w) = world;
        match Map.get(pid, w#positions) {
            case None    => world
            case Some(p) => World.World({positions = Map.insert(pid, clampToScreen(p), w#positions) | w})
        }

    def normalizeDir(dir: Vec2.Vec2): Vec2.Vec2 =
        if (Vec2.length(dir) > 0.0) Vec2.normalized(dir) else dir

    pub def startPosition(): Vec2.Vec2 = {x = 240.0, y = 450.0}
    pub def playerRadiusOf(): Float64 = playerRadius()

    def readInputDirection(): Vec2.Vec2 \ GameEngine.Game =
        let xDir =
            axis(GameEngine.Key.D, 1.0) + axis(GameEngine.Key.Right, 1.0) +
            axis(GameEngine.Key.A, -1.0) + axis(GameEngine.Key.Left, -1.0);
        let yDir =
            axis(GameEngine.Key.S, 1.0) + axis(GameEngine.Key.Down, 1.0) +
            axis(GameEngine.Key.W, -1.0) + axis(GameEngine.Key.Up, -1.0);
        {x = xDir, y = yDir}

    def axis(key: GameEngine.Key, v: Float64): Float64 \ GameEngine.Game =
        if (GameEngine.Game.isKeyPressed(key)) v else 0.0

    def clampToScreen(pos: Vec2.Vec2): Vec2.Vec2 =
        let r = playerRadius();
        let w = toF(World.designWi()) - r;
        let h = toF(World.designHi()) - r;
        {x = Float64.max(r, Float64.min(pos#x, w)),
         y = Float64.max(r, Float64.min(pos#y, h))}
}
