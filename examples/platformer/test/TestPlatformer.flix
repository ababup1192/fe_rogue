// TestPlatformer — ジャンプの手触り 4 要素（可変高・コヨーテ・バッファ・非対称重力）と
// 走り（慣性・空中制御・摩擦）・衝突（着地・頭ぶつけ・崖離れ）を、平文の具体値で固定する。
// dt = 1/64（2進小数）・パラメータは既定値なので、加速や タイマーの pin は厳密値で比べられる。
// 重力の積分は循環小数（1365.33… px/s²）を含むので round4 で比べる。
// シナリオ（Trace）は Replay で純粋な update を流し、結末を固定する = テストと GIF が同じ手順。

mod TestPlatformer {

    /// 小数 4 桁に丸める（重力の循環小数を含む値の比較用）。
    def round4(x: Float64): Float64 = Float64.floor(x * 10000.0 + 0.5) / 10000.0

    def params(): GameParameters.Params = GameParameters.defaults()

    /// シナリオを最後まで流して結末の World を得る。
    def play(cues: List[Replay.Cue[Field.Input]], world: Field.World): Field.World =
        Replay.play(Step.update, Trace.dt(), cues, world)

    /// シナリオの全フレームの World（初期は含まない・1 フレーム目の結果から）。
    def timeline(cues: List[Replay.Cue[Field.Input]], world: Field.World): List[Field.World] =
        Replay.timeline(Step.update, Trace.dt(), cues, world)

