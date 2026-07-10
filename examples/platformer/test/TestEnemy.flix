// TestEnemy — 敵 3 種（歩く敵・パタパタ・トゲ）の当たりの規則を固定する（Track E）。
// 触れたら死・踏んだら倒せてバウンド・トゲは踏んでも死ぬ・死んだ敵は当たらない・
// 敵は床の物理に一切干渉しない、を具体値で pin。位置の pin は probe の実測値。
// 踏み判定 = 前フレーム（carry 後）の足元が敵の頭（上端+2px）より上 ∧ 下向きに落ちている。
// 同フレームで踏みと致命の接触が同時なら死亡が勝つ（安全側）。

mod TestEnemy {

    /// 小数 4 桁に丸める（重力の循環小数を含む値の比較用）。
    def round4(x: Float64): Float64 = Float64.floor(x * 10000.0 + 0.5) / 10000.0

    /// シナリオを最後まで流して結末の World を得る。
    def play(cues: List[Replay.Cue[Field.Input]], world: Field.World): Field.World =
        Replay.play(Step.update, Trace.dt(), cues, world)

    /// シナリオの全フレームの World（初期は含まない・1 フレーム目の結果から）。
    def timeline(cues: List[Replay.Cue[Field.Input]], world: Field.World): List[Field.World] =
        Replay.timeline(Step.update, Trace.dt(), cues, world)

    /// timeline のどこかで名前の出来事が起きたか。
    def eventHappened(name: String, worlds: List[Field.World]): Bool =
        worlds |> List.exists(w -> List.memberOf(name, Trace.eventsOf(w)))

