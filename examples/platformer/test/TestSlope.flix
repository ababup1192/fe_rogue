// TestSlope — 坂（SlopeShape2D）の手触りを平文の具体値で固定する。
// 45° 坂（底辺 64・高さ 64）と緩い坂（底辺 64・高さ 32 ≈ 26.6°）の 2 枚を Trace が供給し、
// 登り・下り・静止摩擦・接地しきい値（groundedNormalY = -0.6）・下り坂の吸着（snapProbe 6px）を見る。
// 坂の上は二本立て（Step 参照）: 登り = 速度を斜面の接線に沿わせる / 静止 = その場に停める /
// 下り・滑走は従来の物理のまま（overspeed は手触りの山）。
// pin は Probe の実測値。重力の循環小数を含む値は round4 で比べる。

mod TestSlope {

    /// 小数 4 桁に丸める（重力の循環小数を含む値の比較用）。
    def round4(x: Float64): Float64 = Float64.floor(x * 10000.0 + 0.5) / 10000.0

    def play(cues: List[Replay.Cue[Field.Input]], world: Field.World): Field.World =
        Replay.play(Step.update, Trace.dt(), cues, world)

    def timeline(cues: List[Replay.Cue[Field.Input]], world: Field.World): List[Field.World] =
        Replay.timeline(Step.update, Trace.dt(), cues, world)

    def groundedFrames(worlds: List[Field.World]): Int32 =
        worlds |> List.filter(Trace.groundedOf) |> List.length

