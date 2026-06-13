/// EffectRuleCodec — 効果 JSON（IDE が編集するデータ）→ `EffectRule.EffectRule` の decode
///
/// これにより特殊効果が resources の JSON として宣言でき、戦闘コードへのベタ書きを無くす。
/// 各軸（when/deliver/if/chance/do/flow）の文字列・オブジェクトをパースする純粋ロジックで、
/// Scene 非依存ゆえテストが JSON 文字列だけで完結する。未知の値は None にして起動時に発覚させる。
///
/// JSON 形状（例）:
///   { "when": "onUse", "deliver": ["self"], "chance": 100,
///     "do": [ { "to": {"role":"self"}, "op":"atkUp",
///               "amount": {"flat":4}, "for": {"turns":3}, "sfx":"cure" } ] }
mod EffectRuleCodec {

    use Util.Json.Json
    use Util.Json.Json.{JObject, JString, JNumber, JArray}
    use JsonCodec.{expectObject, expectString, expectInt, decodeList}
    use EffectDsl.{Amount, AmountBase, Stat, Pred, Atom}
    use EffectRule.{Trigger, Deliver, Role, Faction, TargetState, Op, Dir, Duration, Flow, FollowKind}

    // ── 小ヘルパ ────────────────────────────────────────────

    /// 最初に Some を返す方を採る（eager。Option の選言）。
    def or2(a: Option[t], b: Option[t]): Option[t] = match a {
        case Some(_) => a
        case None    => b
    }

    /// オブジェクトから Int フィールドを引く。
    def getInt(key: String, obj: Map[String, Json]): Option[Int32] =
        Map.get(key, obj) |> Option.flatMap(expectInt)

    /// オブジェクトから String フィールドを引く。
    def getStr(key: String, obj: Map[String, Json]): Option[String] =
        Map.get(key, obj) |> Option.flatMap(expectString)

    // ── 各軸の文字列パース ──────────────────────────────────

    def parseTrigger(s: String): Option[Trigger] = match s {
        case "onUse"       => Some(Trigger.OnUse)
        case "onHit"       => Some(Trigger.OnHit)
        case "onAttack"    => Some(Trigger.OnAttack)
        case "onCast"      => Some(Trigger.OnCast)
        case "onKill"      => Some(Trigger.OnKill)
        case "onDamaged"   => Some(Trigger.OnDamaged)
        case "onDeath"     => Some(Trigger.OnDeath)
        case "onTurnStart" => Some(Trigger.OnTurnStart)
        case "onEquip"     => Some(Trigger.OnEquip)
        case "onEnemyTurn" => Some(Trigger.OnEnemyTurn)
        case _             => None
    }

    def parseDeliver(s: String): Option[Deliver] = match s {
        case "self"  => Some(Deliver.DeliverSelf)
        case "throw" => Some(Deliver.DeliverThrow)
        case "auto"  => Some(Deliver.DeliverAuto)
        case _       => None
    }

    def parseFaction(s: String): Option[Faction] = match s {
        case "any"   => Some(Faction.FactionAny)
        case "ally"  => Some(Faction.FactionAlly)
        case "enemy" => Some(Faction.FactionEnemy)
        case _       => None
    }

    def parseState(s: String): Option[TargetState] = match s {
        case "any"            => Some(TargetState.StateAny)
        case "notImmobilized" => Some(TargetState.StateNotImmobilized)
        case "alive"          => Some(TargetState.StateAlive)
        case _                => None
    }

    def parseOp(s: String): Option[Op] = match s {
        case "healFlat"     => Some(Op.OpHealFlat)
        case "healFull"     => Some(Op.OpHealFull)
        case "lifesteal"    => Some(Op.OpLifesteal)
        case "damageFlat"   => Some(Op.OpDamageFlat)
        case "maxHpUp"      => Some(Op.OpMaxHpUp)
        case "atkUp"        => Some(Op.OpAtkUp)
        case "spdUp"        => Some(Op.OpSpdUp)
        case "spdDown"      => Some(Op.OpSpdDown)
        case "defDown"      => Some(Op.OpDefDown)
        case "defUp"        => Some(Op.OpDefUp)
        case "hitDown"      => Some(Op.OpHitDown)
        case "immobilize"   => Some(Op.OpImmobilize)
        case "reviveCharge" => Some(Op.OpReviveCharge)
        case "powerMul"     => Some(Op.OpPowerMul)
        case "finisher"     => Some(Op.OpFinisher)
        case "knockback"    => Some(Op.OpKnockback)
        case "dropItem"     => Some(Op.OpDropItem)
        case "swapPos"      => Some(Op.OpSwapPos)
        case "warpToStairs" => Some(Op.OpWarpToStairs)
        case "ringify"      => Some(Op.OpRingify)
        case _              => None
    }

