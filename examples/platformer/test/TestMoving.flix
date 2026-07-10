// TestMoving — 動く床（縦リフト・横フェリー）と一方通行の薄板を固定する（Wave A3）。
// 動く床は時刻 t の純関数（三角波 pingPong）なので、往復も途中経過も pin は厳密値で比べられる。
// dt = 1/64・period は 2 の冪秒（4 秒）を選んであるので speed×frame の位置も割り切れる。
// 重力の積分だけは循環小数（1365.33… px/s²）を含むので round4 で比べる（TestPlatformer と同じ流儀）。

mod TestMoving {

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

    // ========================================================================
    // 縦リフト（carry: 位置ベースで足元が床と一緒に動く）
    // ========================================================================

    // 縦リフトに乗って 32 フレーム（idle）: amp32/period4 は 0.5px/frame ちょうどなので、
    // y はちょうど 16.0 上がる。全フレーム接地したまま（carry が毎フレーム足元を運ぶ）。
    @Test
    def testLiftCarriesPlayerUp(): Unit \ Assert =
        let worlds = timeline(Trace.flight(32), Trace.liftWorld());
        let final = play(Trace.flight(32), Trace.liftWorld());
        Assert.assertEq(expected = (115.0, true),
            (Trace.posOf(final)#y, worlds |> List.forAll(Trace.groundedOf)))

    // period 4 秒 = 256 フレームの 1/4 は 64 フレーム目で折り返す。32 フレームで上げたあと
    // さらに 64 フレーム流すと、上昇 32f + 下降 64f で折り返して下がる。下降局面でも
    // 接地が切れない（carry が毎フレーム足元を床の実位置へ運ぶので分離が毎回成立する）。
    @Test
    def testLiftDescendKeepsGrounded(): Unit \ Assert =
        let cues = List.append(Trace.flight(32), Trace.flight(64));
        let worlds = timeline(cues, Trace.liftWorld());
        let final = play(cues, Trace.liftWorld());
        Assert.assertEq(expected = (115.0, true),
            (Trace.posOf(final)#y, worlds |> List.forAll(Trace.groundedOf)))

    // ========================================================================
    // 横フェリー（carry は位置ベース: 速度は汚さない）
    // ========================================================================

    // 横フェリーに乗って 16 フレーム（idle）: amp48/period4 は 0.75px/frame ちょうどなので、
    // x はちょうど +12.0。carry は位置を直接運ぶだけなので vel#x は 0.0 のまま。
    @Test
    def testFerryCarriesPlayerSideways(): Unit \ Assert =
        let final = play(Trace.flight(16), Trace.ferryWorld());
        Assert.assertEq(expected = (172.0, 0.0), (Trace.posOf(final)#x, Trace.velOf(final)#x))

    // フェリーからジャンプ: 離脱の瞬間（1 フレーム目）に床の水平速度 48.0px/s をそのまま
    // 継承する。その後は走り入力なしなので空中の減速（100px/s²）が 3 フレームぶん効いて
    // 43.3125 まで落ち着く。垂直は継承しない — vy はコヨーテ/接地ジャンプと同じ初速に
    // 4 フレームぶんの上昇重力が乗った -426.6667（round4）。
    @Test
    def testFerryJumpInheritsHorizontalOnly(): Unit \ Assert =
        let final = play(Trace.holdJump(4), Trace.ferryWorld());
        Assert.assertEq(expected = (43.3125, -426.6667),
            (round4(Trace.velOf(final)#x), round4(Trace.velOf(final)#y)))

    // 縦リフトからジャンプ: 床の動きが垂直なので水平継承ぶんはゼロ、vy は通常ジャンプと
    // 同じ -426.6667（round4）— 縦の動く床の速度を継承しないことの pin。
    @Test
    def testLiftJumpDoesNotInheritVertical(): Unit \ Assert =
        let final = play(Trace.holdJump(4), Trace.liftWorld());
        Assert.assertEq(expected = (0.0, -426.6667),
            (Trace.velOf(final)#x, round4(Trace.velOf(final)#y)))

    // ========================================================================
    // 一方通行: 上から着地・下から突き抜け・下+ジャンプで降下
    // ========================================================================

    // 一方通行の板の上方から落として着地: land が鳴り、接地して板の上に静止する
    // （落下高さを変えても同じ y に収束する — 分離の解決先は板の実位置だけで決まる）。
    @Test
    def testLandOnOneWayFromAbove(): Unit \ Assert =
        let above = { player = { pos = { x = 160.0, y = 101.0 }, vel = Vec2.zero(), grounded = false,
                                  coyoteLeft = 0.0, bufferLeft = 0.0, jumpHeld = false, squashLeft = 0.0,
                                  facing = 1.0, ridingId = None, dropLeft = 0.0 } | Trace.oneWayWorld() };
        let worlds = timeline(Trace.flight(40), above);
        let final = play(Trace.flight(40), above);
        Assert.assertEq(expected = (true, true, 122.0),
            (eventHappened("land", worlds), Trace.groundedOf(final), Trace.posOf(final)#y))

    // 一方通行の下からフルジャンプで突き抜ける: bump は一度も鳴らず、頂点は板より
    // 高く上がり（95.83 < 板上面 133）、最終的に板の上に乗って接地する。
    @Test
    def testJumpThroughOneWayFromBelow(): Unit \ Assert =
        let cues = List.append(Trace.holdJump(30), Trace.flight(70));
        let worlds = timeline(cues, Trace.oneWayWorld());
        let final = play(cues, Trace.oneWayWorld());
        Assert.assertEq(expected = (false, true, true),
            (eventHappened("bump", worlds), Trace.apexOf(worlds) < 133.0, Trace.groundedOf(final)))

    // 板の上で下+ジャンプを押すとすり抜けて降下する: jump イベントは出ず（暴発防止でバッファに
    // 積まない）、板を抜けて下の地面（y=188）に着地し land が鳴る。
    @Test
    def testDropThroughOneWay(): Unit \ Assert =
        let cues = List.flatten(Trace.pressDownJump() :: Trace.flight(30) :: Nil);
        let worlds = timeline(cues, Trace.onOneWayWorld());
        let final = play(cues, Trace.onOneWayWorld());
        Assert.assertEq(expected = (false, true, 188.0),
            (eventHappened("jump", worlds), eventHappened("land", worlds), Trace.posOf(final)#y))

    // すり抜け降下タイマー（dropLeft ≈ 0.15s ≈ 10f）の間は板を通過しても再着地しない:
    // 板の上面 133 〜 下面 139 の間を通るフレームが存在し、そのフレームは grounded=false
    // （フィルタがまだ一方通行を無視している証拠）。
    @Test
    def testDropTimerPreventsRelanding(): Unit \ Assert =
        let cues = List.flatten(Trace.pressDownJump() :: Trace.flight(30) :: Nil);
        let worlds = timeline(cues, Trace.onOneWayWorld());
        let passesThroughPlank = worlds
            |> List.exists(w -> Trace.posOf(w)#y >= 133.0 and Trace.posOf(w)#y <= 139.0 and not Trace.groundedOf(w));
        Assert.assertEq(expected = true, passesThroughPlank)

    // ========================================================================
    // Field.platformPosAt の単体 pin（三角波の 3 点）
    // ========================================================================

    // liftWorld の mover（基準 (160,150)・振れ幅 32・周期 4 秒・軸は上向き）:
    // t=0 は基準そのまま、t=1（1/4 周期）は pingPong=1.0 で頂点 (160,118)、
    // t=2（1/2 周期）は pingPong=0.0 で基準へ戻る。
    @Test
    def testPlatformPosAtTrianglePoints(): Unit \ Assert =
        let mover = Field.movingAt(400, { x = 160.0, y = 150.0 }, { x = 48.0, y = 14.0 },
            { axis = { x = 0.0, y = -1.0 }, amplitude = 32.0, period = 4.0, phase = 0.0 });
        let p0 = Field.platformPosAt(0.0, mover);
        let p1 = Field.platformPosAt(1.0, mover);
        let p2 = Field.platformPosAt(2.0, mover);
        Assert.assertEq(expected = ((160.0, 150.0), (160.0, 118.0), (160.0, 150.0)),
            ((p0#x, p0#y), (p1#x, p1#y), (p2#x, p2#y)))
}
