// TestUiDialog — 会話窓の開閉・行送り・見えている本文・UiStore への刻み込みを具体値で固定する。
// UiWorld は（既知のコンパイラ制約を避けるため）レコード直構築せず、必ず parse→spawnRoot で作る。
mod TestUiDialog {

    /// 話者の text ノードを持つ最小の会話ページ（本文はスパン描画なのでノード不要）。
    def dialogJson(): String =
        "{\"root\": {\"name\":\"Dialog\",\"widget\":\"none\","
        + "\"children\":[{\"name\":\"panel\",\"widget\":\"box\",\"color\":\"#222034\",\"width\":100,\"height\":40,"
        + "\"children\":["
        + "{\"name\":\"speaker\",\"widget\":\"text\",\"text\":\"\",\"fontSize\":8.0}]}]}}"

    /// JSON テキストを parse して空 UiWorld へ spawnRoot した結果（失敗時 None）。
    def spawnFrom(jsonText: String): Option[UiStore.UiWorld] =
        JsonCompat.parse(jsonText)
            |> Option.flatMap(json -> UiSpec.parse(json) |> Result.toOption)
            |> Option.map(spec -> let (_, ui) = UiSpec.spawnRoot(spec, UiStore.empty()); ui)

    /// テストで使う投影先パス束。
    def paths(): UiDialog.Paths =
        { root = "Dialog", speaker = "Dialog/panel/speaker" }

    /// 2 行の会話（あおの発言 → 地の文）。1 行目は色付き名前 + 太字入りのスパン列。
    def twoLines(): List[UiDialog.Line] =
        ({ speaker = "あおの人",
           body = RichText.colored("みどり", {r = 0.0f32, g = 1.0f32, b = 0.0f32})
               :: RichText.plain("は")
               :: RichText.strong("嘘つき")
               :: RichText.plain("だよ") :: Nil }: UiDialog.Line)
        :: ({ speaker = "", body = RichText.plain("どうする？") :: Nil }: UiDialog.Line)
        :: Nil

    // ── 開閉と行送り ──

    @Test
    def testClosedAndEmptyOpenAreClosed(): Unit \ Assert =
        // closed() も空リストの openWith も「閉じている」。
        Assert.assertEq(expected = (false, false),
            (UiDialog.isOpen(UiDialog.closed()), UiDialog.isOpen(UiDialog.openWith(Nil))))

    @Test
    def testOpenShowsFirstLineFromZero(): Unit \ Assert =
        // 開いた直後は先頭行の話者を指し、本文はまだ 0 文字。
        let dialog = UiDialog.openWith(twoLines());
        Assert.assertEq(expected = (true, Some("あおの人"), false, ""),
            (UiDialog.isOpen(dialog),
             UiDialog.currentLine(dialog) |> Option.map(line -> line#speaker),
             UiDialog.lineDone(dialog),
             RichText.plainText(UiDialog.visibleBody(dialog))))

    @Test
    def testStepRevealsAcrossSpans(): Unit \ Assert =
        // cps=5 × dt=1 → 5 文字。「みどりは嘘」— スパンの境界（色付き名前 → 素の字 → 太字）を
        // またいで先頭から見えていく。
        let dialog = UiDialog.openWith(twoLines()) |> UiDialog.step(cps = 5.0, 1.0);
        Assert.assertEq(expected = "みどりは嘘",
            RichText.plainText(UiDialog.visibleBody(dialog)))

    @Test
    def testAdvanceWhileTypingSkipsToFull(): Unit \ Assert =
        // タイプ中の advance は行送りせず全文表示へ飛ばす（早送り）。
        let dialog = UiDialog.openWith(twoLines()) |> UiDialog.advance;
        Assert.assertEq(expected = (Some("あおの人"), true, "みどりは嘘つきだよ"),
            (UiDialog.currentLine(dialog) |> Option.map(line -> line#speaker),
             UiDialog.lineDone(dialog),
             RichText.plainText(UiDialog.visibleBody(dialog))))

    @Test
    def testAdvanceAfterDoneMovesToNextLine(): Unit \ Assert =
        // 見え終わった行での advance は次の行へ。次の行はまた 0 文字から。
        let dialog = UiDialog.openWith(twoLines()) |> UiDialog.advance |> UiDialog.advance;
        Assert.assertEq(expected = (Some("どうする？"), false),
            (UiDialog.currentLine(dialog)
                 |> Option.map(line -> RichText.plainText(line#body)),
             UiDialog.lineDone(dialog)))

    @Test
    def testAdvancePastLastLineCloses(): Unit \ Assert =
        // 最終行を送り切ると閉じる（skip → 送り → skip → 送り で 2 行を消化）。
        let dialog = UiDialog.openWith(twoLines())
            |> UiDialog.advance |> UiDialog.advance
            |> UiDialog.advance |> UiDialog.advance;
        Assert.assertEq(expected = false, UiDialog.isOpen(dialog))

    // ── apply: UiStore への刻み込み ──

    @Test
    def testApplyWritesSpeakerAndShowsRoot(): Unit \ Assert =
        // 開いた会話を apply すると root が可視になり話者が入る（本文は視点側の仕事）。
        let got = spawnFrom(dialogJson()) |> Option.map(ui -> {
            let ui1 = UiDialog.apply(paths(), UiDialog.openWith(twoLines()), ui);
            (UiStore.visibleOf("Dialog", ui1), UiStore.textOf("Dialog/panel/speaker", ui1))
        });
        Assert.assertEq(expected = Some((Some(true), Some("あおの人"))), got)

    @Test
    def testApplyClosedHidesRoot(): Unit \ Assert =
        // 閉じた会話を apply すると root が不可視になる。
        let got = spawnFrom(dialogJson()) |> Option.map(ui -> {
            let ui1 = UiDialog.apply(paths(), UiDialog.closed(), ui);
            UiStore.visibleOf("Dialog", ui1)
        });
        Assert.assertEq(expected = Some(Some(false)), got)
}
