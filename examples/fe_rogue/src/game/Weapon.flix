/// Weapon — 武器の耐久度消費に関する純粋ロジック
///
/// `UnitCatalog.WeaponResource` は「現在の武器の状態」を保持する型で、攻撃の度に
/// 耐久度（`durability`）が 1 ずつ減る。0 以下になると武器は壊れ、装備者の
/// `weapon` フィールドは `None` に切り替わる。
///
/// このモジュールは Scene[NodeTag] / effect に依存せず、`Option[WeaponResource]` への
/// 写像として書く。テストが純粋値だけで完結する。
mod Weapon {

    use UnitCatalog.WeaponResource

    /// 武器を 1 回使用したあとの状態を返す。
    /// 耐久度が 1 → 0 に遷移するなら `None`（武器が壊れた）。
    /// それ以上残っていれば `Some(更新後 weapon)`。
    pub def consume(weapon: WeaponResource): Option[WeaponResource] =
        let newDur = weapon#durability - 1;
        if (newDur <= 0) None
        else Some({durability = newDur | weapon})

    /// 2 セル間のマンハッタン距離（FE 流の十字 + 斜め判定）。
    /// 反撃や射程内判定に共通で使う。
    pub def manhattan(a: {x = Int32, y = Int32}, b: {x = Int32, y = Int32}): Int32 =
        Int32.abs(a#x - b#x) + Int32.abs(a#y - b#y)

    /// `weapon` が `distance` (マンハッタン距離) の相手に届くか。
    /// `min..max` inclusive で判定する。
    pub def canReach(distance: Int32, weapon: WeaponResource): Bool =
        distance >= weapon#range#min and distance <= weapon#range#max
}
