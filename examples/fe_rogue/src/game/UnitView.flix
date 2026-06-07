/// UnitView — 盤上の 1 ユニットを faction 非依存で見たビュー
///
/// `Board`(座標 + Piece) と各 Scene の `Data`(HP・武器・ステータス) を **id で結合済み**にした
/// 純粋値。「誰が誰に行動できるか」の判定（攻撃可否・推定ダメージ）を味方/敵どちらの視点でも
/// 同じ述語で書けるようにするための共通レイヤ。`Encounter`(Encounter.flix) が scene から
/// `List[UnitView]` を 1 箇所で組み立て、EnemyAI / ActionMenu / BattlePanel がこれを読む。
///
/// Scene[NodeTag] / effect には依存しない（テストは純粋値だけで書ける）。
/// 戦闘数式は `Combat`(`combat: Combat.CombatView`) に、射程判定は `Weapon.inRange` に委譲する。

/// ユニットの所属。攻撃可否は「異なる faction か」で判断する。
pub enum Faction with Eq {
    case Player
    case Enemy
}

/// 盤上の 1 ユニットビュー。位置・残 HP・移動力・装備射程・戦闘ステータスを結合済み。
/// `weaponRange` は装備武器(先頭)の射程。`None` は武器なし＝攻撃不能。
/// `combat` は `Combat.estimate` に渡す戦闘ステータス。`isDying`/`hidden` は除外判定に使う。
pub type alias UnitView = {
    id          = Int32,
    faction     = Faction,
    pos         = {x = Int32, y = Int32},
    hp          = Int32,
    moveTiles   = Int32,
    weaponRange = Option[{min = Int32, max = Int32}],
    combat      = Combat.CombatView,
    isDying     = Bool,
    hidden      = Bool
}

mod UnitView {

    /// `attacker` が今いる位置から `defender` に攻撃できるか。
    /// 条件: 攻撃側が武器を装備（`weaponRange` が Some）し、その射程内に防御側が居て、
    /// 防御側が生存（hp > 0 かつ not isDying）。faction の異同は呼び出し側で絞る前提。
    /// 旧 `ActionMenuScene.canAttackFrom` / `EnemyAI.attackableTargets` の射程判定を集約。
    pub def canAttack(attacker: UnitView, defender: UnitView): Bool =
        defender#hp > 0 and not defender#isDying and
        (match attacker#weaponRange {
            case None    => false
            case Some(r) => Weapon.inRange(Weapon.manhattan(attacker#pos, defender#pos), r)
        })

    /// `attacker` → `defender` の推定ダメージ（命中前提・RNG なし）。`Combat.estimate` の `#damage`。
    /// EnemyAI の「今ターン仕留められるか（Killable）」判定に使う。
    pub def estDamage(attacker: UnitView, defender: UnitView): Int32 =
        Combat.estimate(attacker#combat, defender#combat)#damage

    /// `a` と `b` が異なる faction か（= 交戦相手か）。
    pub def isEnemyOf(a: UnitView, b: UnitView): Bool =
        a#faction != b#faction
}
