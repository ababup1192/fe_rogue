// StaffSystem — 杖の発動を `(World, [SimEvent])` として解く純 sim（CombatSystem.resolveAttack の杖版）。
//
// CombatSystem.resolveAttack を縮約コピーした杖版。view/anim/scene は触らず、演出は SimEvent log から
// 後段（ViewReplay）が replay する。combat と違い **RngDraw を引かない**（杖は命中ロールを持たず、
// rayCast 結果＝`hit` を引数で受けるので完全決定論・no effect）。土台:
//   - World.baseStatsOf / hpOf / posOf / boardOf … 杖が読む World read-model（CombatSystem と同じ accessor 群）。
//   - World.applyEventToWorld … SimEvent を World へ畳む reducer（CombatSystem.applyAll と同型）。
//   - SimEvent（Healed/Damaged/Dying/Moved/Afflicted/ViewFx）… **既存の CLOSED 集合を再利用**し新変種は足さない。
//
// 今周のスコープ（effectRule 無しの 4 enum 杖のうち World 純粋に解ける分）:
//   - Heal     … 対象（味方/敵）の hp を「魔力 + 10」回復（クランプ）＝`Healed`。
//   - Blowback … 1 ダメージ → 敵撃破=Damaged(0)+Dying+ViewFx(Died) / 生存=Damaged+Moved(着地) / 味方撃破=Damaged のみ。
//   - Swap     … caster と対象の位置を交換＝`Moved`×2（順序保存）。
//   - Bind     … 対象を 5 ターン完全停止＝`Afflicted(immobilizeFor(5))`。
//   - Stopgap  … 完全停止 + 階段マスへワープ＝`Afflicted` :: `Moved`（`stairsPosOf` read-model を読む）。
// effectRule(DSL)杖・throw は StaffCast の DSL 経路が担う（敵詠唱の Bind/Stopgap は ecsResolveEnemyStaff 経由）。
mod StaffSystem {

    use World.EntityRef
    use World.SimEvent

    /// かなしばりの既定ターン数（scene 側 `StaffCast.defaultBindTurns`=5 を映す。sim 自己完結のため再掲）。
    /// scene-statuses 等価テストが両者の drift を、sim 側 cmdKey/remaining pin がこの値の退行を捕捉する。
    def bindTurns(): Int32 = 5

    /// SimEvent 列を World へ畳む（`CombatSystem.applyAll` の同型コピー＝`applyEventToWorld` の foldLeft）。
    def applyAll(events: List[SimEvent], world: World): World =
        List.foldLeft((w, e) -> World.applyEventToWorld(e, w), world, events)

    /// 杖 1 発を **sim 解決**し (World', [SimEvent]) を返す。`hit` は rayCast の結果（命中対象か壁/盤外）。
    /// World から read-model を読み、SimEvent を産んで applyEventToWorld で畳む。scene も view も触らない。
    /// 壁/盤外（空振り）は events=Nil ＝ World 不変（呼び出し側がフィードバックログを出す）。
    pub def resolveStaffCast(world: World, caster: EntityRef,
                              effect: Staff.StaffEffect,
                              dir: {x = Int32, y = Int32}, hit: RayHit):
            (World, List[SimEvent]) =
        let events = staffEvents(world, caster, effect, dir, hit);
        (applyAll(events, world), events)

    /// hit から (対象 ref, 対象セル, 味方か) を 1 段 match で導出し、effect ごとの小ヘルパーへ委譲する
    /// （ネストを浅く保つ）。壁/盤外は空＝空振り。
    def staffEvents(world: World, caster: EntityRef, effect: Staff.StaffEffect,
                     dir: {x = Int32, y = Int32}, hit: RayHit): List[SimEvent] =
        match hit {
            case RayHit.HitPlayer(id, cell) =>
                effectEvents(world, caster, effect, dir, EntityRef.Player(id), cell, true)
            case RayHit.HitEnemy(id, cell) =>
                effectEvents(world, caster, effect, dir, EntityRef.Enemy(id), cell, false)
            case _ => Nil
        }

    /// effect 別 dispatch（1 段 match・組み立ては各小ヘルパーへ委譲）。全 5 effect を World read-model だけで解く
    /// （Stopgap は `stairsPosOf` を読む）。
    def effectEvents(world: World, caster: EntityRef, effect: Staff.StaffEffect,
                      dir: {x = Int32, y = Int32}, target: EntityRef,
                      cell: {x = Int32, y = Int32}, isAlly: Bool): List[SimEvent] =
        match effect {
            case Staff.StaffEffect.Heal     => healEvents(world, caster, target)
            case Staff.StaffEffect.Blowback => blowbackEvents(world, target, cell, dir, isAlly)
            case Staff.StaffEffect.Swap     => swapEvents(world, caster, target, cell)
            case Staff.StaffEffect.Bind     => bindEvents(target)
            case Staff.StaffEffect.Stopgap  => stopgapEvents(world, target)
        }