    /// timeline の i 番目の縦速度。
    def vyAt(i: Int32, worlds: List[Field.World]): Option[Float64] =
        worlds |> List.drop(i) |> List.head |> Option.map(w -> Trace.velOf(w)#y)

    /// プレイヤーを空中（速度ゼロ・非接地）に置き直す（落とし込みシナリオの出発点）。
    def fallingAt(x: Float64, y: Float64, world: Field.World): Field.World =
        { player = { pos = { x = x, y = y }, vel = Vec2.zero(), grounded = false,
                     coyoteLeft = 0.0, bufferLeft = 0.0, jumpHeld = false, squashLeft = 0.0,
                     ridingId = None, dropLeft = 0.0 } | world }

    // ========================================================================
    // 歩く敵: 触れたら死・踏んだら倒せる
    // ========================================================================

    // 右へ 30f 歩いて止まると、折り返してきた walker に横から触れて死ぬ:
    // death が鳴り、deaths=1、出発点（Level.spawnOf の x=56）へ戻って着地する。敵は生きたまま。
    @Test
    def testWalkIntoWalkerDies(): Unit \ Assert =
        let cues = List.append(Trace.holdRight(30), Trace.flight(120));
        let worlds = timeline(cues, Trace.walkerWorld());
        let final = play(cues, Trace.walkerWorld());
        Assert.assertEq(expected = (true, 1, 56.0, Some(true)),
            (eventHappened("death", worlds), Trace.deathsOf(final),
             Trace.posOf(final)#x, Trace.enemyAliveOf(600, final)))

    // 真上（x=240, y=140）から落とすと踏める: 11 フレーム目に stomp が鳴り、敵は死に、
    // プレイヤーは死なずにそのフレームの縦速度が -320.0（半ジャンプのバウンド・厳密値）になる。
    @Test
    def testStompKillsWalkerAndBounces(): Unit \ Assert =
        let worlds = timeline(Trace.flight(60), fallingAt(240.0, 140.0, Trace.walkerWorld()));
        let final = play(Trace.flight(60), fallingAt(240.0, 140.0, Trace.walkerWorld()));
        Assert.assertEq(expected = (true, false, Some(-320.0), Some(false), 0),
            (eventHappened("stomp", worlds), eventHappened("death", worlds),
             vyAt(11, worlds), Trace.enemyAliveOf(600, final), Trace.deathsOf(final)))

    // 踏みバウンドの高さ: y=168.6 で踏んで -320 で跳ね、頂点は y=133.4333（round4・実測 pin）。
    // 落とし始めの y=140 より高く戻る = バウンドが目に見える高さである証拠。
    @Test
    def testStompBounceApex(): Unit \ Assert =
        let worlds = timeline(Trace.flight(60), fallingAt(240.0, 140.0, Trace.walkerWorld()));
        Assert.assertEq(expected = 133.4333, round4(Trace.apexOf(worlds)))

    // ========================================================================
    // パタパタ: 上下の閉形式と踏み
    // ========================================================================

    // パタパタの位置は時刻の純関数: t=0 は基準 (240,150)、t=0.5（1/4 周期）は pingPong=1.0 で
    // 頂点 y=126（基準 − 振れ幅 24・厳密値）。
    @Test
    def testFlyerBobsClosedForm(): Unit \ Assert =
        let flyer = Field.flyerAt(601, { x = 240.0, y = 150.0 }, 24.0, 2.0);
        let p0 = Field.enemyPosAt(0.0, flyer);
        let p1 = Field.enemyPosAt(0.5, flyer);
        Assert.assertEq(expected = ((240.0, 150.0), (240.0, 126.0)),
            ((p0#x, p0#y), (p1#x, p1#y)))

    // 上昇してくるパタパタの真上（x=240, y=80）から落とすと踏める（probe 実測: 13 フレーム目）:
    // stomp が鳴って敵は死に、プレイヤーは死なない。
    @Test
    def testStompFlyer(): Unit \ Assert =
        let worlds = timeline(Trace.flight(60), fallingAt(240.0, 80.0, Trace.flyerWorld()));
        let final = play(Trace.flight(60), fallingAt(240.0, 80.0, Trace.flyerWorld()));
        Assert.assertEq(expected = (true, false, Some(false), 0),
            (eventHappened("stomp", worlds), eventHappened("death", worlds),
             Trace.enemyAliveOf(601, final), Trace.deathsOf(final)))

    // ========================================================================
    // トゲ: 踏んでも死ぬ
    // ========================================================================

    // walker と同じ落とし方（真上から）でも、トゲは踏めない: stomp は鳴らず death が鳴り、
    // deaths=1 で出発点へ。トゲは生きたまま。
    @Test
    def testStompSpikyDies(): Unit \ Assert =
        let worlds = timeline(Trace.flight(60), fallingAt(240.0, 140.0, Trace.spikyWorld()));
        let final = play(Trace.flight(60), fallingAt(240.0, 140.0, Trace.spikyWorld()));
        Assert.assertEq(expected = (false, true, 1, Some(true)),
            (eventHappened("stomp", worlds), eventHappened("death", worlds),
             Trace.deathsOf(final), Trace.enemyAliveOf(602, final)))

    // ========================================================================
    // 死んだ敵・物理への不干渉・同フレームの規則
    // ========================================================================

    // 死んだ敵は当たらない: 踏んで倒したあと着地し、骸の巡回域（x 190..270）を右へ歩いて
    // 横切っても何も起きない（stomp は最初の 1 回だけ・death は一度も鳴らない）。
    @Test
    def testDeadEnemyDoesNotCollide(): Unit \ Assert =
        let cues = List.append(Trace.flight(60), Trace.holdRight(24));
        let worlds = timeline(cues, fallingAt(240.0, 140.0, Trace.walkerWorld()));
        let final = play(cues, fallingAt(240.0, 140.0, Trace.walkerWorld()));
        let stomps = worlds |> List.filter(w -> List.memberOf("stomp", Trace.eventsOf(w))) |> List.length;
        Assert.assertEq(expected = (1, false, 0, true),
            (stomps, eventHappened("death", worlds), Trace.deathsOf(final), Trace.groundedOf(final)))

    // 敵は床の物理に一切干渉しない: 触れない距離（x 20..100 を巡回）に walker が居ても、
    // 平地の静止は TestPlatformer.testIdleOnFlatGroundIsStable と同じ厳密値のまま。
    @Test
    def testEnemyDoesNotDisturbPhysics(): Unit \ Assert =
        let world = { enemies = Field.walkerAt(600, { x = 60.0, y = 190.0 }, 40.0, 4.0) :: Nil
                    | Trace.flatWorld() };
        let final = play(Trace.flight(30), world);
        Assert.assertEq(expected = (160.0, 188.0, true, 0.0),
            (Trace.posOf(final)#x, Trace.posOf(final)#y,
             Trace.groundedOf(final), Trace.velOf(final)#y))

    // 同フレームで踏みと致命の接触が同時なら死亡が勝つ（安全側）: walker への踏みが成立する
    // フレーム（f11）に、初めて重なる位置（252,184）へトゲを置くと、stomp は鳴らず death になり、
    // walker もトゲも生きたまま。
    @Test
    def testLethalContactBeatsStompSameFrame(): Unit \ Assert =
        let world = { enemies = List.append(Trace.walkerWorld()#enemies,
                                            Field.spikyAt(602, { x = 252.0, y = 184.0 }) :: Nil)
                    | fallingAt(240.0, 140.0, Trace.walkerWorld()) };
        let worlds = timeline(Trace.flight(60), world);
        let final = play(Trace.flight(60), world);
        Assert.assertEq(expected = (false, true, 1, 2),
            (eventHappened("stomp", worlds), eventHappened("death", worlds),
             Trace.deathsOf(final), Trace.aliveEnemiesOf(final)))
}