    // 45° 坂を登る: 平地（x=120）から右へ 50 フレーム。坂に乗って登り（y が 188 より上がり）、
    // 接地は 50 フレーム全部で途切れない（マイクロホップなし）。終点は実測の pin。
    // 登りは速度が斜面の接線に沿う: 定常の速度は (80, -80) = 斜面に沿って 113px/s
    //（走りの目標 160 の接線 x 成分の 2 乗倍）。旧方式（法線成分ゼロ化まかせ）の
    // 終点 182.7 より大きく進む = 登りが速度を食い潰されない。
    @Test
    def testClimbSteepSlope(): Unit \ Assert =
        let worlds = timeline(Trace.holdRight(50), Trace.slopeWorld());
        let final = play(Trace.holdRight(50), Trace.slopeWorld());
        Assert.assertEq(expected = (true, true, 197.3453, 153.6842, 50),
            (Trace.groundedOf(final), Trace.posOf(final)#y < 188.0,
             round4(Trace.posOf(final)#x), round4(Trace.posOf(final)#y),
             groundedFrames(worlds)))

    // 45° 坂の登り中に入力と逆へ滑らない（ユーザー報告の回帰テスト）: 右を押している間、
    // x は毎フレーム単調非減少。旧方式は低速時に分離の押し出し（下り成分）が勝ち、
    // 右を押しているのに左へ滑って見えた。
    @Test
    def testClimbSteepNeverSlidesBackward(): Unit \ Assert =
        let xs = timeline(Trace.holdRight(40), Trace.slopeWorld())
            |> List.map(w -> Trace.posOf(w)#x);
        let monotonic = List.zip(xs, List.drop(1, xs))
            |> List.forAll(pair -> { let (a, b) = pair; a <= b });
        Assert.assertEq(expected = true, monotonic)

    // 坂を下る（吸着の証明）: 斜辺の頂上寄りから左へ 40 フレーム。下り坂は毎フレーム足元が
    // 逃げるが、snapProbe（6px）の吸着が拾うので接地は一度も切れず、land も鳴らない
    // （鳴ったら接地フリッカの証拠）。平地に降りて左へ走り抜けた終点も実測で pin。
    // D2 の P スピード帯で終点が変わった: 45° の下りは滑りで |vx| が 160 を超え、
    // その帯の減衰は dashAccel（80px/s²）— 下りの勢いがなかなか死なず、より遠くまで走る。
    @Test
    def testDescendSlopeStaysGrounded(): Unit \ Assert =
        let worlds = timeline(Trace.holdLeft(40), Trace.onSlopeWorld());
        let final = play(Trace.holdLeft(40), Trace.onSlopeWorld());
        let landCount = worlds
            |> List.filter(w -> List.memberOf("land", Trace.eventsOf(w)))
            |> List.length;
        Assert.assertEq(expected = (true, 0, 51.978, 188.0),
            (List.forAll(Trace.groundedOf, worlds), landCount,
             round4(Trace.posOf(final)#x), round4(Trace.posOf(final)#y)))

    // 坂の上で静止: 入力なしは滑らない（静止摩擦）。x は 64 フレーム全部で 220.0 のまま動かず、
    // y は分離の平衡（斜面に 0.17px 沈んで釣り合う）へ収束して安定する。接地も切れない。
    // 旧方式は重力 + 分離が斜面方向の速度を毎フレーム残し、1 秒で約 10px 滑り落ちていた。
    @Test
    def testIdleOnSteepSlopeStaysParked(): Unit \ Assert =
        let worlds = timeline(Trace.flight(64), Trace.onSlopeWorld());
        let final = play(Trace.flight(64), Trace.onSlopeWorld());
        let xPinned = worlds |> List.forAll(w -> Trace.posOf(w)#x == 220.0);
        Assert.assertEq(expected = (true, 220.0, 131.1961, 64),
            (xPinned, Trace.posOf(final)#x, round4(Trace.posOf(final)#y),
             groundedFrames(worlds)))

    // 緩い坂（26.6°・法線 y ≈ -0.894）を登る: 右へ 40 フレーム、接地は全フレーム続く。
    // 定常の速度は (128, -64) = 斜面に沿って 143px/s（緩いほど水平換算が 160 に近づく）。
    @Test
    def testClimbGentleSlope(): Unit \ Assert =
        let worlds = timeline(Trace.holdRight(40), Trace.gentleSlopeWorld());
        let final = play(Trace.holdRight(40), Trace.gentleSlopeWorld());
        Assert.assertEq(expected = (true, 198.6108, 171.2782),
            (List.forAll(Trace.groundedOf, worlds),
             round4(Trace.posOf(final)#x), round4(Trace.posOf(final)#y)))

    // しきい値の理由: 45° 斜辺の上の円の接触法線は (-0.7071, -0.7071)。上向き成分 -0.7071 は
    // groundedNormalY（-0.6）を下回るので接地扱いになる（旧しきい値 -0.7 ではぎりぎりの帯だった）。
    @Test
    def testSlopeContactNormalCountsAsGrounded(): Unit \ Assert =
        let world = Trace.onSlopeWorld();
        // 静止位置から 0.5px 沈めて確実に接触させ、法線を読む。
        let positions = world#platforms |> List.map(pf -> (pf#id, pf#pos)) |> List.toMap
            |> Map.insert(Field.playerId(), { y = world#player#pos#y + 0.5 | world#player#pos });
        let shapes = world#platforms |> List.map(pf -> (pf#id, Field.platformShape(pf))) |> List.toMap
            |> Map.insert(Field.playerId(), Field.playerShape());
        let normal = Physics2D.detect(positions, shapes)
            |> Physics2D.contactsOf(Field.playerId())
            |> List.head
            |> Option.map(contact -> contact#normal);
        Assert.assertEq(expected = (Some((-0.7071, -0.7071)), Some(true)),
            (normal |> Option.map(n -> (round4(n#x), round4(n#y))),
             normal |> Option.map(n -> n#y < Field.groundedNormalY())))

    // 平地の回帰: 吸着は平地では一度も発火しない（接触を失わないので条件に入らない）。
    // 30 フレーム静止しても位置・速度は坂対応前と同じ厳密値のまま。
    @Test
    def testSnapIsDormantOnFlatGround(): Unit \ Assert =
        let final = play(Trace.flight(30), Trace.flatWorld());
        Assert.assertEq(expected = (160.0, 188.0, true, 0.0),
            (Trace.posOf(final)#x, Trace.posOf(final)#y,
             Trace.groundedOf(final), Trace.velOf(final)#y))

    // platformShape が坂を坂として物理へ渡している証拠: world.json の platforms に
    // slope="right" が載る（矩形は "none"）。
    @Test
    def testSlopePlatformInWorldDump(): Unit \ Assert =
        let rect = { position = Vec2.zero(), size = { x = Field.designW(), y = Field.designH() } };
        let text = WorldDump.dump(rect, Trace.slopeWorld())
            |> String.replace(src = " ", dst = "")
            |> String.replace(src = "\n", dst = "");
        Assert.assertEq(expected = (true, true),
            (String.contains({substr = "\"slope\":\"right\""}, text),
             String.contains({substr = "\"slope\":\"none\""}, text)))
}
