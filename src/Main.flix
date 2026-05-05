def main(): Unit \ {IO, Chan, NonDet} =
    if (GameEngine.ensureMainThread()) ()
    else {
        let config: GameEngine.EngineConfig = {
            designWidth = Game.designWi(),
            designHeight = Game.designHi(),
            windowWidth = Game.windowWi(),
            windowHeight = Game.windowHi(),
            title = "New Game",
            textureManifest = { name = "inca_tileset",
                                  path = "sprites/Inca_front_by_Kronbits-extended.png",
                                  hasAlpha = true }
                                :: { name = "character_sheet",
                                     path = "sprites/character_sheet_grid_16.png",
                                     hasAlpha = true } :: Nil,
            fontManifest = Nil,
            soundManifest = Nil,
            clearColor = {r = 0.2f32, g = 0.2f32, b = 0.2f32},
            maxDeltaTime = 0.05
        };
        run {
            Game.start()
        } with LwjglLayer.withLwjgl(config)
          with Fs.FileRead.runWithIO
          with Fs.FileWrite.runWithIO
          with Fs.Glob.runWithIO
          with Fs.ModificationTime.runWithFileTime
          with Fs.FileTime.runWithIO
          with Math.Random.runWithIO
    }
