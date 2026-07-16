// エントリーポイント。環境変数で対象プロジェクトとポートを受け取り、Editor.serve を立ち上げる。
//   EDITOR_DIR  … 編集対象のゲームプロジェクト (省略可 — 未選択で起動し POST /project で選ぶ)
//   EDITOR_PORT … HTTP のポート番号 (省略時 8787)

def main(): Unit \ IO =
    Editor.serve(Editor.dirFromEnv(), Editor.portFromEnv())
