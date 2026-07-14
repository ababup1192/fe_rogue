// エントリーポイント。Bench の世界を App に繋ぎ、4 区間を走り切ったら自動終了する。

def main(): Unit \ IO =
    if (GameEngine.ensureMainThread()) ()
    else {
        run {
            App.make(Bench.initialWorld())
                |> App.addSystem(Bench.step)
                |> App.withView((ctx, w) -> checked_ecast(Bench.view(ctx, w)))
                |> App.quitWhen((_frame, w) -> checked_ecast(w#done))
                |> App.launch
        } with LwjglLayer.withProject(".")
          with Fs.FileRead.runWithIO
          with Fs.FileWrite.runWithIO
          with Fs.Glob.runWithIO
          with Fs.ModificationTime.runWithFileTime
          with Fs.FileTime.runWithIO
    }
