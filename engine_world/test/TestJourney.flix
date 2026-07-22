// Journey のテスト。テストするのは「到着時刻 = 距離 / 速さ」「境界で done」
// 「pos と done が同じ Sample から取れる」だけ — 歩きの絵はテストしない。

mod TestJourney {

    /// 横 30px を速さ 10 で歩く 1 脚: 3 秒で到着。
    def leg(): Journey.Leg =
        { src = { x = 0.0, y = 0.0 }, dst = { x = 30.0, y = 0.0 }, speed = 10.0 }

    /// 到着時刻 = 距離 / 速さ。手前は done=false、境界ちょうどで done=true。
    @Test
    def testDoneFlipsAtDistanceOverSpeed(): Unit \ Assert =
        let legs = leg() :: Nil;
        Assert.assertEq(expected = (false, true, true),
            (Journey.at(legs, 2.999)#done, Journey.at(legs, 3.0)#done,
             Journey.at(legs, 100.0)#done))

    /// 途中の pos は直線補間、done 後は最後の to に立つ(同じ Sample から読む)。
    @Test
    def testPosInterpolatesAndClampsAtEnd(): Unit \ Assert =
        let legs = leg() :: Nil;
        let mid = Journey.at(legs, 1.5);
        let end = Journey.at(legs, 9.0);
        Assert.assertEq(expected = ((15.0, 0.0, false), (30.0, 0.0, true)),
            ((mid#pos#x, mid#pos#y, mid#done), (end#pos#x, end#pos#y, end#done)))

    /// walking は歩いた累計 px(= 歩きコマの種)。2 脚目では 1 脚目の距離が乗る。
    @Test
    def testWalkingAccumulatesAcrossLegs(): Unit \ Assert =
        let legs = leg()
            :: { src = { x = 30.0, y = 0.0 }, dst = { x = 30.0, y = 40.0 }, speed = 20.0 } :: Nil;
        Assert.assertEq(expected = (15.0, 50.0, 70.0),
            (Journey.at(legs, 1.5)#walking, Journey.at(legs, 4.0)#walking,
             Journey.at(legs, 5.0)#walking))

    /// 合計尺は各脚の 距離/速さ の和(30/10 + 40/20 = 5 秒)。
    @Test
    def testTotalSumsLegDurations(): Unit \ Assert =
        let legs = leg()
            :: { src = { x = 30.0, y = 0.0 }, dst = { x = 30.0, y = 40.0 }, speed = 20.0 } :: Nil;
        Assert.assertEq(expected = 5.0, Journey.total(legs))

    /// 脚なしと速さ 0 は fail-open: 脚なしは原点で done、速さ 0 の脚は 0 秒で通過。
    @Test
    def testEmptyAndZeroSpeedFailOpen(): Unit \ Assert =
        let zero = { src = { x = 0.0, y = 0.0 }, dst = { x = 30.0, y = 0.0 }, speed = 0.0 };
        let s0 = Journey.at(Nil, 1.0);
        let s1 = Journey.at(zero :: Nil, 0.0);
        Assert.assertEq(expected = ((0.0, 0.0, true), (30.0, 0.0, true)),
            ((s0#pos#x, s0#pos#y, s0#done), (s1#pos#x, s1#pos#y, s1#done)))
}
