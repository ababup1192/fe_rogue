/// EnemyData — 敵駒(Piece)のドメインデータ型（Data / Spawn）。
///
/// scenes/EnemyDriver は再export しつつ scene ノードを管理する view 層になり、
/// game/ 純ロジックはこの game/ 定義に依存できる（game→scenes の型逆流を防ぐ）。
mod EnemyData {

    /// 1 ターン内で `acted` と `isDying` が排他的に敵の行動可否を制御する。
    /// `acted` は EnemyTurn キュー消化時に true にセットされ、ターン終端でリセットされる（二重行動防止の不変条件）。
    /// `isDying = true` の敵は EnemyTurn.Queue / `findIdAt` などから除外され、以降一切行動しない。
    /// `id`/`gridPos` はスポーン時に確定し、以降 EnemyDriver の配置管理キーとして不変。
    /// `alerted` はプレイヤーと同モジュールに入った瞬間 true になり、以降永続（一方向フラグ）。
    /// `homeModuleIdx` はスポーン時の部屋 idx（検知判定の補助情報）。
    /// `moveTiles` は 1 ターンに進めるマス数（FE の「移動力」相当、`resource` から初期値継承）。
    /// EnemyAI が BFS パスからこの値ぶんだけ進めて 1 マスずつ Tween する。
    /// `hp` は残り体力。0 になると `isDying = true` がセットされ、`death_blink`
    /// アニメーションが再生される。アニメ終了で GameManager がノードを scene から削除する。
    /// `resource` はスポーン時のユニット定義テンプレート（EnemyResource）。
    /// ゲームオーバー時の `respawnFromInitial` で同じ敵種別で再生するために保持。
    /// `weapon` は装備中武器。攻撃するたびに耐久度が 1 減り、0 で `None` になる
    /// （以降、その敵は EnemyAI 側で Attack を返さなくなる）。攻撃力は `resource#attack + weapon#attack`。
    pub type alias Data = {
        id             = Int32,
        // この敵を生成した EnemyCatalog の id。スナップショット保存で resource を id 参照に
        // 落とすために記録する（EnemyResource は name を持たず逆引きできないため spawn 時に保持）。
        resourceId     = String,
        gridPos        = {x = Int32, y = Int32},
        alerted        = Bool,
        homeModuleIdx  = Int32,
        moveTiles      = Int32,
        hp             = Int32,
        isDying        = Bool,
        attackTargetId = Option[Int32],
        resource       = EnemyCatalog.EnemyResource,
        weapon         = Option[UnitCatalog.WeaponResource],
        acted          = Bool,
        // 直前にいたマス（`moveTo` が更新）。徘徊(Wander)で「来た道へ戻らない」ために使い、
        // 1 幅通路を前後に揺れず直進・部屋から通路へ抜けて回遊できるようにする。None は初期 / 未移動。
        prevPos        = Option[{x = Int32, y = Int32}],
        // 付与中の時限ステータス効果（目潰し薬/鈍足薬を投げ当てられた場合）。
        // 敵ターン開始 (`clearActedAll`) で `StatusSystem.tick` され、効果は `combatView` に反映される。
        statuses       = List[StatusSystem.Status],
        // 装備中の指輪（効果発動）。多くの敵は持たないので Option。spawn 時に resource#ring から解決。
        ring           = Option[Ring.RingResource],
        // 追撃リングの 2 回攻撃を 1 度に制限するフラグ。敵ターン開始でリセット、追撃発火で true。
        followUpUsed   = Bool,
        // 投擲瓶（ローグ_T3=爆発瓶 / クレリック_T3=火炎瓶）を 1 度だけ投げるための使用済みフラグ。
        // 投擲は `description` で持つ瓶を判定し、未使用かつ直線上に味方が居れば敵ターンに投げる。
        bottleUsed     = Bool
    }

    /// respawn 時に再生成するために必要な最小情報だけを永続保持する型。
    /// Data 全体でなく resource+weapon の初期値のみを保存することで、
    /// アクティブ状態（hp/acted/isDying 等）を Spawn 側に混入させない設計上の境界を維持する。
    pub type alias Spawn = {
        id         = Int32,
        // 生成元 EnemyCatalog の id（resource の id 参照保存用、Data#resourceId と同じ値）。
        resourceId = String,
        gridPos    = {x = Int32, y = Int32},
        moduleIdx  = Int32,
        resource   = EnemyCatalog.EnemyResource,
        weapon     = UnitCatalog.WeaponResource
    }

    /// 敵駒の「現フレーム状態」を Scene を介さずに読み取る effect（PartyQuery の敵版）。
    /// handler は scenes 側の実態に委譲する設計で、game/ ロジックが scenes/ 型に直接依存しない境界を保つ。
    pub eff RosterQuery {
        def get(id: Int32): Option[Data]
        def getAll(): List[Data]
        def findIdAt(coord: {x = Int32, y = Int32}): Option[Int32]
        def anyAttacking(): Bool
    }

    /// World（各 store の単一権威）から `dataFromWorldEnemy` で再構築して読む facade handler
    /// （`PlayerData.withWorld` と同流儀）。findIdAt/anyAttacking は World の pos/attackTarget を直読み。
    pub def withWorld(worldRef: Ref[World, r]):
            (Unit -> a \ ef) -> a \ (ef - RosterQuery) + r =
        thunk -> {
            run {
                thunk()
            } with handler RosterQuery {
                def get(id, k) = k(World.dataFromWorldEnemy(id, Ref.get(worldRef)))
                def getAll(k)  = {
                    let world = Ref.get(worldRef);
                    k(World.enemyIdsOf(world) |> List.filterMap(id -> World.dataFromWorldEnemy(id, world)))
                }
                def findIdAt(coord, k) = k(World.enemyIdAt(coord, Ref.get(worldRef)))
                def anyAttacking(k)    = k(World.anyEnemyAttacking(Ref.get(worldRef)))
            }
        }
}
