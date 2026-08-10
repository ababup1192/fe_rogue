// TestFx — 演出の粒（bursts）の pin。粒の位置そのものは pin しない（GameFx.particles の
// 三角関数を使わない散らし方は見た目の調整で変わり得る）。固定するのは「何が・何個・
// どれだけ生きるか」という閉形式の骨格: 発生条件（ジャンプ 1 回に 1 個）・cadence
// （ダッシュ中の土埃の頻度・実測値）・寿命切れの消滅・alpha の範囲。

mod TestFx {

    /// シナリオの全フレームの World（初期は含まない・1 フレーム目の結果から）。
    def timeline(cues: List[Replay.Cue[Field.Input]], world: Field.World): List[Field.World] =
        Replay.timeline(Step.update, Trace.dt(), cues, world)

    def play(cues: List[Replay.Cue[Field.Input]], world: Field.World): Field.World =
        Replay.play(Step.update, Trace.dt(), cues, world)

    // ジャンプは 1 フレーム目にちょうど 1 個の JetKind バーストを立てる
    // （成立は前フレームの接地を見るので、地面に静止した flatWorld から 1 フレームで発火する）。
    @Test
    def testJumpSpawnsOneJetBurst(): Unit \ Assert =
        let worlds = timeline(Trace.holdJump(1), Trace.flatWorld());
        let jetCount = worlds
            |> List.head
            |> Option.map(w -> w#bursts |> List.filter(b -> b#kind == Field.FxKind.JetKind) |> List.length)
            |> Option.getWithDefault(-1);
        Assert.assertEq(expected = 1, jetCount)

    // 接地ダッシュ中の土埃 cadence（実測値）: 64 フレーム（1 秒）ダッシュすると 9 回土埃が立つ。
    // D2 で cadence は速さ連動（8 + 16×band 回/秒・band = (|vx|-160)/120 の clamp）になった —
    // 加速の助走で少なく、P スピード帯に入るほど頻繁になる合計が 9。
    // 累計はフレームごとの「新規発生（elapsed==0.0）」の数え上げ — 古いバーストは寿命切れで
    // 消えるため、最終フレームの bursts の長さでは測れない。
    @Test
    def testDashDustCadenceOverOneSecond(): Unit \ Assert =
        let worlds = timeline(Trace.holdRightDash(64), Trace.flatWorld());
        let dustSpawns = worlds
            |> List.map(w -> w#bursts
                |> List.filter(b -> b#kind == Field.FxKind.DustKind and b#elapsed == 0.0)
                |> List.length)
            |> List.sum;
        Assert.assertEq(expected = 9, dustSpawns)

    // バーストは寿命が切れると消える: ジャンプ 1 回のあと十分な時間（Jet の寿命 0.25s ＝
    // 16 フレームを大きく超える 31 フレーム）飛ばすと、最終 World の bursts に JetKind は残らない。
    @Test
    def testBurstsExpireAfterLifetime(): Unit \ Assert =
        let cues = List.append(Trace.holdJump(1), Trace.flight(30));
        let final = play(cues, Trace.flatWorld());
        let jetCount = final#bursts |> List.filter(b -> b#kind == Field.FxKind.JetKind) |> List.length;
        Assert.assertEq(expected = 0, jetCount)

    // GameFx.particles は純粋な閉形式: 決まったバーストから決まった数の粒を返し、
    // 透明度は常に [0,1] に収まる（負にも 1 超にもならない）。
    // D2 で ジェットは 12 個（勢い演出の強化）になった。
    @Test
    def testParticlesAreBoundedAndPure(): Unit \ Assert =
        let burst: Field.Burst =
            { kind = Field.FxKind.JetKind, seed = 42,
              pos = { x = 100.0, y = 100.0 }, dir = { x = 0.0, y = 1.0 },
              power = 1.0, elapsed = 0.1 };
        let particles = GameFx.particles(burst);
        let allAlphasValid = particles |> List.forAll(triple -> {
            let (_pos, _r, a) = triple;
            a >= 0.0 and a <= 1.0
        });
        Assert.assertEq(expected = (12, true), (List.length(particles), allAlphasValid))
}