    /// timeline の i 番目の縦速度（round4）。
    def vyAt(i: Int32, worlds: List[Field.World]): Option[Float64] =
        worlds |> List.drop(i) |> List.head |> Option.map(w -> round4(Trace.velOf(w)#y))

    /// timeline のどこかで名前の出来事が起きたか。
    def eventHappened(name: String, worlds: List[Field.World]): Bool =
        worlds |> List.exists(w -> List.memberOf(name, Trace.eventsOf(w)))

    // ========================================================================
    // 静止と着地（土台）
    // ========================================================================

    // 平地で何もしない: 位置は動かず、接地したまま、縦速度は毎フレーム 0 に戻る。
    @Test
    def testIdleOnFlatGroundIsStable(): Unit \ Assert =
        let final = play(Trace.flight(30), Trace.flatWorld());
        Assert.assertEq(expected = (160.0, 188.0, true, 0.0),
            (Trace.posOf(final)#x, Trace.posOf(final)#y,
             Trace.groundedOf(final), Trace.velOf(final)#y))

    // 40px 上から落とすと着地する: land が一度だけ鳴り、地面の上面 − 半径（y=188）で厳密に静止する。
    @Test
    def testLandingComesToRest(): Unit \ Assert =
        let worlds = timeline(Trace.flight(20), Trace.fallingWorld(40.0));
        let final = play(Trace.flight(20), Trace.fallingWorld(40.0));
        Assert.assertEq(expected = (true, true, 188.0, 0.0),
            (eventHappened("land", worlds), Trace.groundedOf(final),
             Trace.posOf(final)#y, round4(Trace.velOf(final)#y)))

    // ========================================================================
    // ジャンプ曲線: 高さ・頂点の時刻・非対称
    // ========================================================================

    // 満タン押し（30f）の頂点: y=188 から 92.17px 上昇して y=95.8333（設計 96px − 離散積分ぶん）。
    // 4f タップの頂点は y=149.8333（38.17px）—— 押す長さがそのまま高さになる（可変ジャンプ高）。
    @Test
    def testJumpApexFullVsTap(): Unit \ Assert =
        let full = timeline(List.append(Trace.holdJump(30), Trace.flight(70)), Trace.flatWorld());
        let tap = timeline(List.append(Trace.holdJump(4), Trace.flight(90)), Trace.flatWorld());
        Assert.assertEq(expected = (95.8333, 149.8333),
            (round4(Trace.apexOf(full)), round4(Trace.apexOf(tap))))

    // 頂点は timeToApex どおり 24 フレーム目: 23f 目はまだ上昇（-10.67）、24f 目でちょうど 0、
    // 25f 目から下降（+10.67）。頂点帯（apexGravityMult=0.5）なので変化が緩い。
    @Test
    def testApexTimingAtFrame24(): Unit \ Assert =
        let worlds = timeline(List.append(Trace.holdJump(30), Trace.flight(70)), Trace.flatWorld());
        Assert.assertEq(expected = (Some(-10.6667), Some(0.0), Some(10.6667)),
            (vyAt(23, worlds), vyAt(24, worlds), vyAt(25, worlds)))

    // 非対称の重力: 上昇（発射 → 頂点）は 23 フレーム、下降（頂点 → 接地）は 21 フレーム。
    // 下降は 1.8 倍の重力で速い（頂点帯のふわりを含めても上昇より短い）。
    @Test
    def testFallIsFasterThanRise(): Unit \ Assert =
        let worlds = timeline(List.append(Trace.holdJump(30), Trace.flight(70)), Trace.flatWorld());
        let indexed = List.zipWithIndex(worlds);
        let apexY = Trace.apexOf(worlds);
        let apexIndex = indexed
            |> List.findLeft(pair -> { let (_i, w) = pair; Trace.posOf(w)#y <= apexY + 0.0001 })
            |> Option.map(pair -> { let (i, _w) = pair; i })
            |> Option.getWithDefault(-1);
        let landIndex = indexed
            |> List.findLeft(pair -> { let (i, w) = pair; i > apexIndex and Trace.groundedOf(w) })
            |> Option.map(pair -> { let (i, _w) = pair; i })
            |> Option.getWithDefault(-1);
        Assert.assertEq(expected = (23, 21), (apexIndex, landIndex - apexIndex))

    // ========================================================================
    // 可変ジャンプ高の芯: 上昇カット
    // ========================================================================

    // カットは上昇にだけ効く: 上昇 -512 は 0.4 倍の -204.8 に削られ、下降 +200 は素通し。
    @Test
    def testCutJumpOnlyAffectsRising(): Unit \ Assert =
        Assert.assertEq(expected = (-204.8, 200.0),
            (Jump.cutJump(params(), -512.0), Jump.cutJump(params(), 200.0)))

    // ========================================================================
    // コヨーテタイムとジャンプバッファ（成立規則の単体 pin）
    // ========================================================================

    // 飛べる条件: バッファに押下が残っていて、接地しているかコヨーテ猶予内。
    @Test
    def testCanJumpGroundedOrCoyote(): Unit \ Assert =
        Assert.assertEq(expected = (true, true),
            (Jump.canJump(true, 0.0, 0.01), Jump.canJump(false, 0.03, 0.01)))

    // 飛べない条件: コヨーテが切れた空中、または押下がバッファに無い。
    @Test
    def testCanJumpExpired(): Unit \ Assert =
        Assert.assertEq(expected = (false, false),
            (Jump.canJump(false, 0.0, 0.01), Jump.canJump(false, 0.02, 0.0)))

    // ========================================================================
    // コヨーテタイム（統合: 崖から歩き出る）
    // ========================================================================

    // 崖を離れた最初のフレームはコヨーテ満タン（直前まで接地で充填）、次のフレームから
    // 1 フレームずつ減る（6/64 − 1/64 = 0.078125 厳密）。
    @Test
    def testWalkOffLedgeStartsCoyote(): Unit \ Assert =
        let worlds = timeline(Trace.holdRight(30), Trace.ledgeWorld());
        let indexed = List.zipWithIndex(worlds);
        let offIndex = indexed
            |> List.findLeft(pair -> { let (_i, w) = pair; not Trace.groundedOf(w) })
            |> Option.map(pair -> { let (i, _w) = pair; i })
            |> Option.getWithDefault(-1);
        let coyoteAtOff = worlds |> List.drop(offIndex) |> List.head |> Option.map(Trace.coyoteOf);
        let coyoteNext = worlds |> List.drop(offIndex + 1) |> List.head |> Option.map(Trace.coyoteOf);
        Assert.assertEq(expected = (Some(0.09375), Some(0.078125)), (coyoteAtOff, coyoteNext))

    // コヨーテ猶予（残り 3 フレーム）内の空中押下は接地と同じく飛べる: jump が鳴り、
    // 4 フレーム押し続けた縦速度は初速 -512 に上昇重力 3 回ぶんが乗った -426.6667。
    @Test
    def testCoyoteJumpWhileAirborne(): Unit \ Assert =
        let cues = Trace.holdJump(4);
        let world = Trace.coyoteWorld(3.0 / 64.0);
        let worlds = timeline(cues, world);
        let final = play(cues, world);
        Assert.assertEq(expected = (true, -426.6667),
            (eventHappened("jump", worlds), round4(Trace.velOf(final)#y)))

    // 同じ空中でもコヨーテが切れていれば飛べない: jump は鳴らず落下が続く。
    @Test
    def testCoyoteExpiredJumpIsDropped(): Unit \ Assert =
        let cues = List.append(Trace.holdJump(3), Trace.flight(2));
        let world = Trace.coyoteWorld(0.0);
        let worlds = timeline(cues, world);
        let final = play(cues, world);
        Assert.assertEq(expected = (false, true),
            (eventHappened("jump", worlds), Trace.velOf(final)#y > 0.0))

    // ========================================================================
    // ジャンプバッファ（統合: 着地前の先行入力）
    // ========================================================================

    // 落下中・着地の 6 フレーム前の押下は捨てられず、着地の直後のフレームで飛ぶ。
    @Test
    def testBufferedJumpFiresAfterLanding(): Unit \ Assert =
        let cues = Trace.hold(Trace.idle(), 7) ::
                   Trace.hold({ jumpDown = true, jumpPressed = true | Trace.idle() }, 1) ::
                   Trace.hold(Trace.idle(), 12) :: Nil;
        let worlds = timeline(cues, Trace.fallingWorld(40.0));
        Assert.assertEq(expected = (true, true),
            (eventHappened("land", worlds), eventHappened("jump", worlds)))

    // 着地の 13 フレーム前の押下はバッファ（8 フレーム）が切れて捨てられる: 飛ばずに静止する。
    @Test
    def testBufferExpiredBeforeLanding(): Unit \ Assert =
        let cues = Trace.hold({ jumpDown = true, jumpPressed = true | Trace.idle() }, 1) ::
                   Trace.hold(Trace.idle(), 25) :: Nil;
        let worlds = timeline(cues, Trace.fallingWorld(40.0));
        let final = play(cues, Trace.fallingWorld(40.0));
        Assert.assertEq(expected = (false, true, 0.0),
            (eventHappened("jump", worlds), Trace.groundedOf(final), round4(Trace.velOf(final)#y)))

    // ========================================================================
    // 走り: 慣性・空中制御・摩擦
    // ========================================================================

    // 同じ 10 フレームの右入力でも、地上（900px/s²）は 140.625 まで乗り、
    // 空中（500px/s²）は 78.125 まで —— 空中制御は効くが地上より弱い。厳密値。
    @Test
    def testAirControlWeakerThanGround(): Unit \ Assert =
        let ground = play(Trace.holdRight(10), Trace.flatWorld());
        let air = play(Trace.holdRight(10), Trace.fallingWorld(150.0));
        Assert.assertEq(expected = (140.625, 78.125),
            (Trace.velOf(ground)#x, Trace.velOf(air)#x))

    // キーを離すと地上摩擦（1200px/s²）が 8 フレームで 140.625 → 0 に止める（行き過ぎない）。
    @Test
    def testGroundFrictionStops(): Unit \ Assert =
        let final = play(List.append(Trace.holdRight(10), Trace.flight(8)), Trace.flatWorld());
        Assert.assertEq(expected = 0.0, Trace.velOf(final)#x)

    // ========================================================================
    // B ダッシュ
    // ========================================================================

    // P スピード（D2）: 加速は 160 まで 900px/s²（11f で 154.69 → 12f 目で 168.75）、
    // 160 を超える帯は 80px/s²（1.25/frame）。30 フレームでは素は 160 で頭打ち、
    // ダッシュは 168.75 + 18×1.25 = 191.25 まで — 280 にはまだ遠い。厳密値。
    @Test
    def testDashRaisesTopSpeed(): Unit \ Assert =
        let walk = play(Trace.holdRight(30), Trace.flatWorld());
        let dash = play(Trace.holdRightDash(30), Trace.flatWorld());
        Assert.assertEq(expected = (160.0, 191.25),
            (Trace.velOf(walk)#x, Trace.velOf(dash)#x))

    // P スピードの完成: 長い助走（実測 101 フレーム・約 330px）で最高速 280.0 にちょうど届く。
    // flatWorld（幅 320）では走り切れないので長い平地（longFlatWorld）で測る。
    @Test
    def testDashReachesTopSpeedWithLongRunup(): Unit \ Assert =
        let final = play(Trace.holdRightDash(128), Trace.longFlatWorld());
        Assert.assertEq(expected = 280.0, Trace.velOf(final)#x)

    // ダッシュを離しても急停止しない — P スピードでは帯の中の減衰も dashAccel（1.25/frame）:
    // 8 フレームで 280 → 270、160 へ戻り切るには 96 フレーム（1.5 秒）かかる。
    // 「勢いがなかなか死なない」を狙った仕様（Jump.horizontalStep の doc 参照）。
    @Test
    def testDashReleaseKeepsMomentum(): Unit \ Assert =
        let mid = play(List.append(Trace.holdRightDash(128), Trace.holdRight(8)), Trace.longFlatWorld());
        let final = play(List.append(Trace.holdRightDash(128), Trace.holdRight(96)), Trace.longFlatWorld());
        Assert.assertEq(expected = (270.0, 160.0),
            (Trace.velOf(mid)#x, Trace.velOf(final)#x))

    // 空中ベクトル変更（スマブラの DI 風）: ダッシュジャンプ中でも切り返し（進行方向と
    // 逆への入力）は P 帯の dashAccel でなく airAccel（500px/s² = 7.8125/frame）で効く。
    // vx=280 の空中で左を 20f 押すと 280 − 20×7.8125 = 123.75（厳密値）。
    // 旧仕様（P 帯が空中の切り返しにも適用）では 280 − 20×1.25 = 255 までしか落ちず、
    // ダッシュジャンプ中の舵がほぼ利かなかった（その回帰の修正を pin する）。
    @Test
    def testAirSteeringUsesAirAccel(): Unit \ Assert =
        let final = play(Trace.holdLeft(20), Trace.airborneWorld(280.0));
        Assert.assertEq(expected = 123.75, Trace.velOf(final)#x)

    // 進行方向への上積みは空中でも P 帯のまま: vx=200 の空中で右ダッシュを 20f 押しても
    // dashAccel（1.25/frame）でしか伸びない — 200 + 20×1.25 = 225.0（空中で速度は盛れない）。
    @Test
    def testAirForwardPushStaysInPBand(): Unit \ Assert =
        let final = play(Trace.holdRightDash(20), Trace.airborneWorld(200.0));
        Assert.assertEq(expected = 225.0, Trace.velOf(final)#x)

    // ========================================================================
    // 崖と崖死亡
    // ========================================================================

    // 地面 B の右端から広い穴（96px）へ歩き出ると落ちて死ぬ: death が鳴り、deaths が 1 になる。
    // リスポーンはレベルのスポーン（Level.spawnOf = x 56）へ — classic 地形のシナリオでも同じ。
    @Test
    def testFallIntoGapDies(): Unit \ Assert =
        let world = { player = Trace.restingPlayer(190.0) | Trace.classicWorld() };
        let cues = List.append(Trace.holdRight(10), Trace.flight(40));
        let worlds = timeline(cues, world);
        let final = play(cues, world);
        Assert.assertEq(expected = (true, 1, 56.0),
            (eventHappened("death", worlds), Trace.deathsOf(final), Trace.posOf(final)#x))

    // 狭い穴（50px）は素の走りジャンプで渡れる: 地面 A（x=60）から 12f ジャンプで
    // 穴と浮き床 A を越えて地面 B（y=188）に降り、死なない。
    @Test
    def testNormalJumpClearsNarrowGap(): Unit \ Assert =
        let world = { player = Trace.restingPlayer(60.0) | Trace.classicWorld() };
        let cues = List.flatten(Trace.rightJump(12) :: Trace.holdRight(45) :: Trace.flight(10) :: Nil);
        let worlds = timeline(cues, world);
        let final = play(cues, world);
        Assert.assertEq(expected = (false, true, 188.0),
            (eventHappened("death", worlds), Trace.groundedOf(final), Trace.posOf(final)#y))

    // 広い穴（80px）は P スピード + 低ホップ（6f）で浮き床 B の下をくぐって渡れる:
    // 渡った先の浮き床 C（y=149）に乗り、死なない。classic の助走路（54px）では 280 に
    // 届かない（P スピードは約 330px 必要 — 助走路は本番レベルが提供）ので、
    // dashGapWorld は vx=280 preset で「P スピード済み」から始めて崖越えゲートだけを見る。
    @Test
    def testDashLowHopClearsWideGap(): Unit \ Assert =
        let worlds = timeline(Trace.dashGapCues(), Trace.dashGapWorld());
        let final = play(Trace.dashGapCues(), Trace.dashGapWorld());
        Assert.assertEq(expected = (false, true, 149.0),
            (eventHappened("death", worlds), Trace.groundedOf(final), Trace.posOf(final)#y))

    // 同じ低ホップでも素の走り（160 止まり・立ち上がりから）では届かず、穴に落ちて死ぬ
    // （= P スピードのゲート。走りの加速は 160 以下の帯なので D2 でも挙動は変わらない）。
    @Test
    def testWalkLowHopFallsIntoWideGap(): Unit \ Assert =
        let world = { player = Trace.restingPlayer(155.0) | Trace.classicWorld() };
        let cues = List.flatten(
            Trace.holdRight(10) :: Trace.rightJump(6) :: Trace.holdRight(60) :: Nil);
        let worlds = timeline(cues, world);
        Assert.assertEq(expected = true, eventHappened("death", worlds))

    // ========================================================================
    // 重力の倍率（非対称の単体 pin）
    // ========================================================================

    // 上昇 = 1.0 / 頂点帯（|vy| ≤ 40）= 0.5 / 下降 = 1.8。
    @Test
    def testGravityScaleThreeBands(): Unit \ Assert =
        Assert.assertEq(expected = (1.0, 0.5, 1.8),
            (Jump.gravityScale(params(), -100.0),
             Jump.gravityScale(params(), 0.0),
             Jump.gravityScale(params(), 100.0)))

    // ========================================================================
    // 頭ぶつけ
    // ========================================================================

    // 60px 上の天井にジャンプ: bump が鳴って上昇が消え、落ちて接地に戻る。
    @Test
    def testHeadBumpStopsRise(): Unit \ Assert =
        let cues = List.append(Trace.holdJump(20), Trace.flight(40));
        let worlds = timeline(cues, Trace.ceilingWorld());
        let final = play(cues, Trace.ceilingWorld());
        Assert.assertEq(expected = (true, true),
            (eventHappened("bump", worlds), Trace.groundedOf(final)))

    // ========================================================================
    // パラメータの F1 リロード（fail-open の芯）
    // ========================================================================

    // JSON のキーで既定値を上書きし、無いキー・壊れた JSON は既定値のまま。
    @Test
    def testParamsFromJson(): Unit \ Assert =
        let overridden = GameParameters.fromJson("{\"jumpHeight\": 120.0}")
            |> Option.map(p -> (p#jumpHeight, p#timeToApex));
        let broken = GameParameters.fromJson("not json")
            |> Option.map(p -> p#jumpHeight);
        Assert.assertEq(expected = (Some((120.0, 0.375)), None), (overridden, broken))
}
