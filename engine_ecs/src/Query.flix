// Query — component store（Map[EntityId, _]）上の汎用 join / update コンビネータ
//
// 各 System が手書きしていた「2 つの component map を突き合わせる」処理を一般化する。
// Bevy の Query<(&A, &B)> に相当。すべて純粋。
// （ecs_flix の Query モジュールを参考にした再利用部品。汎用 lib 化は別途）
// updateWith2 は keyset 不変・値だけ変換だが、3 関数を foldLeftWithKey で揃え版差異リスクを避ける。

mod Query {

    /// 2 種の component を「両方持つ」entity だけを取り出し、その値の組を返す。
    /// 片方しか持たない entity は結果に含めない（Bevy `Query<(&A, &B)>`）。
    pub def with2(a: Map[EntityId, x], b: Map[EntityId, y]): Map[EntityId, (x, y)] =
        a |> Map.foldLeftWithKey((acc, id, va) ->
            match Map.get(id, b) {
                case Some(vb) => Map.insert(id, (va, vb), acc)
                case None     => acc
            }, Map.empty())

    /// target を、other を見ながら更新する。両方持つ entity だけ update を適用し、
    /// other を持たない entity の target 値はそのまま残す（movement 等の土台）。
    pub def updateWith2(target: Map[EntityId, x], other: Map[EntityId, y],
                        update: x -> y -> x): Map[EntityId, x] =
        target |> Map.foldLeftWithKey((acc, id, tv) ->
            match Map.get(id, other) {
                case Some(ov) => Map.insert(id, update(tv, ov), acc)
                case None     => Map.insert(id, tv, acc)
            }, Map.empty())

    /// entity レコードのリストから component store を作る（scene→World read-model mirror の核）。
    /// keyOf で id を、valOf で値を取り出して Map に畳む。
    pub def indexBy(keyOf: a -> EntityId, valOf: a -> v, xs: List[a]): Map[EntityId, v] =
        List.foldLeft((m, x) -> Map.insert(keyOf(x), valOf(x), m), Map.empty(), xs)

    /// entity レコードのリストから id 集合（tag）を作る。
    pub def tagOf(keyOf: a -> EntityId, xs: List[a]): Set[EntityId] =
        xs |> List.map(keyOf) |> List.toSet

    /// tag に属する entity の値だけ f を適用する（Bevy の `With<T>` フィルタ付き System 相当）。
    /// tag 外の entity は値そのまま・keyset 不変。
    pub def updateTagged(tag: Set[EntityId], f: v -> v, store: Map[EntityId, v]): Map[EntityId, v] =
        Map.mapWithKey((id, v) -> if (Set.memberOf(id, tag)) f(v) else v, store)

    /// 2 store を join し、両方持つ entity だけを f で射影して list 化する（with2 の list 版）。
    /// 注: foldLeft の prepend ゆえ結果は id 降順。順序非依存（後段で安定ソート等）の用途向け。
    pub def with2List(a: Map[EntityId, x], b: Map[EntityId, y], f: EntityId -> x -> y -> r): List[r] =
        a |> Map.foldLeftWithKey((acc, id, va) ->
            match Map.get(id, b) {
                case Some(vb) => f(id, va, vb) :: acc
                case None     => acc
            }, Nil)
}
