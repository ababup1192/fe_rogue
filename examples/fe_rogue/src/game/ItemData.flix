/// ItemData — 床アイテムの「中身」を表すドメイン ADT（GroundItemKind）。
///
/// 武器/杖/消費アイテムを区別する。拾う・こうかんでプレイヤーのインベントリに追加される。
/// scenes/ItemScene は床アイテムの Sprite 表示・点滅 process（view）を持ち、この型を参照する。
/// game/ 純ロジック（MoveDraft 等）はこの game/ 定義に依存できる。
mod ItemData {

    /// ground item の中身。武器 (`WeaponItem`) / 杖 (`StaffItem`) / 消費アイテム (`ConsumableItem`)。
    pub enum GroundItemKind {
        case WeaponItem(UnitCatalog.WeaponResource)
        case StaffItem(Staff.StaffResource)
        case ConsumableItem(Consumable.ConsumableResource)
    }
}
