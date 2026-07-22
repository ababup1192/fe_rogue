// エントリーポイント。Doc は App を組む前に読み、その値から初期 World を作る
// （壊れていても defaults で必ず起動する）。App の中でファイルを読むのは F1 の reloadOn と
// 保存検知（watchFile）だけ。外の世界に触れる処理（effect）は隠さず with で並べる。

def main(): Unit \ IO =
    if (GameEngine.ensureMainThread()) ()
    else {
        run {
            let docs = Controls.loadDocs();
            App.make(World.initial(docs))
                |> App.addSystem(Controls.step)
                |> App.addSystem(Controls.interact)
                |> App.withView(View.frame)
                |> App.reloadOn(GameEngine.Key.F1, Controls.reloadAll)
                |> App.watchFile(MapDoc.path(), Controls.reloadMap)
                |> App.watchFile(KindDoc.path(), Controls.reloadKind)
                |> App.watchFile(ThemeDoc.path(), Controls.reloadTheme)
                |> App.watchFile(World.spritePath(), Controls.reloadSprites)
                |> App.withDebug(App.debugFromEnv())
                |> App.launch
        } with LwjglLayer.withProject(".")
          with Fs.FileRead.runWithIO
    }
