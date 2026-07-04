// Harness — everything needed to run the whole game without a screen.
//
// It is short on purpose, and the shortness is the point: tick is a pure
// function, so the rules need no harness at all. Only the *picture* touches
// the outside world, and it wants exactly two things — a font atlas baked
// headlessly, and the Fs handlers to read the ui.json Specs. The pages carry
// only boxes and text, so `UiRender.renderUiWith` draws them from the atlas
// alone: no Game handler, no window.
mod Harness {

    def ttfPath(): String = "assets/Xolonium-Regular.ttf"

    /// The font, baked without a window (AWT headless metrics only).
    pub def atlas(): FontAtlas \ IO =
        HeadlessFont.ensureHeadless();
        HeadlessFont.buildUiAtlas(ttfPath(), "assets/joyo.txt")

    /// Both page Specs spawned into one UiWorld, as the launcher does.
    pub def ui(): Option[UiStore.UiWorld] \ IO =
        run {
            forM (a <- UiSpec.spawnAsset(Sokoban.titleUiPath(), UiStore.empty()) |> Result.toOption;
                  b <- UiSpec.spawnAsset(Sokoban.clearUiPath(), snd(a)) |> Result.toOption)
            yield snd(b)
        } with Fs.FileRead.runWithIO
}
