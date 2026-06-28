/// AnimEvent — AnimationPlayer に渡すアニメ識別子の **型付き enum**
///
/// `AnimationPlayer.Animation#name` と `AnimationPlayer.MethodKey#name` は
/// engine 側では汎用 String として扱われるが、game 側ではこの enum で 1 か所に集約する。
///
/// ねらい:
///   - **書き手側の typo 防止**: 各 Scene の Animation 定義は
///     `name = AnimEvent.tagToString(AnimEvent.Tag.X)` 経由で書く
///     → 存在しない Tag は型エラーになる
///   - **dispatch 側の網羅性**: `CombatScene.process` (per-node dispatch) が
///     `match AnimEvent.parseTag(event#name) { case Some(Tag.X) => ... }` と書けば
///     新しい Tag を追加し忘れた瞬間に Flix の match 網羅性チェックが警告を出す
///
/// AnimationPlayer 自体を parametric にしない理由は、Flix 0.72 のコードベース内に
/// `pub eff Foo[t]` の前例がなく、リスクと費用対効果を見て見送ったため。engine 側は
/// String のまま、game 側で enum という分離を選んだ。

mod AnimEvent {

    /// AnimationPlayer.tickAll が drainEvents で吐き出すイベント識別子。
    /// - **method tag**: アニメーションの中点等で発火する method (例: `AttackHit`)
    /// - **finished tag**: アニメーション完了時に発火する完了通知 (例: `DeathBlink`)
    ///
    /// 命名規約:
    ///   - method: 動詞句 (`AttackHit`)
    ///   - finished: アニメーション名そのまま (`DeathBlink` / `AttackLunge` / `Snag`)
    pub enum Tag with Eq, ToString {
        /// 攻撃モーションの中点で発火。dispatch 側がダメージ適用 + SE + ログを行う。
        case AttackHit
        /// `death_blink` 完了。dispatch 側が bonus.ogg 再生 + ノード削除を行う。
        case DeathBlink
        /// `attack_lunge` 完了。dispatch 側が attackTarget クリア + commitWaitedAndAdvance を行う。
        case AttackLunge
        /// `snag` 完了。CursorScene が `AnimationPlayer.Scheduler.isPlaying(cursorPath())` を
        /// 直接監視するため dispatch 不要。
        case Snag
    }

    /// `Animation#name` / `MethodKey#name` に詰める文字列表現。
    pub def tagToString(t: Tag): String = match t {
        case Tag.AttackHit   => "attack:hit"
        case Tag.DeathBlink  => "death_blink"
        case Tag.AttackLunge => "attack_lunge"
        case Tag.Snag        => "snag"
    }

    /// dispatch 側で `event#name` を Tag に戻す。外部から流入した未知文字列は `None` として
    /// dispatch が no-op になることを保証する（防御的契約）。
    pub def parseTag(s: String): Option[Tag] = match s {
        case "attack:hit"   => Some(Tag.AttackHit)
        case "death_blink"  => Some(Tag.DeathBlink)
        case "attack_lunge" => Some(Tag.AttackLunge)
        case "snag"         => Some(Tag.Snag)
        case _              => None
    }
}
