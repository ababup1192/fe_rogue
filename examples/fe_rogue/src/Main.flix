def main(): Unit \ {IO, Chan, NonDet} =
    if (GameEngine.ensureMainThread()) ()
    else {
        run {
            Game.start()
        } with LwjglLayer.withProject(".")
          with Fs.FileRead.runWithIO
          with Fs.FileWrite.runWithIO
          with Fs.Glob.runWithIO
          with Fs.ModificationTime.runWithFileTime
          with Fs.FileTime.runWithIO
          with Math.Random.runWithIO
    }
