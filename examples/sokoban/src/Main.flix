// エントリーポイント。
//
// project.json（ウィンドウとフォントの設定）を読み込み、ロードしたフォントで
// loop を開始する。withProject は Fs のハンドラを必要とするので、ここで注入する
// （loop 自身は Fs を一切使わない）。

def main(): Unit \ IO =
    if (GameEngine.ensureMainThread()) ()
    else {
        run {
            Sokoban.start(GameEngine.Game.getFontAtlas("default"))
        } with LwjglLayer.withProject(".")
          with Fs.FileRead.runWithIO
          with Fs.FileWrite.runWithIO
          with Fs.Glob.runWithIO
          with Fs.ModificationTime.runWithFileTime
          with Fs.FileTime.runWithIO
    }
