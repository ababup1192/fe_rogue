/// FloorProgress — 現在いるフロア id をゲーム全体で 1 つ保持する effect
///
/// フロア進行（階段で次の階へ / 全滅で 1F へ / クリアで 1F へループ）の判断に使う。
/// `FloorAdvanceRequest` / `GameOverRequest` の handler がここを読み書きして、
/// 「次にどのフロアを組み立てるか」を決める。
///
/// 初期値は `Game.start` で `FloorCatalog.firstFloorId` を渡して先頭フロアにする。
mod FloorProgress {

    /// 現在フロア id の読み書き effect。
    pub eff State {
        /// 現在いるフロアの id（floors.json の sub-entry キー、例 "f01"）を返す。
        def get(): String
        /// 同一フレーム内で複数回呼ぶと後勝ちになる。呼び手は 1 フレームで 1 回だけ呼ぶこと。
        def put(id: String): Unit
    }

    /// `withState` を巻かずに `State` 操作を呼ぶと effect が未解決のままコンパイルエラーになる。
    /// 内部 `floorRef` は closure に閉じ込められ、外からは見えない。
    /// `firstId` は起動時の初期フロア（通常は `FloorCatalog.firstFloorId`）。
    pub def withState(rc: Region[r], firstId: String):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let floorRef: Ref[String, r] = Ref.fresh(rc, firstId);
            run {
                thunk()
            } with handler State {
                def get(k) = k(Ref.get(floorRef))
                def put(id, k) = {
                    Ref.put(id, floorRef);
                    k()
                }
            }
        }
}
