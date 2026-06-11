/// PlayerData — 味方駒(Piece)のドメインデータ型。
///
/// 駒の状態(Data)・スポーン中間表現(Spawn)・インベントリ選択種別(ItemKind)を game/ ドメイン層に集約する。
/// scenes/PlayerScene は「これらの型を再export しつつ scene ノードを管理する view 層」になり、
/// game/ 純ロジック(CounterAttackRules 等)はこの game/ 定義に依存できる（game→scenes の型逆流を防ぐ）。
mod PlayerData {

    /// ItemMenu で選択中のアイテムの種別と inventory 内 index。
    /// 武器と杖は別リストに格納されているため、どちらに属するかを ADT で区別する。
    pub enum ItemKind with Eq, ToString {
        case Weapon(Int32)     // weapons リスト上の index
        case Staff(Int32)      // staves リスト上の index
        case Consumable(Int32) // consumables リスト上の index
    }

    /// プレイヤー固有の状態。詳細フィールドの意味は scenes/PlayerScene の元コメント参照。
    /// gridPos は盤面論理位置、weapons 先頭が装備中、selectedItem は ItemMenu 選択中種別。
    pub type alias Data = {
        id                 = Int32,
        gridPos            = {x = Int32, y = Int32},
        moveTiles          = Int32,
        hp                 = Int32,
        waited             = Bool,
        attackTargetId     = Option[Int32],
        resource           = UnitCatalog.UnitResource,
        weapons            = List[UnitCatalog.WeaponResource],
        staves             = List[Staff.StaffResource],
        consumables        = List[Consumable.ConsumableResource],
        selectedItem       = Option[ItemKind],
        moveStepsTaken     = Int32,
        facing             = Staff.Direction,
        hidden             = Bool,
        usedStairs         = Bool,
        level              = Int32,
        exp                = Int32,
        pendingLevelUp     = Option[LevelSystem.Result]
    }

    /// スポーン時の中間表現（初期 spawn のスナップショット = ゲームオーバー復元用にも使う）。
    pub type alias Spawn = {
        id          = Int32,
        gridPos     = {x = Int32, y = Int32},
        resource    = UnitCatalog.UnitResource,
        weapons     = List[UnitCatalog.WeaponResource],
        staves      = List[Staff.StaffResource],
        consumables = List[Consumable.ConsumableResource]
    }

    /// 装備中の武器 = `weapons` リストの先頭、という規約の単一の読み口（純関数）。
    /// 装備モデルを変えるときの唯一の変更点。
    pub def equippedWeapon(weapons: List[UnitCatalog.WeaponResource]):
            Option[UnitCatalog.WeaponResource] =
        List.head(weapons)

    /// 味方パーティの「現フレーム状態」を Scene を介さずに読み取る effect。
    /// 非 driver Scene (HUD/Camera/Menu/Overlay) はこの effect 経由で味方データを得る（一方向依存）。
    /// handler は Game.start で sceneRef から最新 scene を読み PlayerScene.get/getAll を呼ぶ inline handler。
    pub eff PartyQuery {
        def get(id: Int32): Option[Data]
        def getAll(): List[Data]
    }
}
