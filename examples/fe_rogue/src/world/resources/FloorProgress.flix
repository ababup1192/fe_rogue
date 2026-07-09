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

    /// World の `floorId` field（単一権威）へ委譲する facade handler。`worldRef` を共有窓口として受け取り、
    /// get/put とも World 経由で読み書きする。初期フロアは他 store と同様 build choke の `put` が seed する
    /// （`World.empty` の初期値は ""）。
    pub def withState(worldRef: Ref[World, r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            run {
                thunk()
            } with handler State {
                def get(k) = k(World.floorIdOf(Ref.get(worldRef)))
                def put(id, k) = {
                    Ref.put(World.applyCmd(World.Cmd.SetFloorId(id), Ref.get(worldRef)), worldRef);
                    k()
                }
            }
        }
}
