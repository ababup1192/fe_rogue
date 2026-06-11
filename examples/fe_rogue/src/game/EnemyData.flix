/// EnemyData — 敵駒(Piece)のドメインデータ型（Data / Spawn）。
///
/// scenes/EnemyScene は再export しつつ scene ノードを管理する view 層になり、
/// game/ 純ロジックはこの game/ 定義に依存できる（game→scenes の型逆流を防ぐ）。
mod EnemyData {

    /// 敵駒の状態。`weapon` は装備中武器（攻撃で耐久が減り 0 で None）。
    pub type alias Data = {
        id             = Int32,
        gridPos        = {x = Int32, y = Int32},
        alerted        = Bool,
        homeModuleIdx  = Int32,
        moveTiles      = Int32,
        hp             = Int32,
        isDying        = Bool,
        attackTargetId = Option[Int32],
        resource       = EnemyCatalog.EnemyResource,
        weapon         = Option[UnitCatalog.WeaponResource],
        acted          = Bool
    }

    /// スポーン時の中間表現（respawnFromInitial での復元にも使う）。
    pub type alias Spawn = {
        id        = Int32,
        gridPos   = {x = Int32, y = Int32},
        moduleIdx = Int32,
        resource  = EnemyCatalog.EnemyResource,
        weapon    = UnitCatalog.WeaponResource
    }

    /// 敵駒の「現フレーム状態」を Scene を介さずに読み取る effect（PartyQuery の敵版）。
    /// handler は Game.start で sceneRef から EnemyScene.get/getAll/findIdAt/anyAttacking を呼ぶ。
    pub eff RosterQuery {
        def get(id: Int32): Option[Data]
        def getAll(): List[Data]
        def findIdAt(coord: {x = Int32, y = Int32}): Option[Int32]
        def anyAttacking(): Bool
    }
}
