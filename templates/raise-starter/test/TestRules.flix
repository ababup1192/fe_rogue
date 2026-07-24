// ルールと進行・収支だけをテストする（方針どおり）。演出（きらめき・棒の見た目）や座標の写経はしない。
// 期待値はリテラルでなく Doc（RulesDoc / PlanDoc の defaults）から導く — バランス調整で壊れないように。
//
// World を直接組んで規則関数を当てる。
mod TestRules {

    /// 既定の Doc から Title の World を作る土台。
    def base(): World.World =
        World.initial({ rules = RulesDoc.defaults(), theme = ThemeDoc.defaults(), plan = PlanDoc.defaults() })

    /// Day 場面（メニュー中）にした World（選択・進行のテスト用）。
    def day(cursor: Int32, w: World.World): World.World =
        { phase = World.Phase.Day, cursor = cursor | w }

    // ══════════════════════════════════════════════════════
    // 場面の決定（Title→Day・Result→Title）
    // ══════════════════════════════════════════════════════

    @Test
    def testConfirmFromTitleStartsDay(): Unit \ Assert =
        // Title で決定すると Day になり、育ちは 0・1 日目の前（day=0）から。
        let after = World.confirm(base());
        Assert.assertEq(
            expected = (World.Phase.Day, 0, 0),
            (after#phase, after#day, PlanDoc.total(after#stats)))

    @Test
    def testConfirmFromResultReturnsToTitle(): Unit \ Assert =
        // 発表会（Result）で決定すると Title に戻る（必ず仕切り直せる）。
        let w = { phase = World.Phase.Result | base() };
        Assert.assertEq(expected = World.Phase.Title, World.confirm(w)#phase)

    // ══════════════════════════════════════════════════════
    // メニューのカーソル（端で回り込む・Day 以外では動かない）
    // ══════════════════════════════════════════════════════

    @Test
    def testCursorWrapsAtEnds(): Unit \ Assert =
        // 先頭で前へ動かすと末尾へ回り込む（行動数は PlanDoc.actionCount から導く）。
        let n = PlanDoc.actionCount(PlanDoc.defaults());
        let after = World.moveCursor(-1, day(0, base()));
        Assert.assertEq(expected = n - 1, after#cursor)

    @Test
    def testCursorFrozenOutsideDay(): Unit \ Assert =
        // Title など Day 以外ではカーソルは動かない（メニューが出ていないので選べない）。
        let after = World.moveCursor(1, base());     // base は Title
        Assert.assertEq(expected = 0, after#cursor)

    // ══════════════════════════════════════════════════════
    // 行動で数値が育つ（伸び幅は Doc の行動 = PlanDoc.actionAt）
    // ══════════════════════════════════════════════════════

    @Test
    def testChooseActionGrowsStatsByGain(): Unit \ Assert =
        // 0 番の行動を決めると、その行動の伸び幅ぶんだけ各パラメータが増え、Reveal に移る。
        // イベントが混ざらないよう eventChance=0 の rules に差し替える（純粋に伸びだけ見る）。
        let rules = { eventChance = 0.0 | RulesDoc.defaults() };
        let w = day(0, { rules = rules | base() });
        let gain = PlanDoc.actionAt(0, w#plan)#gain;
        let after = World.confirm(w);
        Assert.assertEq(
            expected = (World.Phase.Reveal, gain#power, gain#spirit, gain#skill),
            (after#phase, after#stats#power, after#stats#spirit, after#stats#skill))

    @Test
    def testGrowthIsCappedAtStatCap(): Unit \ Assert =
        // 上限（statCap）を超えて伸びない。上限ちょうどの状態から伸ばしても上限のまま。
        let cap = RulesDoc.defaults()#statCap;
        let rules = { eventChance = 0.0 | RulesDoc.defaults() };
        let full = { power = cap, spirit = cap, skill = cap };
        let w = { stats = full | day(0, { rules = rules | base() }) };
        let after = World.confirm(w);
        Assert.assertEq(
            expected = (cap, cap, cap),
            (after#stats#power, after#stats#spirit, after#stats#skill))

    // ══════════════════════════════════════════════════════
    // 日の進行（決めるたびに day++ ／ 使い切ったら発表会へ）
    // ══════════════════════════════════════════════════════

    @Test
    def testRevealAdvancesToNextDay(): Unit \ Assert =
        // まだ日が残っていれば、Reveal を送ると次の日のメニュー（Day）へ進み day が 1 増える。
        let w = { phase = World.Phase.Reveal, day = 0 | base() };
        let after = World.confirm(w);
        Assert.assertEq(expected = (World.Phase.Day, 1), (after#phase, after#day))

    @Test
    def testLastDayGoesToResult(): Unit \ Assert =
        // 日数（dayCount）ぶん決め切った次は発表会（Result）になる。
        let dayCount = RulesDoc.defaults()#dayCount;
        let w = { phase = World.Phase.Reveal, day = dayCount - 1 | base() };
        let after = World.confirm(w);
        Assert.assertEq(expected = World.Phase.Result, after#phase)

    // ══════════════════════════════════════════════════════
    // 発表会の結末（合計値のしきい値で決まる = PlanDoc.endingFor）
    // ══════════════════════════════════════════════════════

    @Test
    def testEndingPicksTopWhenAboveTopThreshold(): Unit \ Assert =
        // 合計が一番上のしきい値以上なら、一番上の結末になる（結末は Doc から導く）。
        let plan = PlanDoc.defaults();
        let top = plan#endings |> List.sortBy(e -> -e#threshold) |> List.head;
        let topLabel = top |> Option.map(e -> e#label) |> Option.getWithDefault("");
        let topThreshold = top |> Option.map(e -> e#threshold) |> Option.getWithDefault(0);
        // 合計 = topThreshold ちょうどに届く育ちを組む（power に全部寄せる — 上限内）。
        let w = { stats = { power = topThreshold, spirit = 0, skill = 0 } | base() };
        Assert.assertEq(expected = topLabel, World.ending(w)#label)

    @Test
    def testEndingPicksLowestWhenZero(): Unit \ Assert =
        // 何も育っていない（合計 0）なら、しきい値が一番小さい結末（0 のもの）になる。詰まない。
        let plan = PlanDoc.defaults();
        let lowest = plan#endings |> List.sortBy(e -> e#threshold) |> List.head
            |> Option.map(e -> e#label) |> Option.getWithDefault("");
        Assert.assertEq(expected = lowest, World.ending(base())#label)

    // ══════════════════════════════════════════════════════
    // 育ちの合計（3 パラメータの和 = しきい値と比べる値）
    // ══════════════════════════════════════════════════════

    @Test
    def testTotalIsSumOfThreeStats(): Unit \ Assert =
        // total は 3 パラメータの単純な和（結末の判定に使う値）。
        let s = { power = 10, spirit = 20, skill = 5 };
        Assert.assertEq(expected = 35, PlanDoc.total(s))
}
