// エントリーポイント。
//
// フロー地図: Main → Game.loop →（World |> Step |> View → 画面）
//   World … 1 プレイぶんの状態の「値」。Step が進め、View が絵にし、Game の縁だけが副作用。
//   毎フレーム: Game がキーと時計を読み（縁）→ Step.update で World を次の World へ（純）→
//   View.frame で Drawable へ投影（純）→ Game がエンジンへ描く（縁）。
//   値が流れ、Step で進み、View で絵になり、縁だけが世界に触れる。
//
// project.json（ウィンドウとフォントの設定）を読み込み、ロードしたフォントで loop を開始する。
// withProject は Fs のハンドラを必要とするので、ここで注入する（loop 自身は Fs を一切使わない）。

def main(): Unit \ IO =
    if (GameEngine.ensureMainThread()) ()
    else {
        run {
            Game.start(GameEngine.Game.getFontAtlas("default"))
        } with LwjglLayer.withProject(".")
          with Fs.FileRead.runWithIO
          with Fs.FileWrite.runWithIO
          with Fs.Glob.runWithIO
          with Fs.ModificationTime.runWithFileTime
          with Fs.FileTime.runWithIO
    }
