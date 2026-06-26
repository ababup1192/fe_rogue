// エントリポイント
//
// 単層 ECS のスパイク。描画は scene-tree を介さず World -> List[GameEngine.Drawable]。
// withProject が +Fs.FileRead を課すため Fs.FileRead ハンドラは必須（loop 本体は Fs 不要）。

def main(): Unit \ IO =
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
