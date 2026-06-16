/// StatusSystem — 時限ステータス効果（バフ / デバフ）の純粋ロジック
///
/// 「N ターン持続し、毎ターン残りが 1 ずつ減り、0 で消える」一時効果を表す。
/// 味方・敵どちらにも乗るので faction 非依存に保ち、`PlayerData.Data` /
/// `EnemyData.Data` の `statuses = List[Status]` として持たせる。
///
/// 使い道（消費アイテム）:
///   - 目潰し薬   → `HitDown`（命中-N%）を当たった敵に付与
///   - 鈍足薬     → `SpdDown`（速さ-N＝回避ダウン）を当たった敵に付与
///   - ちから薬   → `AtkUp`（攻+N）を自分に付与
///   - すばやさ薬 → `SpdUp`（速+N＝回避アップ）を自分に付与
///
/// このモジュールは Scene[NodeTag] / effect / Java 呼び出しに依存しない。
/// 効果値を戦闘へ反映するのは `PlayerScene.combatView` / `EnemyScene.combatView`
/// （`StatusSystem.sumOf` を攻撃力・速さ・命中補正に足し込む）、
/// 毎ターンの減算は `PlayerScene.clearAllWaited` / `EnemyScene.clearActedAll`
/// （`StatusSystem.tick` を畳む）が担う。テストは数値だけで完結する。
mod StatusSystem {

    /// 時限効果の種類。`magnitude` の意味は種類ごとに異なる:
    ///   - `HitDown` : 保有者「自身の命中率」を magnitude% 下げる（目潰し）
    ///   - `SpdDown` : 保有者の速さを magnitude 下げる（回避ダウン。鈍足）
    ///   - `AtkUp`   : 保有者の攻撃力を magnitude 上げる
    ///   - `SpdUp`   : 保有者の速さを magnitude 上げる（回避アップ）
    ///   - `DefDown` : 保有者の守備（物理防御）を magnitude 下げる（ほころび薬）
    ///   - `Immobilized` : 保有者を完全停止（移動も攻撃も不可）。`remaining` ターンの経過で
    ///                     自然解除され、被攻撃 or 被投擲（`clearImmobilized`）でも即時解除される。
    ///                     `magnitude` は使わない（`immobilize()` で 0 を入れる）。
    pub enum StatusEffect with Eq, ToString {
        case HitDown
        case SpdDown
        case AtkUp
        case SpdUp
        case DefDown
        case Immobilized
    }

    /// 付与中の時限効果 1 件。
    /// `effect` は種類、`magnitude` は効果量（常に非負で持つ。符号は反映側で決める）、
    /// `remaining` は残りターン数（`tick` で 1 ずつ減り、0 以下で除去される）。
    pub type alias Status = {
        effect    = StatusEffect,
        magnitude = Int32,
        remaining = Int32
    }

    /// 効果を 1 件付与する。重ねがけはしない: 同じ `effect` 種別が既にあれば積まず
    /// 既存をそのまま据え置く（最初に付与した magnitude / remaining が生きる）。別種は共存する。
    pub def add(status: Status, xs: List[Status]): List[Status] =
        if (List.exists(s -> s#effect == status#effect, xs)) xs
        else status :: xs

    /// 1 ターン経過。各効果の `remaining` を 1 減らし、0 以下になったものを除去する。
    /// `Immobilized` も同じく減算され、`remaining` が尽きると自然解除される。
    /// ターン開始フック（味方 `clearAllWaited` / 敵 `clearActedAll`）から各ユニットに畳む。
    pub def tick(xs: List[Status]): List[Status] =
        xs
            |> List.map(s -> {remaining = s#remaining - 1 | s})
            |> List.filter(s -> s#remaining > 0)

    /// 完全停止（`Immobilized`）の Status を `turns` ターンで作る。被攻撃 / 被投擲なら
    /// `clearImmobilized` で即時解除される（被弾解除は status 型に内在）。magnitude は未使用。
    pub def immobilizeFor(turns: Int32): Status =
        {effect = StatusEffect.Immobilized, magnitude = 0, remaining = turns}

    /// 既定 5 ターンの完全停止 Status（legacy 既定値）。
    pub def immobilize(): Status = immobilizeFor(5)

    /// このユニットが完全停止中か（`Immobilized` を 1 つでも持つか）。
    pub def isImmobilized(xs: List[Status]): Bool =
        List.exists(s -> s#effect == StatusEffect.Immobilized, xs)

    /// 完全停止だけを取り除く（被攻撃 or 被投擲で呼ぶ）。他の時限効果は残す。
    pub def clearImmobilized(xs: List[Status]): List[Status] =
        List.filter(s -> s#effect != StatusEffect.Immobilized, xs)

    /// 指定種別の効果量を返す。`add` が重ねがけを防ぐので通常は 0 件か 1 件だが、
    /// 防御的に合計する（該当無しは 0）。戦闘ビュー構築で攻撃力・速さ・命中補正へ足し込む。
    pub def sumOf(effect: StatusEffect, xs: List[Status]): Int32 =
        xs
            |> List.filter(s -> s#effect == effect)
            |> List.map(s -> s#magnitude)
            |> List.sum

    /// 戦闘ビューへ反映する補正をまとめて返す。`PlayerScene.combatView` /
    /// `EnemyScene.combatView` が `resource` 値にこれを足し込む。
    ///   - `atkBonus` : 攻撃力への加算（`AtkUp`）
    ///   - `spdDelta` : 速さへの増減（`SpdUp` − `SpdDown`）。回避 = 速さ×2+幸運 に効く
    ///   - `hitMod`   : 自身の命中率への補正（`HitDown` ぶん負値。目潰し）
    ///   - `defDelta` : 守備（物理防御）への増減（`DefDown` ぶん負値。ほころび薬）
    pub def combatMods(xs: List[Status]):
            {atkBonus = Int32, spdDelta = Int32, hitMod = Int32, defDelta = Int32} =
        {atkBonus = sumOf(StatusEffect.AtkUp, xs),
         spdDelta = sumOf(StatusEffect.SpdUp, xs) - sumOf(StatusEffect.SpdDown, xs),
         hitMod   = 0 - sumOf(StatusEffect.HitDown, xs),
         defDelta = 0 - sumOf(StatusEffect.DefDown, xs)}

    /// `StatusEffect` の文字列表現（JSON セーブ用）。`parseEffect` と round-trip する。
    pub def effectToString(effect: StatusEffect): String = match effect {
        case StatusEffect.HitDown     => "HitDown"
        case StatusEffect.SpdDown     => "SpdDown"
        case StatusEffect.AtkUp       => "AtkUp"
        case StatusEffect.SpdUp       => "SpdUp"
        case StatusEffect.DefDown     => "DefDown"
        case StatusEffect.Immobilized => "Immobilized"
    }

    /// 文字列 → `StatusEffect` のパース。未知文字列は `Err(その文字列)`。
    /// `effectToString` と round-trip する（JSON セーブ復元で使う）。
    pub def parseEffect(name: String): Result[String, StatusEffect] = match name {
        case "HitDown"     => Ok(StatusEffect.HitDown)
        case "SpdDown"     => Ok(StatusEffect.SpdDown)
        case "AtkUp"       => Ok(StatusEffect.AtkUp)
        case "SpdUp"       => Ok(StatusEffect.SpdUp)
        case "DefDown"     => Ok(StatusEffect.DefDown)
        case "Immobilized" => Ok(StatusEffect.Immobilized)
        case other         => Err(other)
    }
}
