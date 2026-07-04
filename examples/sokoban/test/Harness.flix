// Harness — everything needed to run the whole game without a screen.
//
// It is short on purpose, and the shortness is the point: tick is a pure
// function, so the rules need no harness at all. Only the *picture* touches
// the outside world, and it wants exactly three things — a font atlas baked
// headlessly, the Fs handlers to read the ui.json Specs, and a stub of the
// Game effect whose only real answer is that font atlas. Every other
// operation returns a constant.
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

    /// A Game handler with no GL behind it. renderUi only ever asks for the
    /// font atlas; a handler must still name every operation, so the rest
    /// answer with constants.
    pub def withMockGame(atlas: FontAtlas, f: Unit -> a \ ef + GameEngine.Game): a \ ef =
        run f() with handler GameEngine.Game {
            def renderCommands(_, _, _, k)  = k(())
            def initTileBuffer(_, k)        = k((0i32, 0i32))
            def shouldClose(k)              = k(false)
            def getDeltaTime(k)             = k(Duration.seconds(0.1))
            def isKeyPressed(_, k)          = k(false)
            def getMousePosition(k)         = k({x = 0.0, y = 0.0})
            def isMouseButtonPressed(_, k)  = k(false)
            def consumeScrollDelta(k)       = k(0.0)
            def getFontAtlas(_, k)          = k(atlas)
            def getViewportRect(k)          = k({position = Vec2.zero(), size = {x = 320.0, y = 240.0}})
            def getTextureInfo(_, k)        = k(None)
            def setCursor(_, k)             = k(())
        }
}
