/// CounterAttackRules — 味方の攻撃完了後に「次に何が起きるか」を決める純粋ルール
///
/// 攻撃モーション (`attack_lunge`) の finished イベントが届いた瞬間、ゲームは
/// 以下の 3 通りのどれかに進む:
///   - Kill: 狙った敵が瀕死 (death_blink 中) → kill 演出を見せる
///   - Counter(eid): 敵が生存 + 隣接 + 武器あり → 反撃モーション開始
///   - Commit: 敵が生存だが反撃不能 (武器なし / 射程外) → そのまま waited に
///
/// このモジュールは Scene[NodeTag] / effect に一切依存せず、Player / Enemy の
/// Data record だけで判断する。Scene からの値の取り出しは呼び出し側が済ませる。
/// テストは Data fixture を直接組み立てて純粋値だけで完結できる。
mod CounterAttackRules {

    /// 攻撃完了後の分類。呼び出し側はこれを match して
    /// Pacing.hold / CombatDriver.startAttack / commit のいずれかを起動する。
    pub enum Outcome with Eq, ToString {
        /// 狙った敵が瀕死 (death_blink 中) → kill 演出
        case Kill
        /// 敵が生存 + 反撃可能 → 反撃モーション開始 (反撃する敵 id)
        case Counter(Int32)
        /// 敵が生存だが反撃不能、または対象が無い → 通常 commit
        case Commit
    }

    /// **Track A（faction 分岐除去）: 旧 `decide`(味方→敵) と `decidePlayerCounter`(敵→味方) の
    /// faction-split mirror pair を faction-blind な UnitView ベースの 1 関数に統合した置換。**
    /// `UnitView` は既に所属非依存（pos/hp/isDying/weaponRange を id 結合済み）ゆえ、攻撃側/防御側の
    /// faction を `match` せずに判定できる。Kill 条件は敵の `isDying` と味方の `hp<=0` を一律に畳む
    /// （死亡モデルの非対称を view 判定側で吸収）。反撃可否は既存の faction-blind 述語 `UnitView.canAttack`。
    ///   target = None             → Commit
    ///   target が瀕死 or hp<=0     → Kill
    ///   target が attacker へ反撃可 → Counter(target id)
    ///   それ以外                   → Commit
    pub def decideView(attacker: UnitView, target: Option[UnitView]): Outcome =
        match target {
            case None    => Outcome.Commit
            case Some(t) =>
                if (t#isDying or t#hp <= 0) Outcome.Kill
                else if (UnitView.canAttack(t, attacker)) Outcome.Counter(t#id)
                else Outcome.Commit
        }

    /// attack_lunge 完了直後に呼ぶことで、KillOutcome 判定と敵 id 取得を一度に行える。
    /// decide より先に呼んで Kill か否かを確認し、kill 演出の対象 id を得るのが想定用途。
    pub def killedTargetEnemyId(target: Option[EnemyData.Data]): Option[Int32] =
        match target {
            case Some(e) => if (e#isDying) Some(e#id) else None
            case None    => None
        }
}
