/// 公開ファサード。
///
/// エンジン層・対話層が `Yarn` 経由で内部モジュールへアクセスする際の入口。
/// 直接 `Yarn.Loader` 等を `use` しても良いが、ここに集めると見通しが良い。
mod Yarn {
    use Yarn.Types.YarnProject
    use Yarn.Types.Value
    use Yarn.Types.Value.{FloatV}

    /// 既存 `YarnProject` の `initialValues` で 1 つの変数だけ上書きした
    /// 新しい `YarnProject` を返す。
    ///
    /// 用途: ゲーム起動時に外部から HP などの初期値を注入したいとき、
    /// `Yarn.Loader.parseProject` で得た project を VM に渡す前に当てる。
    /// 変更は純粋（元の project は変えない）。
    /// 注意: Flix では `project` は予約語のため、引数名は `loaded` を採用している。
    pub def overrideInitialFloat(name: String, value: Float64, loaded: YarnProject):
                                  YarnProject =
        let newInitial =
            Map.insert(name, FloatV(value), loaded#program#initialValues);
        let newProgram = { initialValues = newInitial | loaded#program };
        { program = newProgram | loaded }

    /// VM 内部の `VariableStorage` をエンジン外（gameLoop 等）から
    /// 読み書きするための effect。
    ///
    /// `VariableStorage` は VM の region rc に閉じているため、外側から直接
    /// 触れない。この effect の handler を `Dialogue.Runner.withRunner` 内で
    /// 注入することで、handler が `vmRef` 経由で storage を proxy する。
    ///
    /// 用途:
    ///   - `<<flag set X>>` で `$flag_X = true` を立てる
    ///   - `<<item add Y>>` で `$inv_Y = true` を立てる
    ///   - `has_item("Y")` builtin が読む `$inv_Y` の真偽値を gameLoop 側から書き込む
    pub eff VariableAccess {
        /// Bool 値を Yarn 変数に書き込む。VM が未開始（None）のときは無視する。
        def setBool(name: String, value: Bool): Unit
        /// Bool 値を Yarn 変数から読む。未設定 / VM 未開始 / 型不一致は None。
        def getBool(name: String): Option[Bool]
        /// 現在 VM がいるノードの名前。未開始なら None。
        /// `<<save>>` ハンドラが「セーブの保存先ノード名」を取るのに使う。
        def currentNode(): Option[String]
        /// VM の全変数スナップショット。未開始なら空 Map。
        /// `<<save>>` ハンドラが直列化対象として取得する。
        def variableSnapshot(): Map[String, Yarn.Types.Value]
    }
}
