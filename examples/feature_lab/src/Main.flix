// エントリーポイント。
//
// feature_lab は新機能を雑多に試す実験場。今日の実験は engine_world の Transition（画面遷移）:
// W/A/S/D キーで FadeOut/FadeIn/WipeLeft/WipeRight を選び、Space で再生し直して眺められる。
// 値が流れ、Controls.step で進み、View.frame で絵になる。effect は隠さず Main の with で列挙する。
// あわせて withFixedStep（固定タイムステップ）も控えめに検証中: countStep がサブステップも
// 含め毎回数え、statusLine の steps= に出る（絵は F8 なしでも肉眼で違和感が無ければ OK）。

def main(): Unit \ IO =
    if (GameEngine.ensureMainThread()) ()
    else {
        let ui = run { GameUi.loadUi() } with Fs.FileRead.runWithIO;
        run {
            App.make(World.initial(ui))
                |> App.addSystem(Controls.step)
                |> App.addSystem(Controls.countStep)
                |> App.addSystem(Controls.projectUi)
                |> App.reloadOn(GameEngine.Key.F1, Controls.reloadUi)
                |> App.withView(View.frame)
                |> App.withStatusLine(World.statusLine)
                |> App.withFixedStep(1.0 / 60.0)
                |> App.withDebug(App.debugFromEnv())
                |> App.launch
        } with LwjglLayer.withProject(".")
          with Fs.FileRead.runWithIO
          with Fs.FileWrite.runWithIO
          with Fs.Glob.runWithIO
          with Fs.ModificationTime.runWithFileTime
          with Fs.FileTime.runWithIO
    }
