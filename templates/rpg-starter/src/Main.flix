// エントリーポイント。Doc は App を組む前に読み、その値から初期 World を作る
// （壊れていても defaults で必ず起動する）。App の中でファイルを読むのは F1 の reloadOn と
// 保存検知（watchFile）だけ。外の世界に触れる処理（effect）は隠さず with で並べる。

def main(): Unit \ IO =
    if (GameEngine.ensureMainThread()) ()
    else {
        run {
            let docs = Controls.loadDocs();
            App.make(World.initial(docs))
                // ActiveDocs.step だけ Fs.FileWrite を使うので、純粋な部品は checked_ecast で
                // 同じ効果行へそろえる（部品側の ef は {} のまま保つ）。
                |> App.addSystem((f, w) -> checked_ecast(Controls.step(f, w)))
                |> App.addSystem((f, w) -> checked_ecast(Controls.interact(f, w)))
                // 表示中の Doc を debug/active-docs.json に名乗る（Studio の「表示中」バッジ。
                // 一覧が変わった瞬間だけ書くので、毎フレームでも無駄な IO は走らない）。
                |> App.addSystem((_f, w) -> ActiveDocs.step(World.activeDocs(w), w))
                |> App.withView((ctx, w) -> checked_ecast(View.frame(ctx, w)))
                |> App.reloadOn(GameEngine.Key.F1, Controls.reloadAll)
                |> App.watchFile(MapDoc.path(), Controls.reloadMap)
                |> App.watchFile(KindDoc.path(), Controls.reloadKind)
                |> App.watchFile(ThemeDoc.path(), Controls.reloadTheme)
                |> App.watchFile(World.spritePath(), Controls.reloadSprites)
                // 走行中の POST /bake（Studio の「焼いて」）は Bake.all と同じ実体を呼ぶ。
                |> App.onBakeRequest(Bake.allShots)
                |> App.withDebug(App.debugFromEnv())
                |> App.launch
        } with LwjglLayer.withProject(".")
          with Fs.FileRead.runWithIO
          with Fs.FileWrite.runWithIO
    }
