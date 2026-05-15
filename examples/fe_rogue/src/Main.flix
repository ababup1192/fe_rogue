def main(): Unit \ IO =
    if (GameEngine.ensureMainThread()) ()
    else {
        run {
            Game.start()
        } with LwjglLayer.withProject(".")
          with Fs.FileRead.runWithIO
          with Math.Random.runWithIO
    }
