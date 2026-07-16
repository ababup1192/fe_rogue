// エントリーポイント。
//
// feature_lab は新機能を雑多に試す実験場。今日の実験は engine_world の Transition（画面遷移）:
// W/A/S/D キーで FadeOut/FadeIn/WipeLeft/WipeRight を選び、Space で再生し直して眺められる。
// 値が流れ、Controls.step で進み、View.frame で絵になる。effect は隠さず Main の with で列挙する。
// あわせて withFixedStep（固定タイムステップ）も控えめに検証中: countStep がサブステップも
// 含め毎回数え、statusLine の steps= に出る（絵は F8 なしでも肉眼で違和感が無ければ OK）。
// もうひとつの実験は AudioFade + マスター音量: B で BGM のフェードの向きを反転、
// M でマスター音量 1.0/0.3 を切り替え、statusLine の bgm= / master= で値を確かめる。
// もうひとつの実験はフルスクリーン切替とカーソル非表示: Enter でウィンドウ⇄ボーダーレス
// フルスクリーンを切り替え、H でマウスカーソルの表示/非表示を切り替える。実窓の挙動なので
// gallery には出せず、statusLine の fullscreen= / cursor= で値を確かめる（起動確認のみ）。

def main(): Unit \ IO =
    if (GameEngine.ensureMainThread()) ()
    else {
        let ui = run { GameUi.loadUi() } with Fs.FileRead.runWithIO;
        run {
            // App の effect 集合は全フック共通の 1 つの型変数なので、Audio だけ・Game だけの
            // system が混在すると単一化できない。全 system を checked_ecast で
            // {Audio, Game} へそろえる（呼び出し式ごと widen すれば効く）。
            App.make(World.initial(ui))
                |> App.addSystem((frame, world) -> checked_ecast(Controls.step(frame, world)))
                |> App.addSystem((frame, world) -> checked_ecast(Controls.countStep(frame, world)))
                |> App.addSystem((frame, world) -> checked_ecast(Controls.audioStep(frame, world)))
                |> App.addSystem((frame, world) -> checked_ecast(Controls.windowStep(frame, world)))
                |> App.addSystem((frame, world) -> checked_ecast(Controls.projectUi(frame, world)))
                |> App.reloadOn(GameEngine.Key.F1, Controls.reloadUi)
                |> App.withView((ctx, world) -> checked_ecast(View.frame(ctx, world)))
                |> App.withStatusLine(world -> checked_ecast(World.statusLine(world)))
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
