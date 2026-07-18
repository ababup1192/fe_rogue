// エントリーポイント。
//
// feature_lab は新機能を雑多に試す実験場。今日の実験は engine_world の Transition（画面遷移）:
// 起動時は覆いなしの Idle。W/A/S/D で FadeOut/FadeIn/WipeLeft/WipeRight を再生し、
// 終わると自動で Idle に戻る（Space は今の種類を再生し直す）。
// 値が流れ、Controls.step で進み、View.frame で絵になる。effect は隠さず Main の with で列挙する。
// あわせて withFixedStep（固定タイムステップ）も控えめに検証中: countStep がサブステップも
// 含め毎回数え、statusLine の steps= に出る（絵は F8 なしでも肉眼で違和感が無ければ OK）。
// もうひとつの実験は AudioFade + マスター音量: B で BGM のフェードの向きを反転、
// M でマスター音量 1.0/0.3 を切り替え、statusLine の bgm= / master= で値を確かめる。
// もうひとつの実験はフルスクリーン切替とカーソル非表示: Enter でウィンドウ⇄ボーダーレス
// フルスクリーンを切り替え、H でマウスカーソルの表示/非表示を切り替える。値は statusLine の
// fullscreen= / cursor= と画面内 HUD の両方で確かめられる。実窓の切替そのもの（黒帯の出方）は
// gallery には出せず起動確認のみ。画面の縁取り・四隅マーカー（View.viewportMarkerItems）は
// フルスクリーン時に viewport が design 通りか目視するための目印。
// もうひとつの実験は Light（放射グロー+穴あき暗幕）: 矢印キーでカンテラ（プレイヤー=光源）を
// 動かし、LeftShift で暗闇の有無を切り替える。暗闇 on では Light.items が
// 「Multiply の穴あき暗幕+Add の暖色ハロ」を光の位置に重ね、目印図形が光の周りだけ見える。
// 光の質感（暗さ・照り返しフチ・ハロの大きさ）は assets/Lantern.light.json が持ち、
// make debug で起動中は保存するたびに即反映される（App.watchFile。F1 の ui.json 再読込と同居）。

def main(): Unit \ IO =
    if (GameEngine.ensureMainThread()) ()
    else {
        let ui = run { GameUi.loadUi() } with Fs.FileRead.runWithIO;
        let lightDoc = run { Controls.loadLightDoc() } with Fs.FileRead.runWithIO;
        // 面の json パスとフォールバックは env（LAVA_DEMO）で決めて起動時に 1 度だけ読む。
        let surfacePath = Controls.surfacePath();
        let surfaceFallback = Controls.surfaceFallback();
        let surfaceLoaded = run { ShaderJson.load(surfacePath) } with Fs.FileRead.runWithIO;
        let surfaceSpec = Result.getWithDefault(surfaceFallback, surfaceLoaded);
        // SHADER_DEMO=1 で宣言シェーダー面（eff Shader）の骨格デモを on にする（既定 off）。
        let shaderDemo = Controls.shaderDemoFromEnv();
        run {
            // App の effect 集合は全フック共通の 1 つの型変数なので、Audio だけ・Game だけの
            // system が混在すると単一化できない。全 system を checked_ecast で
            // {Audio, Game} へそろえる（呼び出し式ごと widen すれば効く）。
            App.make(World.initial(ui, lightDoc, shaderDemo, surfaceSpec))
                |> App.addSystem((frame, world) -> checked_ecast(Controls.step(frame, world)))
                |> App.addSystem((frame, world) -> checked_ecast(Controls.countStep(frame, world)))
                |> App.addSystem((frame, world) -> checked_ecast(Controls.shaderStep(frame, world)))
                |> App.addSystem((frame, world) -> checked_ecast(Controls.audioStep(frame, world)))
                |> App.addSystem((frame, world) -> checked_ecast(Controls.windowStep(frame, world)))
                |> App.addSystem((frame, world) -> checked_ecast(Controls.blendStep(frame, world)))
                |> App.addSystem((frame, world) -> checked_ecast(Controls.lanternStep(frame, world)))
                |> App.addSystem((frame, world) -> checked_ecast(Controls.projectUi(frame, world)))
                |> App.reloadOn(GameEngine.Key.F1, Controls.reloadUi)
                |> App.watchFile("assets/Lantern.light.json", Controls.reloadLightDoc)
                |> App.watchFile(surfacePath, Controls.surfaceReloader(surfacePath, surfaceFallback))
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
