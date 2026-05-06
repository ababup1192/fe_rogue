/// InitialPlayers — ゲーム開始時のプレイヤー spawn 情報を保持する effect
///
/// `InitialEnemies` のプレイヤー版。プレイヤー HP=0 のゲームオーバー時、
/// 同じマップで全プレイヤーを「初期位置・初期 HP・waited=false」で復活させたい。
/// `Game.start` で初回 build 直後の player spawn 一覧をこの effect の Ref に
/// 保存しておき、`handlePlayerDeath` から `respawnFromInitial` を呼んで再現する。
mod InitialPlayers {

    /// プレイヤー初期 spawn 一覧の読み書き effect。
    pub eff State {
        /// 保存済みスポーン一覧を返す（初期化前は空リスト）。
        def get(): List[PlayerScene.Spawn]
        /// 一覧を上書き保存する。`Game.start` で初回 build 直後に 1 度だけ呼ぶ想定。
        def put(spawns: List[PlayerScene.Spawn]): Unit
    }

    /// `InitialEnemies.withState` と同じ流儀の handler 注入。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let spawnsRef: Ref[List[PlayerScene.Spawn], r] = Ref.fresh(rc, Nil);
            run {
                thunk()
            } with handler State {
                def get(k) = k(Ref.get(spawnsRef))
                def put(spawns, k) = {
                    Ref.put(spawns, spawnsRef);
                    k()
                }
            }
        }
}
