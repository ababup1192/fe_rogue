// TestUiSlider — 左右キーの刻み・クランプ、マウス x → 値の逆写像、track 上への投影を固定する。
mod TestUiSlider {

    // ── step: notch 刻みとクランプ ──

    /// 値 50、範囲 [0,100]、notch 10 のスライダー。
    def st(): UiSlider.State = { value = 50.0, min = 0.0, max = 100.0, notch = 10.0 }

    @Test
    def testStepMovesByNotch(): Unit \ Assert =
        // 右キー（delta=1）で 50 → 60、左キー（delta=-1）で 50 → 40。
        Assert.assertEq(
            expected = (60.0, 40.0),
            (UiSlider.step(1, st())#value, UiSlider.step(-1, st())#value))

    @Test
    def testStepClampsAtBounds(): Unit \ Assert =
        // 上限 100 手前の 95 から notch 10 進めても 100 で止まる。下限も同様。
        let near100 = { value = 95.0 | st() };
        let near0   = { value = 5.0 | st() };
        Assert.assertEq(
            expected = (100.0, 0.0),
            (UiSlider.step(1, near100)#value, UiSlider.step(-1, near0)#value))

    // ── dragValue: マウス x → 値 ──

    @Test
    def testDragValueAtTrackEnds(): Unit \ Assert =
        // トラック幅 100、左端 x=20。左端をクリックすると min、右端をクリックすると max。
        Assert.assertEq(
            expected = (0.0, 100.0),
            (UiSlider.dragValue(20.0, 20.0, 100.0, st()),
             UiSlider.dragValue(120.0, 20.0, 100.0, st())))

    @Test
    def testDragValueAtTrackCenter(): Unit \ Assert =
        // トラック中央（左端+50）は範囲 [0,100] の中央 50。
        Assert.assertEq(expected = 50.0, UiSlider.dragValue(70.0, 20.0, 100.0, st()))

    @Test
    def testDragValueClampsOutsideTrack(): Unit \ Assert =
        // トラック外の x はクランプされ min/max を超えない。
        Assert.assertEq(
            expected = (0.0, 100.0),
            (UiSlider.dragValue(0.0, 20.0, 100.0, st()),
             UiSlider.dragValue(500.0, 20.0, 100.0, st())))

    // ── project: 値 → 塗り幅・つまみ位置 ──

    @Test
    def testProjectAtHalfValue(): Unit \ Assert =
        // 値 50/[0,100] はトラック幅 100 の半分 = 塗り幅 50・つまみ x = 50。
        let p = UiSlider.projectTo(st(), 100.0);
        Assert.assertEq(expected = (50.0, 50.0), (p#fillWidth, p#knobX))

    @Test
    def testProjectAtMinAndMax(): Unit \ Assert =
        // 値が下限なら塗り幅・つまみ x = 0、上限ならトラック幅いっぱい。
        let atMin = UiSlider.projectTo({ value = 0.0 | st() }, 100.0);
        let atMax = UiSlider.projectTo({ value = 100.0 | st() }, 100.0);
        Assert.assertEq(
            expected = ((0.0, 0.0), (100.0, 100.0)),
            ((atMin#fillWidth, atMin#knobX), (atMax#fillWidth, atMax#knobX)))

    // ── apply: UiWorld への書き込み ──

    /// track/fill/knob の 3 兄弟を持つ簡易スライダー UI（fill は幅可変、knob は abs 位置）。
    def sliderUi(): Option[UiStore.UiWorld] =
        let doc = "{\"root\": {\"name\":\"vol\",\"widget\":\"none\",\"children\":["
            + "{\"name\":\"track\",\"widget\":\"box\",\"color\":\"#333333\",\"width\":100,\"height\":8},"
            + "{\"name\":\"fill\",\"widget\":\"box\",\"color\":\"#66ccff\",\"width\":0,\"height\":8},"
            + "{\"name\":\"knob\",\"widget\":\"box\",\"color\":\"#ffffff\",\"width\":6,\"height\":12,\"abs\":[0,-2]}"
            + "]}}";
        JsonCompat.parse(doc)
            |> Option.flatMap(json -> UiSpec.parse(json) |> Result.toOption)
            |> Option.map(spec -> { let (_, ui) = UiSpec.spawnRoot(spec, UiStore.empty()); ui })

    @Test
    def testApplyWritesFillWidthAndKnobPosition(): Unit \ Assert =
        // 値 50/[0,100] をトラック幅 100 へ適用すると、fill 幅・knob x が 50 になる
        // （knob の y は呼び側が渡した -2 をそのまま保つ）。
        let got = sliderUi() |> Option.map(ui -> {
            let ui1 = UiSlider.apply("vol", st(), 100.0, -2.0, ui);
            let knob = UiStore.absOf("vol/knob", ui1) |> Option.map(pos -> (pos#x, pos#y));
            (UiStore.widthPxOf("vol/fill", ui1), knob)
        });
        Assert.assertEq(expected = Some((Some(50.0), Some((50.0, -2.0)))), got)
}
