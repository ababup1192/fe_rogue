// TestGalleryOutcomes — ギャラリーの各台本（bake/Gallery が焼くシナリオ）の結末を
// 安い 1 本ずつのスモークで固定する。GIF は目で見ないと壊れに気づけない —— かつて
// flyer_bob の台本が別ウェーブの調整で無言破綻していた教訓から、台本と同じ cue を
// ここでも流し、結末（出来事の回数・接地・死亡）だけを検証する。
// pin は緩いが意味のある値（イベント数・Bool）に留める: 手触り調整のウェーブで
// 位置の小数が動いても、台本が成立している限りここは揺れない。
// full_jump / short_hop（垂直ジャンプ）は TestPlatformer の頂点 pin が、
// full_clear_run は TestCamera.testFullClearRun が既に結末を固定しているので除く。

mod TestGalleryOutcomes {

    def play(cues: List[Replay.Cue[Field.Input]], world: Field.World): Field.World =
        Replay.play(Step.update, Trace.dt(), cues, world)

    def timeline(cues: List[Replay.Cue[Field.Input]], world: Field.World): List[Field.World] =
        Replay.timeline(Step.update, Trace.dt(), cues, world)

    /// 名前の出来事が起きたフレーム数。
    def countEvent(name: String, worlds: List[Field.World]): Int32 =
        worlds |> List.filter(w -> List.memberOf(name, Trace.eventsOf(w))) |> List.length

    // run_across: 浮き床を渡り切って死なずに接地で終わる（結末の床は C — y は緩く見ない）。
    @Test
    def testRunAcrossOutcome(): Unit \ Assert =
        let worlds = timeline(Trace.runAcrossCues(), Trace.runAcrossWorld());
        let final = play(Trace.runAcrossCues(), Trace.runAcrossWorld());
        Assert.assertEq(expected = (0, true),
            (countEvent("death", worlds), Trace.groundedOf(final)))

    // dash_gap: P スピードの低ホップで広い穴を渡り切り、死なずに接地で終わる。
    @Test
    def testDashGapOutcome(): Unit \ Assert =
        let worlds = timeline(Trace.dashGapCues(), Trace.dashGapWorld());
        let final = play(Trace.dashGapCues(), Trace.dashGapWorld());
        Assert.assertEq(expected = (0, true),
            (countEvent("death", worlds), Trace.groundedOf(final)))

    // gap_death: ちょうど 1 回死に、リスポーン地点（x=56）へ戻って接地で終わる。
    @Test
    def testGapDeathOutcome(): Unit \ Assert =
        let worlds = timeline(Trace.gapDeathCues(), Trace.gapDeathWorld());
        let final = play(Trace.gapDeathCues(), Trace.gapDeathWorld());
        Assert.assertEq(expected = (1, 56.0, true),
            (countEvent("death", worlds), Trace.posOf(final)#x, Trace.groundedOf(final)))

    // lift_ride: 縦リフトの往復に全フレーム乗ったまま（接地が一度も切れない）。
    @Test
    def testLiftRideOutcome(): Unit \ Assert =
        let worlds = timeline(Trace.flight(256), Trace.liftWorld());
        Assert.assertEq(expected = true, worlds |> List.forAll(Trace.groundedOf))

    // one_way_drop: 下+ジャンプで板（上面 133）を抜けて下の地面（y=188）へ降り、死なない。
    @Test
    def testOneWayDropOutcome(): Unit \ Assert =
        let cues = List.flatten(
            Trace.flight(20) :: Trace.pressDownJump() :: Trace.flight(50) :: Nil);
        let worlds = timeline(cues, Trace.onOneWayWorld());
        let final = play(cues, Trace.onOneWayWorld());
        Assert.assertEq(expected = (0, true, 188.0),
            (countEvent("death", worlds), Trace.groundedOf(final), Trace.posOf(final)#y))

    // slope_walk: 45° 坂を登って前へ進み（x が増える）、接地のまま終わる（静止摩擦）。
    @Test
    def testSlopeWalkOutcome(): Unit \ Assert =
        let cues = List.append(Trace.holdRight(70), Trace.flight(20));
        let worlds = timeline(cues, Trace.slopeWorld());
        let final = play(cues, Trace.slopeWorld());
        Assert.assertEq(expected = (0, true, true),
            (countEvent("death", worlds), Trace.groundedOf(final),
             Trace.posOf(final)#x > 120.0))

    // stomp_patrol: walker A を踏んで倒し（stomp 1 回）、walker B に触れて死ぬ（death 1 回）。
    @Test
    def testStompPatrolOutcome(): Unit \ Assert =
        let worlds = timeline(Trace.stompPatrolCues(), Trace.stompPatrolWorld());
        Assert.assertEq(expected = (1, 1),
            (countEvent("stomp", worlds), countEvent("death", worlds)))

    // flyer_bob: 下降中にパタパタへ重なって踏む（stomp 1 回・死なない）。
    @Test
    def testFlyerBobOutcome(): Unit \ Assert =
        let worlds = timeline(Trace.flyerBobCues(), Trace.flyerWorld());
        Assert.assertEq(expected = (1, 0),
            (countEvent("stomp", worlds), countEvent("death", worlds)))

    // spiky_trap: トゲは踏めず死ぬ（death 1 回・stomp 0 回）— トゲは生きたまま。
    @Test
    def testSpikyTrapOutcome(): Unit \ Assert =
        let worlds = timeline(Trace.spikyTrapCues(), Trace.spikyWorld());
        let final = play(Trace.spikyTrapCues(), Trace.spikyWorld());
        Assert.assertEq(expected = (1, 0, Some(true)),
            (countEvent("death", worlds), countEvent("stomp", worlds),
             Trace.enemyAliveOf(602, final)))
}
