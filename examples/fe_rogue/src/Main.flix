import java.lang.{System => JSystem}

def main(): Unit \ IO =
    let mode = unsafe IO { JSystem.getenv("FE_ROGUE_MODE") };
    let isConvert = not Object.isNull(mode) and mode == "convert-ldtk";
    if (isConvert) runConvert()
    else            runGame()

/// 全 .ldtkl を MapResource.Level として assets/maps/ に書き出す 1 回限りの bootstrap。
def runConvert(): Unit \ IO =
    run {
        LdtkConvertScript.convertAll()
    } with Fs.FileRead.runWithIO
      with Fs.FileWrite.runWithIO

/// 通常起動: GLFW window を開いてゲームループを走らせる。
def runGame(): Unit \ IO =
    if (GameEngine.ensureMainThread()) ()
    else {
        run {
            Game.start()
        } with LwjglLayer.withProject(".")
          with Fs.FileRead.runWithIO
          with Math.Random.runWithIO
    }
