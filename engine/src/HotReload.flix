// HotReload — シーン定義 JSON の更新を検知してリロード要求を出す
//
// 実装方式: 別スレッドで定期ポーリング、Channel 経由でメインループに通知。
// メインループは select の default 節で非ブロッキング受信する。
//
// 監視対象は src/scenes 配下の *.scene.json を Fs.Glob で動的に列挙するため、
// 新しい scene.json を追加してもコード変更不要。
//
// パフォーマンス:
// - watcher スレッドは 250ms 周期で sleep + glob + N stat
// - メインループは毎フレーム select 1 回（チャネル空なら即 false）
// - メインスレッドの IO 負荷ゼロ
//
// 制約:
// - GameOver フェーズ中はリロードを無効化する（GameOver は既存シーンへの
//   overlay 方式で構築されており、再度 enterGameOver すると重複するため）
// - リロード時は現在の GamePhase を再構築するので、プレイ中の進行（鳥位置・スコア）はリセットされる
// - 状態保持は GamePhase / bestScore のみ

mod HotReload {
    import java.lang.{Thread => JThread}

    /// scene.json を検索するベースディレクトリ
    def watchedDir(): String = "src/scenes"

    /// scene.json を検索するための glob パターン
    def watchedGlob(): String = "*.scene.json"

    /// ポーリング周期（ミリ秒）。短すぎると CPU を食い、長すぎると体感遅延が増える
    def pollIntervalMs(): Int64 = 250i64

    /// watcher スレッドを起動し、リロード通知を受け取る Receiver を返す。
    /// チャネルは容量 1 でバッファリング。複数回の変更が連続しても OK
    /// （同期されていない変更は次回ポーリングで mtime 差分として検出される）。
    /// spawn @ Static の中で許可される effect は Chan + IO + NonDet までなので、
    /// Fs 系の effect は spawn の内側で run ... with ... チェーンで解消する
    pub def startWatcher():
        Receiver[Unit] \ {Chan, IO, Fs.Glob, Fs.ModificationTime} =
        let (tx, rx) = Channel.buffered(1);
        let initialSnapshot = takeSnapshot();
        spawn {
            run { watcherLoop(tx, initialSnapshot) }
                with Fs.Glob.runWithIO
                with Fs.ModificationTime.runWithFileTime
                with Fs.FileTime.runWithIO
        } @ Static;
        rx

    /// 別スレッドで延々と回る本体。sleep → snapshot → 差分があれば send → 繰り返し
    def watcherLoop(tx: Sender[Unit], prevSnapshot: Map[String, Int64]):
        Unit \ {Chan, IO, Fs.Glob, Fs.ModificationTime} =
        JThread.sleep(pollIntervalMs());
        let currSnapshot = takeSnapshot();
        if (currSnapshot != prevSnapshot) {
            Channel.send((), tx)
        } else ();
        watcherLoop(tx, currSnapshot)

    /// メインループから毎フレーム呼ぶ非ブロッキング受信。
    /// チャネルにメッセージが来ていれば true、なければ即 false を返す
    pub def pollReload(rx: Receiver[Unit]): Bool \ {Chan, NonDet} =
        select {
            case _ <- recv(rx) => true
            case _             => false
        }

    /// 監視対象ファイルの mtime（ミリ秒）スナップショットを取得する。
    /// src/scenes 配下の *.scene.json を全て探索し、ファイルが読めない場合は 0 として扱う
    def takeSnapshot(): Map[String, Int64] \ {Fs.Glob, Fs.ModificationTime} =
        Fs.Glob.glob(watchedDir(), watchedGlob())
            |> Result.getWithDefault(Nil)
            |> List.foldLeft((acc, path) ->
                let mtime = Fs.ModificationTime.modificationTime(path)
                    |> Result.getWithDefault(0i64);
                Map.insert(path, mtime, acc), Map.empty())
}
