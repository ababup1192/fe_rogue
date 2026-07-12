// TestHero — ヒーロー描画の pin: ポーズ選択（状態機械）・走りコマの移動量駆動・
// 向きの鏡映・全ポーズの描画網羅。ジオメトリの数値は Hero のポーズ表から手計算で導ける
// 正確な二進小数（±3.5, ±2.25 など）だけを pin する。

mod TestHero {

    def basePlayer(): Field.Player = Trace.flatWorld()#player

    def lookOf(pose: Hero.Pose, frame: Int32, facing: Float64): Hero.Look =
        { pose = pose, frame = frame, facing = facing,
          tint = Palette.player(), stretch = 0.0, squash = 0.0 }

    // ポーズ選択の状態機械: 接地静止 = 待機 / 接地走り = 走り / 上昇 = ジャンプ / 下降 = 落下。
    @Test
    def testPoseSelection(): Unit \ Assert =
        let p = basePlayer();
        let idle = { grounded = true, vel = { x = 0.0, y = 0.0 } | p };
        let running = { grounded = true, vel = { x = 100.0, y = 0.0 } | p };
        let jumping = { grounded = false, vel = { x = 0.0, y = -100.0 } | p };
        let falling = { grounded = false, vel = { x = 0.0, y = 100.0 } | p };
        Assert.assertEq(
            expected = (Hero.Pose.IdlePose, Hero.Pose.RunPose, Hero.Pose.JumpPose, Hero.Pose.FallPose),
            (Hero.poseOf(idle), Hero.poseOf(running), Hero.poseOf(jumping), Hero.poseOf(falling)))

    // 走りのコマは走行距離駆動: 10px ごとに 1 コマ進み、4 コマで一周する（時刻は無関係）。
    @Test
    def testRunGaitByDistance(): Unit \ Assert =
        let frameAtX = x -> Hero.frameOf(Hero.Pose.RunPose, 999.0, x);
        Assert.assertEq(expected = (0, 1, 2, 3, 0),
            (frameAtX(0.0), frameAtX(10.0), frameAtX(25.0), frameAtX(35.0), frameAtX(40.0)))

    // 待機の呼吸は時刻駆動（2 コマ/秒・2 コマ循環）。空中ポーズは常に 1 コマ目。
    @Test
    def testIdleAndAirFrames(): Unit \ Assert =
        let idleAt = t -> Hero.frameOf(Hero.Pose.IdlePose, t, 12345.0);
        Assert.assertEq(expected = (0, 1, 0, 0, 0),
            (idleAt(0.0), idleAt(0.5), idleAt(1.0),
             Hero.frameOf(Hero.Pose.JumpPose, 7.0, 500.0),
             Hero.frameOf(Hero.Pose.FallPose, 7.0, 500.0)))

    // facing で横オフセットが鏡映される: 瞳（z=2 の 2 パーツ・向いている側へ +1.25 寄る）の
    // ローカル x は facing +1 で (-2.25, 4.75)、-1 でその符号反転。
    @Test
    def testFacingMirrorsPupils(): Unit \ Assert =
        let pupilXs = facing ->
            Hero.parts(lookOf(Hero.Pose.RunPose, 0, facing))
            |> List.filter(p -> p#z == 2)
            |> List.map(p -> p#cx);
        Assert.assertEq(expected = ((-2.25) :: 4.75 :: Nil, 2.25 :: (-4.75) :: Nil),
            (pupilXs(1.0), pupilXs(-1.0)))

    // 全ポーズ × 両向きで描画は必ず 7 パーツ（体 + 白目 2 + 瞳 2 + 脚 2）を返す。
    @Test
    def testDrawIsTotal(): Unit \ Assert =
        let poses = Hero.Pose.IdlePose :: Hero.Pose.RunPose :: Hero.Pose.JumpPose :: Hero.Pose.FallPose :: Nil;
        let counts = poses |> List.flatMap(pose ->
            List.map(facing ->
                List.length(Hero.draw(10, { x = 100.0, y = 100.0 }, lookOf(pose, 0, facing))),
                1.0 :: -1.0 :: Nil));
        Assert.assertEq(expected = true, List.forAll(n -> n == 7, counts))
}