    def parseDir(s: String): Option[Dir] = match s {
        case "fromAttacker" => Some(Dir.DirFromAttacker)
        case "castRay"      => Some(Dir.DirCastRay)
        case "awayFromSelf" => Some(Dir.DirAwayFromSelf)
        case _              => None
    }

    def parseBase(s: String): Option[AmountBase] = match s {
        case "max"      => Some(AmountBase.Max)
        case "dealt"    => Some(AmountBase.Dealt)
        case "incoming" => Some(AmountBase.Incoming)
        case _          => None
    }

    def parseStat(s: String): Option[Stat] = match s {
        case "magic" => Some(Stat.Magic)
        case _       => None
    }

    def parseFollowKind(s: String): Option[FollowKind] = match s {
        case "brave"   => Some(FollowKind.Brave)
        case "pursuit" => Some(FollowKind.Pursuit)
        case _         => None
    }

    def parseAtomNullary(s: String): Option[Atom] = match s {
        case "targetAlive"     => Some(Atom.TargetAlive)
        case "equippedIsRogue" => Some(Atom.EquippedIsRogue)
        case "adjacent"        => Some(Atom.Adjacent)
        case _                 => None
    }

    // ── 効果量 amount ───────────────────────────────────────

    def decodePct(j: Json): Option[Amount] =
        forM (
            obj     <- expectObject(j);
            baseStr <- getStr("base", obj);
            base    <- parseBase(baseStr);
            v       <- getInt("value", obj)
        ) yield Amount.Pct(base, v)

    def decodeStatPlus(j: Json): Option[Amount] =
        forM (
            obj     <- expectObject(j);
            statStr <- getStr("stat", obj);
            stat    <- parseStat(statStr);
            v       <- getInt("value", obj)
        ) yield Amount.StatPlus(stat, v)

    /// amount オブジェクト（1キー）を解決する。{"flat":15} / {"pct":{...}} など。
    def decodeAmount(j: Json): Option[Amount] = match expectObject(j) {
        case None      => None
        case Some(obj) =>
            let r1 = getInt("flat", obj)  |> Option.map(v -> Amount.Flat(v));
            let r2 = or2(r1, getInt("mul", obj)   |> Option.map(v -> Amount.Mul(v)));
            let r3 = or2(r2, getInt("tiles", obj) |> Option.map(v -> Amount.Tiles(v)));
            let r4 = or2(r3, getInt("count", obj) |> Option.map(v -> Amount.Count(v)));
            let r5 = or2(r4, Map.get("pct", obj)      |> Option.flatMap(decodePct));
            or2(r5, Map.get("statPlus", obj) |> Option.flatMap(decodeStatPlus))
    }

    // ── 継続 for ────────────────────────────────────────────

    def decodeDuration(j: Json): Option[Duration] = match j {
        case JString(s) => parseDurationStr(s)
        case _          => match expectObject(j) {
            case Some(obj) => getInt("turns", obj) |> Option.map(n -> Duration.DurTurns(n))
            case None      => None
        }
    }

    def parseDurationStr(s: String): Option[Duration] = match s {
        case "instant"       => Some(Duration.DurInstant)
        case "permanent"     => Some(Duration.DurPermanent)
        case "whileEquipped" => Some(Duration.DurWhileEquipped)
        case "everyTurn"     => Some(Duration.DurEveryTurn)
        case "untilHit"      => Some(Duration.DurUntilHit)
        case _               => None
    }

    // ── 対象 to ─────────────────────────────────────────────

    def decodeRole(s: String, obj: Map[String, Json]): Option[Role] = match s {
        case "self"       => Some(Role.RoleSelf)
        case "attacker"   => Some(Role.RoleAttacker)
        case "target"     => Some(Role.RoleTarget)
        case "areaAround" => or2(getInt("r", obj) |> Option.map(r -> Role.RoleArea(r)),
                                 Some(Role.RoleArea(1)))
        case _            => None
    }

    def decodeTarget(j: Json): Option[EffectRule.Target] =
        forM (
            obj     <- expectObject(j);
            roleStr <- getStr("role", obj);
            role    <- decodeRole(roleStr, obj)
        ) yield {
            let faction = getStr("faction", obj) |> Option.flatMap(parseFaction)
                            |> Option.getWithDefault(Faction.FactionAny);
            let state = getStr("state", obj) |> Option.flatMap(parseState)
                            |> Option.getWithDefault(TargetState.StateAny);
            {role = role, faction = faction, state = state}
        }

    // ── 投射系 action ───────────────────────────────────────

