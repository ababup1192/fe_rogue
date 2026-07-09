/// InitialSpawns — ゲーム開始時の敵 / プレイヤー spawn 情報を保持する effect
///
/// プレイヤー HP=0 のゲームオーバー時、同じマップで「初期配置・初期 HP・waited=false」
/// で敵とプレイヤーをまとめて復活させたい。`EnemyDriver.add` は `Math.Random` でランダムに
/// 敵を配置するため、再呼び出しでは同じ配置が再現できない。そこで `Game.start` で
/// 初回 build 直後の spawn 一覧をこの effect の Ref に保存しておき、
/// ゲームオーバー時のフロア再構築でこの snapshot から同じ配置を復元する。
///
/// 敵スポーンと味方スポーンは「常に同じタイミングでセットし、同じタイミングで読み出される」
/// ため、1 つの record (`Snapshot`) にまとめて単一の effect で扱う。
mod InitialSpawns {

    /// ゲームオーバー復活用の不変スナップショット。`Game.start` 初回 build 直後に一度だけ保存し、以後は読み出し専用として扱う。
    pub type alias Snapshot = {
        enemies = List[EnemyData.Spawn],
        players = List[PlayerData.Spawn]
    }

    /// Ref を直接公開せず handler 注入で差し替え可能にするための effect 境界。テストや将来の実装切り替えでハンドラを替えるだけで済む。
    pub eff State {
        /// 保存済みスポーン一覧を返す（初期化前は空リスト同士の record）。
        def get(): Snapshot
        /// 一覧を上書き保存する。`Game.start` の初回 build 直後 / ホットリロード時に
        /// 1 度ずつ呼ぶ想定。
        def put(snapshot: Snapshot): Unit
    }

    /// World の `initialSpawns` field（単一権威）へ委譲する facade handler。`worldRef` を共有窓口として
    /// 受け取り、get/put とも World 経由で読み書きする（初期値 `{enemies=Nil, players=Nil}` は `World.empty` が持つ）。
    pub def withState(worldRef: Ref[World, r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            run {
                thunk()
            } with handler State {
                def get(k) = k(World.initialSpawnsOf(Ref.get(worldRef)))
                def put(snapshot, k) = {
                    Ref.put(World.applyCmd(World.Cmd.SetInitialSpawns(snapshot), Ref.get(worldRef)), worldRef);
                    k()
                }
            }
        }
}
