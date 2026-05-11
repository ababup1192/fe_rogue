/// Yarn 変数の格納庫。region 内 `MutMap` を薄くラップする。
///
/// `init` で初期値マップから作り、その後は `get` / `set` / `incrementFloat` で操作する。
/// VM が `RunNode` で訪問カウンタを更新するときも `incrementFloat` を呼ぶ。
///
/// 将来 SQLite ベース等の差し替え可能ストレージを足すなら trait 抽象を被せる。
mod Yarn.VariableStorage {
    use Yarn.Types.Value
    use Yarn.Types.Value.{FloatV}

    /// region rc に紐づく変数領域。
    pub type alias VariableStorage[r: Region] = MutMap[String, Value, r]

    /// 初期値マップから新しい storage を作る。
    pub def init(rc: Region[r], initialValues: Map[String, Value]): VariableStorage[r] \ r =
        let storage = MutMap.empty(rc);
        Map.forEach((name, value) -> MutMap.put(name, value, storage), initialValues);
        storage

    /// 変数の現在値を取り出す（未設定なら None）。
    pub def get(name: String, storage: VariableStorage[r]): Option[Value] \ r =
        MutMap.get(name, storage)

    /// 変数を上書きする。
    pub def set(name: String, value: Value, storage: VariableStorage[r]): Unit \ r =
        MutMap.put(name, value, storage)

    /// 数値変数を 1 増やす。未設定なら 1 に初期化する。
    /// VM が `RunNode` で訪問カウンタ `$Yarn.Internal.Visiting.<NodeName>` を進めるのに使う。
    pub def incrementFloat(name: String, storage: VariableStorage[r]): Unit \ r =
        let current = match MutMap.get(name, storage) {
            case Some(FloatV(n)) => n
            case _               => 0.0
        };
        MutMap.put(name, FloatV(current + 1.0), storage)

    /// 全エントリを不変 `Map` に書き出す。セーブ用スナップショットに使う。
    pub def toMap(storage: VariableStorage[r]): Map[String, Value] \ r =
        MutMap.toMap(storage)

    /// 全エントリを破棄して、`initialValues` で再初期化する。
    /// セーブデータからのロード（`restart` 経路）など、storage を「フレッシュな状態」に
    /// 戻したいときに使う。`MutMap` 自体の identity は保持するので、storage への
    /// 参照を持っている VM/handler は壊れない。
    pub def reset(storage: VariableStorage[r], initialValues: Map[String, Value]): Unit \ r =
        MutMap.clear(storage);
        Map.forEach((name, value) -> MutMap.put(name, value, storage), initialValues)
}
