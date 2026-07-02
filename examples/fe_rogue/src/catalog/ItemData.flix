/// ItemData — 床アイテムの「中身」を scenes 層から独立したドメイン ADT として定義する。
///
/// GroundItems（Sprite 表示・点滅）と MoveDraft 等の移動ロジックの両方が「床に何が置かれているか」を
/// 参照するため、scenes でも game でもなく game/ に置くことで双方から import できる。
/// 表示・副作用の責務は GroundItems/InventoryScene が担い、このモジュールは純データのみを持つ。
mod ItemData {

    /// 床に置かれるアイテムの種別。武器・杖・消費アイテムの 3 種が現在のゲームデザインの柱であり、
    /// 弓や防具など新カテゴリを追加する場合は新 variant を追加してここを拡張する。
    pub enum GroundItemKind {
        case WeaponItem(UnitCatalog.WeaponResource)
        case StaffItem(Staff.StaffResource)
        case ConsumableItem(Consumable.ConsumableResource)
        case RingItem(Ring.RingResource)
    }
}
