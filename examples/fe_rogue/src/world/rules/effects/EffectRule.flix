/// EffectRule — 特殊効果 DSL の「ルール」構造・日本語プレビュー・ルール検証
///
/// `EffectDsl`（効果量・述語・レンジ検証の純粋コア）の上に、効果1件 = `EffectRule` の
/// 型（6軸 × 2系統）と、IDE が見せる日本語1文プレビュー `previewRule`、保存前の検証
/// `validateRule`（未結線 op・数値レンジ・whileEquipped 縛り）を置く。すべて Scene 非依存。
///
/// 6軸: trigger（発動契機）/ deliver（配送）/ cond（ガード述語）/ chance（確率）/
///       actions（投射系 do[]）/ flow（制御フロー系）。
/// 予約語回避でフィールド名は trigger / deliver / cond / chance / actions / flow とする
/// （when/if/do/for は Flix 予約語のため使わない）。
mod EffectRule {

    use EffectDsl.{Amount, Pred, Verdict, Stat, AmountBase}

    // ════════════════════════════════════════════════════════
    // 軸の型
    // ════════════════════════════════════════════════════════

    /// 発動契機。interpreter がこの瞬間にルールを評価する。
    pub enum Trigger with Eq, ToString {
        case OnUse
        case OnHit
        case OnAttack
        case OnCast
        case OnKill
        case OnDamaged
        case OnDeath
        case OnTurnStart
        case OnEquip
        case OnEnemyTurn
    }

    /// 配送。self=使用者自身 / throw=ray を飛ばす / auto=自動発火（所持中フック）。
    pub enum Deliver with Eq, ToString {
        case DeliverSelf
        case DeliverThrow
        case DeliverAuto
    }

    /// 対象の役割。Area は半径を持つ（周囲 r マス）。
    pub enum Role with Eq, ToString {
        case RoleSelf
        case RoleAttacker
        case RoleTarget
        case RoleArea(Int32)
    }

    /// 当たり判定を陣営で絞るか。Any=絞らない（rayFirst・陣営無視）。
    pub enum Faction with Eq, ToString {
        case FactionAny
        case FactionAlly
        case FactionEnemy
    }

    /// 対象の状態フィルタ。
    pub enum TargetState with Eq, ToString {
        case StateAny
        case StateNotImmobilized
        case StateAlive
    }

    /// 効果本体の op。A=純粋委譲（即再生可）/ B=Scene custom（要結線）。`isPureOp` で分類。
    pub enum Op with Eq, ToString {
        // A 純粋
        case OpHealFlat
        case OpHealFull
        case OpLifesteal
        case OpDamageFlat
        case OpMaxHpUp
        case OpAtkUp
        case OpSpdUp
        case OpSpdDown
        case OpDefDown
        case OpHitDown
        // 守備+N（まもりのリング）。時限デバフ DefDown と対で、whileEquipped 常時補正専用。
        // DefUp の時限ステータスは存在しない（Ring.bonuses が処理）ため for:whileEquipped でのみ使う。
        case OpDefUp
        case OpImmobilize
        case OpReviveCharge
        case OpPowerMul
        case OpFinisher
        // B Scene custom（要結線）
        case OpKnockback
        case OpDropItem
        case OpSwapPos
        case OpWarpToStairs
        case OpRingify
    }

    /// ノックバックの向き。
    pub enum Dir with Eq, ToString {
        case DirFromAttacker
        case DirCastRay
        case DirAwayFromSelf
    }

    /// 継続。Turns は時限、WhileEquipped は装備中常時補正（Ring.bonuses 経路）。
    pub enum Duration with Eq, ToString {
        case DurInstant
        case DurTurns(Int32)
        case DurPermanent
        case DurWhileEquipped
        case DurEveryTurn
        case DurUntilHit
    }

    /// 制御フローの種類。
    pub enum FollowKind with Eq, ToString {
        case Brave
        case Pursuit
    }

