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

    /// timeline の i 番目の jumpHeld（踏みバウンドの可変高の印）。
    def heldAt(i: Int32, worlds: List[Field.World]): Option[Bool] =
        worlds |> List.drop(i) |> List.head |> Option.map(w -> w#player#jumpHeld)

    /// timeline の i 番目の (x, round4 した y, 時刻)。ヒットストップの凍結比較用。
    def kinAt(i: Int32, worlds: List[Field.World]): Option[(Float64, Float64, Float64)] =
        worlds |> List.drop(i) |> List.head
            |> Option.map(w -> (w#player#pos#x, round4(w#player#pos#y), w#time))

    /// プレイヤーを空中（速度ゼロ・非接地）に置き直す（落とし込みシナリオの出発点）。
    def fallingAt(x: Float64, y: Float64, world: Field.World): Field.World =
        { player = { pos = { x = x, y = y }, vel = Vec2.zero(), grounded = false,
                     coyoteLeft = 0.0, bufferLeft = 0.0, jumpHeld = false, squashLeft = 0.0,
                     facing = 1.0, ridingId = None, dropLeft = 0.0,
                     viewMode = CharStage.Mode.IdleMode, viewModeT = 0.0, guardLeft = 0, invulnLeft = 0.0 } | world }

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

    // パタパタの位置は時刻の純関数: t=0 は基準 (240,150)、t=0.5（1/4 周期）は triWave=1.0 で
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

    // ========================================================================
    // 踏みホールド大バウンス（ジャンプを押しながら踏む）とヒットストップ
    // ========================================================================

    /// ジャンプを押しっぱなしのまま n フレーム流す（押下エッジなし = バッファに入れない）。
    def holdJumpDownOnly(frames: Int32): List[Replay.Cue[Field.Input]] =
        Trace.hold({ jumpDown = true | Trace.idle() }, frames) :: Nil

    // 踏みの瞬間にジャンプを押していると大バウンド: walker と同じ落とし方（f11 で踏み）でも
    // そのフレームの縦速度は -480.0（厳密値・通常の -320 より高い）になり、jumpHeld が立つ
    // （あとで離すと上昇カットが効く印）。押しっぱなしはエッジではないのでバッファに入らず、
    // ジャンプの成立を横取りしない（jump は一度も鳴らない）。
    @Test
    def testStompHoldBigBounce(): Unit \ Assert =
        let worlds = timeline(holdJumpDownOnly(60), fallingAt(240.0, 140.0, Trace.walkerWorld()));
        Assert.assertEq(expected = (true, false, false, Some(-480.0), Some(true)),
            (eventHappened("stomp", worlds), eventHappened("death", worlds),
             eventHappened("jump", worlds), vyAt(11, worlds), heldAt(11, worlds)))

    // 大バウンスは可変高（ジャンプと同じカット経路）: 踏み f11（-480）→ 凍結 f12-14 →
    // f15 は押したまま上昇（重力だけ掛かって -458.6667）→ f16 で離すと上昇カット（×0.4）で
    // -162.1333 になり jumpHeld が下りる（round4・probe 実測）。
    @Test
    def testStompHoldReleaseCutsBounce(): Unit \ Assert =
        let cues = List.append(holdJumpDownOnly(16), Trace.flight(44));
        let worlds = timeline(cues, fallingAt(240.0, 140.0, Trace.walkerWorld()));
        Assert.assertEq(expected = (Some(-458.6667), Some(-162.1333), Some(false)),
            (vyAt(15, worlds) |> Option.map(round4), vyAt(16, worlds) |> Option.map(round4),
             heldAt(16, worlds)))

    // 通常踏み（ジャンプを押していない）は従来のまま: バウンド -320.0 で jumpHeld は
    // 立たない（あとで離しても上昇カットは掛からない）。
    @Test
    def testStompNormalKeepsJumpHeldFalse(): Unit \ Assert =
        let worlds = timeline(Trace.flight(60), fallingAt(240.0, 140.0, Trace.walkerWorld()));
        Assert.assertEq(expected = (Some(-320.0), Some(false)),
            (vyAt(11, worlds), heldAt(11, worlds)))

    // ヒットストップ: 踏み（f11・位置 (240,168.6)・時刻 0.1875）の直後 3 コマ（f12-14）は
    // 世界が丸ごと止まる — 位置も時刻も f11 と同一（時刻が同じ = 時刻の純関数で動く敵・床も
    // 止まる）で、events は空（stomp の音は f11 の 1 回だけ）。f15 から再開して時刻が進む
    // （0.203125 = 0.1875 + 1/64）。
    @Test
    def testHitStopFreezesThreeFrames(): Unit \ Assert =
        let worlds = timeline(Trace.flight(60), fallingAt(240.0, 140.0, Trace.walkerWorld()));
        let frozen = Some((240.0, 168.6, 0.1875));
        Assert.assertEq(
            expected = (frozen, frozen, frozen, frozen, Some(Nil), Some(0.203125)),
            (kinAt(11, worlds), kinAt(12, worlds), kinAt(13, worlds), kinAt(14, worlds),
             worlds |> List.drop(12) |> List.head |> Option.map(Trace.eventsOf),
             worlds |> List.drop(15) |> List.head |> Option.map(w -> w#time)))

    // 凍結中の入力は無効: 凍結 1 コマ目（f12）にジャンプを押しても World は素通しで返る —
    // バッファは充填されず（0.0 のまま）、jump は鳴らず、凍結明けの隠れジャンプも起きない。
    @Test
    def testFreezeIgnoresJumpInput(): Unit \ Assert =
        let cues = List.flatten(Trace.flight(12) ::
            (Trace.hold({ jumpDown = true, jumpPressed = true | Trace.idle() }, 1) :: Nil) ::
            Trace.flight(47) :: Nil);
        let worlds = timeline(cues, fallingAt(240.0, 140.0, Trace.walkerWorld()));
        Assert.assertEq(expected = (Some(0.0), true, false),
            (worlds |> List.drop(12) |> List.head |> Option.map(w -> w#player#bufferLeft),
             eventHappened("stomp", worlds), eventHappened("jump", worlds)))

    // ========================================================================
    // 死んだ敵・物理への不干渉・同フレームの規則（続き）
    // ========================================================================

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
