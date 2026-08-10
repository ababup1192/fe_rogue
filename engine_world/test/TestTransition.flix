// Transition のテスト。純関数層（itemsAt の被覆矩形とアルファ）を t=0/0.5/1 の具体値で固定し、
// 進行層（Progress）のクランプと done を確かめる。

mod TestTransition {

    def black(): Color = { r = 0.0f32, g = 0.0f32, b = 0.0f32 }

    def viewport(): Vec2.Vec2 = { x = 160.0, y = 120.0 }

    /// itemsAt へ渡す指定（種類と t 以外はテスト共通の値で固定）。
    def coverAt(kind: Transition.Kind, t: Float64): Transition.Cover =
        { kind = kind, t = t, viewport = viewport(), color = black(), z = Transition.defaultZ() }

    /// PlacedItem から Box の (幅, 高さ, alpha) を取り出す（Transition.itemsAt は Box しか返さない）。
    def boxOf(placed: Render.PlacedItem): Option[(Float64, Float64, Float32)] =
        match placed#item {
            case Render.Item.Box(b) => Some((b#size#x, b#size#y, b#alpha))
            case _                  => None
        }

    /// PlacedItem から Box の zIndex を取り出す。
    def zOf(placed: Render.PlacedItem): Option[Int32] =
        match placed#item {
            case Render.Item.Box(b) => Some(b#zIndex)
            case _                  => None
        }

    // ── itemsAt: FadeOut ──

    // FadeOut は t=0 で覆いなし（0 個）。
    @Test
    def testFadeOutAtZeroIsEmpty(): Unit \ Assert =
        Assert.assertEq(expected = 0,
            List.length(Transition.itemsAt(coverAt(Transition.Kind.FadeOut, 0.0))))

    // FadeOut は t=0.5 で画面全体を覆う 1 枚・alpha は 0.5。
    @Test
    def testFadeOutAtHalf(): Unit \ Assert =
        let items = Transition.itemsAt(coverAt(Transition.Kind.FadeOut, 0.5));
        Assert.assertEq(expected = (1, Some((160.0, 120.0, 0.5f32))),
            (List.length(items), List.head(items) |> Option.flatMap(boxOf)))

    // FadeOut は t=1 で不透明の全面覆い・左上原点は (0,0)。
    @Test
    def testFadeOutAtOne(): Unit \ Assert =
        let items = Transition.itemsAt(coverAt(Transition.Kind.FadeOut, 1.0));
        let at = List.head(items) |> Option.map(p -> (p#at#x, p#at#y));
        Assert.assertEq(expected = (Some((0.0, 0.0)), Some((160.0, 120.0, 1.0f32))),
            (at, List.head(items) |> Option.flatMap(boxOf)))

    // ── itemsAt: FadeIn（FadeOut の裏返し）──

    // FadeIn は t=0 で不透明の全面覆い（覆いが晴れる前＝真っ黒から開始）。
    @Test
    def testFadeInAtZeroIsOpaque(): Unit \ Assert =
        let items = Transition.itemsAt(coverAt(Transition.Kind.FadeIn, 0.0));
        Assert.assertEq(expected = Some((160.0, 120.0, 1.0f32)), List.head(items) |> Option.flatMap(boxOf))

    // FadeIn は t=1 で覆いなし（完全に晴れた）。
    @Test
    def testFadeInAtOneIsEmpty(): Unit \ Assert =
        Assert.assertEq(expected = 0,
            List.length(Transition.itemsAt(coverAt(Transition.Kind.FadeIn, 1.0))))

    // ── itemsAt: WipeLeft / WipeRight ──

    // WipeLeft は右端から帯が伸びる: t=0.5 で幅 80（画面幅の半分）、x は 80（右半分を覆う）。
    @Test
    def testWipeLeftAtHalfCoversRightHalf(): Unit \ Assert =
        let items = Transition.itemsAt(coverAt(Transition.Kind.WipeLeft, 0.5));
        let at = List.head(items) |> Option.map(p -> p#at#x);
        Assert.assertEq(expected = (Some(80.0), Some((80.0, 120.0, 1.0f32))),
            (at, List.head(items) |> Option.flatMap(boxOf)))

    // WipeRight は左端から帯が伸びる: t=0.5 で幅 80、x は 0（左半分を覆う）。
    @Test
    def testWipeRightAtHalfCoversLeftHalf(): Unit \ Assert =
        let items = Transition.itemsAt(coverAt(Transition.Kind.WipeRight, 0.5));
        let at = List.head(items) |> Option.map(p -> p#at#x);
        Assert.assertEq(expected = (Some(0.0), Some((80.0, 120.0, 1.0f32))),
            (at, List.head(items) |> Option.flatMap(boxOf)))

    // WipeRight は t=0 で覆いなし。
    @Test
    def testWipeRightAtZeroIsEmpty(): Unit \ Assert =
        Assert.assertEq(expected = 0,
            List.length(Transition.itemsAt(coverAt(Transition.Kind.WipeRight, 0.0))))

    // ── itemsAt: クランプ（[0,1] の外を渡しても暴れない）──

    // 範囲外の t は境界へクランプされる（-1 は 0 と同じ結果、2 は 1 と同じ結果）。
    @Test
    def testItemsAtClampsOutOfRangeT(): Unit \ Assert =
        Assert.assertEq(expected = (0, 1),
            (List.length(Transition.itemsAt(coverAt(Transition.Kind.FadeOut, -1.0))),
             List.length(Transition.itemsAt(coverAt(Transition.Kind.FadeOut, 2.0)))))

    // ── itemsAt: z の配線 ──

    // 覆いの zIndex は Cover の z がそのまま使われる（fade も wipe も同じ）。
    @Test
    def testCoverUsesGivenZ(): Unit \ Assert =
        let fadeZ = Transition.itemsAt({ z = 42 | coverAt(Transition.Kind.FadeOut, 0.5) })
                    |> List.head |> Option.flatMap(zOf);
        let wipeZ = Transition.itemsAt({ z = 7 | coverAt(Transition.Kind.WipeLeft, 0.5) })
                    |> List.head |> Option.flatMap(zOf);
        Assert.assertEq(expected = (Some(42), Some(7)), (fadeZ, wipeZ))

    // defaultZ は UI の layer 帯（layer × 10000）より手前・HUD 帯（ZBand.hudBase）より奥。
    @Test
    def testDefaultZSitsBetweenUiAndDebugBands(): Unit \ Assert =
        Assert.assertEq(expected = 100000, Transition.defaultZ())

    // ── Progress（進行層）──

    // start は経過 0 から始まり、tOf は 0.0。
    @Test
    def testStartBeginsAtZero(): Unit \ Assert =
        Assert.assertEq(expected = 0.0, Transition.tOf(Transition.start(2.0)))

    // advance は経過秒を積み上げ、duration に対する割合が tOf になる（1 秒 / 2 秒 = 0.5）。
    @Test
    def testAdvanceAccumulatesTowardDuration(): Unit \ Assert =
        let progress = Transition.start(2.0) |> Transition.advance(1.0);
        Assert.assertEq(expected = 0.5, Transition.tOf(progress))

    // advance は duration を超えて進めても elapsed が伸び続けない（t は 1.0 で頭打ち）。
    @Test
    def testAdvanceClampsAtDuration(): Unit \ Assert =
        let progress = Transition.start(2.0) |> Transition.advance(5.0);
        Assert.assertEq(expected = (1.0, true), (Transition.tOf(progress), Transition.done(progress)))

    // done は t が 1.0 に届くまで false（duration 直前まで進めてもまだ途中）。
    @Test
    def testDoneRequiresFullProgress(): Unit \ Assert =
        let progress = Transition.start(2.0) |> Transition.advance(1.999);
        Assert.assertEq(expected = false, Transition.done(progress))

    // duration が 0 以下の Progress は開始直後から完了扱い（一瞬で終わる遷移）。
    @Test
    def testZeroDurationIsImmediatelyDone(): Unit \ Assert =
        Assert.assertEq(expected = (1.0, true),
            (Transition.tOf(Transition.start(0.0)), Transition.done(Transition.start(0.0))))
}
