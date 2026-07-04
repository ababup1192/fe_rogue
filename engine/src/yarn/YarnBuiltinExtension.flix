/// Yarn の `callFunc` で未対応の関数名が来たときの拡張ポイント。
/// エンジン同梱の組み込み関数で見つからない名前をゲーム側の handler に問い合わせられる
/// ので、エンジンはゲーム固有の状態（部屋・インベントリ等）を知らないまま結合できる。
/// 利用例: `Game.start` で実体 handler を注入する / テストは `withNoExtension` を被せる。
/// 注意: `lookup` が `NotFound` を返すと `Yarn.Builtins.call` が "unknown builtin" にする。
mod Yarn.BuiltinExtension {
    use Yarn.Types.Value

    /// `lookup` の戻り値。
    /// 名前と引数が一致して値を返せるなら `Found(value)`、対応外なら `NotFound`。
    /// `NotFound` を返すと `Yarn.Builtins.call` 側が "unknown builtin" エラーに丸める。
    pub enum LookupResult with Eq, ToString {
        case Found(Value)
        case NotFound
    }

    /// ゲーム側ビルトインの問い合わせ。
    /// ハンドラ実装はゲーム effect (`Game.Inventory.Access` 等) を自由に使ってよい。
    pub eff Access {
        def lookup(name: String, arguments: List[Value]): LookupResult
    }

    /// 拡張なしのデフォルト handler。`lookup` は常に `NotFound` を返す。
    /// テストやエンジン単体検証で使う。
    pub def withNoExtension(thunk: Unit -> a \ ef): a \ (ef - Access) =
        run thunk() with handler Access {
            def lookup(_name, _arguments, k) = k(LookupResult.NotFound)
        }
}
