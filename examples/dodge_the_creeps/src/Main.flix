def main(): Unit \ IO =
    if (GameEngine.ensureMainThread()) ()
    else {
        let config: GameEngine.EngineConfig = {
            designWidth  = Game.designWi(),
            designHeight = Game.designHi(),
            windowWidth  = Game.windowWi(),
            windowHeight = Game.windowHi(),
            title = "Dodge the Creeps!",
            textureManifest =
                {name = "playerGrey_walk1",   path = "textures/playerGrey_walk1.png",   hasAlpha = true} ::
                {name = "playerGrey_walk2",   path = "textures/playerGrey_walk2.png",   hasAlpha = true} ::
                {name = "playerGrey_up1",     path = "textures/playerGrey_up1.png",     hasAlpha = true} ::
                {name = "playerGrey_up2",     path = "textures/playerGrey_up2.png",     hasAlpha = true} ::
                {name = "enemyWalking_1",     path = "textures/enemyWalking_1.png",     hasAlpha = true} ::
                {name = "enemyWalking_2",     path = "textures/enemyWalking_2.png",     hasAlpha = true} ::
                {name = "enemyFlyingAlt_1",   path = "textures/enemyFlyingAlt_1.png",   hasAlpha = true} ::
                {name = "enemyFlyingAlt_2",   path = "textures/enemyFlyingAlt_2.png",   hasAlpha = true} ::
                {name = "enemySwimming_1",    path = "textures/enemySwimming_1.png",    hasAlpha = true} ::
                {name = "enemySwimming_2",    path = "textures/enemySwimming_2.png",    hasAlpha = true} ::
                Nil,
            fontManifest =
                {name = "default", path = "textures/Xolonium-Regular.ttf", fontSize = 60.0} ::
                Nil,
            soundManifest =
                {name = "music", path = "sounds/House In a Forest Loop.ogg", looping = true} ::
                {name = "death", path = "sounds/gameover.wav",                looping = false} ::
                Nil,
            clearColor = {r = 0.219608f32, g = 0.372549f32, b = 0.380392f32},
            maxDeltaTime = 0.05
        };
        run {
            Game.start(GameEngine.Game.getFontAtlas("default"))
        } with LwjglLayer.withLwjgl(config)
          with Math.Random.runWithIO
          with Fs.FileRead.runWithIO
          with Fs.FileWrite.runWithIO
          with Fs.Glob.runWithIO
          with Fs.ModificationTime.runWithFileTime
          with Fs.FileTime.runWithIO
    }
