// AudioFade のテスト。volumeOf を t=0/0.5/1 とクランプ域の具体値で固定し、
// フェードイン・フェードアウト・クロスフェード・Transition.Progress との組み合わせが
// すべてこの 1 つの純関数で組めることを確かめる。

mod TestAudioFade {

    // ── volumeOf: フェードイン（0 → 1）──

    // フェードインは t=0 で無音・t=0.5 で半分・t=1 で全開。
    @Test
    def testFadeInAtKeyPoints(): Unit \ Assert =
        let fade = AudioFade.fadeIn();
        Assert.assertEq(expected = (0.0, 0.5, 1.0),
            (AudioFade.volumeOf(fade, 0.0), AudioFade.volumeOf(fade, 0.5), AudioFade.volumeOf(fade, 1.0)))

    // ── volumeOf: フェードアウト（1 → 0）──

    // フェードアウトは t=0 で全開・t=0.5 で半分・t=1 で無音。
    @Test
    def testFadeOutAtKeyPoints(): Unit \ Assert =
        let fade = AudioFade.fadeOut();
        Assert.assertEq(expected = (1.0, 0.5, 0.0),
            (AudioFade.volumeOf(fade, 0.0), AudioFade.volumeOf(fade, 0.5), AudioFade.volumeOf(fade, 1.0)))

    // ── volumeOf: クランプと任意の端点 ──

    // t が範囲の外でも音量は端の値で止まる（負や 1 超の音量にならない）。
    @Test
    def testVolumeClampsOutOfRangeT(): Unit \ Assert =
        let fade = AudioFade.fadeIn();
        Assert.assertEq(expected = (0.0, 1.0),
            (AudioFade.volumeOf(fade, -0.5), AudioFade.volumeOf(fade, 1.5)))

    // 端点は 0/1 でなくてもよい（例: BGM を 0.2 から 0.8 へ持ち上げる）。t=0.5 で中点。
    @Test
    def testVolumeWithCustomEndpoints(): Unit \ Assert =
        Assert.assertEq(expected = 0.5,
            AudioFade.volumeOf({ start = 0.2, target = 0.8 }, 0.5))

    // ── crossfadeOf: 2 曲の入れ替え ──

    // t=0.25 で消える側 0.75・現れる側 0.25。同じ t の volumeOf 2 回と一致する。
    @Test
    def testCrossfadeAtQuarter(): Unit \ Assert =
        Assert.assertEq(expected = (0.75, 0.25), AudioFade.crossfadeOf(0.25))

    // どの t でも 2 つの和は 1.0（入れ替えの途中で合計音量が凹まない）。
    @Test
    def testCrossfadeSumIsOne(): Unit \ Assert =
        let sums = List.map(t -> {
            let (fading, rising) = AudioFade.crossfadeOf(t);
            fading + rising
        }, 0.0 :: 0.3 :: 0.7 :: 1.0 :: Nil);
        Assert.assertEq(expected = 1.0 :: 1.0 :: 1.0 :: 1.0 :: Nil, sums)

    // ── Transition.Progress との組み合わせ（進行管理はエンジンの既存部品を再利用）──

    // 2 秒のフェードインを 0.5 秒進めると t=0.25 → 音量 0.25。
    // 進行（Progress）と音量（volumeOf）の分業がこの 1 行の合成で成り立つことの pin。
    @Test
    def testProgressDrivesFadeIn(): Unit \ Assert =
        let progress = Transition.start(2.0) |> Transition.advance(0.5);
        Assert.assertEq(expected = 0.25,
            AudioFade.volumeOf(AudioFade.fadeIn(), Transition.tOf(progress)))

    // duration を超えて進めても音量は端で止まる（advance が elapsed を上限で止めるため）。
    @Test
    def testProgressOverrunStopsAtTarget(): Unit \ Assert =
        let progress = Transition.start(1.0) |> Transition.advance(5.0);
        Assert.assertEq(expected = 1.0,
            AudioFade.volumeOf(AudioFade.fadeIn(), Transition.tOf(progress)))
}
