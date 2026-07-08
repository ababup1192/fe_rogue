// プロジェクトルート相対のアセットパスを解決する小ヘルパ。
//
// 通常の `flix run` は CWD = プロジェクトルートで動くため相対パスのまま読めるが、
// jpackage で生成した .exe / .app は CWD がリソース位置と無関係（macOS の .app は "/"）。
// そのためランチャが渡す `-DprojectPath=<絶対ルート>` を読み、全アセットパスを絶対化する。
//
// projectPath は JVM 起動時に固定され以後変化しないので `unsafe IO` で純粋に読み出してよい
// (MapResource が定数読み出しに使っているのと同じパターン)。これにより
// resolve() などの純粋関数の効果型を変えずに済む。
mod AssetPath {
    import java.lang.System

    /// 絶対ルート。未設定（通常実行）なら "." を返す。
    pub def root(): String =
        unsafe IO {
            let p = System.getProperty("projectPath");
            if (Object.isNull(p)) "." else p
        }

    /// プロジェクトルート相対 `rel` を解決する。
    /// root = "." のときは `rel` をそのまま返すので、既存の `flix run` の挙動は不変。
    pub def resolve(rel: String): String =
        let r = root();
        if (r == ".") rel else "${r}/${rel}"
}
