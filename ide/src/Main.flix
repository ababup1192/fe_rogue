// ide/src/Main.flix — Step C.2: proj.json を読んで scene を描画する IDE エントリ
//
// 動作確認:
//   cd ide && ./bin/flix run
// 期待:
//   - flappy_bird の MenuScene.scene.json (タイトルロゴ・instructions・play ボタン) が描画される
//   - clearColor (空色) の背景
//   - × クリックで終了
//
// Step C.2 のスコープ:
//   - プロジェクトパスはハードコード ("../examples/flappy_bird")。
//     argv での切替は Step C.3 で対応する
//   - シーンは static — マウス入力なし・編集なし

def main(): Unit \ IO =
    run {
        loadAndRun("../examples/flappy_bird")
    } with Fs.FileRead.runWithIO

/// proj.json を読んで SwingLayer 上で scene 描画ループに入る。
/// main から `Fs.FileRead.runWithIO` でラップされて呼ばれる前提。
def loadAndRun(projPath: String): Unit \ {IO, Fs.FileRead} =
    let proj = ProjectLoader.loadProject(projPath);
    run {
        ideLoop(proj#mainScenePath)
    } with SwingLayer.withSwing(proj#config)

/// シーンを読み込み、shouldClose まで毎フレーム同じシーンを描画する。
def ideLoop(scenePath: String): Unit \ {GameEngine.Game, Fs.FileRead} =
    let scene: Scene[Unit] = SceneLoader.loadScene(
        scenePath,
        SceneLoader.constTagParser(()),
        Scene.empty());
    renderLoop(scene)

def renderLoop(scene: Scene[Unit]): Unit \ GameEngine.Game =
    if (GameEngine.Game.shouldClose()) ()
    else {
        GameEngine.render(scene);
        renderLoop(scene)
    }
