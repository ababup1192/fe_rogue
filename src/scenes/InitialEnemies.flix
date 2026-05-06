/// InitialEnemies — ゲーム開始時の敵スポーン情報を保持する effect
///
/// プレイヤー HP=0 のゲームオーバー時、同じマップで敵を「初期位置・初期HP」で復活させたい。
/// `EnemyScene.add` は `Math.Random` でランダムにスポーンするため、再呼び出しでは
/// 同じ配置が再現できない。そこで `Game.start` で初回 build 直後の敵 spawn 一覧を
/// この effect の Ref に保存しておき、`handlePlayerDeath` から `respawnFromInitial`
/// を呼んで再現する。
///
/// `TurnPhase.withState` と同じ Ref-based handler 注入パターンに揃える。
mod InitialEnemies {

    /// 敵初期 spawn 一覧の読み書き effect。
    pub eff State {
        /// 保存済みスポーン一覧を返す（初期化前は空リスト）。
        def get(): List[EnemyScene.Spawn]
        /// 一覧を上書き保存する。`Game.start` で初回 build 直後に 1 度だけ呼ぶ想定。
        def put(spawns: List[EnemyScene.Spawn]): Unit
    }

    /// `TurnPhase.withState` と同じ流儀の handler 注入。
    /// 内部 `spawnsRef` は closure に閉じ込められ、外からは見えない。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let spawnsRef: Ref[List[EnemyScene.Spawn], r] = Ref.fresh(rc, Nil);
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