    /// Heal: 対象の hp を「caster の魔力 + 10」回復（maxHp クランプ）。`Healed`（→Cmd.SetHp）。
    /// 回復量源泉は `baseStatsOf(caster)#magicAttack`（resource verbatim＝legacy `player#resource#magicAttack` と一致）。
    /// caster/target が World 未登録なら空（legacy の防御 `case None => scene` と同義）。
    def healEvents(world: World, caster: EntityRef, target: EntityRef): List[SimEvent] =
        let ev = forM (
            mag   <- World.baseStatsOf(caster, world) |> Option.map(b -> b#magicAttack);
            hp    <- World.hpOf(target, world);
            maxHp <- World.baseStatsOf(target, world) |> Option.map(b -> b#maxHp)
        ) yield {
            let newHp = Combat.heal(hp, maxHp, mag + 10)#newHp;
            SimEvent.Healed(target, {newHp = newHp, amt = newHp - hp})
        };
        Option.toList(ev)

    /// Blowback: 1 ダメージ → 敵撃破 / 味方撃破 / 生存 を内部で fold（本体のネストを浅く保つ）。
    ///   - 敵撃破: hard-0 clamp の `Damaged(newHp=0)`（リテラル）+ `Dying` + `ViewFx(Died)`（legacy startDeathAnimation 相当）。
    ///   - 味方撃破: `Damaged(raw newHp)` のみ（Dying/Died なし＝player 死 deferred・combat 敵攻撃 path と同流儀）。
    ///   - 生存: `Damaged(raw newHp)` ::（`knockbackPath` の着地があれば）`Moved(着地)`。押す先なしなら Damaged のみ。
    /// 対象が World 未登録なら空。hitCell は legacy hitCell を byte-for-byte スレッドする。
    def blowbackEvents(world: World, target: EntityRef, cell: {x = Int32, y = Int32},
                        dir: {x = Int32, y = Int32}, isAlly: Bool): List[SimEvent] =
        match World.hpOf(target, world) {
            case None     => Nil
            case Some(hp) =>
                let dmgRes = Combat.damage(hp = hp, amount = 1);
                if (dmgRes#isDead and not isAlly)
                    SimEvent.Damaged(target, {newHp = 0, dmg = 1})
                        :: SimEvent.Dying(target)
                        :: SimEvent.ViewFx(World.ViewFxKind.Died(target)) :: Nil
                else if (dmgRes#isDead)
                    SimEvent.Damaged(target, {newHp = dmgRes#newHp, dmg = 1}) :: Nil
                else {
                    let landing = World.boardOf(world)
                        |> Option.flatMap(board -> List.last(Board.knockbackPath(cell, dir, board)));
                    let moved = landing
                        |> Option.map(c -> SimEvent.Moved(target, c))
                        |> Option.toList;
                    SimEvent.Damaged(target, {newHp = dmgRes#newHp, dmg = 1}) :: moved
                }
        }

    /// Swap: caster セル=`posOf(caster)`（legacy player#gridPos 相当）と対象セル=`cell` を交換。
    /// `Moved(caster, 対象セル)` :: `Moved(target, caster セル)`（snapTo×2 と順序一致）。caster 未登録なら空。
    def swapEvents(world: World, caster: EntityRef, target: EntityRef,
                    cell: {x = Int32, y = Int32}): List[SimEvent] =
        match World.posOf(caster, world) {
            case None             => Nil
            case Some(casterCell) =>
                SimEvent.Moved(caster, cell) :: SimEvent.Moved(target, casterCell) :: Nil
        }

    /// Bind: 対象を `bindTurns()`(=5) ターン完全停止＝`Afflicted(immobilizeFor(5))`（→Cmd.Add）。
    /// statuses は scene 権威ゆえ、呼び出し側が `applyEcsStaffSceneEffects` で scene #statuses へも add する。
    def bindEvents(target: EntityRef): List[SimEvent] =
        SimEvent.Afflicted(target, StatusSystem.immobilizeFor(bindTurns())) :: Nil

    /// Stopgap: 完全停止 + 階段マスへワープ（legacy `applyStopgapToPlayer` = bind → warp を映す）。
    ///   - bind: `Afflicted(immobilizeFor(5))`（Bind と同じ・順序も bind が先）。
    ///   - warp: `warpCellFor(stairsPosOf, boardOf)` が Some なら `Moved(target, warpCell)`。階段が埋まっていれば
    ///           隣接空きマス、どちらも無ければ warp なし（bind だけ・legacy「ワープ先がなかった」相当）。
    /// warp 先計算に要る階段位置は World read-model `stairsPosOf`、地形は `boardOf`。両方揃わなければ warp 略。
    def stopgapEvents(world: World, target: EntityRef): List[SimEvent] =
        let bind = SimEvent.Afflicted(target, StatusSystem.immobilizeFor(bindTurns()));
        let warp = World.boardOf(world)
            |> Option.flatMap(board -> StaffRules.warpCellFor(World.stairsPosOf(world), board))
            |> Option.map(cell -> SimEvent.Moved(target, cell))
            |> Option.toList;
        bind :: warp

}
