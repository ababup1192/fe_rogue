// World — ハイブリッド ECS 化の足場（S0）
//
// シミュレーション状態を寄せていく不変 World の最小版。S0 では scene→World の一方向 sync
// （読み取りのみ）で player/enemy の id 集合と tick を毎フレーム写すだけ。World は描画にも
// ロジックにも影響しない（gameLoop の末尾再帰に thread されるだけ）＝ゲーム挙動は不変。
// S1 以降でここに component store（statuses/hp/gridPos…）を足し、正を段階的に移す。
// 道標: ルート ECS_WORKFLOW.md（§D ロードマップ）。

pub enum World {
    case World({ tick = Int32,
                 playerIds = Set[EntityId],
                 enemyIds  = Set[EntityId] })
}

mod World {

    pub def empty(): World =
        World.World({tick = 0, playerIds = Set.empty(), enemyIds = Set.empty()})

    /// scene→World の一方向 sync（純粋・読み取りのみ）。tick を 1 進め、id 集合を scene から写す。
    /// PlayerScene.getAll / EnemyScene.getAll（既存・純粋）を再利用（新規走査は書かない）。
    pub def syncFromScene(scene: Scene[NodeTag], world: World): World =
        let World.World(w) = world;
        let pids = PlayerScene.getAll(scene) |> List.map(d -> d#id) |> List.toSet;
        let eids = EnemyScene.getAll(scene) |> List.map(d -> d#id) |> List.toSet;
        World.World({tick = w#tick + 1, playerIds = pids, enemyIds = eids})
}