    // Flow は List[Action]（record alias）を含むため Eq/ToString は自動導出できない。
    // 比較・文字列化は不要なので導出しない（preview/validate は match で処理する）。
    pub enum Flow {
        case FollowUp(FollowKind)
        case ReplaceAttack(Int32, List[Action])
    }

    /// 対象指定。faction 省略は FactionAny（rayFirst）として decode で埋める。
    pub type alias Target = {
        role    = Role,
        faction = Faction,
        state   = TargetState
    }

    /// 投射系の作用 1 つ。
    pub type alias Action = {
        to       = Target,
        op       = Op,
        amount   = Option[Amount],
        dir      = Option[Dir],
        duration = Option[Duration],
        vfx      = Option[String],
        sfx      = Option[String]
    }

    /// 効果ルール 1 件。
    pub type alias EffectRule = {
        trigger = Trigger,
        deliver = List[Deliver],
        cond    = Pred,
        chance  = Int32,
        actions = List[Action],
        flow    = Option[Flow]
    }

    /// op が A 純粋（即再生可）か。false は B Scene custom（要結線）。
    /// IDE の緑/灰の色分けと、validateRule の未結線ブロックの根拠。
    pub def isPureOp(op: Op): Bool = match op {
        case Op.OpKnockback    => false
        case Op.OpDropItem     => false
        case Op.OpSwapPos      => false
        case Op.OpWarpToStairs => false
        case Op.OpRingify      => false
        case _                 => true
    }

    // ════════════════════════════════════════════════════════
    // previewRule — 日本語1文プレビュー（IDE 表示。「日本語でプログラミング」の中核）
    // ════════════════════════════════════════════════════════

    def statJa(s: Stat): String = match s {
        case Stat.Magic => "魔力"
    }

    /// 効果量を表示用文字列へ。
    def amountJa(a: Amount): String = match a {
        case Amount.Flat(v)        => "${v}"
        case Amount.Pct(_, v)      => "${v}%"
        case Amount.Mul(v)         => "${v / 100}.${(v - (v / 100) * 100)}倍"
        case Amount.Tiles(v)       => if (v == 0) "無制限" else "${v}マス"
        case Amount.Count(v)       => "${v}"
        case Amount.StatPlus(s, v) => "${statJa(s)}+${v}"
    }

    /// 対象＋助詞＋効果を 1 つの自然な句にする（「敵に 15 の固定ダメージを与える」等）。
    /// 助詞（の／に／を／は／と）は効果ごとに変わるため、対象文字列を効果側で埋め込む。
    def opClause(op: Op, amount: Option[Amount], tgt: String): String =
        let n = Option.map(amountJa, amount) |> Option.getWithDefault("");
        match op {
            case Op.OpHealFlat     => "${tgt}の HP を ${n} 回復する"
            case Op.OpHealFull     => "${tgt}の HP を全回復する"
            case Op.OpLifesteal    => "${tgt}は 与えたダメージの ${n} を回復する"
            case Op.OpDamageFlat   => "${tgt}に ${n} の固定ダメージを与える"
            case Op.OpMaxHpUp      => "${tgt}の 最大 HP を ${n} 上げる"
            case Op.OpAtkUp        => "${tgt}の攻撃力を ${n} 上げる"
            case Op.OpSpdUp        => "${tgt}の速さを ${n} 上げる"
            case Op.OpSpdDown      => "${tgt}の速さを ${n} 下げる"
            case Op.OpDefDown      => "${tgt}の守備を ${n} 下げる"
            case Op.OpDefUp        => "${tgt}の守備を ${n} 上げる"
            case Op.OpHitDown      => "${tgt}の命中を ${n}% 下げる"
            case Op.OpImmobilize   => "${tgt}を 完全に動けなくする（攻撃を受けると解除）"
            case Op.OpReviveCharge => "${tgt}は 倒れても全回復してよみがえる"
            case Op.OpPowerMul     => "${tgt}の 攻撃の威力を ${n} にする"
            case Op.OpFinisher     => "${tgt}に 必ず必殺を当てる"
            case Op.OpKnockback    => if (String.isEmpty(n)) "${tgt}を 押し流す" else "${tgt}を ${n} 押し流す"
            case Op.OpDropItem     => "${tgt}に アイテムを落とさせる"
            case Op.OpSwapPos      => "${tgt}と 位置を入れ替える"
            case Op.OpWarpToStairs => "${tgt}を 止めて 階段マスへ飛ばす"
            case Op.OpRingify      => "${tgt}の 持ち物を指輪に変える"
        }

