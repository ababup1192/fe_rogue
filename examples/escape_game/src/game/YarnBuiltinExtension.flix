/// Yarn のゲーム固有ビルトイン関数の handler。
///
/// `Yarn.BuiltinExtension.Access.lookup` を捌き、エンジン同梱 builtin で対応していない
/// 名前のうち、ゲーム側で意味のあるものを処理する。
///
/// 提供する関数:
///   - `inv_has(itemId: String)`        -> Bool   `Game.Inventory.has`
///   - `inv_selected()`                 -> String 選択スロットのアイテム id（無ければ ""）
///   - `current_room()`                 -> String 現在の部屋 id
///   - `is_locked(hotspotId: String)`   -> Bool   ホットスポットのロック状態
///
/// 設計意図:
///   - `Game.start` で `withGameBuiltins(...)` を `with` チェーンに 1 行加えるだけで配線完了
///   - 内部では `Game.Inventory.Access` / `Game.RoomState.Access` を呼ぶので、これらの
///     handler はこの handler よりも内側（先に注入）に置く必要がある
///   - 引数の型・個数が合わなければ `Some(Err(...))` を返す（ハンドラが自分で対応する
///     名前については握り、未対応名は `None` で外側に流す）
mod Game.YarnBuiltinExtension {
    use Yarn.Types.Value
    use Yarn.Types.Value.{BoolV, StringV}
    use Yarn.BuiltinExtension.LookupResult

    /// Yarn のゲームビルトイン handler を 1 段被せる。
    /// 未対応関数名は `NotFound` を返して `Yarn.Builtins` 側のエラーにフォールスルーする。
    /// 引数の型・個数が合わない場合も `NotFound` 扱い（"unknown builtin" として表面化する）。
    pub def withGameBuiltins(thunk: Unit -> a \ ef):
            a \ (ef - Yarn.BuiltinExtension.Access)
              + Game.Inventory.Access + Game.RoomState.Access =
        run thunk() with handler Yarn.BuiltinExtension.Access {
            def lookup(name, arguments, k) = k(dispatch(name, arguments))
        }

    /// `Inventory.Access` / `RoomState.Access` を呼んでゲーム状態を読む。
    /// 認識できない名前・引数は `NotFound` を返す。
    def dispatch(name: String, arguments: List[Value]):
            LookupResult \ Game.Inventory.Access + Game.RoomState.Access =
        match (name, arguments) {
            case ("inv_has", StringV(itemId) :: Nil) =>
                LookupResult.Found(BoolV(Game.Inventory.has(itemId)))

            case ("inv_selected", Nil) =>
                LookupResult.Found(StringV(Game.Inventory.selectedId()))

            case ("current_room", Nil) =>
                LookupResult.Found(StringV(Game.RoomState.currentRoom()))

            case ("is_locked", StringV(hotspotId) :: Nil) =>
                LookupResult.Found(BoolV(Game.RoomState.isLocked(hotspotId)))

            case _ => LookupResult.NotFound
        }
}
