/// EffectLabels — 効果 enum（武器/消費/指輪/杖の `effect`）の内部値 → 日本語表示ラベル。
///
/// IDE の Property パネルで効果のドロップダウンを **日本語で表示**するための辞書。
/// JSON に書く内部値（"Heal" 等の英字）はそのまま保ち、コンボボックスの見た目だけ日本語にする
/// （buildEnumWidget が表示=label / コミット=内部値 で使う）。未知の値はそのまま返すので、
/// 効果以外の enum（weaponType 等）には影響しない。
/// 注: fe_rogue 固有の効果名に対応する。別プロジェクトでは値がそのまま表示される。
mod EffectLabels {

    /// 効果の内部値 → 日本語ラベル。未知の値は素通し（その値自身を返す）。
    /// 同じ内部値が複数カテゴリで使われるもの（Heal/Lifesteal）は両方に通る汎用ラベルにする。
    pub def label(value: String): String = match value {
        // 消費アイテム
        case "Heal"        => "回復"
        case "FullHeal"    => "全回復"
        case "MaxHpUp"     => "最大HP増加"
        case "AutoRevive"  => "自動蘇生"
        case "BlindHit"    => "目つぶし（命中-）"
        case "SpdDownHit"  => "鈍足（速さ-）"
        case "DefDownHit"  => "守備-"
        case "AtkUp"       => "攻撃+"
        case "SpdUp"       => "速さ+"
        case "FireBottle"  => "火炎（固定ダメージ）"
        case "BlastBottle" => "爆発（範囲ダメージ）"
        // 武器
        case "NoEffect"     => "効果なし"
        case "BraveOnSpeed" => "速さ差で2回攻撃"
        case "Knockback"    => "ノックバック"
        case "Desperation"  => "背水（瀕死で威力増）"
        case "Lifesteal"    => "吸収（与ダメ回復）"
        case "ThiefDrop"    => "盗む（アイテム）"
        // 指輪
        case "Power"    => "攻撃+（装備中）"
        case "Swift"    => "速さ+（装備中）"
        case "Guard"    => "守備+（装備中）"
        case "Mend"     => "毎ターン回復"
        case "Finisher" => "瀕死に必殺"
        case "Pursuit"  => "追撃"
        case "Trivial"  => "効果なし"
        // 杖
        case "Blowback" => "ふきとばし"
        case "Swap"     => "位置交換"
        case "Bind"     => "かなしばり"
        case "Stopgap"  => "一時しのぎ"
        case other      => other
    }

    /// 表示ラベルから内部値へ逆引きする（options の中で label が一致する最初の値）。
    /// 1 コンボ内のラベルは一意なので曖昧さは無い。見つからなければ label 自身を返す。
    pub def valueOf(displayLabel: String, options: List[String]): String =
        List.find(opt -> label(opt) == displayLabel, options)
            |> Option.getWithDefault(displayLabel)
}
