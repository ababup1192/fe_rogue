// TestClear — Track F の勝ち筋まわりを固定する: P スピードゲート（ダッシュだけが渡れる大穴）・
// 中間地点（1 回だけ発動・以後の死亡はそこへ戻る）・クリア（1 回だけ・ゲームは続く）・
// 花火（タメ 0.6 秒 → 0.2 秒間隔で 10 発）。
// 舞台は本番レベル（Field.initialWorld）。プレイヤーだけを狙いの地点に接地で置き換えて始める
// （Trace.levelRestingPlayer）— 助走のフレーム数に依存せず、見たい規則だけを検証できる。

mod TestClear {

    def play(cues: List[Replay.Cue[Field.Input]], world: Field.World): Field.World =
        Replay.play(Step.update, Trace.dt(), cues, world)

    def timeline(cues: List[Replay.Cue[Field.Input]], world: Field.World): List[Field.World] =
        Replay.timeline(Step.update, Trace.dt(), cues, world)

    /// 名前の出来事が起きたフレーム数。
    def countEvent(name: String, worlds: List[Field.World]): Int32 =
        worlds |> List.filter(w -> List.memberOf(name, Trace.eventsOf(w))) |> List.length

    /// 本番レベルでプレイヤーだけを x の地面に接地静止させた World。
    def atGround(x: Float64): Field.World =
        { player = Trace.levelRestingPlayer(x) | Field.initialWorld() }

    /// 敵なし版。ゲートの検証は地形だけを見る（敵の歩き位相は台本の時刻に合わせてあり、
    /// テストの別時刻では対岸の歩く敵に当たり得るため外す）。
    def atGroundNoFoes(x: Float64): Field.World =
        { enemies = Nil | atGround(x) }

    // ========================================================================
    // P スピードゲート（列 144-151 の大穴 128px）
    // ========================================================================

