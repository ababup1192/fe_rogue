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
                                     hasAlpha = true }
                                :: { name = "move_tile",
                                     path = "sprites/move_tile.png",
                                     hasAlpha = true }
                                :: { name = "cursor",
                                     path = "sprites/cursor.png",
                                     hasAlpha = true }
                                :: { name = "tilemap_floor",
                                     path = "sprites/tilemap.png",
                                     hasAlpha = true } :: Nil,
            fontManifest = { name = "ui", path = "fonts/BestTen-DOT.otf",
                              fontSize = 16.0 } :: Nil,
            soundManifest = { name = "bgm",    path = "audio/bgm.ogg",    looping = true }
                              :: { name = "damage", path = "audio/damage.ogg", looping = false }
                              :: { name = "bonus",  path = "audio/bonus.ogg",  looping = false }
                              :: Nil,
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
