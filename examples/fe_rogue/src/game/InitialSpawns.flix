/// InitialSpawns — ゲーム開始時の敵 / プレイヤー spawn 情報を保持する effect
///
/// プレイヤー HP=0 のゲームオーバー時、同じマップで「初期配置・初期 HP・waited=false」
/// で敵とプレイヤーをまとめて復活させたい。`EnemyScene.add` は `Math.Random` でランダムに
/// 敵を配置するため、再呼び出しでは同じ配置が再現できない。そこで `Game.start` で
/// 初回 build 直後の spawn 一覧をこの effect の Ref に保存しておき、
/// `handlePlayerDeath` から `respawnFromInitial` を呼んで再現する。
///
/// 敵スポーンと味方スポーンは「常に同じタイミングでセットし、同じタイミングで読み出される」
/// ため、1 つの record (`Snapshot`) にまとめて単一の effect で扱う。
mod InitialSpawns {

    /// 初回 build 時のスポーン一覧。敵 / 味方を 1 つの record で持つ。
    pub type alias Snapshot = {
        enemies = List[EnemyData.Spawn],
        players = List[PlayerData.Spawn]
    }

    /// スポーン一覧の読み書き effect。
    pub eff State {
        /// 保存済みスポーン一覧を返す（初期化前は空リスト同士の record）。
        def get(): Snapshot
        /// 一覧を上書き保存する。`Game.start` の初回 build 直後 / ホットリロード時に
        /// 1 度ずつ呼ぶ想定。
        def put(snapshot: Snapshot): Unit
    }

    /// `TurnPhase.withState` と同じ流儀の handler 注入。
    /// 内部 `snapshotRef` は closure に閉じ込められ、外からは見えない。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let snapshotRef: Ref[Snapshot, r] =
                Ref.fresh(rc, {enemies = Nil, players = Nil});
            run {
                thunk()
            } with handler State {
                def get(k) = k(Ref.get(snapshotRef))
                def put(snapshot, k) = {
                    Ref.put(snapshot, snapshotRef);
                    k()
                }
            }
        }
}