    def decodeAction(j: Json): Option[EffectRule.Action] =
        forM (
            obj    <- expectObject(j);
            toJ    <- Map.get("to", obj);
            to     <- decodeTarget(toJ);
            opStr  <- getStr("op", obj);
            op     <- parseOp(opStr)
        ) yield {
            let amount = Map.get("amount", obj) |> Option.flatMap(decodeAmount);
            let dir    = getStr("dir", obj) |> Option.flatMap(parseDir);
            let dur    = Map.get("for", obj) |> Option.flatMap(decodeDuration);
            let vfx    = getStr("vfx", obj);
            let sfx    = getStr("sfx", obj);
            {to = to, op = op, amount = amount, dir = dir, duration = dur, vfx = vfx, sfx = sfx}
        }

    // ── 述語 if（allOf/anyOf 木）────────────────────────────

    def decodeAtomObj(obj: Map[String, Json]): Option[Atom] =
        or2(getInt("selfHpPctAtMost", obj)   |> Option.map(n -> Atom.SelfHpPctAtMost(n)),
            getInt("targetHpPctAtMost", obj) |> Option.map(n -> Atom.TargetHpPctAtMost(n)))

    /// 述語 1 つを decode。string=葉 / array=暗黙 allOf / object={allOf|anyOf|パラメータ付き葉}。
    def decodePred(j: Json): Option[Pred] = match j {
        case JString(s) => parseAtomNullary(s) |> Option.map(a -> Pred.PAtom(a))
        case JArray(_)  => decodeList(decodePred, j) |> Option.map(ps -> Pred.AllOf(ps))
        case _          => match expectObject(j) {
            case None      => None
            case Some(obj) =>
                match Map.get("allOf", obj) {
                    case Some(arr) => decodeList(decodePred, arr) |> Option.map(ps -> Pred.AllOf(ps))
                    case None      => match Map.get("anyOf", obj) {
                        case Some(arr) => decodeList(decodePred, arr) |> Option.map(ps -> Pred.AnyOf(ps))
                        case None      => decodeAtomObj(obj) |> Option.map(a -> Pred.PAtom(a))
                    }
                }
        }
    }

    // ── 制御フロー flow ─────────────────────────────────────

    def decodeFollowUp(j: Json): Option[Flow] =
        forM (
            obj <- expectObject(j);
            ts  <- getStr("trigger", obj);
            t   <- parseFollowKind(ts)
        ) yield Flow.FollowUp(t)

    def decodeReplace(j: Json): Option[Flow] =
        forM (
            obj  <- expectObject(j);
            c    <- getInt("chance", obj);
            doJ  <- Map.get("do", obj);
            acts <- decodeList(decodeAction, doJ)
        ) yield Flow.ReplaceAttack(c, acts)

    def decodeFlow(j: Json): Option[Flow] = match expectObject(j) {
        case None      => None
        case Some(obj) =>
            or2(Map.get("followUp", obj)      |> Option.flatMap(decodeFollowUp),
                Map.get("replaceAttack", obj) |> Option.flatMap(decodeReplace))
    }

    def decodeDeliverList(j: Json): Option[List[Deliver]] =
        decodeList(dj -> expectString(dj) |> Option.flatMap(parseDeliver), j)

    // ── ルール本体 ──────────────────────────────────────────

    /// 省略可フィールドの decode。キーが無ければ既定値、有れば decode 必須
    /// （有るのに decode 失敗 → None でルール全体を失敗させる）。
    /// これにより `op` の typo 等が「黙って空アクション」に化けず起動時に発覚する。
    def optField(key: String, obj: Map[String, Json], dec: Json -> Option[a], dflt: a): Option[a] =
        match Map.get(key, obj) {
            case None    => Some(dflt)
            case Some(j) => dec(j)
        }

    /// 効果 JSON 1 件を `EffectRule.EffectRule` へ decode する。
    /// when（必須）以外は省略可: deliver 既定 [self]、if 既定 always、chance 既定 100、
    /// do 既定 []、flow 既定なし。未知の enum 文字列や不正フィールドが混じれば None
    /// （省略は既定で許すが、書いてあるのに壊れている場合はルールごと失敗させる）。
    pub def decodeRule(j: Json): Option[EffectRule.EffectRule] =
        forM (
            obj     <- expectObject(j);
            whenStr <- getStr("when", obj);
            trigger <- parseTrigger(whenStr);
            deliver <- optField("deliver", obj, decodeDeliverList, Deliver.DeliverSelf :: Nil);
            cond    <- optField("if", obj, decodePred, Pred.AllOf(Nil));
            chance  <- optField("chance", obj, expectInt, 100);
            actions <- optField("do", obj, dj -> decodeList(decodeAction, dj), Nil);
            flow    <- optField("flow", obj, fj -> decodeFlow(fj) |> Option.map(f -> Some(f)), None)
        ) yield {
            {trigger = trigger, deliver = deliver, cond = cond,
             chance = chance, actions = actions, flow = flow}
        }
}
