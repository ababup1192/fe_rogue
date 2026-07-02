// CollisionSystem — プレイヤーと mob の接触判定（純粋）
//
// 衝突“検出”は共有モジュール Collision.detectCollisions に委譲（layer/mask＋broadphase＋
// engine の checkOverlap）。この System は「player を含むペアが出たら GameOver」という
// ゲーム固有の応答だけを持つ。旧 node 版の Area2D+layer/mask+AreaHandler と同じ意味論。
// 効果音（death）は phase の立ち上がりを見て gameLoop 側が鳴らす（System は純粋に保つ）。

mod CollisionSystem {

    pub def collisionSystem(world: World): World =
        let World.World(w) = world;
        if (w#phase != GamePhase.Playing) world
        else match w#player {
            case None      => world
            case Some(pid) => checkPlayer(pid, world)
        }

    def checkPlayer(pid: EntityId, world: World): World =
        let World.World(w) = world;
        let hit = Collision.detectCollisions(w#positions, w#colliders)
            |> List.exists(pair -> involvesPlayer(pid, pair));
        if (hit) onHit(pid, world) else world

    def involvesPlayer(pid: EntityId, pair: (EntityId, EntityId)): Bool =
        let (a, b) = pair;
        a == pid or b == pid

    def onHit(pid: EntityId, world: World): World =
        let despawned = World.removeEntity(pid, world);
        let World.World(w) = despawned;
        World.World({
            phase  = GamePhase.GameOver,
            player = None,
            // gameOverMsg: "Game Over" 表示時間 / title: その後のタイトル表示時間
            timers = {gameOverMsg = 2.0, title = 1.0 | w#timers}
            | w
        })
}
