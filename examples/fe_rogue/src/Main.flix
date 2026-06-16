def main(): Unit \ IO =
    if (GameEngine.ensureMainThread()) ()
    else {
        run {
            Game.start()
        } with LwjglLayer.withProject(AssetPath.root())
          with Fs.FileRead.runWithIO
          with Fs.FileWrite.runWithIO
          with Math.Random.runWithIO
    }
