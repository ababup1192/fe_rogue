/// Yarn の `callFunc` で未対応関数名が来たときの拡張ポイント。
///
/// 設計意図:
///   - `Yarn.Builtins.call` はエンジン同梱の組み込み関数（visited / Number.* / Bool.* / has_item）を
///     ハードコードで実装している。それ以外の関数名はフォールバックとして本 effect の
///     `lookup` を呼び、`Some(result)` が返れば採用、`None` なら "unknown builtin" エラー。
///   - 実体（部屋・インベントリなどゲーム固有状態を覗く handler）は `Game.start` で注入する。
///     エンジン側はゲーム effect を一切知らないまま、効果システム経由で結合する。
///   - テストや CLI ヘッドレス利用では `withNoExtension` を被せれば既存挙動と変わらない
///     （常に `None` を返す = ハードコード builtin だけが効く）。
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
