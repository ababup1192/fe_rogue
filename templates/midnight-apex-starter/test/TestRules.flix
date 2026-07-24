// ゲームの進行・操作・収支と、道路座標の共有だけをテストする。
// 浮遊マシンの頂点、遠近、光、文字の大きさは golden と目視へ任せる。
mod TestRules {

    /// 既定 Doc から表紙を作る。
    def initial(): World.World =
        World.initial({
            tuning = TuningDoc.defaults(),
            theme = ThemeDoc.defaults(),
            course = CourseDoc.defaults(),
            copy = CopyDoc.defaults(),
            scenery = SceneryDoc.defaults(),
            sprites = PxSpriteDoc.empty()
        })

    /// 決定して3秒進め、走行中の状態を作る。
    def racing(world: World.World): World.World =
        let countdown = World.step(
            { deltaTime = 0.0, input = { confirm = true | World.noInput() } }, world);
        World.step({ deltaTime = 3.0, input = World.noInput() }, countdown)

    /// コース上の仕掛けを除き、車体規則だけを調べる走行状態。
    def plainRacing(world: World.World): World.World =
        world
            |> World.resetWithCourse({
                version = 1,
                rows = "########################" :: "########################" :: Nil
            })
            |> racing

    /// アクセルだけを踏んだ入力。
    def throttle(): World.Input =
        { throttle = true | World.noInput() }

    /// ブレーキだけを踏んだ入力。
    def brake(): World.Input =
        { brake = true | World.noInput() }

    /// ブーストだけを使う入力。
    def boost(): World.Input =
        { boost = true | World.noInput() }

    // ========================================================================
    // 場面: 表紙 → 開始合図 → 走行 → 結果 → 表紙
    // ========================================================================

