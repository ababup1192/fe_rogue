def main(): Unit \ {IO, Chan, NonDet} =
    if (GameEngine.ensureMainThread()) ()
    else {
        run {
            Game.start(GameEngine.Game.getFontAtlas("default"))
        } with LwjglLayer.withProject(".")
          with Math.Random.runWithIO
          with Fs.FileRead.runWithIO
          with Fs.FileWrite.runWithIO
          with Fs.Glob.runWithIO
          with Fs.ModificationTime.runWithFileTime
          with Fs.FileTime.runWithIO
    }
