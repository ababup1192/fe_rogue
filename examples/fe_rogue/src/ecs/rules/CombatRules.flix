/// CombatRules — 戦闘解決の純粋 leaf rules（Scene / effect 非依存）
///
/// `CombatScene` の orchestration から切り出した、乱数も Scene も持たない純関数群。
/// 1 撃解決（`resolveStrike`）・追撃判定（`shouldFollowUp` / `braveFollowUp`）・
/// 命中 SE 名（`hitSoundName`）・武器リスト先頭差し替え（`replaceOrDropHead`）。
/// 数値だけでテストでき、味方→敵 / 敵→味方の両方向が同じ式を通ることで
/// 攻守の式ドリフトを防ぐ。`Combat`（ecs/systems）に計算を委譲する。
mod CombatRules {

    /// 攻守共通の 1 撃解決（純粋）。`Combat.estimate` で命中率・素ダメージを出し、
    /// `Combat.damage` で防御側 HP に適用した結果を 1 レコードで返す。
    /// 味方→敵（`attackForecast`）と敵→味方（`applyDamageToPlayer`）の両方向が
    /// 必ずここを通ることで、攻守の式ドリフトを防ぐ。
    pub def resolveStrike(attacker: Combat.CombatView, defender: Combat.CombatView):
            {hit = Int32, dmg = Int32, newHp = Int32, killed = Bool, crit = Int32} =
        let est    = Combat.estimate(attacker, defender);
        let result = Combat.damage(hp = defender#hp, amount = est#damage);
        {hit = est#hit, dmg = est#damage, newHp = result#newHp, killed = result#isDead,
         crit = est#crit}

    /// 追撃するか（純粋）。攻撃側 speed が防御側 speed +3 以上、追撃リング所持、15% 抽選命中、
    /// かつまだこの攻撃で追撃していない。`roll` は 0..99。
    pub def shouldFollowUp(atkSpeed: Int32, defSpeed: Int32, roll: Int32,
                            hasPursuit: Bool, alreadyFollowedUp: Bool): Bool =
        hasPursuit and not alreadyFollowedUp and atkSpeed >= defSpeed + 3 and roll < 15

    /// はやぶさの剣などブレイブ武器による 2 回攻撃判定（純粋）。攻撃側 speed が防御側 speed +d
    /// 以上なら**確定**で追撃（指輪 Pursuit の 15% 抽選とは別。乱数なし）。`braveThreshold` は
    /// 装備武器から導く（None=ブレイブ武器でない）。`alreadyFollowedUp` で 1 攻撃 1 回に制限。
    pub def braveFollowUp(atkSpeed: Int32, defSpeed: Int32, alreadyFollowedUp: Bool,
                           braveThreshold: Option[Int32]): Bool =
        not alreadyFollowedUp and (match braveThreshold {
            case Some(d) => atkSpeed >= defSpeed + d
            case None    => false
        })

    /// 命中時に鳴らす SE 名を決める（純粋）。優先順位は上から:
    ///   - ダメージ 0（防御で防がれた）→ "guard"
    ///   - 必殺（クリティカル）発動    → "critical"
    ///   - 魔法武器の命中             → "magic"
    ///   - それ以外（物理で 1 以上）   → "damage"
    /// ダメージ 0 判定を最優先する（必殺でも魔法でも 0 なら防がれた音を出す）。
    pub def hitSoundName(damage: Int32, isCrit: Bool,
                          weaponType: WeaponCatalog.WeaponType): String =
        if (damage <= 0) "guard"
        else if (isCrit) "critical"
        else match weaponType {
            case WeaponCatalog.WeaponType.Magic => "magic"
            case _                              => "damage"
        }

    /// 先頭要素を `updated` の中身で差し替える。`None`（耐久 0 で破損）なら先頭を取り除く。
    pub def replaceOrDropHead(updated: Option[a], list: List[a]): List[a] =
        match (updated, list) {
            case (Some(w), _ :: rest) => w :: rest
            case (None,    _ :: rest) => rest
            case (_,       Nil)       => list
        }

}
