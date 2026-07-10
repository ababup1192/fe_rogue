// TestCamera — FollowCam（不感帯 → 追従 → クランプ）と Step の camX 前進を固定する（Wave B2-B3）。
// dt = 1/64 なので寄せ率 followK×dt = 0.125 は 2 進小数ちょうど — 1 歩の追従は厳密値で pin できる。
// 反復の漸近だけは丸めを含むので round4 で比べる（TestPlatformer と同じ流儀）。
// design は 480×360（カメラ引き後）— 画面中央は designW/2 = 240。classic シナリオの World は
// 320×240（design より小さい）なので camX/camY とも常に 0 に張り付く — これも pin する。
// 本番の Field.initialWorld はワイドレベル（3328×480）— 末尾のスモークで固定する。

mod TestCamera {

    /// 小数 4 桁に丸める（漸近値の比較用）。
    def round4(x: Float64): Float64 = Float64.floor(x * 10000.0 + 0.5) / 10000.0

    /// シナリオを最後まで流して結末の World を得る。
    def play(cues: List[Replay.Cue[Field.Input]], world: Field.World): Field.World =
        Replay.play(Step.update, Trace.dt(), cues, world)

    /// シナリオの全フレームの World（初期は含まない・1 フレーム目の結果から）。
    def timeline(cues: List[Replay.Cue[Field.Input]], world: Field.World): List[Field.World] =
        Replay.timeline(Step.update, Trace.dt(), cues, world)

    // ========================================================================
    // FollowCam 単体（広いレベル levelW=1280）
    // ========================================================================

    // 不感帯: 画面中央から ±39.9px（< 40）では両側ともカメラは 1px も動かない。
    // camX=100 → 中央は 340。
    @Test
    def testDeadzoneHoldsCamera(): Unit \ Assert =
        Assert.assertEq(expected = (100.0, 100.0),
            (FollowCam.stepCam(Trace.dt(), 1280.0, 379.9, 100.0),
             FollowCam.stepCam(Trace.dt(), 1280.0, 300.1, 100.0)))

    // 追従の 1 歩: 中央 240・対象 400 → はみ出し 160-40=120。寄せ率 8×(1/64)=0.125 なので
    // camX は 0 → 15.0 ちょうど（全部 2 進小数・厳密値）。
    @Test
    def testFollowStepExact(): Unit \ Assert =
        Assert.assertEq(expected = 15.0, FollowCam.stepCam(Trace.dt(), 1280.0, 400.0, 0.0))

    // 反復で漸近: 対象 400 に向けて 64 歩（1 秒）進めると、camX は不感帯の縁
    // （400-240-40=120）へ漸近する。閉形式 120×(1-0.875^64) ≈ 119.9767（round4 pin）。
    @Test
    def testFollowConverges(): Unit \ Assert =
        let final = List.range(0, 64)
            |> List.foldLeft((cam, _) -> FollowCam.stepCam(Trace.dt(), 1280.0, 400.0, cam), 0.0);
        Assert.assertEq(expected = 119.9767, round4(final))

    // クランプ: snapCam は左端 0・右端 levelW-designW（1280-480=800）で止まる。
    @Test
    def testSnapClampsToLevelEdges(): Unit \ Assert =
        Assert.assertEq(expected = (0.0, 800.0),
            (FollowCam.snapCam(1280.0, 30.0), FollowCam.snapCam(1280.0, 1270.0)))

    // levelW = classic の 320（< designW 480・既存の全 classic World）では
    // 追従もスナップも常に 0 — 休眠の証明。
    @Test
    def testClassicLevelStaysZero(): Unit \ Assert =
        Assert.assertEq(expected = (0.0, 0.0),
            (FollowCam.stepCam(Trace.dt(), 320.0, 999.0, 0.0), FollowCam.snapCam(320.0, 60.0)))

    // ========================================================================
    // Step 統合（camX を Step が進める）
    // ========================================================================

    /// 確実に崖死亡する台本: 地面 B の右端（x=190）から広い穴へ歩き出て落ちる
    /// （TestPlatformer.testFallIntoGapDies と同じ振り付け）。
    def deathCues(): List[Replay.Cue[Field.Input]] =
        List.append(Trace.holdRight(10), Trace.flight(40))

