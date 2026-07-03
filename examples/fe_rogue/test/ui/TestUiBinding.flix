/// UiBinding.apply の宣言的テキストバインディングを固定する:
///   - resolver が Some を返した bind key の entity は text 差し替え
///   - resolver が None の key は現在の text を保つ
///   - bind 宣言の無い entity は resolver の戻り値に関わらず据え置き
mod TestUiBinding {

    def white(): Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}

    /// 表示文字列だけを変える単純な TextComp。
    def mkText(text: String): UiWidget.TextComp =
        {text = text, font = "ui", fontSize = 4.0, tint = white(), zIndex = 0}

    /// entity 1 = bind "greeting" 付き / entity 2 = text だが bind 無し、の最小 UiWorld。
    def sample(): UiStore.UiWorld =
        let ui0 = UiStore.empty();
        {texts = ui0#texts |> Map.insert(1, mkText("old1")) |> Map.insert(2, mkText("old2")),
         bindings = Map.insert(1, "greeting", ui0#bindings)
         | ui0}

    /// entity の現在の表示文字列（未登録は None）。
    def textOf(id: EntityId, ui: UiStore.UiWorld): Option[String] =
        Map.get(id, ui#texts) |> Option.map(comp -> comp#text)

    @Test
    def testAppliesBoundText(): Unit \ Assert =
        let resolve = key -> if (key == "greeting") Some("hello") else None;
        let ui = UiBinding.apply(resolve, sample());
        Assert.assertEq(expected = Some("hello"), textOf(1, ui))

    @Test
    def testLeavesUnresolvedText(): Unit \ Assert =
        let resolve = _key -> (None: Option[String]);
        let ui = UiBinding.apply(resolve, sample());
        Assert.assertEq(expected = Some("old1"), textOf(1, ui))

    @Test
    def testIgnoresUnboundEntity(): Unit \ Assert =
        // resolver が何にでも Some を返しても、bind 宣言の無い entity(2) は据え置き。
        let resolve = _key -> Some("hello");
        let ui = UiBinding.apply(resolve, sample());
        Assert.assertEq(expected = Some("old2"), textOf(2, ui))
}
