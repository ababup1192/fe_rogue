///
/// Shape Survivors — Upgrade（レベルアップ強化：純粋）
///
/// 強化の種類（enum）と、それを World へ適用する純粋関数。
/// 「強化を選ぶ＝World を作り直す」だけなので、UI とは無関係に値だけでテストできる。
/// エンジン非依存（Model だけに依存）。
///
mod Upgrade {

    /// 強化の種類。敵に HP が無いゲームなので「火力で押す」のではなく、
    /// 連射・弾数・移動・耐久を伸ばして生存力を上げる 4 種。
    pub enum Kind with Eq, ToString {
        case FireRate    // 発射間隔を短く（連射が速くなる）
        case MultiShot   // 1 回の発射数 +1（近い敵から順に撃つ）
        case MoveSpeed   // 移動速度 +
        case MaxHp       // 最大 HP +1（同時に 1 回復）
        case Damage      // 弾 1 発の威力 +1（Tank を速く倒せる）
    }

    /// 全種類（ランダム提示の母集合）。
    pub def all(): List[Kind] =
        Kind.FireRate :: Kind.MultiShot :: Kind.MoveSpeed :: Kind.MaxHp :: Kind.Damage :: Nil

    /// 強化を World に適用する（純粋）。該当ステータスだけ作り直す。
    pub def apply(kind: Kind, world: Model.World): Model.World =
        match kind {
            case Kind.FireRate  => { fireInterval = Float64.max(0.08, world#fireInterval * 0.85) | world }
            case Kind.MultiShot => { multiShot = world#multiShot + 1 | world }
            case Kind.MoveSpeed => { moveSpeed = world#moveSpeed + 20.0 | world }
            case Kind.MaxHp     => { maxHp = world#maxHp + 1, hp = world#hp + 1 | world }
            case Kind.Damage    => { damage = world#damage + 1 | world }
        }

    /// 表示用ラベル。
    pub def label(kind: Kind): String =
        match kind {
            case Kind.FireRate  => "Fire Rate +"
            case Kind.MultiShot => "Multi Shot +1"
            case Kind.MoveSpeed => "Move Speed +"
            case Kind.MaxHp     => "Max HP +1"
            case Kind.Damage    => "Damage +1"
        }
}
