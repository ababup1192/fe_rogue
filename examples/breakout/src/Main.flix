// エントリーポイント。
//
// フロー地図: Main は App に三点 — World の出発点・Controls.step・View.frame — を繋ぎ、
// 外の世界（窓・時計・ファイル）に触れるハンドラを `with` で明示的に張って launch へ渡す。
//   毎フレーム: App がキーと時計を Frame に焼く（外の世界）→ Controls.step が World を進める（純粋）→
//   View.frame が絵へ投影する（純粋）→ App が画面へ描く（外の世界）。
//   値が流れ、Step で進み、View で絵になる。effect は隠さず Main の with で列挙する。

def main(): Unit \ IO =
    if (GameEngine.ensureMainThread()) ()
    else {
        run {
            App.make(Field.initialWorld())
                |> App.addSystem(Controls.step)
                |> App.reloadOn(GameEngine.Key.F1, Controls.reloadParams)
                |> App.withView(View.frame)
                |> App.withAudio(Sfx.events)
                |> App.withStatusLine(Field.statusLine)
                |> App.withDebug(App.debugFromEnv())
                |> App.launch
        } with LwjglLayer.withProject(".")
          with Fs.FileRead.runWithIO
          with Fs.FileWrite.runWithIO
          with Fs.Glob.runWithIO
          with Fs.ModificationTime.runWithFileTime
          with Fs.FileTime.runWithIO
    }