    // classic の World（levelW=320）では崖死亡込みのシナリオを丸ごと流しても
    // camX は全フレーム 0.0 のまま — 追従もスナップも休眠する。
    @Test
    def testStepKeepsCamZeroInClassicWorld(): Unit \ Assert =
        let world = { player = Trace.restingPlayer(190.0) | Trace.classicWorld() };
        let worlds = timeline(deathCues(), world);
        Assert.assertEq(expected = true, worlds |> List.forAll(w -> w#camX == 0.0))

    // 死亡スナップ: classic 地形を広く見立てた World（camX=300 から開始）で崖死亡すると、
    // その死亡フレームで camX はスポーン（x=56）中心へ即スナップする
    // （snapCam(1280,56) = 56−240 → 左端クランプで 0）。以降プレイヤーはスポーン付近に
    // 留まるので、結末も 0 のまま。
    @Test
    def testDeathSnapsCameraToSpawn(): Unit \ Assert =
        let wide = { player = Trace.restingPlayer(190.0), levelW = 1280.0, camX = 300.0
                     | Trace.classicWorld() };
        let worlds = timeline(deathCues(), wide);
        let deathCam = worlds
            |> List.findLeft(w -> List.memberOf("death", Trace.eventsOf(w)))
            |> Option.map(w -> w#camX);
        let final = play(deathCues(), wide);
        Assert.assertEq(expected = (Some(0.0), 0.0), (deathCam, final#camX))

    // 追従の統合: 広い平地で右へ 120 フレーム走ると、camX は一度も戻らず（単調非減少）
    // 正の値まで進む。結末は round4 で pin する。舞台は longFlatWorld（地面幅 1280）—
    // design 480 の視界では中央 240 + 不感帯 40 を越えるまでに 180px 走る必要があり、
    // classic の 320 地面（flatWorld）では走り切る前に届かないため。
    // pin の 129.5088 は先読み（ターゲット +40）込みの実測値: 先読みなしの追従なら
    // 89.5597（+39.9491 ≈ +40・追従の transient がほぼ減衰した後なので、ずれ幅がそのまま乗る）。
    @Test
    def testRunRightPansCameraMonotonically(): Unit \ Assert =
        let wide = { levelW = 1280.0 | Trace.longFlatWorld() };
        let worlds = timeline(Trace.holdRight(120), wide);
        let camXs = worlds |> List.map(w -> w#camX);
        let monotonic = List.zip(camXs, List.drop(1, camXs))
            |> List.forAll(pair -> { let (a, b) = pair; a <= b });
        let final = play(Trace.holdRight(120), wide);
        Assert.assertEq(expected = (true, true, 129.5088),
            (monotonic, final#camX > 0.0, round4(final#camX)))

    // ========================================================================
    // カメラ先読み（追従ターゲットを facing × lookAhead = 40px だけ進行方向へ寄せる）
    // ========================================================================

    // facing は最後の非ゼロ入力の向きを保持する: 右へ走って離しても +1 のまま、
    // 左を 1 フレーム叩けば −1 に変わる（カメラ先読みの向きの権威・初期値は +1）。
    @Test
    def testFacingKeepsLastDirection(): Unit \ Assert =
        let ranRight = play(List.append(Trace.holdRight(10), Trace.flight(10)), Trace.flatWorld());
        let tappedLeft = play(Trace.holdLeft(1), ranRight);
        Assert.assertEq(expected = (1.0, -1.0),
            (Trace.facingOf(ranRight), Trace.facingOf(tappedLeft)))

    // 先読みの定常値: 広い平地を右へ 240 フレーム走ると、追従は定常状態
    // （毎フレーム 2.5px = 走りと同速）へ収束し、camX の遅れは x−257.5 —
    // 先読みなしの定常（x−297.5）よりちょうど 40 前へ出る。実測 pin
    // （429.502 = 687.002 − 257.5・先読みなしなら 389.502 だった）。
    @Test
    def testLookAheadPansAheadOfRun(): Unit \ Assert =
        let wide = { levelW = 1280.0 | Trace.longFlatWorld() };
        let final = play(Trace.holdRight(240), wide);
        Assert.assertEq(expected = (687.002, 429.502),
            (round4(Trace.posOf(final)#x), round4(final#camX)))

    // classic（levelW=320 < designW 480）では先読みでターゲットが +40 ずれても
    // クランプが受け、camX は全フレーム 0 のまま — classic シナリオのカメラは不変。
    @Test
    def testLookAheadClassicStaysZero(): Unit \ Assert =
        let cues = List.flatten(
            Trace.holdRight(30) :: Trace.rightJump(12) :: Trace.holdRight(30) :: Nil);
        let worlds = timeline(cues, Trace.runAcrossWorld());
        Assert.assertEq(expected = true, worlds |> List.forAll(w -> w#camX == 0.0))

    // ========================================================================
    // ワイドレベル（Field.initialWorld = Level の 3328×480px）のスモーク
    // ========================================================================

    // スポーン（56,392）から何もしないと助走路の地面（行 26・上面 y=416）に落ちて接地する
    // （中心は 416 − 半径 12 = 404）。camX は初期 0 のまま、camY は下端クランプの 120
    // （levelH 480 − designH 360）に張り付く。levelH の pin も兼ねる。
    @Test
    def testWideSpawnFallsOntoGround(): Unit \ Assert =
        let final = play(Trace.flight(40), Field.initialWorld());
        Assert.assertEq(expected = (56.0, 404.0, true, 0.0, 120.0, 480.0),
            (Trace.posOf(final)#x, Trace.posOf(final)#y, Trace.groundedOf(final),
             final#camX, final#camY, final#levelH))

    // 縦の不感帯: 地面からの満タンジャンプ（頂点 96px）では camY は 1px も動かない。
    // 地面ビューは下端クランプ（camY=120・中央 300）。立ち姿（404）は中央の下 104px で
    // 不感帯 60 を越えているが下端クランプが受け、頂点（≈312）は中央の上 12px で帯の中。
    @Test
    def testGroundJumpKeepsCamY(): Unit \ Assert =
        let settled = play(Trace.flight(20), Field.initialWorld());
        let cues = List.append(Trace.holdJump(24), Trace.flight(50));
        let worlds = timeline(cues, settled);
        Assert.assertEq(expected = true, worlds |> List.forAll(w -> w#camY == 120.0))

    // 縦の追従: 高所の一方通行の棚（行13・上面 208・立ち中心 196）に立つと、camY は
    // 不感帯を越えたぶんだけ毎フレーム上がり（値は減る）、64 フレームで不感帯の縁
    // （196−180+60=76）へ漸近する（64 フレーム後の実測値 76.0098 を round4 で pin）。
    @Test
    def testHighShelfPullsCamYUp(): Unit \ Assert =
        let onShelf = { pos = { x = 3112.0, y = 196.0 } | Trace.levelRestingPlayer(3112.0) };
        let world = { player = onShelf, camX = 2952.0, camY = 240.0 | Field.initialWorld() };
        let worlds = timeline(Trace.flight(64), world);
        let camYs = worlds |> List.map(w -> w#camY);
        let monotonic = List.zip(camYs, List.drop(1, camYs))
            |> List.forAll(pair -> { let (a, b) = pair; a >= b });
        let final = play(Trace.flight(64), world);
        Assert.assertEq(expected = (true, 76.0098),
            (monotonic, round4(final#camY)))

    // レベル走破の台本（levelRunCues・実測振り付け・1124 フレーム）: スタートから
    // 止まらずに走り切り、死なずにゴール（x=3272）を越えてクリアする。踏みで敵を 3 体
    // 倒し（生存 8→5）、中間地点も発動する（respawnPos が旗へ移る）。結末は右壁
    // （x=3316）で静止・camX はレベル右端クランプ（3328−480=2848）・camY は地面ビュー
    // の下端クランプ（480−360=120）へ戻り切っている。
    @Test
    def testFullClearRun(): Unit \ Assert =
        let final = play(Trace.levelRunCues(), Field.initialWorld());
        Assert.assertEq(expected =
            (3316.0, 0, false, 5, 1688.0, 2848.0, 120.0),
            (Trace.posOf(final)#x, Trace.deathsOf(final),
             Option.isEmpty(final#clearedAt), Trace.aliveEnemiesOf(final),
             final#respawnPos#x, round4(final#camX), round4(final#camY)))
}
