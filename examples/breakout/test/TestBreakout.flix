// TestBreakout — 反射角・加速・ハード2発・不壊ブロック・シェイク減衰・スコア・落下・レベル進行を、
// 平文の具体値で固定する。反射角・加速は無理数（sin/cos・2進で表せない倍率）を含むので
// round4（小数4桁）で比べ、それ以外は厳密値で pin する。
// シナリオ（Trace）は Replay で純粋な update を最後まで流し、結末を固定する = テストと GIF が同じ手順。

mod TestBreakout {

    /// 小数 4 桁に丸める（sin/cos を含む値の比較用）。
    def round4(x: Float64): Float64 = Float64.floor(x * 10000.0 + 0.5) / 10000.0

    /// 飛行中のボールの速さ（|velocity|）を読む。飛んでいなければ速度は無いので None。
    def ballSpeedOf(world: Field.World): Option[Float64] =
        Trace.ballVelOf(world) |> Option.map(v -> round4(Vec2.length(v)))

    // ========================================================================
    // パドル反射角（本作の要）: 5 ゾーンの角度差
    // ========================================================================

    // 中央=真上 (0,-1)、±0.5=±30°、±1=±60°。速さ 1 で向きだけを見る。
    //
    //   left端    左中間    中央    右中間    右端
    //    ↖         ↖        ↑        ↗        ↗
    //  (-.87,-.5)(-.5,-.87)(0,-1)(.5,-.87)(.87,-.5)
    //
    @Test
    def testPaddleBounceFiveZones(): Unit \ Assert =
        let zones = -1.0 :: -0.5 :: 0.0 :: 0.5 :: 1.0 :: Nil;
        let actual = List.map(zone -> {
            let velocity = Bounce.paddleReflect(zone, 1.0);
            (round4(velocity#x), round4(velocity#y))
        }, zones);
        Assert.assertEq(expected =
            (-0.866, -0.5) :: (-0.5, -0.866) :: (0.0, -1.0) :: (0.5, -0.866) :: (0.866, -0.5) :: Nil,
            actual)

    // 当たり位置の正規化: 中央=0、右端=+1、左端=-1、端の外は 1 を超える（クランプは反射側で行う）。
    @Test
    def testOffsetFraction(): Unit \ Assert =
        let halfWidth = 20.0;
        let actual = (Bounce.offsetFraction(100.0, 100.0, halfWidth),
                      Bounce.offsetFraction(120.0, 100.0, halfWidth),
                      Bounce.offsetFraction(80.0, 100.0, halfWidth),
                      Bounce.offsetFraction(140.0, 100.0, halfWidth));
        Assert.assertEq(expected = (0.0, 1.0, -1.0, 2.0), actual)

    // 反射は与えた速さをそのまま使う（角度を変えても大きさは 130 のまま）。
    @Test
    def testPaddleBouncePreservesSpeed(): Unit \ Assert =
        Assert.assertEq(expected = 130.0, round4(Vec2.length(Bounce.paddleReflect(0.5, 130.0))))

    // ========================================================================
    // 加速規則: ヒット毎 +2.5%・端当てボーナス・上限クランプ
    // ========================================================================

    // 中央で受けると +2.5% だけ: 130 → 133.25。端ボーナスは付かない。
    @Test
    def testSpeedGainCenterHit(): Unit \ Assert =
        let actual = Bounce.speedAfterHit({ current = 130.0, offsetFrac = 0.0, base = 130.0 });
        Assert.assertEq(expected = 133.25, round4(actual))

    // 端いっぱいで受けると +2.5% にさらに +5%: 130 → 130×1.025×1.05 = 139.9125。
    @Test
    def testSpeedGainEdgeHit(): Unit \ Assert =
        let actual = Bounce.speedAfterHit({ current = 130.0, offsetFrac = 1.0, base = 130.0 });
        Assert.assertEq(expected = 139.9125, round4(actual))

    // どれだけ加速しても上限 base×1.6 = 208 でクランプされる（204×1.025×1.05 = 219.5 → 208）。
    @Test
    def testSpeedClampsAtMax(): Unit \ Assert =
        let actual = Bounce.speedAfterHit({ current = 204.0, offsetFrac = -1.0, base = 130.0 });
        Assert.assertEq(expected = 208.0, round4(actual))

    // 基準より遅くなっていたら（サーブ直後の異常など）基準まで戻してから加速する。
    @Test
    def testSpeedFloorsAtBase(): Unit \ Assert =
        let actual = Bounce.speedAfterHit({ current = 50.0, offsetFrac = 0.0, base = 130.0 });
        Assert.assertEq(expected = 133.25, round4(actual))

    // 統合: パドル中央に当てたボールは真上へ返り（vx=0・vy<0）、速さは 133.25 に増える。
    @Test
    def testPaddleCenterBounceAcceleratesStraightUp(): Unit \ Assert =
        let final = Replay.play(Step.update, Trace.dt(), Trace.flight(30), Trace.paddleBounceWorld(0.0));
        let actual = Trace.ballVelOf(final)
            |> Option.map(v -> (round4(v#x), v#y < 0.0, round4(Vec2.length(v))));
        Assert.assertEq(expected = Some((0.0, true, 133.25)), actual)

    // ミス（落下）でサーブに戻ると速さは基準へリセット: 落下 → 再サーブ発射で |v| = 130。
    @Test
    def testSpeedResetsAfterMiss(): Unit \ Assert =
        // 画面下端の外を速い速度で落下中のボール。
        let falling = Trace.mkWorld({ statics = Nil,
                                      ball = { pos = Trace.vec(160.0, 260.0), vel = Trace.vec(0.0, 200.0) },
                                      blocks = Nil, durabilities = Nil });
        let missed = Step.update(Trace.idle(), Trace.dt(), falling);
        let relaunched = Step.update({ launch = true | Trace.idle() }, Trace.dt(), missed);
        Assert.assertEq(expected = (Some(2), true, Some(130.0)),
                        (Trace.livesOf(missed), Trace.isWaiting(missed), ballSpeedOf(relaunched)))

    // ========================================================================
    // ボールの残像（位置リング＋速度→色ランプ）
    // ========================================================================

    // リングは有界: 何フレーム走らせても長さは trailLength (12) を超えない。
    // また最新の点はボールの現在位置と一致する（尾はボールから生える）。
    @Test
    def testTrailRingIsBounded(): Unit \ Assert =
        let final = Replay.play(Step.update, Trace.dt(), Trace.flight(40),
            Trace.mkWorld({ statics = Nil,
                            ball = { pos = Trace.vec(160.0, 120.0), vel = Trace.vec(30.0, -20.0) },
                            blocks = Nil, durabilities = Nil }));
        let trail = Trace.trailOf(final);
        let headXY = List.head(trail) |> Option.map(p -> (p#x, p#y));
        let ballXY = Trace.coreOf(final) |> Option.map(c -> (c#ballPos#x, c#ballPos#y));
        Assert.assertEq(expected = (12, true), (List.length(trail), headXY == ballXY))

    // ミスでサーブへ戻ると残像は消える（瞬間移動に尾を引かせない）。
    @Test
    def testTrailClearsOnMiss(): Unit \ Assert =
        let falling = Trace.mkWorld({ statics = Nil,
                                      ball = { pos = Trace.vec(160.0, 260.0), vel = Trace.vec(0.0, 200.0) },
                                      blocks = Nil, durabilities = Nil });
        let flown = Replay.play(Step.update, Trace.dt(), Trace.flight(3), falling);
        Assert.assertEq(expected = 0, List.length(Trace.trailOf(flown)))

    // 速度→色ランプの境界を具体色で pin: 基準(0)=冷・中間(0.5)=温・最大(1)=熱。
    // Color には Eq が無いので (r, g, b) の組で比べる。
    @Test
    def testTrailColorRamp(): Unit \ Assert =
        let rgb = c -> (c#r, c#g, c#b);
        let actual = (rgb(Palette.trailColor(0.0)), rgb(Palette.trailColor(0.5)), rgb(Palette.trailColor(1.0)));
        Assert.assertEq(
            expected = (rgb(Palette.trailCool()), rgb(Palette.trailWarm()), rgb(Palette.trailHot())),
            actual)

    // 速さの正規化: 基準 130 → 0、上限 208 → 1、中間 169 → 0.5、範囲外はクランプ。
    // 除算の 2 進誤差が乗るので round4 で比べる。
    @Test
    def testSpeedRatioNormalizes(): Unit \ Assert =
        let ratio = speed -> round4(Bounce.speedRatio(speed, 130.0));
        let actual = (ratio(130.0), ratio(169.0), ratio(208.0), ratio(300.0), ratio(50.0));
        Assert.assertEq(expected = (0.0, 0.5, 1.0, 1.0, 0.0), actual)

    // ========================================================================
    // カメラシェイクの減衰
    // ========================================================================

    // t=0 で全振幅、寿命(0.35s)を過ぎたら 0、途中は単調に減る、振幅 0 は揺れない。
    @Test
    def testShakeEnvelopeDecays(): Unit \ Assert =
        let full = View.shakeEnvelope(4.0, 0.0);
        let afterLifetime = View.shakeEnvelope(4.0, 1.0);
        let decreasing = View.shakeEnvelope(4.0, 0.05) > View.shakeEnvelope(4.0, 0.15);
        let zeroAmplitude = View.shakeEnvelope(0.0, 0.0);
        Assert.assertEq(expected = (4.0, 0.0, true, 0.0), (full, afterLifetime, decreasing, zeroAmplitude))

    // ========================================================================
    // ブロックの耐久・破壊・スコア・シェイク
    // ========================================================================

    /// ブロック 1 個の真下にボールを重ねて上向きに置いた World（update 1 回で確実に当たる）。
    /// durability = None なら耐久の店に載せない = 壊れないブロック。
    def overlapWorld(durability: Option[Field.Durability]): Field.World =
        Trace.mkWorld({
            statics = (Trace.blockId(), Trace.vec(160.0, 60.0), Trace.rect(30.0, 12.0)) :: Nil,
            ball = { pos = Trace.vec(160.0, 68.0), vel = Trace.vec(0.0, -130.0) },
            blocks = (Trace.blockId(), 0) :: Nil,
            durabilities = durability |> Option.map(d -> (Trace.blockId(), d)) |> Option.toList })

    def blockHp(id: EntityId, world: Field.World): Option[Int32] =
        Trace.coreOf(world)
            |> Option.flatMap(c -> Map.get(id, c#durabilities))
            |> Option.map(durability -> durability#hp)

    // ハードブロックの 1 発目: 耐えて hp 2→1、得点なし、小シェイク（1.5）。
    @Test
    def testHardBlockSurvivesFirstHit(): Unit \ Assert =
        let after = Step.update(Trace.idle(), Trace.dt(), overlapWorld(Some({ hp = 2, maxHp = 2 })));
        Assert.assertEq(expected = (Some(1), Some(0), Some(1.5)),
                        (blockHp(Trace.blockId(), after), Trace.scoreOf(after),
                         Trace.coreOf(after) |> Option.map(c -> c#shakeMagnitude)))

    // ハードブロックの 2 発目（残り1発）: 破壊して消え、得点 30、大シェイク（4.0）。
    @Test
    def testHardBlockDestroyedOnSecondHit(): Unit \ Assert =
        let after = Step.update(Trace.idle(), Trace.dt(), overlapWorld(Some({ hp = 1, maxHp = 2 })));
        Assert.assertEq(expected = (None, Some(30), Some(4.0)),
                        (blockHp(Trace.blockId(), after), Trace.scoreOf(after),
                         Trace.coreOf(after) |> Option.map(c -> c#shakeMagnitude)))

    // 通常ブロック: 1発で破壊して消え、得点 10、小シェイク（1.5）。
    @Test
    def testNormalBlockDestroyed(): Unit \ Assert =
        let after = Step.update(Trace.idle(), Trace.dt(), overlapWorld(Some({ hp = 1, maxHp = 1 })));
        Assert.assertEq(expected = (None, Some(10), Some(1.5)),
                        (blockHp(Trace.blockId(), after), Trace.scoreOf(after),
                         Trace.coreOf(after) |> Option.map(c -> c#shakeMagnitude)))

    // 壊れないブロック（耐久の店に不在）: 当たっても盤に残り、得点もシェイクも起きない。
    // ボールは物理で跳ね返るだけ（y 速度が下向きへ反転）。
    @Test
    def testUnbreakableBlockShrugsOffHit(): Unit \ Assert =
        let after = Step.update(Trace.idle(), Trace.dt(), overlapWorld(None));
        let core = Trace.coreOf(after);
        let bouncedDown = Trace.ballVelOf(after) |> Option.map(v -> v#y > 0.0);
        Assert.assertEq(expected = (Some(true), Some(0), Some(0.0), Some(true)),
                        (core |> Option.map(c -> Map.memberOf(Trace.blockId(), c#positions)),
                         Trace.scoreOf(after),
                         core |> Option.map(c -> c#shakeMagnitude), bouncedDown))

    // クリア判定は「壊せるブロックが 0」: 不壊ブロックだけが残った盤は勝ち、通常が残れば未決着。
    // 通常ブロック 1 個の盤（未決着）から耐久の店だけ空にすると、盤に残るブロックは壊せなくなり勝ち
    // （不壊ブロック = positions/blocks には居るが durabilities に不在、を耐久を抜いて作る）。
    @Test
    def testWonIgnoresUnbreakableBlocks(): Unit \ Assert =
        let coreWith = Trace.coreOf(overlapWorld(Some({ hp = 1, maxHp = 1 })));
        let coreOnly = coreWith |> Option.map(c -> { durabilities = Map.empty() | c });
        Assert.assertEq(expected = (Some(true), Some(false)),
                        (coreOnly |> Option.map(c -> Field.won(c)), coreWith |> Option.map(c -> Field.won(c))))

    // ========================================================================
    // レベル配置と進行
    // ========================================================================

    /// レベル n の（壊せる数, 壊れない数）。
    def levelCensus(n: Int32): (Int32, Int32) =
        let core = Field.freshCore(n);
        (Map.size(core#durabilities), Map.size(core#blocks) - Map.size(core#durabilities))

    // 配置の宣言データを数で固定: 1面=導入22個（不壊なし）/ 2面=19+不壊7 / 3面=26+不壊8。
    @Test
    def testLevelCensus(): Unit \ Assert =
        Assert.assertEq(expected = ((22, 0), (19, 7), (26, 8)),
                        (levelCensus(1), levelCensus(2), levelCensus(3)))

    // クリア後の Enter は次の面へ進み、スコアと残機を持ち越す。
    @Test
    def testClearAdvancesToNextLevelCarryingScore(): Unit \ Assert =
        let clearedCore = { durabilities = Map.empty(), score = 220, lives = 2 | Field.freshCore(1) };
        let cleared = { params = GameParameters.defaults(), phase = Field.Phase.Cleared(clearedCore) };
        let next = Step.update({ enter = true | Trace.idle() }, Trace.dt(), cleared);
        let nextCore = Trace.coreOf(next);
        Assert.assertEq(expected = (Some(2), Some(220), Some(2), Some(19)),
                        (nextCore |> Option.map(c -> c#level),
                         nextCore |> Option.map(c -> c#score),
                         nextCore |> Option.map(c -> c#lives),
                         nextCore |> Option.map(c -> Map.size(c#durabilities))))

    // 最終面（3面）をクリアして Enter するとタイトルへ戻る。
    @Test
    def testClearOfLastLevelReturnsToTitle(): Unit \ Assert =
        let clearedCore = { durabilities = Map.empty() | Field.freshCore(3) };
        let cleared = { params = GameParameters.defaults(), phase = Field.Phase.Cleared(clearedCore) };
        let after = Step.update({ enter = true | Trace.idle() }, Trace.dt(), cleared);
        Assert.assertEq(expected = true, Trace.isTitle(after))

    // 最後のブロックを壊した瞬間、局面は Cleared になり、速度という状態はボールごと消える
    // （Moving でなくなる）。クリアはモーダルなので、以降 Enter を押さずに何フレーム進めても
    // ボールの位置は 1px も動かない（物理は回らない・ballPos は凍結）。
    @Test
    def testBallFreezesAfterClear(): Unit \ Assert =
        let justWon = Step.update(Trace.idle(), Trace.dt(), overlapWorld(Some({ hp = 1, maxHp = 1 })));
        let frozen = Trace.coreOf(justWon) |> Option.map(c -> (c#ballPos#x, c#ballPos#y));
        let later = Replay.play(Step.update, Trace.dt(), Trace.flight(10), justWon);
        let laterPos = Trace.coreOf(later) |> Option.map(c -> (c#ballPos#x, c#ballPos#y));
        Assert.assertEq(
            expected = (true, true, true),
            (Trace.isCleared(justWon),                    // クリア局面へ移った
             Option.isEmpty(Trace.ballVelOf(justWon)),    // 速度という状態が無い
             frozen == laterPos))                          // ballPos は凍結して動かない

    // ========================================================================
    // 落下でミス
    // ========================================================================

    // 画面下端より下のボールは 1 フレームで残機を 1 減らし、サーブ待ちに戻る。
    @Test
    def testBallFallLosesLife(): Unit \ Assert =
        let fallen = Trace.mkWorld({ statics = Nil,
                                     ball = { pos = Trace.vec(160.0, 260.0), vel = Trace.vec(0.0, 130.0) },
                                     blocks = Nil, durabilities = Nil });
        let after = Step.update(Trace.idle(), Trace.dt(), fallen);
        Assert.assertEq(expected = (Some(2), true), (Trace.livesOf(after), Trace.isWaiting(after)))

    // ========================================================================
    // シナリオ Trace（Replay で純粋 update を駆動し結末を固定）
    // ========================================================================

    // 破壊シナリオ: 3 個並びの中央（通常ブロック）へ下から当てて壊す。中央だけ消えて 2 個残り、得点 10。
    @Test
    def testBlockBreakScenarioBreaksCenter(): Unit \ Assert =
        let final = Replay.play(Step.update, Trace.dt(), Trace.flight(60), Trace.blockBreakWorld());
        Assert.assertEq(expected = (Some(2), Some(10)),
                        (Trace.coreOf(final) |> Option.map(c -> Map.size(c#blocks)), Trace.scoreOf(final)))

    // ハードシェイクシナリオ: 床で跳ね返って中央のハードブロックへ 2 回当てて壊す。2 個残り、得点 30。
    @Test
    def testHardShakeScenarioDestroysCenter(): Unit \ Assert =
        let final = Replay.play(Step.update, Trace.dt(), Trace.flight(160), Trace.hardShakeWorld());
        Assert.assertEq(expected = (Some(2), Some(30)),
                        (Trace.coreOf(final) |> Option.map(c -> Map.size(c#blocks)), Trace.scoreOf(final)))

    // ポケットシナリオ: レベル 3 の縦通路へ撃ち込むと、ポケット内で壊し続けて得点が伸びる。
    // 600 フレーム（9.4 秒）で通常 5 個 = 50 点（決定論なので値は毎回同じ。実走 oracle で確認済み）。
    @Test
    def testPocketScenarioChewsThroughTopRows(): Unit \ Assert =
        let final = Replay.play(Step.update, Trace.dt(), Trace.flight(600), Trace.pocketWorld());
        Assert.assertEq(expected = (Some(50), Some(21)),
                        (Trace.scoreOf(final), Trace.coreOf(final) |> Option.map(c -> Map.size(c#durabilities))))

    // 加速ラリーシナリオ: 密閉ラリー室での垂直往復はヒット毎に +2.5% ずつ速くなる。
    // 1000 フレーム（15.6 秒）後の速さを pin する（値は実走 oracle で確認済み）。
    @Test
    def testSpeedRampScenarioAccelerates(): Unit \ Assert =
        let final = Replay.play(Step.update, Trace.dt(), Trace.flight(1000), Trace.speedRampWorld());
        Assert.assertEq(expected = Some(174.8355), ballSpeedOf(final))
}
