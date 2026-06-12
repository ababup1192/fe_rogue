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
    pub enum StatusEffect with Eq, ToString {
        case HitDown
        case SpdDown
        case AtkUp
        case SpdUp
    }

    /// 付与中の時限効果 1 件。
    /// `effect` は種類、`magnitude` は効果量（常に非負で持つ。符号は反映側で決める）、
    /// `remaining` は残りターン数（`tick` で 1 ずつ減り、0 以下で除去される）。
    pub type alias Status = {
        effect    = StatusEffect,
        magnitude = Int32,
        remaining = Int32
    }

    /// 効果を 1 件付与する（リスト先頭に積む）。同種が複数あれば `sumOf` で合算される。
    pub def add(status: Status, xs: List[Status]): List[Status] =
        status :: xs

    /// 1 ターン経過。各効果の `remaining` を 1 減らし、0 以下になったものを除去する。
    /// ターン開始フック（味方 `clearAllWaited` / 敵 `clearActedAll`）から各ユニットに畳む。
    pub def tick(xs: List[Status]): List[Status] =
        xs
            |> List.map(s -> {remaining = s#remaining - 1 | s})
            |> List.filter(s -> s#remaining > 0)

    /// 指定種別の効果量の合計。同種の重ねがけを合算する。該当無しは 0。
    /// 戦闘ビュー構築で攻撃力・速さ・命中補正へ足し込むのに使う。
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
    pub def combatMods(xs: List[Status]): {atkBonus = Int32, spdDelta = Int32, hitMod = Int32} =
        {atkBonus = sumOf(StatusEffect.AtkUp, xs),
         spdDelta = sumOf(StatusEffect.SpdUp, xs) - sumOf(StatusEffect.SpdDown, xs),
         hitMod   = 0 - sumOf(StatusEffect.HitDown, xs)}
}
