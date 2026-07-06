// エントリーポイント。
//
// フロー地図: Main は App に三点 — World の出発点・Game.step・View.frame — を繋ぐだけ。
//   毎フレーム: App がキーと時計を Frame に焼く（縁）→ Game.step が World を進める（純）→
//   View.frame が絵へ投影する（純）→ App が画面へ描く（縁）。
//   値が流れ、Step で進み、View で絵になり、縁は App の中に閉じる。

def main(): Unit \ IO =
    App.make(Field.initialWorld())
        |> App.addSystem(Game.step)
        |> App.reloadOn(GameEngine.Key.F1, Game.reloadParams)
        |> App.withView(View.frame)
        |> App.withAudio(Sfx.events)
        |> App.launch
