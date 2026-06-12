/// PlayerData — 味方駒(Piece)のドメインデータ型。
///
/// 駒ドメインデータを scenes/ から切り離し、engine・game 双方が参照できる
/// 単一源泉とするために game/ に置く。
/// game/ 純ロジック(CounterAttackRules 等)はここに依存してよい。
/// game/ から scenes/ の型を参照することは禁じる（依存方向の不変条件）。
mod PlayerData {

    /// ItemMenu で選択中のアイテムの種別と inventory 内 index。
    /// 武器と杖は別リストに格納されているため、どちらに属するかを ADT で区別する。
    pub enum ItemKind with Eq, ToString {
        case Weapon(Int32)     // weapons リスト上の index
        case Staff(Int32)      // staves リスト上の index
        case Consumable(Int32) // consumables リスト上の index
    }

    /// プレイヤー固有の状態。
    /// `id` は連番（Player_<id> ノード名と一致）。
    /// `gridPos` は盤面論理位置（`moveTo` で更新）。
    /// `moveTiles` は 1 ターン移動力。
    /// `hp` は残り体力（最小 0）。0 を検知した呼び手がゲームオーバー処理を行う責務を持つ。
    /// `waited` は行動済みフラグ（灰色表示・選択不可）。
    /// `attackTargetId` は体当たり攻撃中の被攻撃対象 id（Some の間はモーション実行中）。
    /// `resource` はユニット定義テンプレート（Spawn と同一参照を保持し、復元時に Spawn を再構築できる）。
    /// `weapons` は武器インベントリ（先頭が装備中）。
    /// `staves` は杖インベントリ（ItemMenu で使用）。
    /// `consumables` は消費アイテムインベントリ。
    /// `selectedItem` は ItemMenu で選択中の種別と index。
    /// `moveStepsTaken` は AutoMove 当ターンに進行済みマス数（範囲 0..moveTiles）。
    ///   ターン開始時に 0 にリセットされ、moveTiles に達した時点で移動完了とみなす。
    /// `facing` は向き（`walk_<dir>` アニメーション用）。
    /// `hidden` は集合・階段退場で盤面から除外されている状態。
    /// `usedStairs` は階段退場フラグ。
    /// `level` は現レベル（フロア跨ぎで継承）。
    /// `exp` は経験値（0..99）。
    /// `pendingLevelUp` は直近レベルアップ結果。LevelUpScene が演出を終えた後に None へ戻す責務を持つ。
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
        pendingLevelUp     = Option[LevelSystem.Result],
        // 付与中の時限ステータス効果（ちから薬/すばやさ薬の自己バフ、投擲デバフを被弾した場合等）。
        // 味方ターン開始 (`clearAllWaited`) で `StatusSystem.tick` され、効果は `combatView` に反映される。
        statuses           = List[StatusSystem.Status]
    }

    /// スポーン時の中間表現（初期 spawn のスナップショット）。ゲームオーバー復元にも使う。
    /// hp・waited・exp 等の可変フィールドは含まず、resource から再構築できる最小情報のみを保持する設計。
    pub type alias Spawn = {
        id          = Int32,
        gridPos     = {x = Int32, y = Int32},
        resource    = UnitCatalog.UnitResource,
        weapons     = List[UnitCatalog.WeaponResource],
        staves      = List[Staff.StaffResource],
        consumables = List[Consumable.ConsumableResource]
    }

    /// 装備中の武器 = `weapons` リストの先頭、という規約の単一の読み口。
    /// 装備モデルを変えるときはここだけ修正すればよい。
    pub def equippedWeapon(weapons: List[UnitCatalog.WeaponResource]):
            Option[UnitCatalog.WeaponResource] =
        List.head(weapons)

    /// 味方パーティの現フレーム状態を副作用なく読み取る effect。
    /// 非 driver Scene (HUD/Camera/Menu/Overlay) はこの effect 経由で味方データを得ることで、
    /// PlayerScene への直接型参照を持たずに済む（一方向依存の維持）。
    pub eff PartyQuery {
        def get(id: Int32): Option[Data]
        def getAll(): List[Data]
    }
}
