// エントリーポイント。Doc は App を組む前に読み、その値から初期 World を作る
// （壊れていても defaults で必ず起動する）。App の中でファイルを読むのは F1 の reloadOn と
// 保存検知（watchFile）だけ。外の世界に触れる処理（effect）は隠さず with で並べる。
//
// ゲーム 1 本の標準形は App.game の 1 レコードに宣言する — ここを読めばループの全体像
// （出発点 init・毎フレームの更新 update・描画 view・保存で読み直す Doc reloads）が掴める。
// update は「1 本の合成関数」: 複数のシステムを `w |> step |> interact |> …` と中で繋いで渡す
// （繋ぎが Main に見えるのが教育的）。App.game の外側の口（reloadOn・onBakeRequest・withDebug）は
// 戻り値の App に従来どおり後ろから pipe で足す。

def main(): Unit \ IO =
    if (GameEngine.ensureMainThread()) ()
    else {
        run {
            let docs = Controls.loadDocs();
            App.game({
                init = World.initial(docs),
                // 毎フレーム: 入力で状態を進め → 相互作用を解決し → 報せと表示中の Doc を名乗る。
                // SceneNotes.step と ActiveDocs.step が Fs.FileWrite を使うので、純粋な部品は
                // checked_ecast で同じ効果行へそろえる（部品側の ef は {} のまま保つ）。
                // SceneNotes は演じ終えたシーンの報せを debug/scene-notes.log に、ActiveDocs は
                // 「表示中」を debug/active-docs.json に書くだけ（どちらも内容が変わった瞬間だけ
                // 書くので無駄な IO は走らない）。
                // Director が先頭に立つ: イベントシーンの最中は入力を預かって脚本が
                // キャラクターを動かし、ふだんは Controls(歩く・話す)へ流す。
                update = (f, w) ->
                    checked_ecast(Director.step(f, w))
                        |> (w1 -> checked_ecast(Director.interact(f, w1)))
                        |> (w2 -> SceneNotes.step(w2))
                        |> (w3 -> ActiveDocs.step(World.activeDocs(w3), w3)),
                view = (ctx, w) -> checked_ecast(View.frame(ctx, w)),
                // 保存即反映で読み直す Doc たち（各 1 本の watchFile に展開される）。
                reloads = List.append(
                    CutsceneDoc.paths() |> List.map(p -> (p, Controls.reloadScenes)),
                    (MapDoc.path(), Controls.reloadMap) ::
                    (KindDoc.path(), Controls.reloadKind) ::
                    (ThemeDoc.path(), Controls.reloadTheme) ::
                    (World.spritePath(), Controls.reloadSprites) ::
                    (World.terrainPath(), Controls.reloadTerrain) :: Nil)
            })
                // 以下は App.game の外側の高度な口（戻り値の App に後ろから pipe で足す）。
                |> App.reloadOn(GameEngine.Key.F1, Controls.reloadAll)
                // 走行中の POST /bake（Studio の「焼いて」）は Bake.all と同じ実体を呼ぶ。
                |> App.onBakeRequest(Bake.allShots)
                |> App.withDebug(App.debugFromEnv())
                |> App.launch
        } with LwjglLayer.withProject(".")
          with Fs.FileRead.runWithIO
          with Fs.FileWrite.runWithIO
    }
