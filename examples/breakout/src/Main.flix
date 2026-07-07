// エントリーポイント。
//
// フロー地図: Main は App に三点 — World の出発点・Controls.step・View.frame — を繋ぐだけ。
//   毎フレーム: App がキーと時計を Frame に焼く（外の世界）→ Controls.step が World を進める（純粋）→
//   View.frame が絵へ投影する（純粋）→ App が画面へ描く（外の世界）。
//   値が流れ、Step で進み、View で絵になる。外の世界に触れる処理は App の中に閉じる。

def main(): Unit \ IO =
    App.make(Field.initialWorld())
        |> App.addSystem(Controls.step)
        |> App.reloadOn(GameEngine.Key.F1, Controls.reloadParams)
        |> App.withView(View.frame)
        |> App.withAudio(Sfx.events)
        |> App.launch
