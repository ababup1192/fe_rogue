def main(): Unit \ {IO, Chan, NonDet} =
    if (GameEngine.ensureMainThread()) ()
    else {
        let config: GameEngine.EngineConfig = {
            screenWidth = Game.screenWi(),
            screenHeight = Game.screenHi(),
            title = "New Game",
            textureManifest = Nil,
            fontManifest = Nil,
            soundManifest = Nil,
            clearColor = {r = 0.2f32, g = 0.2f32, b = 0.2f32},
            maxDeltaTime = 0.05
        };
        run {
            Game.start()
        } with LwjglLayer.withLwjgl(config)
          with Math.Random.runWithIO
          with Fs.FileRead.runWithIO
          with Fs.FileWrite.runWithIO
          with Fs.Glob.runWithIO
          with Fs.ModificationTime.runWithFileTime
          with Fs.FileTime.runWithIO
    }
