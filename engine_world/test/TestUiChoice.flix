// TestUiChoice — 候補の循環（末尾↔先頭）と表示文言の書き込みを固定する。
mod TestUiChoice {

    // ── next/prev: 循環 ──

    @Test
    def testNextWrapsFromLastToFirst(): Unit \ Assert =
        // 候補 3 個（index 0,1,2）の末尾から次へ進むと先頭へ戻る。
        let st = { index = 2, count = 3 };
        Assert.assertEq(expected = 0, UiChoice.next(st)#index)

    @Test
    def testPrevWrapsFromFirstToLast(): Unit \ Assert =
        // 先頭から前へ戻ると末尾（index 2）へ回り込む。
        let st = { index = 0, count = 3 };
        Assert.assertEq(expected = 2, UiChoice.prev(st)#index)

    @Test
    def testNextAdvancesByOne(): Unit \ Assert =
        let st = { index = 0, count = 3 };
        Assert.assertEq(expected = 1, UiChoice.next(st)#index)

    /// label 子を持つ簡易サイクラー行。
    def choiceUi(): Option[UiStore.UiWorld] =
        let doc = "{\"root\": {\"name\":\"res\",\"widget\":\"none\",\"children\":["
            + "{\"name\":\"label\",\"widget\":\"text\",\"text\":\"\",\"fontSize\":8.0}]}}";
        JsonCompat.parse(doc)
            |> Option.flatMap(json -> UiSpec.parse(json) |> Result.toOption)
            |> Option.map(spec -> { let (_, ui) = UiSpec.spawnRoot(spec, UiStore.empty()); ui })

    def labelOf(index: Int32): String = match index {
        case 0 => "640x480"
        case 1 => "1280x720"
        case _ => "1920x1080"
    }

    @Test
    def testApplyWritesLabelForCurrentIndex(): Unit \ Assert =
        let got = choiceUi() |> Option.map(ui -> {
            let ui1 = UiChoice.apply("res", { index = 1, count = 3 }, labelOf, ui);
            UiStore.textOf("res/label", ui1)
        });
        Assert.assertEq(expected = Some(Some("1280x720")), got)
}
