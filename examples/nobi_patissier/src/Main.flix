// 起動: いまは絵作りフェーズの足場だけ（空の World で起動し Escape で終了）。
// ゲーム本体は絵の承認（gallery/index.html）が全部 OK になってから組む。
// 外の世界（窓・時計・ファイル）に触れるハンドラは Main が `with` で明示的に張る（effect は隠さない）。

def main(): Unit \ IO =
    if (GameEngine.ensureMainThread()) ()
    else {
        run {
            App.make({ stub = 0 })
                |> App.launch
        } with LwjglLayer.withProject(".")
          with Fs.FileRead.runWithIO
          with Fs.FileWrite.runWithIO
          with Fs.Glob.runWithIO
          with Fs.ModificationTime.runWithFileTime
          with Fs.FileTime.runWithIO
    }