    /// 表紙で決定すると、すぐ走らず開始合図へ入る。
    @Test
    def testConfirmOnTitleBeginsCountdown(): Unit \ Assert =
        let after = World.step(
            { deltaTime = 0.0, input = { confirm = true | World.noInput() } }, initial());
        Assert.assertEq(expected = World.Phase.Countdown, after#phase)

    /// 開始合図の3秒を使い切ると走行へ入る。
    @Test
    def testCountdownEndsInRace(): Unit \ Assert =
        Assert.assertEq(expected = World.Phase.Racing, racing(initial())#phase)

    // ========================================================================
    // 操作: アクセル・ブレーキ・自然減速・ハンドル
    // ========================================================================

    /// 1秒アクセルを踏むと、Doc の acceleration ぶん速度が増える。
    @Test
    def testThrottleRaisesSpeedByAcceleration(): Unit \ Assert =
        let after = World.step({ deltaTime = 1.0, input = throttle() }, racing(initial()));
        Assert.assertEq(expected = TuningDoc.defaults()#acceleration, after#speed)

    /// 長くアクセルを踏んでも、Doc の maxSpeed を越えない。
    @Test
    def testThrottleStopsAtMaximumSpeed(): Unit \ Assert =
        let after = World.step({ deltaTime = 10.0, input = throttle() }, racing(initial()));
        Assert.assertEq(expected = TuningDoc.defaults()#maxSpeed, after#speed)

    /// 加速後にブレーキを1秒踏むと0で止まり、後退しない。
    @Test
    def testBrakeNeverReversesCar(): Unit \ Assert =
        let moving = World.step({ deltaTime = 1.0, input = throttle() }, racing(initial()));
        let stopped = World.step({ deltaTime = 1.0, input = brake() }, moving);
        Assert.assertEq(expected = 0.0, stopped#speed)

    /// 加速後に何も押さないと、Doc の coastDrag ぶん自然に遅くなる。
    @Test
    def testCoastingLosesSpeedByDrag(): Unit \ Assert =
        let tuning = TuningDoc.defaults();
        let moving = World.step({ deltaTime = 1.0, input = throttle() }, plainRacing(initial()));
        let after = World.step({ deltaTime = 1.0, input = World.noInput() }, moving);
        Assert.assertEq(expected = tuning#acceleration - tuning#coastDrag, after#speed)

    /// 長く右へ切っても、車体の右端は画面から出ない。
    @Test
    def testSteeringStopsAtScreenEdge(): Unit \ Assert =
        let input = { steer = 1.0 | World.noInput() };
        let after = World.step({ deltaTime = 100.0, input = input }, racing(initial()));
        Assert.assertEq(
            expected = World.designWidth() - World.carWidth() / 2.0,
            after#playerX)

    /// 同じ速さと時間なら、ブレーキ中は Doc の倍率ぶん大きく向きを変えられる。
    @Test
    def testBrakeMakesTightCorneringEasier(): Unit \ Assert =
        let tuning = TuningDoc.defaults();
        let base = {
            speed = tuning#maxSpeed,
            rivals = Nil | plainRacing(initial())
        };
        let duration = 0.2;
        let steerOnly = World.step(
            { deltaTime = duration,
              input = { steer = 1.0 | World.noInput() } },
            base);
        let brakeTurn = World.step(
            { deltaTime = duration,
              input = { steer = 1.0, brake = true | World.noInput() } },
            base);
        let normalMovement = steerOnly#playerX - base#playerX;
        let brakeMovement = brakeTurn#playerX - base#playerX;
        Assert.assertTrue(
            Float64.abs(
                brakeMovement - normalMovement * tuning#brakeSteerMultiplier
            ) < 0.000001)

    /// 路外では1秒で offRoadMaxSpeed まで落ち、フレーム数に依存する係数減速を使わない。
    @Test
    def testOffRoadLimitsSpeed(): Unit \ Assert =
        let tuning = TuningDoc.defaults();
        let course = {
            version = 1,
            rows = "........########........" :: "........########........" :: Nil
        };
        let road = Course.sample(
            { totalProgress = 0.0, screenWidth = World.designWidth() }, course);
        let outside = {
            speed = tuning#maxSpeed,
            playerX = road#centerX - road#width / 2.0 - tuning#fallMargin / 2.0
                | initial()
                    |> World.resetWithCourse(course)
                    |> racing
        };
        let after = World.step({ deltaTime = 1.0, input = World.noInput() }, outside);
        Assert.assertEq(expected = tuning#offRoadMaxSpeed, after#speed)

    /// 今拍の操舵で路外へ出た場合、その拍のブーストを許さない。
    @Test
    def testSteeringOffRoadCancelsBoostImmediately(): Unit \ Assert =
        let course = {
            version = 1,
            rows = "..........####.........." :: "..........####.........." :: Nil
        };
        let world = initial()
            |> World.resetWithCourse(course)
            |> racing;
        let after = World.step(
            { deltaTime = 0.25,
              input = { steer = 1.0, boost = true | World.noInput() } },
            { speed = TuningDoc.defaults()#maxSpeed, rivals = Nil | world });
        Assert.assertEq(
            expected = (false, false, World.maxEnergy()),
            (after#onRoad, after#boosting, after#energy))

    /// ブーストは通常加速より強く、押している時間ぶんだけエネルギーを使う。
    @Test
    def testBoostAcceleratesAndConsumesEnergy(): Unit \ Assert =
        let tuning = TuningDoc.defaults();
        let duration = 0.25;
        let after = World.step(
            { deltaTime = duration, input = boost() },
            { rivals = Nil | racing(initial()) });
        Assert.assertEq(
            expected = (tuning#boostAcceleration * duration,
                        World.maxEnergy() - tuning#boostDrain * duration,
                        true),
            (after#speed, after#energy, after#boosting))

    /// 共用エネルギーが空ならブーストを始めず、爆発中へ入る。
    @Test
    def testEmptyEnergyCrashesMachine(): Unit \ Assert =
        let empty = { energy = 0.0, speed = 0.0, rivals = Nil | racing(initial()) };
        let first = World.step({ deltaTime = 0.25, input = boost() }, empty);
        let second = World.step({ deltaTime = 0.25, input = boost() }, first);
        Assert.assertEq(
            expected = (0.0, false, World.Phase.Crashed,
                        0.0, false, World.Phase.Crashed),
            (first#energy, first#boosting, first#phase,
             second#energy, second#boosting, second#phase))

    /// ブーストを離しても通常最高速へ瞬間移動せず、毎秒の自然減速で戻る。
    @Test
    def testReleasedBoostDecaysSmoothly(): Unit \ Assert =
        let tuning = TuningDoc.defaults();
        let duration = 0.25;
        let fast = {
            speed = tuning#boostMaxSpeed,
            energy = 0.0,
            rivals = Nil | racing(initial())
        };
        let after = World.step(
            { deltaTime = duration, input = World.noInput() },
            fast);
        Assert.assertEq(
            expected = tuning#boostMaxSpeed - tuning#coastDrag * duration,
            after#speed);
        Assert.assertEq(expected = true, after#speed > tuning#maxSpeed)

    /// `=` の加速帯は、Spaceを押さなくても加速し、エネルギーを消費しない。
    @Test
    def testTrackBoostDoesNotConsumeEnergy(): Unit \ Assert =
        let course = { version = 1, rows = "========" :: "========" :: Nil };
        let world = initial()
            |> World.resetWithCourse(course)
            |> racing;
        let duration = 0.25;
        let after = World.step(
            { deltaTime = duration, input = World.noInput() },
            { rivals = Nil | world });
        Assert.assertEq(
            expected = (TuningDoc.defaults()#boostAcceleration * duration,
                        World.maxEnergy(),
                        true),
            (after#speed, after#energy, after#boosting))

    /// Spaceを押したまま加速帯へ入っても、無料加速を優先してエネルギーを回復する。
    @Test
    def testHeldBoostOnTrackStripRemainsFree(): Unit \ Assert =
        let course = { version = 1, rows = "========" :: "========" :: Nil };
        let world = initial()
            |> World.resetWithCourse(course)
            |> racing;
        let duration = 0.25;
        let startEnergy = 40.0;
        let after = World.step(
            { deltaTime = duration, input = boost() },
            { energy = startEnergy, rivals = Nil | world });
        Assert.assertEq(
            expected = startEnergy + TuningDoc.defaults()#energyRecharge * duration,
            after#energy)

    // ========================================================================
    // コース: 描画と判定が共有する滑らかな道路断面
    // ========================================================================

    /// 右寄りの道と左寄りの道の中間では、道路中央も画面中央へ補間される。
    @Test
    def testCourseInterpolatesBetweenRows(): Unit \ Assert =
        let course = { version = 1, rows = "####...." :: "....####" :: Nil };
        let sample = Course.sample(
            { totalProgress = Course.rowDistance() / 2.0, screenWidth = 100.0 }, course);
        Assert.assertEq(expected = 50.0, sample#centerX)

    /// `=` は路面の幅に数えられ、同時に加速帯として読める。
    @Test
    def testBoostStripIsRoadAndFeature(): Unit \ Assert =
        let course = { version = 1, rows = "..====.." :: "..====.." :: Nil };
        let sample = Course.sample(
            { totalProgress = 0.0, screenWidth = 80.0 }, course);
        Assert.assertEq(
            expected = (40.0, 40.0, true),
            (sample#centerX, sample#width, Course.isBoostStrip(0.0, course)))

    /// `^` は路面幅に数え、`[ ]` がある行だけ反発壁として読める。
    @Test
    def testJumpRampAndWallMarkersRemainRoad(): Unit \ Assert =
        let course = {
            version = 1,
            rows = "..[^^^^].." :: "..####.." :: Nil
        };
        let sample = Course.sample(
            { totalProgress = 0.0, screenWidth = 100.0 }, course);
        Assert.assertEq(
            expected = (40.0, true, true),
            (sample#width,
             Course.isJumpRamp(0.0, course),
             Course.hasWalls(0.0, course)))

    /// 同じ Sample を使い、中央の車は路面内、道路の外の車は路面外と判定する。
    @Test
    def testRoadContainmentUsesSampleEdges(): Unit \ Assert =
        let sample = Course.sample(
            { totalProgress = 0.0, screenWidth = World.designWidth() }, CourseDoc.defaults());
        Assert.assertEq(
            expected = (true, false),
            (Course.contains({ centerX = sample#centerX, halfWidth = World.carWidth() / 2.0 }, sample),
             Course.contains({ centerX = 0.0, halfWidth = World.carWidth() / 2.0 }, sample)))

    /// rows を増やすと一周も同じ割合で長くなり、コースと周回の帳尻がずれない。
    @Test
    def testLapLengthFollowsCourseRows(): Unit \ Assert =
        let shortCourse = { version = 1, rows = "###" :: "###" :: Nil };
        Assert.assertEq(
            expected = Course.rowDistance() * 2.0,
            Course.lapLength(shortCourse))

    // ========================================================================
    // 競争: 追い抜き・順位・周回・結果の凍結
    // ========================================================================

    /// 十分に速い自機が2台を抜くと、1位になり2台分だけ得点する。
    @Test
    def testPassingRivalsChangesRankAndScoreOnce(): Unit \ Assert =
        let defaults = TuningDoc.defaults();
        let fast = {
            maxSpeed = 300.0, acceleration = 300.0,
            rivalSpeedA = 1.0, rivalSpeedB = 1.0 | defaults
        };
        let world = initial() |> World.withTuning(fast) |> racing;
        let after = World.step({ deltaTime = 1.0, input = throttle() }, world);
        let onceMore = World.step({ deltaTime = 0.1, input = throttle() }, after);
        Assert.assertEq(
            expected = (1, defaults#scorePerPass * 2, defaults#scorePerPass * 2),
            (after#rank, after#score, onceMore#score))

    /// 接触は速度とエネルギーを一度失わせ、待ち時間中の次拍では二重に引かない。
    @Test
    def testCollisionLossIsAppliedOnceDuringCooldown(): Unit \ Assert =
        let tuning = TuningDoc.defaults();
        let rival = {
            totalProgress = 0.0,
            laneOffset = 0.0,
            cruiseSpeed = 0.0,
            passed = false
        };
        let touching = {
            speed = 100.0,
            energy = World.maxEnergy(),
            totalProgress = 0.0,
            playerX = World.designWidth() / 2.0,
            rivals = rival :: Nil | racing(initial())
        };
        let first = World.step(
            { deltaTime = 0.0, input = World.noInput() },
            touching);
        let second = World.step(
            { deltaTime = 0.0, input = World.noInput() },
            first);
        Assert.assertEq(
            expected = (100.0 - tuning#collisionSpeedLoss,
                        World.maxEnergy() - tuning#collisionEnergyLoss,
                        100.0 - tuning#collisionSpeedLoss,
                        World.maxEnergy() - tuning#collisionEnergyLoss),
            (first#speed, first#energy, second#speed, second#energy))

    /// 壁区間の外端へ触れると、路面内へ戻され、反対向きの勢いと接触損失を受ける。
    @Test
    def testWallBouncesMachineAndConsumesEnergy(): Unit \ Assert =
        let tuning = TuningDoc.defaults();
        let course = {
            version = 1,
            rows = "....[########]...." :: "....[########]...." :: Nil
        };
        let world = initial()
            |> World.resetWithCourse(course)
            |> racing
            |> (racingWorld -> {
                playerX = 0.0,
                speed = 100.0,
                rivals = Nil | racingWorld
            });
        let road = Course.sample(
            { totalProgress = 0.0, screenWidth = World.designWidth() }, course);
        let after = World.step(
            { deltaTime = 0.0, input = World.noInput() }, world);
        Assert.assertEq(
            expected = (
                road#centerX - road#width / 2.0 + World.carWidth() / 2.0,
                true,
                100.0 - tuning#collisionSpeedLoss,
                World.maxEnergy() - tuning#collisionEnergyLoss
            ),
            (after#playerX, after#bounceVelocity > 0.0,
             after#speed, after#energy))

    /// 同じ壁へ押し続けても、接触待ち時間中はエネルギーを二重に引かない。
    @Test
    def testWallCooldownPreventsRepeatedDamage(): Unit \ Assert =
        let course = {
            version = 1,
            rows = "....[########]...." :: "....[########]...." :: Nil
        };
        let outside = initial()
            |> World.resetWithCourse(course)
            |> racing
            |> (racingWorld -> { playerX = 0.0, rivals = Nil | racingWorld });
        let first = World.step(
            { deltaTime = 0.0, input = World.noInput() }, outside);
        let second = World.step(
            { deltaTime = 0.0, input = World.noInput() },
            { playerX = 0.0 | first });
        Assert.assertEq(
            expected = (first#energy, first#energy),
            (first#energy, second#energy))

    /// 壁なし区間では、路端を少し越えただけなら減速しつつ立て直せる。
    @Test
    def testOpenCourseShoulderDoesNotKillImmediately(): Unit \ Assert =
        let tuning = TuningDoc.defaults();
        let course = {
            version = 1,
            rows = "........########........" :: "........########........" :: Nil
        };
        let road = Course.sample(
            { totalProgress = 0.0, screenWidth = World.designWidth() }, course);
        let shoulder = initial()
            |> World.resetWithCourse(course)
            |> racing
            |> (racingWorld -> {
                playerX = road#centerX - road#width / 2.0 - tuning#fallMargin / 2.0,
                rivals = Nil | racingWorld
            });
        let after = World.step(
            { deltaTime = 0.0, input = World.noInput() }, shoulder);
        Assert.assertEq(
            expected = (World.Phase.Racing, false),
            (after#phase, after#onRoad))

    /// 壁なし区間で路端から転落距離を越えると、パワーを全て失い爆発へ入る。
    @Test
    def testOpenCourseFallCrashesMachine(): Unit \ Assert =
        let tuning = TuningDoc.defaults();
        let course = {
            version = 1,
            rows = "........########........" :: "........########........" :: Nil
        };
        let road = Course.sample(
            { totalProgress = 0.0, screenWidth = World.designWidth() }, course);
        let falling = initial()
            |> World.resetWithCourse(course)
            |> racing
            |> (racingWorld -> {
                playerX = road#centerX - road#width / 2.0 - tuning#fallMargin - 1.0,
                rivals = Nil | racingWorld
            });
        let after = World.step(
            { deltaTime = 0.0, input = World.noInput() }, falling);
        Assert.assertEq(
            expected = (World.Phase.Crashed, 0.0, 0.0),
            (after#phase, after#energy, after#speed))

    /// 同じ逸脱量でも空中なら落下せず、着地後の拍で現在位置を再判定する。
    @Test
    def testAirborneMachineFallsOnlyAfterLanding(): Unit \ Assert =
        let tuning = TuningDoc.defaults();
        let course = {
            version = 1,
            rows = "........########........" :: "........########........" :: Nil
        };
        let road = Course.sample(
            { totalProgress = 0.0, screenWidth = World.designWidth() }, course);
        let airborne = initial()
            |> World.resetWithCourse(course)
            |> racing
            |> (racingWorld -> {
                playerX = road#centerX + road#width / 2.0 + tuning#fallMargin + 1.0,
                jump = TimedHop.start(tuning#jumpDuration, TimedHop.grounded()),
                rivals = Nil | racingWorld
            });
        let inAir = World.step(
            { deltaTime = 0.0, input = World.noInput() }, airborne);
        let landed = World.step(
            { deltaTime = tuning#jumpDuration, input = World.noInput() }, inAir);
        let afterLanding = World.step(
            { deltaTime = 0.0, input = World.noInput() }, landed);
        Assert.assertEq(
            expected = (World.Phase.Racing, World.Phase.Crashed),
            (inAir#phase, afterLanding#phase))

    /// 最高速で短い1行の台をまたいでも、通過区間からジャンプを開始する。
    @Test
    def testFastMachineCannotSkipJumpRamp(): Unit \ Assert =
        let course = {
            version = 1,
            rows = "########" :: "^^^^^^^^" :: "########" :: Nil
        };
        let world = initial()
            |> World.resetWithCourse(course)
            |> racing
            |> (racingWorld -> {
                speed = TuningDoc.defaults()#maxSpeed,
                rivals = Nil | racingWorld
            });
        let after = World.step(
            { deltaTime = 0.5, input = throttle() }, world);
        Assert.assertTrue(TimedHop.isAirborne(after#jump))

    /// 空中では同じ位置のライバルに重なっても、速度とエネルギーを失わない。
    @Test
    def testAirborneMachineIgnoresRivalCollision(): Unit \ Assert =
        let rival = {
            totalProgress = 0.0,
            laneOffset = 0.0,
            cruiseSpeed = 0.0,
            passed = false
        };
        let airborne = {
            speed = 100.0,
            energy = 60.0,
            totalProgress = 0.0,
            playerX = World.designWidth() / 2.0,
            jump = TimedHop.start(TuningDoc.defaults()#jumpDuration, TimedHop.grounded()),
            rivals = rival :: Nil | plainRacing(initial())
        };
        let after = World.step(
            { deltaTime = 0.0, input = World.noInput() }, airborne);
        Assert.assertEq(
            expected = (100.0, 60.0),
            (after#speed, after#energy))

    /// エネルギー0では完走より爆発を優先し、演出後だけGameOverへ進む。
    @Test
    def testCrashFreezesRaceBeforeGameOver(): Unit \ Assert =
        let crashed = World.step(
            { deltaTime = 0.0, input = boost() },
            { energy = 0.0, elapsedTime = 12.0 | racing(initial()) });
        let gameOver = World.step(
            { deltaTime = 0.85, input = World.noInput() }, crashed);
        let reset = World.step(
            { deltaTime = 0.0,
              input = { confirm = true | World.noInput() } },
            gameOver);
        Assert.assertEq(
            expected = (World.Phase.Crashed, 12.0,
                        World.Phase.GameOver, 12.0,
                        World.Phase.Title),
            (crashed#phase, crashed#elapsedTime,
             gameOver#phase, gameOver#elapsedTime,
             reset#phase))

    /// 1周だけの短いコースを走り切ると、最終周で Finish へ入る。
    @Test
    def testFinalLapFinishesRace(): Unit \ Assert =
        let course = { version = 1, rows = "########" :: "########" :: Nil };
        let tuning = {
            maxSpeed = 200.0, acceleration = 200.0,
            rivalSpeedA = 1.0, rivalSpeedB = 1.0, totalLaps = 1 | TuningDoc.defaults()
        };
        let world = initial()
            |> World.resetWithCourse(course)
            |> World.withTuning(tuning)
            |> racing;
        let after = World.step({ deltaTime = 1.0, input = throttle() }, world);
        Assert.assertEq(
            expected = (World.Phase.Finish, tuning#totalLaps),
            (after#phase, after#lap))

    /// Finish 中は時間と順位を進めず、結果を画面に固定する。
    @Test
    def testFinishFreezesRankAndTime(): Unit \ Assert =
        let finished = { phase = World.Phase.Finish, elapsedTime = 12.0, rank = 2 | initial() };
        let after = World.step({ deltaTime = 10.0, input = throttle() }, finished);
        Assert.assertEq(
            expected = (12.0, 2),
            (after#elapsedTime, after#rank))

    /// Finish で決定すると、同じ Doc を保った表紙へ戻る。
    @Test
    def testConfirmOnFinishReturnsToTitle(): Unit \ Assert =
        let finished = { phase = World.Phase.Finish | initial() };
        let after = World.step(
            { deltaTime = 0.0, input = { confirm = true | World.noInput() } }, finished);
        Assert.assertEq(expected = World.Phase.Title, after#phase)

    /// tuning の保存即反映では、すでにいるライバル2台の巡航速度も更新する。
    @Test
    def testTuningReloadUpdatesRivalSpeeds(): Unit \ Assert =
        let tuning = { rivalSpeedA = 10.0, rivalSpeedB = 20.0 | TuningDoc.defaults() };
        let after = World.withTuning(tuning, initial());
        Assert.assertEq(
            expected = (Some(10.0), Some(20.0)),
            (List.nth(0, after#rivals) |> Option.map(rival -> rival#cruiseSpeed),
             List.nth(1, after#rivals) |> Option.map(rival -> rival#cruiseSpeed)))
}
