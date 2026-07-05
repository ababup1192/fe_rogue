// TestPhysics2D — 合成可能な 4 つの純関数（integrate・detect・bounce・separate）を関数ごとに固定する。
// 物体は「位置・速度・形・反発」を別々の店に置いて組み立て、店の在・不在から振る舞いが決まることを確かめる。
// 反射後の速度は法線が軸に沿うので符号反転 = 誤差なく厳密な値になる（比較は成分の (x, y) 組で行う）。

mod TestPhysics2D {

    // ── 組み立て補助 ──

    def vec(x: Float64, y: Float64): Vec2.Vec2 = { x = x, y = y }
    def xy(v: Vec2.Vec2): (Float64, Float64) = (v#x, v#y)

    def circle(radius: Float64): CollisionShape2D = CollisionShape2D.CircleShape2D({ radius = radius })

    def store(pairs: List[(EntityId, v)]): Map[EntityId, v] = List.toMap(pairs)

    def posXY(id: EntityId, positions: Map[EntityId, Vec2.Vec2]): Option[(Float64, Float64)] =
        Map.get(id, positions) |> Option.map(xy)
    def velXY(id: EntityId, velocities: Map[EntityId, Vec2.Vec2]): Option[(Float64, Float64)] =
        Map.get(id, velocities) |> Option.map(xy)

    // 登場する entity。
    def ball(): EntityId = 1
    def wall(): EntityId = 2

    // ========================================================================
    // integrate — 速度を持つものだけ動く（静止は「速度の店に不在」で表す）
    // ========================================================================

    // ball は速度を持つので進み、wall は velocities に居ないので静止したまま = 静的性の創発。
    @Test
    def testIntegrateMovesOnlyThoseWithVelocity(): Unit \ Assert =
        let positions  = store((ball(), vec(0.0, 0.0)) :: (wall(), vec(5.0, 5.0)) :: Nil);
        let velocities = store((ball(), vec(10.0, 20.0)) :: Nil);        // wall は不在
        let moved = Physics2D.integrate(1.0, velocities, positions);
        // ball は (10, 20) へ、wall は (5, 5) のまま。
        Assert.assertEq(expected = (Some((10.0, 20.0)), Some((5.0, 5.0))),
                        (posXY(ball(), moved), posXY(wall(), moved)))

    // ========================================================================
    // detect — 重なりを接触として集める（検出だけ）
    // ========================================================================

    // 距離 5 で半径 2+4 の 2 円は重なる。接触は a を b から離す法線（b が右なので左向き）と
    // めり込み 1 を報告する。
    @Test
    def testDetectReportsPairNormalAndPenetration(): Unit \ Assert =
        let positions = store((ball(), vec(0.0, 0.0)) :: (wall(), vec(5.0, 0.0)) :: Nil);
        let shapes    = store((ball(), circle(2.0)) :: (wall(), circle(4.0)) :: Nil);
        let actual = List.map(c -> (c#a, c#b, xy(c#normal), c#penetration), Physics2D.detect(positions, shapes));
        Assert.assertEq(expected = (ball(), wall(), (-1.0, 0.0), 1.0) :: Nil, actual)

    // 離れた 2 体は接触ゼロ。
    @Test
    def testDetectFindsNothingWhenApart(): Unit \ Assert =
        let positions = store((ball(), vec(0.0, 0.0)) :: (wall(), vec(1000.0, 0.0)) :: Nil);
        let shapes    = store((ball(), circle(2.0)) :: (wall(), circle(4.0)) :: Nil);
        Assert.assertEq(expected = 0, List.length(Physics2D.detect(positions, shapes)))

    // ========================================================================
    // bounce — 速度を持つ側だけ反射する（相手が壁なら壁反射になる）
    // ========================================================================

    // 右の壁（法線 -1,0）への正面衝突。反発 1 なら x 成分を反転して速さを保つ (-100, 0)。
    // wall は velocities に居ないので反射せず、ball にとって壁として振る舞う。
    @Test
    def testBounceElasticFlipsX(): Unit \ Assert =
        let contact = { a = ball(), b = wall(), normal = vec(-1.0, 0.0),
                        point = vec(0.0, 0.0), penetration = 1.0 };
        let velocities  = store((ball(), vec(100.0, 0.0)) :: Nil);
        let restitutions = store((ball(), 1.0) :: Nil);
        let bounced = Physics2D.bounce(contact :: Nil, restitutions, velocities);
        Assert.assertEq(expected = Some((-100.0, 0.0)), velXY(ball(), bounced))

    // 反発 0.5 なら反射後の速さは半分 (-50, 0)。
    @Test
    def testBounceHalfRestitution(): Unit \ Assert =
        let contact = { a = ball(), b = wall(), normal = vec(-1.0, 0.0),
                        point = vec(0.0, 0.0), penetration = 1.0 };
        let bounced = Physics2D.bounce(contact :: Nil,
            store((ball(), 0.5) :: Nil), store((ball(), vec(100.0, 0.0)) :: Nil));
        Assert.assertEq(expected = Some((-50.0, 0.0)), velXY(ball(), bounced))

    // restitutions に登録が無ければ反発 0 = 跳ねずに止まる (0, 0)。
    @Test
    def testBounceWithoutRestitutionStops(): Unit \ Assert =
        let contact = { a = ball(), b = wall(), normal = vec(-1.0, 0.0),
                        point = vec(0.0, 0.0), penetration = 1.0 };
        let bounced = Physics2D.bounce(contact :: Nil,
            Map.empty(), store((ball(), vec(100.0, 0.0)) :: Nil));
        Assert.assertEq(expected = Some((0.0, 0.0)), velXY(ball(), bounced))

    // 下の床（法線 0,-1）への斜め衝突は y だけ反転し x（横進み）を保つ = 軸反射。
    @Test
    def testBounceFloorFlipsYKeepsX(): Unit \ Assert =
        let contact = { a = ball(), b = wall(), normal = vec(0.0, -1.0),
                        point = vec(0.0, 0.0), penetration = 1.0 };
        let bounced = Physics2D.bounce(contact :: Nil,
            store((ball(), 1.0) :: Nil), store((ball(), vec(30.0, 40.0)) :: Nil));
        Assert.assertEq(expected = Some((30.0, -40.0)), velXY(ball(), bounced))

    // 速度の店に居ない side は反射されない（壁は跳ね返らない）= 静的性の創発。
    @Test
    def testBounceLeavesVelocitylessSideUntouched(): Unit \ Assert =
        let contact = { a = ball(), b = wall(), normal = vec(-1.0, 0.0),
                        point = vec(0.0, 0.0), penetration = 1.0 };
        // wall は velocities に不在。bounce しても wall のエントリは生えない。
        let bounced = Physics2D.bounce(contact :: Nil,
            store((ball(), 1.0) :: Nil), store((ball(), vec(100.0, 0.0)) :: Nil));
        Assert.assertEq(expected = None, velXY(wall(), bounced))

    // ========================================================================
    // separate — めり込みを、動かせる側だけ押し出す
    // ========================================================================

    // ball は velocities に居るので法線ぶん押し出され、wall は静止なので動かない。
    @Test
    def testSeparatePushesOnlyMovableSide(): Unit \ Assert =
        let contact = { a = ball(), b = wall(), normal = vec(-1.0, 0.0),
                        point = vec(0.0, 0.0), penetration = 1.0 };
        let positions  = store((ball(), vec(0.0, 0.0)) :: (wall(), vec(5.0, 0.0)) :: Nil);
        let velocities = store((ball(), vec(100.0, 0.0)) :: Nil);          // wall は不在
        let separated = Physics2D.separate(contact :: Nil, velocities, positions);
        // ball は法線 (-1,0) ぶん (-1,0) へ、wall は (5,0) のまま。
        Assert.assertEq(expected = (Some((-1.0, 0.0)), Some((5.0, 0.0))),
                        (posXY(ball(), separated), posXY(wall(), separated)))

    // ========================================================================
    // 接触の読み取り補助 — contactsOf / touches / other
    // ========================================================================

    // 3 者（ball・wall・brick）の接触列を作る補助。ball-wall と wall-brick の 2 接触。
    def brick(): EntityId = 3

    def sampleContacts(): List[Physics2D.Contact] =
        { a = ball(), b = wall(), normal = vec(-1.0, 0.0), point = vec(0.0, 0.0), penetration = 1.0 } ::
        { a = wall(), b = brick(), normal = vec(0.0, -1.0), point = vec(5.0, 5.0), penetration = 0.5 } :: Nil

    // contactsOf は id が絡む接触だけを残す: ball は 1 件・wall は 2 件・部外者は 0 件。
    @Test
    def testContactsOfFiltersByParticipant(): Unit \ Assert =
        let counts = (List.length(Physics2D.contactsOf(ball(), sampleContacts())),
                      List.length(Physics2D.contactsOf(wall(), sampleContacts())),
                      List.length(Physics2D.contactsOf(99, sampleContacts())));
        Assert.assertEq(expected = (1, 2, 0), counts)

    // touches は「1 つでも絡んでいるか」: 当事者 3 者は true、部外者は false、空列は false。
    @Test
    def testTouchesDetectsParticipation(): Unit \ Assert =
        let actual = (Physics2D.touches(ball(), sampleContacts()),
                      Physics2D.touches(brick(), sampleContacts()),
                      Physics2D.touches(99, sampleContacts()),
                      Physics2D.touches(ball(), Nil));
        Assert.assertEq(expected = (true, true, false, false), actual)

    // other は接触の相手側: a から見れば b、b から見れば a、部外者には None。
    @Test
    def testOtherReturnsOpposingSide(): Unit \ Assert =
        let contact = { a = ball(), b = wall(), normal = vec(-1.0, 0.0),
                        point = vec(0.0, 0.0), penetration = 1.0 };
        let actual = (Physics2D.other(ball(), contact), Physics2D.other(wall(), contact),
                      Physics2D.other(99, contact));
        Assert.assertEq(expected = (Some(wall()), Some(ball()), None), actual)
}
