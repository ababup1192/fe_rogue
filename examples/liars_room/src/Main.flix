// 起動: Session（UI ページ + 部屋の World）を組み、App に部品を繋いで走らせる。
// キー入力（外の世界）→ Controls.step が Session を進める（純粋）→ Controls.projectUi が
// ページを整える（純粋）→ View.compose が絵へ投影する（純粋）→ App が画面へ描く（外の世界）。

def main(): Unit \ IO =
    let ui = run { GameUi.loadUi() } with Fs.FileRead.runWithIO;
    App.make({ ui = ui, world = Room.initialWorld() })
        |> App.addSystem(Controls.step)
        |> App.addSystem(Controls.projectUi)
        |> App.reloadOn(GameEngine.Key.F1, Controls.reloadUi)
        |> App.withView(View.compose)
        |> App.withAudio(Sfx.events)
        |> App.quitWhen(Controls.wantsQuit)
        |> App.launch
