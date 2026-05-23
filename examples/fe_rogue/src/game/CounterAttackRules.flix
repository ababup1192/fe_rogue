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
    /// Pacing.hold / EnemyScene.startAttack / commit のいずれかを起動する。
    pub enum Outcome with Eq, ToString {
        /// 狙った敵が瀕死 (death_blink 中) → kill 演出
        case Kill
        /// 敵が生存 + 反撃可能 → 反撃モーション開始 (反撃する敵 id)
        case Counter(Int32)
        /// 敵が生存だが反撃不能、または対象が無い → 通常 commit
        case Commit
    }

    /// 攻撃側プレイヤーと、その attackTargetId が指している敵 (居なければ None) から
    /// 次の挙動を決める。
    ///   target = None        → Commit (対象消失)
    ///   target#isDying       → Kill
    ///   target に武器 + 射程内 → Counter(target#id)
    ///   それ以外              → Commit
    pub def decide(player: PlayerScene.Data, target: Option[EnemyScene.Data]): Outcome =
        match target {
            case None      => Outcome.Commit
            case Some(eid) =>
                if (eid#isDying) Outcome.Kill
                else match eid#weapon {
                    case None    => Outcome.Commit
                    case Some(w) =>
                        let d = Weapon.manhattan(eid#gridPos, player#gridPos);
                        if (Weapon.canReach(d, w)) Outcome.Counter(eid#id)
                        else Outcome.Commit
                }
        }

    /// 反撃する敵 id を返す。Counter ケースだけ Some、それ以外は None。
    /// 呼び出し側の利便のためのアダプタ (`decide` を使うのが推奨)。
    pub def attackerForPlayer(player: PlayerScene.Data,
                               target: Option[EnemyScene.Data]): Option[Int32] =
        match decide(player, target) {
            case Outcome.Counter(eid) => Some(eid)
            case _                    => None
        }

    /// `decide` の鏡像。敵の攻撃完了後に「味方が反撃するか」を決める。
    /// PlayerScene.Data は isDying を持たない (HP <= 0 で即 scene から除去される) ため、
    /// hp <= 0 を kill 判定として扱う。武器は先頭 (weapons.head) を反撃武器として使う想定。
    ///   target = None        → Commit
    ///   target#hp <= 0       → Kill (実際は次フレームで scene から消える)
    ///   weapons 空           → Commit
    ///   先頭武器が射程内      → Counter(target#id)
    ///   それ以外              → Commit
    pub def decidePlayerCounter(enemy: EnemyScene.Data,
                                 target: Option[PlayerScene.Data]): Outcome =
        match target {
            case None    => Outcome.Commit
            case Some(p) =>
                if (p#hp <= 0) Outcome.Kill
                else match List.head(p#weapons) {
                    case None    => Outcome.Commit
                    case Some(w) =>
                        let d = Weapon.manhattan(p#gridPos, enemy#gridPos);
                        if (Weapon.canReach(d, w)) Outcome.Counter(p#id)
                        else Outcome.Commit
                }
        }

    /// 攻撃で倒した敵 id を返す。target が isDying なら Some(id)、それ以外は None。
    /// 「いま完了した attack_lunge が敵を倒したか」判定に使う。
    pub def killedTargetEnemyId(target: Option[EnemyScene.Data]): Option[Int32] =
        match target {
            case Some(e) => if (e#isDying) Some(e#id) else None
            case None    => None
        }
}
