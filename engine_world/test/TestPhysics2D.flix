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

    // ========================================================================
    // 坂とカプセル — detect が新形状の接触を報告し、separate が動く側だけ押し出す
    // ========================================================================

    def rect(w: Float64, h: Float64): CollisionShape2D =
        CollisionShape2D.RectShape2D({ width = w, height = h })
    def capsule(radius: Float64, height: Float64): CollisionShape2D =
        CollisionShape2D.CapsuleShape2D({ radius = radius, height = height, vertical = true })
    def slope(w: Float64, h: Float64): CollisionShape2D =
        CollisionShape2D.SlopeShape2D({ width = w, height = h, riseRight = true })

    // 斜辺の法線は無理数成分を持つので小数 4 桁へ丸めて比較する。
    def round4(x: Float64): Float64 = Float64.floor(x * 10000.0 + 0.5) / 10000.0
    def xyRound4(v: Vec2.Vec2): (Float64, Float64) = (round4(v#x), round4(v#y))

    // 45° 坂（右登り）の斜辺にめり込んだ円。法線は斜辺の外向き (-1,-1)/√2 = y が負（上向きの押し出し）。
    // 円は斜辺中点 (0,0) から法線方向へ 6 の位置・半径 8 → めり込み 2。
    @Test
    def testDetectCircleOnSlopeNormal(): Unit \ Assert =
        let n = Vec2.normalized(vec(-1.0, -1.0));
        let positions = store((ball(), Vec2.mul(n, 6.0)) :: (wall(), vec(0.0, 0.0)) :: Nil);
        let shapes    = store((ball(), circle(8.0)) :: (wall(), slope(32.0, 32.0)) :: Nil);
        let actual = List.map(c -> (c#a, c#b, xyRound4(c#normal), round4(c#penetration)),
                              Physics2D.detect(positions, shapes));
        Assert.assertEq(expected = (ball(), wall(), (-0.7071, -0.7071), 2.0) :: Nil, actual)

    // separate は速度を持つ円だけを坂の外（中心距離 = 半径 8）まで押し出し、坂は動かない。
    @Test
    def testSeparateCircleFromSlopePushesOnlyCircle(): Unit \ Assert =
        let n = Vec2.normalized(vec(-1.0, -1.0));
        let positions  = store((ball(), Vec2.mul(n, 6.0)) :: (wall(), vec(0.0, 0.0)) :: Nil);
        let shapes     = store((ball(), circle(8.0)) :: (wall(), slope(32.0, 32.0)) :: Nil);
        let velocities = store((ball(), vec(1.0, 0.0)) :: Nil);   // 坂は不在 = 静止
        let contacts = Physics2D.detect(positions, shapes);
        let separated = Physics2D.separate(contacts, velocities, positions);
        let actual = (Option.map(xyRound4, Map.get(ball(), separated)), posXY(wall(), separated));
        Assert.assertEq(expected = (Some((-5.6569, -5.6569)), Some((0.0, 0.0))), actual)

    // カプセル（速度あり）が静的な矩形にめり込む → separate でカプセルだけが -x へ 1 動く。
    // カプセルは以前 MTV を返せず分離できなかった（この修正の主目的）。
    @Test
    def testSeparateCapsuleFromStaticRect(): Unit \ Assert =
        let positions  = store((ball(), vec(0.0, 0.0)) :: (wall(), vec(5.0, 0.0)) :: Nil);
        let shapes     = store((ball(), capsule(2.0, 10.0)) :: (wall(), rect(8.0, 8.0)) :: Nil);
        let velocities = store((ball(), vec(1.0, 0.0)) :: Nil);   // 矩形は不在 = 静止
        let contacts = Physics2D.detect(positions, shapes);
        let separated = Physics2D.separate(contacts, velocities, positions);
        Assert.assertEq(expected = (Some((-1.0, 0.0)), Some((5.0, 0.0))),
                        (posXY(ball(), separated), posXY(wall(), separated)))

    // カプセルと円の接触。軸間距離 3・半径和 4 → 法線 (-1,0)（単位長）とめり込み 1。
    @Test
    def testDetectCapsuleCircleContact(): Unit \ Assert =
        let positions = store((ball(), vec(0.0, 0.0)) :: (wall(), vec(3.0, 0.0)) :: Nil);
        let shapes    = store((ball(), capsule(2.0, 10.0)) :: (wall(), circle(2.0)) :: Nil);
        let actual = List.map(c -> (c#a, c#b, xyRound4(c#normal), round4(c#penetration)),
                              Physics2D.detect(positions, shapes));
        Assert.assertEq(expected = (ball(), wall(), (-1.0, 0.0), 1.0) :: Nil, actual)

    // ========================================================================
    // normalToward / slide / contactsAlong — 接触の読み取り補助
    // ========================================================================

    // 法線は「その id を押し出す向き」: a 側はそのまま、b 側は反転して返る。
    @Test
    def testNormalTowardFlipsForSideB(): Unit \ Assert =
        let contact = { a = ball(), b = wall(), normal = vec(0.0, -1.0),
                        point = vec(0.0, 0.0), penetration = 1.0 };
        Assert.assertEq(expected = ((0.0, -1.0), (0.0, 1.0)),
            (xy(Physics2D.normalToward(ball(), contact)),
             xy(Physics2D.normalToward(wall(), contact))))

    // slide は面に近づく法線成分だけ消す: 床（法線 0,-1）へ落ちながら走る速度 (100, 50) は
    // vy だけ消えて (100, 0) — 慣性が残る。離れる向き (100, -50) は触らない。
    @Test
    def testSlideKillsOnlyApproachingComponent(): Unit \ Assert =
        let floor = { a = ball(), b = wall(), normal = vec(0.0, -1.0),
                      point = vec(0.0, 0.0), penetration = 1.0 };
        Assert.assertEq(expected = ((100.0, 0.0), (100.0, -50.0)),
            (xy(Physics2D.slide(ball(), floor :: Nil, vec(100.0, 50.0))),
             xy(Physics2D.slide(ball(), floor :: Nil, vec(100.0, -50.0)))))

    // slide は検出順に畳む: 床 → 右壁の 2 接触で vy が消えたあと vx も消えて (0, 0)。
    @Test
    def testSlideFoldsContactsInOrder(): Unit \ Assert =
        let floor = { a = ball(), b = wall(), normal = vec(0.0, -1.0),
                      point = vec(0.0, 0.0), penetration = 1.0 };
        let rightWall = { a = ball(), b = wall(), normal = vec(-1.0, 0.0),
                          point = vec(0.0, 0.0), penetration = 1.0 };
        Assert.assertEq(expected = (0.0, 0.0),
            xy(Physics2D.slide(ball(), floor :: rightWall :: Nil, vec(100.0, 50.0))))

    // contactsAlong はしきい値ちょうどを含まない（>）: dot = 0.6 ぴったりの接触は落ち、
    // 真上向きの床接触（dot = 1.0）だけが残る。
    @Test
    def testContactsAlongThresholdIsStrict(): Unit \ Assert =
        let flatFloor = { a = ball(), b = wall(), normal = vec(0.0, -1.0),
                          point = vec(0.0, 0.0), penetration = 1.0 };
        let atThreshold = { a = ball(), b = wall(), normal = vec(0.8, -0.6),
                            point = vec(0.0, 0.0), penetration = 1.0 };
        let kept = Physics2D.contactsAlong(ball(), vec(0.0, -1.0), 0.6,
                                           flatFloor :: atThreshold :: Nil);
        Assert.assertEq(expected = (0.0, -1.0) :: Nil,
            List.map(c -> xy(c#normal), kept))
}
