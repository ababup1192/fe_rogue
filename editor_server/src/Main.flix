// エントリーポイント。環境変数で対象プロジェクトとポートを受け取り、Editor.serve を立ち上げる。
//   EDITOR_DIR  … 編集対象のゲームプロジェクトのディレクトリ (必須)
//   EDITOR_PORT … HTTP のポート番号 (省略時 8787)

def main(): Unit \ IO =
    match Editor.dirFromEnv() {
        case None =>
            println("[editor] EDITOR_DIR が未設定です。make editor DIR=<game project dir> で起動してください。")
        case Some(dir) =>
            Editor.serve(dir, Editor.portFromEnv())
    }
