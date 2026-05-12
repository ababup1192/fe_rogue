/// セーブデータの slot ベース I/O。
///
/// `Saveable` を実装した任意の型をスロット番号で `saves/slot{N}.json`
/// に書き出す薄いユーティリティ。`Persistence.save` / `Persistence.load`
/// に対して「パス規約だけ固定する」役割を担う。
///
/// 別のディレクトリ・ファイル名規約を使いたいときは `Persistence` を
/// 直接呼べばよい。本モジュールは `slot N` を JSON 1 ファイルに対応付ける
/// 最頻パターンの省略形。
///
/// 親ディレクトリ `saves/` の作成は呼び出し側（または devbox init_hook）で
/// 行う前提（`Fs.WriteFile` は親ディレクトリを自動作成しない）。
mod SaveManager {

    /// `saves/slot{N}.json` のパス。
    pub def slotPath(slot: Int32): String = "saves/slot${slot}.json"

    /// スロット `slot` に `data` を書き出す。失敗時は `Err(message)`。
    pub def write(slot: Int32, data: a): Result[String, Unit] \ Fs.FileWrite with Saveable[a] =
        Persistence.save(slotPath(slot), data)

    /// スロット `slot` から読み出す。ファイル不在・パース失敗・形式不一致は `None`。
    pub def read(slot: Int32): Option[a] \ Fs.FileRead with Saveable[a] =
        Persistence.load(slotPath(slot))
}
