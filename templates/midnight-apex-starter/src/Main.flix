// Main — Doc、入力、状態更新、描画を App へ接続する目次。
//
// 読む順:
//   init    … Doc から表紙の World を作る
//   update  … Controls が入力を解釈し、World が一拍進める
//   view    … View が World を画面へ写す
//   reloads … Studio で保存した Doc をその場で読み直す
//
// ゲームの規則は World、道路の座標変換は Course にあり、Main は外部との接続だけを持つ。
def main(): Unit \ IO =
    if (GameEngine.ensureMainThread()) ()
    else {
        run {
            let docs = Controls.loadDocs();
            App.game({
                init = World.initial(docs),
                update = (frame, world) ->
                    checked_ecast(Controls.step(frame, world))
                        |> (next -> ActiveDocs.step(World.activeDocs(next), next)),
                view = (context, world) -> checked_ecast(View.frame(context, world)),
                reloads =
                    (TuningDoc.path(), Controls.reloadTuning)
                    :: (ThemeDoc.path(), Controls.reloadTheme)
                    :: (CopyDoc.path(), Controls.reloadCopy)
                    :: (SceneryDoc.path(), Controls.reloadScenery)
                    :: (SceneryDoc.spritePath(), Controls.reloadSprites)
                    :: (CourseDoc.path(), Controls.reloadCourse)
                    :: Nil
            })
                |> App.addSystem(
                    (frame, world) ->
                        checked_ecast(AudioSystem.step(frame, world)))
                |> App.reloadOn(GameEngine.Key.F1, Controls.reloadAll)
                |> App.onBakeRequest(Bake.allShots)
                |> App.withAudio(worlds -> checked_ecast(AudioView.cues(worlds)))
                |> App.withDebug(App.debugFromEnv())
                |> App.launch
        } with LwjglLayer.withProject(".")
          with Fs.FileRead.runWithIO
          with Fs.FileWrite.runWithIO
    }
