// Calendar（時計と暦）— 秒が分に積もること、日をまたぐこと、季節と年が回ること。
mod TestCalendar {

    def spec(): Calendar.Spec =
        { minutesPerDay = 1440, minutesPerHour = 60, secondsPerMinute = 0.5,
          daysPerSeason = 4, seasons = "春" :: "夏" :: "秋" :: "冬" :: Nil }

    @Test
    def testAdvanceAccumulatesWholeMinutes(): Unit \ Assert =
        // 1 分 = 0.5 秒なら、1.2 秒で 2 分進み 0.2 秒が持ち越される。
        let after = Calendar.advance(spec(), 1.2, Calendar.at(spec(), 0, 0));
        Assert.assertEq(expected = 2, Calendar.minuteOfDay(spec(), after))

    @Test
    def testAdvanceDoesNotDropTimeAcrossFrames(): Unit \ Assert =
        // 小刻みに進めても端数を貯め込むので、まとめて進めたのとほぼ同じ時刻に着く。
        // ぴったり一致は求めない — 小数の足し算の丸めで 1 分ぶんまではずれうる。
        let once = Calendar.advance(spec(), 3.0, Calendar.at(spec(), 0, 0));
        let split = List.range(0, 10) |> List.foldLeft((s, _) ->
            Calendar.advance(spec(), 0.3, s), Calendar.at(spec(), 0, 0));
        Assert.assertEq(expected = true, Int32.abs(once#minute - split#minute) <= 1)

    @Test
    def testHourAndMinuteReadTheClock(): Unit \ Assert =
        let s = Calendar.at(spec(), 0, 6 * 60 + 30);
        Assert.assertEq(expected = (6, 30, "6:30"),
            (Calendar.hourOf(spec(), s), Calendar.minuteOfHour(spec(), s), Calendar.hhmm(spec(), s)))

    @Test
    def testDayRollsWhenTheClockPassesMidnight(): Unit \ Assert =
        let before = Calendar.at(spec(), 0, 1439);
        let after = Calendar.advance(spec(), 1.0, before);
        Assert.assertEq(expected = (true, 1), (Calendar.dayRolled(spec(), before, after),
                                               Calendar.dayOf(spec(), after)))

    @Test
    def testSeasonAndYearWrapAround(): Unit \ Assert =
        // 1 季節 4 日・四季なら、16 日目で 2 年目の春 1 日目に戻る。
        let s = Calendar.at(spec(), 16, 0);
        Assert.assertEq(expected = ("春", 1, 2),
            (Calendar.seasonOf(spec(), s), Calendar.dayOfSeason(spec(), s), Calendar.yearOf(spec(), s)))

    @Test
    def testSleepToAlwaysLandsOnTheNextDay(): Unit \ Assert =
        // すでに朝 6 時を過ぎていても、寝れば必ず翌朝になる。
        let s = Calendar.at(spec(), 3, 20 * 60);
        let woken = Calendar.sleepTo(spec(), 6 * 60, s);
        Assert.assertEq(expected = (4, 360), (Calendar.dayOf(spec(), woken),
                                              Calendar.minuteOfDay(spec(), woken)))

    @Test
    def testDayFractionSpansTheWholeDay(): Unit \ Assert =
        Assert.assertEq(expected = (0.0, 0.5),
            (Calendar.dayFraction(spec(), Calendar.at(spec(), 0, 0)),
             Calendar.dayFraction(spec(), Calendar.at(spec(), 0, 720))))

    @Test
    def testNonFiniteDeltaDoesNotStopTheClock(): Unit \ Assert =
        // 数でない dt が持ち越しに混ざると、以後どれだけ呼んでも時計が進まなくなる。
        let spec = Calendar.defaults();
        let broken = Calendar.advance(spec, Float64.nan(), Calendar.at(spec, 0, 0));
        let after = Calendar.advance(spec, 10.0, broken);
        Assert.assertEq(expected = true, after#minute > 0)

    @Test
    def testMinutesBeforeTheStartReadAsThePreviousDay(): Unit \ Assert =
        // 「今より 30 分前」は前日の終わり。日と時刻が食い違ってはいけない。
        let spec = Calendar.defaults();
        let s = Calendar.at(spec, 0, -30);
        Assert.assertEq(expected = (-1, spec#minutesPerDay - 30),
                        (Calendar.dayOf(spec, s), Calendar.minuteOfDay(spec, s)))
}