    // ダッシュ: トゲの先（x=1700）から助走すると、穴の縁で最高速 280 に達している
    // （161 フレーム目 = 縁の手前 x≈2292 で vx=280.0 を厳密に pin）。
    @Test
    def testDashReaches280BeforeGap(): Unit \ Assert =
        let final = play(Trace.holdRightDash(161), atGroundNoFoes(1700.0));
        Assert.assertEq(expected = (280.0, true),
            (Trace.velOf(final)#x, Trace.posOf(final)#x < 2304.0))

    // ダッシュ + 縁で満タンジャンプ: 128px の大穴を渡り切り、死なずに対岸へ接地する。
    @Test
    def testDashJumpClearsGate(): Unit \ Assert =
        let cues = List.flatten(
            Trace.holdRightDash(161) :: Trace.rightDashJump(24) :: Trace.holdRightDash(30) :: Nil);
        let final = play(cues, atGroundNoFoes(1700.0));
        Assert.assertEq(expected = (0, true, true),
            (Trace.deathsOf(final), Trace.groundedOf(final), Trace.posOf(final)#x > 2440.0))

    // 素の走り（160 止まり）: 同じ縁でジャンプしても届かず（最長 ≈110px < 128px）、
    // 穴へ落ちて死ぬ = P スピードのゲート。
    @Test
    def testWalkJumpFallsIntoGate(): Unit \ Assert =
        let cues = List.flatten(
            Trace.holdRight(242) :: Trace.rightJump(24) :: Trace.holdRight(60) :: Nil);
        let worlds = timeline(cues, atGroundNoFoes(1700.0));
        Assert.assertEq(expected = true, countEvent("death", worlds) > 0)

    // ========================================================================
    // 中間地点（x=1688 の旗）
    // ========================================================================

    // 旗を越えた 1 回だけ checkpoint が鳴り、リスポーン地点が旗（1688, 392）へ移る。
    // そのまま走り続けても 2 回目は鳴らない。
    @Test
    def testCheckpointFiresOnce(): Unit \ Assert =
        let worlds = timeline(Trace.holdRight(60), atGround(1650.0));
        let final = play(Trace.holdRight(60), atGround(1650.0));
        Assert.assertEq(expected = (1, 1688.0, 392.0),
            (countEvent("checkpoint", worlds),
             final#respawnPos#x, final#respawnPos#y))

    // 中間地点より前の死亡: 穴 1（列 43-44）へ歩き出て落ちると、出発点（56,392）へ戻り、
    // カメラは両軸ともスポーンへスナップ（左端クランプで camX=0・下端クランプで camY=120）。
    @Test
    def testDeathBeforeCheckpointRespawnsAtSpawn(): Unit \ Assert =
        let cues = List.append(Trace.holdRight(12), Trace.flight(60));
        let worlds = timeline(cues, atGround(670.0));
        let final = play(cues, atGround(670.0));
        Assert.assertEq(expected = (true, 56.0, 0.0, 120.0),
            (countEvent("death", worlds) > 0,
             final#respawnPos#x, final#camX, final#camY))

    // 中間地点より後の死亡: 旗を越えてから大穴に落ちると、旗（1688,392）へ戻り、
    // camX は snapCam(3328, 1688) = 1688−240 = 1448 へスナップする（camY は下端 120 のまま）。
    @Test
    def testDeathAfterCheckpointRespawnsAtFlag(): Unit \ Assert =
        let cues = List.append(Trace.holdRight(30), Trace.flight(70));
        let world = atGround(2270.0);
        let worlds = timeline(cues, world);
        let final = play(cues, world);
        let respawned = worlds
            |> List.findLeft(w -> List.memberOf("death", Trace.eventsOf(w)))
            |> Option.map(w -> (w#player#pos#x, w#player#pos#y, w#camX, w#camY));
        Assert.assertEq(expected = (Some((1688.0, 392.0, 1448.0, 120.0)), 1),
            (respawned, Trace.deathsOf(final)))

    // ========================================================================
    // クリアと花火
    // ========================================================================

    // ゴール線（x=3272）を初めて越えた 1 回だけ clear が鳴り、clearedAt に時刻が入る。
    // クリア後もゲームは止まらず走り続けられる（位置が進み続ける）。
    @Test
    def testClearFiresOnceAndPlayContinues(): Unit \ Assert =
        let worlds = timeline(Trace.holdRight(60), atGround(3230.0));
        let final = play(Trace.holdRight(60), atGround(3230.0));
        Assert.assertEq(expected = (1, false, true),
            (countEvent("clear", worlds),
             Option.isEmpty(final#clearedAt),
             Trace.posOf(final)#x > 3272.0))

    // タメ: クリアの後 0.6 秒間は花火が 1 発も上がらない（静寂の間 → どんと来る）。
    @Test
    def testFireworksHoldBackDuringTame(): Unit \ Assert =
        let cues = List.append(Trace.holdRight(30), Trace.flight(230));
        let worlds = timeline(cues, atGround(3230.0));
        let clearAt = worlds
            |> List.findLeft(w -> List.memberOf("clear", Trace.eventsOf(w)))
            |> Option.map(w -> w#time)
            |> Option.getWithDefault(-1.0);
        let early = worlds |> List.filter(w -> w#time <= clearAt + 0.6);
        let noEarlyFirework = early |> List.forAll(w ->
            w#bursts |> List.forAll(b -> b#kind != Field.FxKind.FireworkKind));
        Assert.assertEq(expected = (true, true), (clearAt > 0.0, noEarlyFirework))

    // 花火はちょうど 10 発: クリア後 3.6 秒（230f）流すと firework イベントが 10 フレームで
    // 鳴り、それ以上は増えない。
    @Test
    def testFireworksLaunchExactlyTen(): Unit \ Assert =
        let cues = List.append(Trace.holdRight(30), Trace.flight(230));
        let worlds = timeline(cues, atGround(3230.0));
        Assert.assertEq(expected = 10, countEvent("firework", worlds))

    // classic の世界（goal がレベル外）では走ってもクリアも花火も決して起きない — 休眠の証明。
    @Test
    def testClassicWorldNeverClears(): Unit \ Assert =
        let worlds = timeline(Trace.holdRight(120), Trace.flatWorld());
        Assert.assertEq(expected = (0, 0, true),
            (countEvent("clear", worlds), countEvent("firework", worlds),
             worlds |> List.forAll(w -> Option.isEmpty(w#clearedAt))))
}
