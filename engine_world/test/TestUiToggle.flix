// TestUiToggle — ON/OFF の反転とマーク文言の出し分けを固定する。
mod TestUiToggle {

    @Test
    def testToggledFlipsOnOff(): Unit \ Assert =
        Assert.assertEq(expected = (false, true), (UiToggle.toggled(true), UiToggle.toggled(false)))

    @Test
    def testMarkTextPicksByState(): Unit \ Assert =
        Assert.assertEq(
            expected = ("ON", "OFF"),
            (UiToggle.markText(true, "ON", "OFF"), UiToggle.markText(false, "ON", "OFF")))

    /// mark 子を持つ簡易トグル行。
    def toggleUi(): Option[UiStore.UiWorld] =
        let doc = "{\"root\": {\"name\":\"bgm\",\"widget\":\"none\",\"children\":["
            + "{\"name\":\"mark\",\"widget\":\"text\",\"text\":\"\",\"fontSize\":8.0}]}}";
        JsonCompat.parse(doc)
            |> Option.flatMap(json -> UiSpec.parse(json) |> Result.toOption)
            |> Option.map(spec -> { let (_, ui) = UiSpec.spawnRoot(spec, UiStore.empty()); ui })

    @Test
    def testApplyWritesMarkText(): Unit \ Assert =
        let got = toggleUi() |> Option.map(ui -> {
            let ui1 = UiToggle.apply("bgm", true, "ON", "OFF", ui);
            UiStore.textOf("bgm/mark", ui1)
        });
        Assert.assertEq(expected = Some(Some("ON")), got)
}
