// 起動: Session（UI ページ + 部屋の World）を組み、App に部品を繋いで走らせる。
// キー入力（外の世界）→ Controls.step が Session を進める（純粋）→ Controls.projectUi が
// ページを整える（純粋）→ View.compose が絵へ投影する（純粋）→ App が画面へ描く（外の世界）。
// 外の世界（ウィンドウ・時計・ファイル）に触れるハンドラは Main が `with` で明示的に張る（effect は隠さない）。

def main(): Unit \ IO =
    if (GameEngine.ensureMainThread()) ()
    else {
        let ui = run { GameUi.loadUi() } with Fs.FileRead.runWithIO;
        run {
            App.make({ ui = ui, world = Room.initialWorld() })
                |> App.addSystem(Controls.step)
                |> App.addSystem(Controls.projectUi)
                |> App.reloadOn(GameEngine.Key.F1, Controls.reloadUi)
                |> App.withView(View.compose)
                |> App.withAudio(Sfx.events)
                |> App.quitWhen(Controls.wantsQuit)
                |> App.withDebug(App.debugFromEnv())
                |> App.withStatusLine(WorldDump.statusLine)
                |> App.withWorldDump(WorldDump.dump)
                |> App.launch
        } with LwjglLayer.withProject(".")
          with Fs.FileRead.runWithIO
          with Fs.FileWrite.runWithIO
          with Fs.Glob.runWithIO
          with Fs.ModificationTime.runWithFileTime
          with Fs.FileTime.runWithIO
    }