    /// 対象を「誰に / 誰を」の句にする。
    def targetJa(t: Target): String =
        let core = match t#role {
            case Role.RoleSelf      => "自分"
            case Role.RoleAttacker  => "攻撃側"
            case Role.RoleArea(_)   => "周囲"
            case Role.RoleTarget    => match t#faction {
                case Faction.FactionAny   => "最初に当たった相手"
                case Faction.FactionAlly  => "味方"
                case Faction.FactionEnemy => "敵"
            }
        };
        match t#state {
            case TargetState.StateNotImmobilized => "止まっていない${core}"
            case _                               => core
        }

    /// 継続を句にする。
    def durationJa(d: Option[Duration]): String = match d {
        case None => ""
        case Some(dur) => match dur {
            case Duration.DurInstant       => ""
            case Duration.DurTurns(n)      => "${n} ターンのあいだ"
            case Duration.DurPermanent     => "永続で"
            case Duration.DurWhileEquipped => "装備しているあいだ（常時補正）"
            case Duration.DurEveryTurn     => "毎ターン"
            case Duration.DurUntilHit      => "攻撃を受けるまで"
        }
    }

    /// 1 アクションの句「（継続、）対象＋助詞＋効果」。助詞は opClause が対象を埋めて決める。
    def actionJa(a: Action): String =
        let dur = durationJa(a#duration);
        let durPart = if (String.isEmpty(dur)) "" else "${dur}、";
        "${durPart}${opClause(a#op, a#amount, targetJa(a#to))}"

    /// 文頭の導入句。トリガーで決まる（onUse のときだけ配送 self/throw で「使用すると/投げて」を出し分け）。
    /// onEquip は継続句「装備しているあいだ」が時制を担うので導入句なし。
    /// `throwLead` は throw 配送の動詞（消費=「投げて、」杖=「杖をふって、」とアイテム種で替える）。
    def leadInJa(trigger: Trigger, ds: List[Deliver], throwLead: String): String = match trigger {
        case Trigger.OnUse =>
            if (List.memberOf(Deliver.DeliverThrow, ds)) throwLead
            else if (List.memberOf(Deliver.DeliverSelf, ds)) "使用すると、"
            else ""
        case Trigger.OnEquip     => ""
        case Trigger.OnTurnStart => "自分のターンの始めに、"
        case Trigger.OnKill      => "敵を倒すと、"
        case Trigger.OnDeath     => "倒れたとき、"
        case Trigger.OnHit       => "攻撃が当たると、"
        case Trigger.OnAttack    => "攻撃するとき、"
        case Trigger.OnCast      => "唱えると、"
        case Trigger.OnDamaged   => "ダメージを受けると、"
        case Trigger.OnEnemyTurn => "敵のターンに、"
    }

    def flowJa(f: Flow): String = match f {
        case Flow.FollowUp(FollowKind.Brave)   => "速さが相手より速ければ、もう一度攻撃する"
        case Flow.FollowUp(FollowKind.Pursuit) => "速さが相手より速いと一定確率でもう一度攻撃する"
        case Flow.ReplaceAttack(c, _)          => "${c}% で通常攻撃をやめて差し替える"
    }

    /// 効果ルールを日本語1文にする。flow があれば flow 文、なければ deliver + actions 文。
    /// 既定の throw 動詞は「投げて、」。杖など別の動詞を出したいときは `previewRuleWith`。
    pub def previewRule(rule: EffectRule): String =
        previewRuleWith(rule, "投げて、")

    /// `previewRule` の throw 配送動詞を差し替えられる版（杖＝「杖をふって、」など）。
    pub def previewRuleWith(rule: EffectRule, throwLead: String): String = match rule#flow {
        case Some(f) => flowJa(f)
        case None =>
            let body = rule#actions
                        |> List.map(actionJa)
                        |> String.intercalate("、さらに ");
            "${leadInJa(rule#trigger, rule#deliver, throwLead)}${body}。"
    }

    // ════════════════════════════════════════════════════════
    // validateRule — 保存前検証（未結線 op / 数値レンジ / whileEquipped 縛り）
    // ════════════════════════════════════════════════════════

    def isGood(v: Verdict): Bool = match v {
        case Verdict.Good => true
        case _            => false
    }

    /// op が結線済みか（B custom で未結線だと保存できない）。Phase1 では A 純粋のみ結線済みとする。
    /// B custom op が結線されるたびこの集合を広げる（Phase3）。
    def isWired(op: Op): Bool = isPureOp(op)

    /// amount のレンジ検証（kind ごとに EffectDsl の validator へ）。
    def amountVerdicts(amt: Option[Amount]): List[Verdict] = match amt {
        case None => Nil
        case Some(a) => match a {
            case Amount.Mul(v)         => EffectDsl.validateMul(v) :: Nil
            case Amount.Pct(_, v)      => EffectDsl.validatePct(v) :: Nil
            case Amount.Tiles(v)       => EffectDsl.validateTiles(v) :: Nil
            case Amount.StatPlus(_, v) => EffectDsl.validateStatPlus(v) :: Nil
            case Amount.Flat(v)        =>
                (if (v < 1) Verdict.Reject("flat は 1 以上。${v} は無効果") else Verdict.Good) :: Nil
            case Amount.Count(_)       => Nil
        }
    }

    /// 継続のレンジ・文脈検証。whileEquipped は self 役割のみ許可（隠れルーティング封じ §5/#5）。
    def durationVerdicts(a: Action): List[Verdict] = match a#duration {
        case None => Nil
        case Some(dur) => match dur {
            case Duration.DurTurns(n)      => EffectDsl.validateTurns(n) :: Nil
            case Duration.DurWhileEquipped =>
                (match a#to#role {
                    case Role.RoleSelf => Verdict.Good
                    case _             => Verdict.Reject("whileEquipped は自分(self)にしか使えません（常時補正は装備者のみ）")
                }) :: Nil
            case _ => Nil
        }
    }

    /// 1 アクションの全検証。未結線 op は保存ブロック（reject）。
    def actionVerdicts(a: Action): List[Verdict] =
        let wired = if (isWired(a#op)) Verdict.Good
                    else Verdict.Reject("この効果は未結線の op（${a#op}）を含むため保存できません");
        wired :: List.append(amountVerdicts(a#amount), durationVerdicts(a))

    /// ルール全体を検証し、問題（Reject / Warn）だけを返す。空なら健全。
    pub def validateRule(rule: EffectRule): List[Verdict] =
        let chanceV = EffectDsl.validateChance(rule#chance);
        let actionVs = List.flatMap(actionVerdicts, rule#actions);
        List.filter(v -> not isGood(v), chanceV :: actionVs)

    /// ルールが保存可能（Reject が 1 つも無い）か。Warn は許容。
    pub def isSavable(rule: EffectRule): Bool =
        validateRule(rule) |> List.forAll(v -> match v {
            case Verdict.Reject(_) => false
            case _                 => true
        })

    // ════════════════════════════════════════════════════════
    // resolveTarget — 対象解決（rayFirst / faction 絞り / state フィルタ）
    //   設計の核心: deliver:throw は「ray が最初に当たった1体を陣営無視で対象化」が既定。
    //   faction を明示したときだけ陣営で絞る（火炎瓶=enemy / かなしばり=ally）。
    // ════════════════════════════════════════════════════════

    /// ray 上の候補ユニット 1 体。`ally` は **PlayerDriver 側のユニットか（＝is-player）**、
    /// `immobilized` は完全停止中か、`alive` は HP>0 か。実 Scene が PlayerData/EnemyData から
    /// 組んで渡す（ここは純粋判定のみ）。陣営（味方/敵）は actor の is-player と突き合わせて判定する
    /// （factionOk）ので、この `ally` 単体は「使用者と同陣営か」ではなく「player 側か」を表す。
    pub type alias RayUnit = {
        id          = Int32,
        ally        = Bool,
        immobilized = Bool,
        alive       = Bool
    }

    /// 陣営フィルタ。FactionAny は常に true（rayFirst・陣営無視＝既定）。
    /// `isPlayerUnit` は対象が PlayerDriver 側か、`actorIsPlayer` は使用者が player 側か。
    /// 味方（Ally）＝両者の is-player が一致、敵（Enemy）＝不一致。これにより敵 actor 視点でも
    /// 「敵から見た enemy＝player 駒」が正しく解決される（player actor では従来挙動と一致）。
    pub def factionOk(want: Faction, isPlayerUnit: Bool, actorIsPlayer: Bool): Bool = match want {
        case Faction.FactionAny   => true
        case Faction.FactionAlly  => isPlayerUnit == actorIsPlayer
        case Faction.FactionEnemy => isPlayerUnit != actorIsPlayer
    }

    /// 状態フィルタ。NotImmobilized は停止中を除外（かなしばり詠唱の対象選定）。
    pub def stateOk(want: TargetState, u: RayUnit): Bool = match want {
        case TargetState.StateAny            => true
        case TargetState.StateNotImmobilized => not u#immobilized
        case TargetState.StateAlive          => u#alive
    }

    /// 解決済みの対象。`id` に加え `ally`（**PlayerDriver 側か＝is-player**）を持つ。
    /// player/enemy のノード名前空間が別（id は衝突しうる）ため、runPlan が
    /// player へ作用するか enemy へ作用するかを `ally` で出し分ける。
    pub type alias UnitRef = {
        id   = Int32,
        ally = Bool
    }

    /// throw/target の対象: ray が最初に当たった、faction/state を満たすユニット。
    /// faction 省略（FactionAny）なら敵味方を問わず最初の1体（杖 Heal が敵にも当たる既存挙動）。
    /// `actorIsPlayer` は陣営判定（factionOk）に使う（使用者が player 側か）。
    pub def resolveRayTarget(t: Target, rayUnits: List[RayUnit], actorIsPlayer: Bool): Option[UnitRef] =
        rayUnits
            |> List.filter(u -> factionOk(t#faction, u#ally, actorIsPlayer) and stateOk(t#state, u))
            |> List.head
            |> Option.map(u -> {id = u#id, ally = u#ally})

    /// 役割に応じて対象を解決する。self / attacker は使用者自身なので ally は使用者の is-player
    /// （`actorIsPlayer`）。これにより敵 actor の自己回復（吸血）が EnemyDriver 側へ正しく流れる。
    /// Area は単一 id ではない（runPlan が Board.cellsWithin で展開）。
    pub def resolveTarget(t: Target, selfId: Int32, attackerId: Int32,
                          rayUnits: List[RayUnit], actorIsPlayer: Bool): Option[UnitRef] = match t#role {
        case Role.RoleSelf     => Some({id = selfId, ally = actorIsPlayer})
        case Role.RoleAttacker => Some({id = attackerId, ally = actorIsPlayer})
        case Role.RoleTarget   => resolveRayTarget(t, rayUnits, actorIsPlayer)
        case Role.RoleArea(_)  => None
    }
}
