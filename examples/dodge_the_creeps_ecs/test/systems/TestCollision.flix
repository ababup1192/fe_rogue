// Collision モジュールのテスト — detectCollisions（broadphase＋layer/mask＋narrowphase）
// dodge の collider は全て円 r30 なので cellSize = 2×30 = 60（境界は 60 の倍数）。

mod TestCollision {

    def player(): Collision.Collider = World.circleCollider(30.0, World.playerLayer(), World.mobLayer())
    def mob(): Collision.Collider    = World.circleCollider(30.0, World.mobLayer(), 0i32)

    /// 重なる player×mob（layer/mask 一致）はペアとして1回だけ検出される。
    @Test
    def testDetectsOverlappingMatched(): Unit \ Assert =
        let positions = Map#{ 0 => {x = 100.0, y = 100.0}, 1 => {x = 110.0, y = 100.0} };
        let colliders = Map#{ 0 => player(), 1 => mob() };
        let pairs = Collision.detectCollisions(positions, colliders);
        Assert.assertEq(expected = true, List.memberOf((0, 1), pairs) and List.length(pairs) == 1)

    /// 離れていれば（別セル・非重なり）ペアは出ない。
    @Test
    def testNoPairWhenFar(): Unit \ Assert =
        let positions = Map#{ 0 => {x = 0.0, y = 0.0}, 1 => {x = 500.0, y = 500.0} };
        let colliders = Map#{ 0 => player(), 1 => mob() };
        Assert.assertEq(expected = true, List.isEmpty(Collision.detectCollisions(positions, colliders)))

    /// 重なっていても mob×mob（mask=0 同士）は layer/mask で除外される。
    @Test
    def testLayerMaskExcludesMobMob(): Unit \ Assert =
        let positions = Map#{ 0 => {x = 100.0, y = 100.0}, 1 => {x = 110.0, y = 100.0} };
        let colliders = Map#{ 0 => mob(), 1 => mob() };
        Assert.assertEq(expected = true, List.isEmpty(Collision.detectCollisions(positions, colliders)))

    /// セル境界（60 の倍数）をまたぐ重なりも broadphase の近傍探索で検出され、重複しない。
    @Test
    def testBroadphaseAcrossCellBoundary(): Unit \ Assert =
        let positions = Map#{ 0 => {x = 59.0, y = 100.0}, 1 => {x = 61.0, y = 100.0} };
        let colliders = Map#{ 0 => player(), 1 => mob() };
        let pairs = Collision.detectCollisions(positions, colliders);
        Assert.assertEq(expected = true, List.memberOf((0, 1), pairs) and List.length(pairs) == 1)

    /// 負座標（画面外）でも cell 割り当て（floor）が破綻せず検出できる。
    @Test
    def testNegativeCoords(): Unit \ Assert =
        let positions = Map#{ 0 => {x = -100.0, y = -100.0}, 1 => {x = -90.0, y = -100.0} };
        let colliders = Map#{ 0 => player(), 1 => mob() };
        Assert.assertEq(expected = true, List.memberOf((0, 1), Collision.detectCollisions(positions, colliders)))

    /// 逆方向: id0=mob(mask0) / id1=player(mask=mob)。masksMatch の第2項 (b#mask & a#layer) を踏む。
    @Test
    def testReverseMaskDirection(): Unit \ Assert =
        let positions = Map#{ 0 => {x = 100.0, y = 100.0}, 1 => {x = 110.0, y = 100.0} };
        let colliders = Map#{ 0 => mob(), 1 => player() };
        Assert.assertEq(expected = true, List.memberOf((0, 1), Collision.detectCollisions(positions, colliders)))
}
