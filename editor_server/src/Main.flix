// エントリーポイント。環境変数で対象プロジェクトとポートを受け取り、Editor.serve を立ち上げる。
//   EDITOR_DIR  … 編集対象のゲームプロジェクト (省略可 — 未選択で起動し POST /project で選ぶ)
//   EDITOR_PORT … HTTP のポート番号 (省略時 8787)
//   EDITOR_WEB  … ビルド済みエディタ画面のディレクトリ (省略時は隣の flix_ge_editor/dist。無ければ配信無効)

def main(): Unit \ IO =
    Editor.serve(Editor.dirFromEnv(), Editor.portFromEnv())
