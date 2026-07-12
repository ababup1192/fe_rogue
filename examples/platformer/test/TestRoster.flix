// TestRoster — 全キャラ参戦の pin: 左 Shift の巡回（15 → 1 の折り返し・死んでも引き継ぐ）、
// 個性の倍率（1 番は恒等 = 既存 pin の守り神・跳躍/落下/最高速の実測 pin）、
// ガード（致命接触に 1 回耐える → 無敵 → 切れたら死ぬ）、見た目の演技区分（viewMode）の状態機械。

mod TestRoster {

    /// 小数 4 桁に丸める（重力の循環小数を含む値の比較用）。
    def round4(x: Float64): Float64 = Float64.floor(x * 10000.0 + 0.5) / 10000.0

    def play(cues: List[Replay.Cue[Field.Input]], world: Field.World): Field.World =
        Replay.play(Step.update, Trace.dt(), cues, world)

    def timeline(cues: List[Replay.Cue[Field.Input]], world: Field.World): List[Field.World] =
        Replay.timeline(Step.update, Trace.dt(), cues, world)

    def eventHappened(name: String, worlds: List[Field.World]): Bool =
        worlds |> List.exists(w -> List.memberOf(name, Trace.eventsOf(w)))

    /// timeline の i 番目の viewMode。
    def modeAt(i: Int32, worlds: List[Field.World]): Option[CharStage.Mode] =
        worlds |> List.drop(i) |> List.head |> Option.map(w -> w#player#viewMode)

    /// 接地するまでのフレーム数（落下の柔らかさの物差し）。
    def framesToLand(worlds: List[Field.World]): Int32 =
        worlds |> List.takeWhile(w -> not Trace.groundedOf(w)) |> List.length

    // ========================================================================
    // 個性の適用（applyTraits）
    // ========================================================================

    // 1 番（HERO）は全倍率 1.0 の恒等 — 既定パラメータと厳密一致（既存 pin が全部生きる根拠）。
    @Test
    def testHeroTraitsAreIdentity(): Unit \ Assert =
        let base = GameParameters.defaults();
        let applied = Roster.applyTraits(Roster.traitsOf(1), base);
        Assert.assertEq(
            expected = (base#maxRunSpeed, base#dashMult, base#dashAccel, base#jumpHeight,
                        base#fallGravityMult, base#maxFallSpeed, base#airAccel, base#coyoteTime),
            (applied#maxRunSpeed, applied#dashMult, applied#dashAccel, applied#jumpHeight,
             applied#fallGravityMult, applied#maxFallSpeed, applied#airAccel, applied#coyoteTime))

    // ========================================================================
    // キャラ切り替え（左 Shift の巡回）
    // ========================================================================

    // 3 回押すと 1 → 4。切り替えのフレームには switch が鳴る。
    @Test
    def testSwitchAdvancesIndex(): Unit \ Assert =
        let cues = List.range(0, 3) |> List.flatMap(_ ->
            List.append(Trace.switchChar(), Trace.flight(1)));
        let worlds = timeline(cues, Trace.flatWorld());
        let final = play(cues, Trace.flatWorld());
        Assert.assertEq(expected = (4, true),
            (final#charIndex, eventHappened("switch", worlds)))

    // 15 回押すと 1 周して 1 へ戻る（15 → 1 の折り返し）。
    @Test
    def testSwitchWrapsAfterFifteen(): Unit \ Assert =
        let cues = List.range(0, 15) |> List.flatMap(_ ->
            List.append(Trace.switchChar(), Trace.flight(1)));
        Assert.assertEq(expected = 1, (play(cues, Trace.flatWorld()))#charIndex)

    // キャラは死んでも引き継ぐ: 7 番で崖に落ちて死んでも 7 番のまま。
    @Test
    def testCharIndexSurvivesDeath(): Unit \ Assert =
        let world = { charIndex = 7 | Trace.gapDeathWorld() };
        let final = play(Trace.gapDeathCues(), world);
        Assert.assertEq(expected = (7, 1), (final#charIndex, Trace.deathsOf(final)))

    // ========================================================================
    // 個性の実測 pin（跳躍・落下・最高速）
    // ========================================================================

    // 12 ODORIKO（jumpMult 1.2）: 立ちジャンプの頂点が基準より約 18px 高い（実測 pin）。
    @Test
    def testOdorikoJumpsHigher(): Unit \ Assert =
        let cues = List.append(Trace.holdJump(30), Trace.flight(40));
        let heroApex = Trace.apexOf(timeline(cues, Trace.flatWorld()));
        let odorikoApex = Trace.apexOf(timeline(cues, { charIndex = 12 | Trace.flatWorld() }));
        Assert.assertEq(expected = (95.8333, 77.4),
            (round4(heroApex), round4(odorikoApex)))

    // 4 FIREFLY（fallMult 0.65・maxFallMult 0.6）: 100px の自由落下が基準より長くかかる
    // （ふわ落下・フレーム数の実測 pin）。
    @Test
    def testFireflyFallsSofter(): Unit \ Assert =
        let heroFrames = framesToLand(timeline(Trace.flight(120), Trace.fallingWorld(100.0)));
        let fireflyFrames = framesToLand(timeline(Trace.flight(120),
            { charIndex = 4 | Trace.fallingWorld(100.0) }));
        Assert.assertEq(expected = (20, 24), (heroFrames, fireflyFrames))

    // 11 HIKYAKU（dashTopMult 1.145）: 長い助走の B ダッシュで最高速が 280 でなく約 320 に届く。
    @Test
    def testHikyakuDashTop(): Unit \ Assert =
        let final = play(Trace.holdRightDash(160), { charIndex = 11 | Trace.longFlatWorld() });
        Assert.assertEq(expected = 320.6, round4(Trace.velOf(final)#x))

    // ========================================================================
    // ガード（敵の致命接触に 1 回耐える）
    // ========================================================================

    // 4 番から切り替えて 5 GOLEM（guard 1）で walker に触れる: 1 回目は guard —
    // 生きたまま（deaths 0）・ガードを使い切り・無敵が入り・小さく跳ね（vy=-200）、敵も生きている。
    // 無敵（1 秒）が切れたあと折り返してきた walker に再び触れて死ぬ（deaths 1）。
    @Test
    def testGolemGuardsOnceThenDies(): Unit \ Assert =
        let cues = List.flatten(Trace.switchChar() :: Trace.holdRight(30) :: Trace.flight(250) :: Nil);
        let worlds = timeline(cues, { charIndex = 4 | Trace.walkerWorld() });
        let final = play(cues, { charIndex = 4 | Trace.walkerWorld() });
        let guardFrame = worlds |> List.filter(w -> List.memberOf("guard", Trace.eventsOf(w))) |> List.head;
        Assert.assertEq(
            expected = (true, Some(0), Some(true), Some(0), Some(-200.0), Some(true), 1),
            (eventHappened("guard", worlds),
             guardFrame |> Option.map(w -> w#deaths),
             guardFrame |> Option.map(w -> w#player#invulnLeft > 0.0),
             guardFrame |> Option.map(w -> w#player#guardLeft),
             guardFrame |> Option.map(w -> w#player#vel#y),
             Trace.enemyAliveOf(600, final),
             Trace.deathsOf(final)))

    // 切り替えでガードが張り直される: 5 GOLEM へ乗り換えた瞬間の guardLeft は 1。
    @Test
    def testSwitchGrantsGuard(): Unit \ Assert =
        let final = play(Trace.switchChar(), { charIndex = 4 | Trace.flatWorld() });
        Assert.assertEq(expected = (5, 1), (final#charIndex, final#player#guardLeft))

    // ========================================================================
    // 見た目の演技区分（viewMode）の状態機械
    // ========================================================================

    // 走り出し → P 帯ダッシュ → 逆入力のスキッド → ジャンプ → 落下 → 着地 → 待機、を
    // 1 本の台本で通す: 各区分の代表フレームの mode を pin（落下と着地は存在を確認）。
    @Test
    def testViewModeMachine(): Unit \ Assert =
        let cues = List.flatten(
            Trace.holdRight(20) :: Trace.holdRightDash(120) :: Trace.holdLeft(6) ::
            Trace.holdJump(20) :: Trace.flight(100) :: Nil);
        let worlds = timeline(cues, Trace.longFlatWorld());
        let lastMode = worlds |> List.reverse |> List.head |> Option.map(w -> w#player#viewMode);
        Assert.assertEq(
            expected = (Some(CharStage.Mode.RunMode), Some(CharStage.Mode.DashMode),
                        Some(CharStage.Mode.SkidMode), Some(CharStage.Mode.JumpMode),
                        true, true, Some(CharStage.Mode.IdleMode)),
            (modeAt(5, worlds), modeAt(139, worlds), modeAt(141, worlds), modeAt(146, worlds),
             worlds |> List.exists(w -> w#player#viewMode == CharStage.Mode.FallMode),
             worlds |> List.exists(w -> w#player#viewMode == CharStage.Mode.LandMode),
             lastMode))
}
