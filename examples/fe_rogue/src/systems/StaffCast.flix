/// StaffCast — 杖の発動と消費アイテムの使用（効果の適用層）
///
/// `PlayerScene` から「杖を撃つ / 消費アイテムを使う」という、盤面・敵・アニメ・ターン進行に
/// またがる適用ロジックを切り出した層（`src/systems/` の配置分界は
/// CombatDriver.flix 冒頭を参照）。`PlayerScene` 本体は味方の状態所有と
/// 移動・選択・戦闘に専念し、ここは「選択中の杖/アイテムを実際に効かせる」段だけを担う。
/// 駒の状態は World が権威を持つ。読みは `World.WorldQuery`、書きは `World.Command.emit` を通す。
///
/// 杖の発動の流れ（`applyStaffCast`）:
///   1. プレイヤーの `staves[staffIdx]` と `gridPos` / `magicAttack` を取り出す
///   2. `Board.rayCast` で射線上の最初の当たり対象を `RayHit` で得る
///   3. `staff#effect × hit` で効果を分岐適用（Heal / Blowback / Swap）
///   4. `Staff.consume` で耐久 -1、0 なら staves から除去 + 破損ログ
///   5. 選択中アイテムをクリア → `commitWaitedAndAdvance` で waited 確定し次ターンへ
/// 杖は CounterAttackRules を経由しない（反撃なし）。
///
/// `PlayerScene` と `EnemyScene` は `Data` / `get` / `snapTo` を**両方が**持つため、
/// このモジュールでは味方側を必ず `PlayerScene.`、敵側を `EnemyScene.` で完全修飾する。
/// 方向選択の純粋計算（`deltaToDirection` / `pickHealDirection`）は `Staff` モジュールに置く。
mod StaffCast {

    // ────────────────────────────────────────────────────────
    // 杖の発動 — direction → 直線レイキャスト → 効果適用 → ターン進行
    // ────────────────────────────────────────────────────────

    /// 杖を発動する。`StaffAim` フェーズで方向キーが押された瞬間に呼ばれる。
    /// 該当プレイヤー / 杖が見つからない場合は防御的に no-op。
    pub def applyStaffCast(playerId: Int32, staffIdx: Int32,
                             direction: Dir4.Dir4):
            Unit
            \ {RangeOverlayState.State,
                BoardQuery, GameLogger.GameLogger,
                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State, CursorState.State,
                GameEngine.Audio, World.Command, World.WorldQuery} =
        // プレイヤーと杖の両方が解決できたときだけ発動。どちらか欠ければ no-op。
        // 在庫（staves）は World 権威＝dataFromWorld で読む。
        let cast = forM (
            player <- World.dataFromWorld(playerId, World.WorldQuery.get());
            staff  <- List.nth(staffIdx, player#staves)
        ) yield fireStaff(playerId, staffIdx, player, staff, direction);
        Option.getWithDefault((), cast)

    /// プレイヤーと杖が解決できたときの本体: レイキャスト → 命中音 → 効果適用 →
    /// 耐久消費 → 選択クリア → ターン進行。
    def fireStaff(playerId: Int32, staffIdx: Int32, player: PlayerScene.Data,
                   staff: Staff.StaffResource, direction: Dir4.Dir4):
            Unit
            \ {RangeOverlayState.State,
                BoardQuery, GameLogger.GameLogger,
                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State, CursorState.State,
                GameEngine.Audio, World.Command, World.WorldQuery} =
        let board = BoardQuery.board();
        let dir   = Staff.toVec2i(direction);
        // 杖は射程を持たない: 盤面外は壁扱いなので、十分大きい上限を渡せば
        // 必ず壁または駒で止まる（無限射程と等価）。
        let hit   = Board.rayCast(player#gridPos, dir, staffMaxRange(), board);
        playHitSound(staff#effect, hit);
        applyStaffEffect(playerId, player, staff, dir, hit);
        consumeStaff(playerId, staffIdx, staff);
        PlayerScene.clearSelectedItem(playerId);
        TurnFlow.commitWaitedAndAdvance();
        ()

    /// 回復の杖が味方/敵に当たった瞬間だけ回復音を鳴らす（空振りは鳴らさない）。
    /// Blowback / Swap は命中と移動が視覚的に自明なため効果音を持たない（現状 SE 未設定）。
    def playHitSound(effect: Staff.StaffEffect, hit: RayHit): Unit \
            {GameEngine.Audio, World.Command, World.WorldQuery} =
        match (effect, hit) {
            case (Staff.StaffEffect.Heal, RayHit.HitPlayer(_, _)) => ViewReplay.sound("cure")
            case (Staff.StaffEffect.Heal, RayHit.HitEnemy(_, _))  => ViewReplay.sound("cure")
            case _                                                 => ()
        }

    /// 杖の射程上限。盤面の最大寸法より大きければ実質「無限」として機能する。
    def staffMaxRange(): Int32 = 1000

    /// 杖を構えるときの初期照準方向。選択中アイテムが回復の杖で、HP が減っている味方が
    /// 居れば、一番ふさわしい味方の方向(4方位)を返す。同じ行/列に並ぶ(=射線が届く)味方を
    /// 優先し、無ければ最も近い負傷味方の主軸方向を返す。
    /// 回復杖でない / 負傷味方が居ないなら None（呼び出し側はデフォルト Up のまま）。
    /// ネストした match を避けるため Option の forM で短絡的に畳む。
    pub def staffAimInitialDirection(playerId: Int32):
            Option[Dir4.Dir4] \ World.WorldQuery =
        // selectedItem / staves は World 権威＝dataFromWorld で読む。
        let w = World.WorldQuery.get();
        forM (
            player <- World.dataFromWorld(playerId, w);
            idx    <- selectedStaffIndex(player);
            staff  <- List.nth(idx, player#staves);
            dir    <- healDirectionFor(player, playerId, staff)
        ) yield dir

    /// 選択中アイテムが杖ならその staves index、それ以外は None。
    def selectedStaffIndex(player: PlayerScene.Data): Option[Int32] =
        match player#selectedItem {
            case Some(PlayerData.ItemKind.Staff(idx)) => Some(idx)
            case _                                      => None
        }

    /// 回復杖なら負傷味方への方向、それ以外（攻撃杖等）は None。
    /// 負傷味方の位置だけを `Staff.pickHealDirection` に渡す（純粋計算へ委譲）。
    def healDirectionFor(player: PlayerScene.Data, playerId: Int32,
                          staff: Staff.StaffResource): Option[Dir4.Dir4] \ World.WorldQuery =
        if (staff#effect == Staff.StaffEffect.Heal)
            Staff.pickHealDirection(player#gridPos,
                injuredAlliesExcept(playerId) |> List.map(a -> a#gridPos))
        else None

    /// 自分以外で HP が最大未満（負傷している）の味方一覧。
    /// 自己を除外するのは、自己回復はメニューの「つかう → きずぐすり」で行う別フローだから。
    /// HP < maxHp を「負傷」と定義しており、最大 HP ちょうどの味方は照準候補に含めない。
    def injuredAlliesExcept(playerId: Int32):
            List[PlayerScene.Data] \ World.WorldQuery =
        // 位置（照準方向計算に使う）は World 権威の Data で。hp は World.hpOf で判定する
        // （overlay 化済みの読み手が大半だがここは負傷判定のみ）。
        let w = World.WorldQuery.get();
        PlayerScene.getAll()
            |> List.filter(a -> a#id != playerId
                and (World.hpOf(World.EntityRef.Player(a#id), w) |> Option.getWithDefault(a#hp)) < a#resource#hp)

    /// 杖の効果適用。IDE 合成エディタの effectRule（onUse）があれば **DSL 経路**（runPlan）で
    /// 効かせ、無ければ従来の `staff#effect × hit` legacy 分岐へ落とす。
    /// DSL 経路は当たったユニット（味方/敵）へ rayFirst で効かせる（消費アイテムの投げ経路と同形）。
    def applyStaffEffect(playerId: Int32, player: PlayerScene.Data,
                          staff: Staff.StaffResource,
                          dir: {x = Int32, y = Int32},
                          hit: RayHit):
            Unit \ {GameLogger.GameLogger, World.Command, BoardQuery,
                              GameEngine.Audio, World.WorldQuery} =
        match dslStaffRule(staff) {
            case Some(rule) => applyStaffEffectDsl(playerId, staff, rule, hit, dir)
            // effectRule 無しの enum 杖は sim 経路（壁空振り〔events=Nil〕のときだけ
            // ecsResolveStaffCast 内でフィードバックログを出す）。
            case None       => ecsResolveStaffCast(playerId, player, staff, dir, hit)
        }

    /// 杖の解決経路: `StaffSystem.resolveStaffCast` で 1 発の sim を解いて [SimEvent] を得、
    /// `eventToCmds` で World へ反映し、`ViewReplay.replay` で演出を再生する。`applyEcsStaffSceneEffects` で
    /// statuses も World へ反映する。events が `Nil`（壁=空振り）なら emit/replay はせず
    /// 『届かなかった/消えた』フィードバックログだけ出す（whiff 退行防止）。
    /// 演出進行（耐久消費/選択クリア/turn 進行）は `fireStaff` 後段が担う。
    /// この seam そのものを traced harness で踏むため pub（`TestStaffGolden`:
    /// whiff の log／hit 時 emit ループが eventToCmds と一致 を固定）。
    pub def ecsResolveStaffCast(playerId: Int32, _player: PlayerScene.Data,
                             staff: Staff.StaffResource,
                             dir: {x = Int32, y = Int32}, hit: RayHit):
            Unit \ {GameLogger.GameLogger, World.Command,
                              GameEngine.Audio, World.WorldQuery} =
        let world = World.WorldQuery.get();
        let (_, events) = StaffSystem.resolveStaffCast(world,
            World.EntityRef.Player(playerId), staff#effect, dir, hit);
        if (List.isEmpty(events)) {
            // 空振り（壁/盤外）: フィードバックログのみで emit/replay はしない
            //（Swap だけ文言が違う=『消えた』、他 4 effect は『届かなかった』）。
            let msg = match staff#effect {
                case Staff.StaffEffect.Swap => "${PlayerScene.displayName(playerId)} の ${staff#name} は消えた"
                case _                      => "${PlayerScene.displayName(playerId)} の ${staff#name} は届かなかった"
            };
            GameLogger.playerLog(msg)
        } else {
            List.forEach(c -> World.Command.emit(c), events |> List.flatMap(World.eventToCmds));
            ViewReplay.replay(events);
            applyEcsStaffSceneEffects(events)
        }

    /// ECS 経路の event 後処理（`CombatDriver.applyEcsSceneEffects` を縮約）。statuses は World 権威:
    /// Afflicted/Released は直前の eventToCmds（Cmd.Add / ClearImmobilized）で
    /// World へ適用済みで、ここでは適用後の全リストを `Cmd.Seed`（全置換）で確定 emit する
    /// （golden が凍結する Cmd-stream 契約の一部）。hp(Healed/Damaged)・pos(Moved)・dying(Dying) は
    /// eventToCmds→World で反映済み。今周は Bind のみ Afflicted を発火。
    /// Bind の statuses 等価オラクル（`TestStaffGolden`）が World statuses と突き合わせるため pub。
    pub def applyEcsStaffSceneEffects(events: List[World.SimEvent]): Unit \ {World.Command, World.WorldQuery} =
        List.forEach(ev -> match ev {
            case World.SimEvent.Afflicted(World.EntityRef.Player(id), _) =>
                PlayerScene.updateStatuses(id, xs -> xs)
            case World.SimEvent.Afflicted(World.EntityRef.Enemy(id), _) =>
                EnemyScene.updateStatuses(id, xs -> xs)
            case World.SimEvent.Released(World.EntityRef.Player(id)) =>
                PlayerScene.updateStatuses(id, xs -> xs)
            case World.SimEvent.Released(World.EntityRef.Enemy(id)) =>
                EnemyScene.updateStatuses(id, xs -> xs)
            case _ => ()
        }, events)

    /// effectRule があり trigger が onUse なら EffectRule を返す（消費の `dslUseRule` と同形）。
    def dslStaffRule(staff: Staff.StaffResource): Option[EffectRule.EffectRule] =
        match staff#effectRule {
            case Some(j) => match EffectBridge.fromComposer(j) {
                case Some(rule) => if (rule#trigger == EffectRule.Trigger.OnUse) Some(rule) else None
                case None       => None
            }
            case None => None
        }

    /// 当たり対象を (id, ally) で返す。壁/盤外（空振り）は None。
    def staffHitTarget(hit: RayHit): Option[(Int32, Bool)] = match hit {
        case RayHit.HitPlayer(id, _) => Some((id, true))
        case RayHit.HitEnemy(id, _)  => Some((id, false))
        case _                       => None
    }

    /// DSL 経路: 当たったユニットへ effectRule を runPlan で効かせる。
    /// 空振り（壁/盤外）は legacy と同じ「届かなかった」ログを出す。
    /// `dir` は cast 方向（knockback の押し出し方向に使う。CustomAt が dir を運ばないためここで渡す）。
    /// `TestStaffCast` から effectRule 駆動を検証するため pub。
    pub def applyStaffEffectDsl(playerId: Int32, staff: Staff.StaffResource,
                             rule: EffectRule.EffectRule, hit: RayHit,
                             dir: {x = Int32, y = Int32}):
            Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery, BoardQuery} =
        match staffHitTarget(hit) {
            case Some((id, ally)) =>
                let ctx = {selfId = playerId, attackerId = playerId, actorIsPlayer = true,
                           rayUnits = ({id = id, ally = ally, immobilized = false, alive = true}: EffectRule.RayUnit) :: Nil,
                           amount = {max = 0, dealt = 0, incoming = 0, magic = 0}};
                let plan = EffectPlan.planActions(rule, ctx);
                World.emitStatusAdds(plan);  // 境界で World へ status を発行
                EffectRunner.runPlan(staffEffectHandlers(playerId, dir), plan, ());
                World.emitHpSets(plan)  // hp も境界で World へ emit（maxHpUp はここで baseStats/resource も dual-write）
            case None =>
                GameLogger.playerLog("${PlayerScene.displayName(playerId)} の ${staff#name} は届かなかった")
        }

    /// DSL 杖ハンドラ。当たったユニット(ally)へ op を適用する。
    /// immobilize は legacy applyBindToPlayer/Enemy、custom（knockback/swapPos/warpToStairs）は
    /// legacy applyBlowback*/applySwap*/applyStopgap* をそのまま呼ぶのでログ・挙動が一致する。
    /// heal/status は投げ経路と共用の healUnit/statusUnit を再利用。maxHpUp は境界の
    /// `World.emitHpSets` が処理するのでここでは no-op。
    /// 状態は畳まない（Unit）ので各 handler は id/ally を受けて直接 World へ作用する。
    /// effect 行は legacy 委譲先（Tween / GameLogger）に合わせ広く取る。
    def staffEffectHandlers(srcId: Int32, dir: {x = Int32, y = Int32}):
            EffectRunner.PlanHandlers[Unit,
                {GameLogger.GameLogger, World.Command, World.WorldQuery, BoardQuery}] = {
        heal       = (_u, id, ally, n)        -> checked_ecast(healUnit(id, ally, n)),
        fullHeal   = (_u, id, ally)           -> checked_ecast(fullHealUnit(id, ally)),
        maxHpUp    = (u, _, _, _)            -> checked_ecast(u),
        status     = (_u, id, ally, se, m, t) -> checked_ecast(statusUnit(id, ally, se, m, t)),
        immobilize = (_u, id, ally, turns)    -> checked_ecast(immobilizeUnit(srcId, id, ally, turns)),
        custom     = (_u, op, id, ally)       -> customStaffEffect(srcId, dir, op, id, ally),
        damage     = (u, _, _, _)            -> checked_ecast(u),
        revive     = (u, _, _)               -> checked_ecast(u),
        sfx        = (u, _)                  -> checked_ecast(u),
        noOp       = (u, _)                  -> checked_ecast(u)
    }

    /// 完全停止を当たったユニットへ `turns` ターン付与。legacy applyBindToPlayer/Enemy をそのまま呼ぶ
    /// （ログ込みで同一）。turns は effectRule の for:turns から来る（被弾解除は Immobilized 型に内在）。
    def immobilizeUnit(srcId: Int32, id: Int32, ally: Bool, turns: Int32):
            Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery} =
        let srcLabel = PlayerScene.displayName(srcId);
        if (ally) applyBindToPlayer(srcLabel, id, turns)
        else      applyBindToEnemy(srcLabel, id, turns)

    /// 対象の現在グリッド座標を ally で出し分けて取る（custom op の位置導出用。攻撃直後は hitCell と一致）。
    def gridOf(id: Int32, ally: Bool): Option[{x = Int32, y = Int32}] \ World.WorldQuery =
        // 現在位置は World.posOf（gridPos は World 権威）。
        let ref = if (ally) World.EntityRef.Player(id) else World.EntityRef.Enemy(id);
        World.posOf(ref, World.WorldQuery.get())

    /// custom op（盤面副作用系）を当たったユニットへ。位置は id 逆引き、方向は cast の dir。
    /// knockback/swapPos/warpToStairs を legacy 関数へ委譲（挙動・ログ一致）。未知 op / 対象不在は防御 no-op。
    def customStaffEffect(srcId: Int32, dir: {x = Int32, y = Int32},
                           op: String, id: Int32, ally: Bool):
            Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery, BoardQuery} =
        let srcLabel = PlayerScene.displayName(srcId);
        match op {
            case "knockback" =>
                match gridOf(id, ally) {
                    case Some(cell) =>
                        if (ally) applyBlowbackToPlayer(srcId, id, cell, dir)
                        else      applyBlowbackToEnemy(srcId, id, cell, dir)
                    case None => ()
                }
            case "swapPos" =>
                match (gridOf(srcId, true), gridOf(id, ally)) {
                    case (Some(srcCell), Some(otherCell)) =>
                        if (ally) applySwapWithPlayer({id = srcId, cell = srcCell}, {id = id, cell = otherCell})
                        else      applySwapWithEnemy({id = srcId, cell = srcCell}, {id = id, cell = otherCell})
                    case _ => ()
                }
            case "warpToStairs" =>
                if (ally) applyStopgapToPlayer(srcLabel, id)
                else      applyStopgapToEnemy(srcLabel, id)
            case _ =>
                GameLogger.playerLog("${srcLabel} の杖は 何も起きなかった")
        }

    /// ふきとばし × 味方: 1 ダメ → 死亡なら止まる、生存なら最終位置までスナップで移動。
    /// 将来: sequence engine が揃えば 1 マスずつ tween に置換できる（現在は瞬間移動）。
    def applyBlowbackToPlayer(srcId: Int32, targetId: Int32,
                                hitCell: {x = Int32, y = Int32},
                                dir: {x = Int32, y = Int32}):
            Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery, BoardQuery} =
        match PlayerScene.get(targetId) {
            case None         => ()
            case Some(target) =>
                let curHp = World.hpOf(World.EntityRef.Player(targetId), World.WorldQuery.get())
                                |> Option.getWithDefault(target#hp);
                let dmgResult = Combat.damage(hp = curHp, amount = 1);
                PlayerScene.setHp(targetId, dmgResult#newHp);
                GameLogger.playerLog(
                    "${PlayerScene.displayName(srcId)} ▶ ${PlayerScene.displayName(targetId)} を ふきとばし (1ダメージ)");
                if (dmgResult#isDead) ()
                else applyBlowbackMove({hit = hitCell, dir = dir}, cell -> PlayerScene.snapTo(targetId, cell))
        }

    /// ふきとばし × 敵: 1 ダメ → 死亡なら startDeathAnimation、生存なら最終位置に snapTo。
    def applyBlowbackToEnemy(srcId: Int32, enemyId: Int32,
                               hitCell: {x = Int32, y = Int32},
                               dir: {x = Int32, y = Int32}):
            Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery, BoardQuery} =
        match EnemyScene.get(enemyId) {
            case None        => ()
            case Some(enemy) =>
                let curHp = World.hpOf(World.EntityRef.Enemy(enemyId), World.WorldQuery.get())
                                |> Option.getWithDefault(enemy#hp);
                let dmgResult = Combat.damage(hp = curHp, amount = 1);
                if (dmgResult#isDead) {
                    GameLogger.playerLog("${PlayerScene.displayName(srcId)} ▶ ${EnemyScene.displayName(enemyId)} を ふきとばし撃破");
                    EnemyScene.startDeathAnimation(enemyId)
                } else {
                    EnemyScene.setHp(enemyId, dmgResult#newHp);
                    GameLogger.playerLog(
                        "${PlayerScene.displayName(srcId)} ▶ ${EnemyScene.displayName(enemyId)} を ふきとばし (1ダメージ)");
                    applyBlowbackMove({hit = hitCell, dir = dir}, cell -> EnemyScene.snapTo(enemyId, cell))
                }
        }

    /// 押される対象の最終位置を `Board.knockbackPath` で計算し、`moveFn` で動かす。
    /// 経路が空（押される先がない）なら何もしない。
    def applyBlowbackMove(geom: {hit = {x = Int32, y = Int32}, dir = {x = Int32, y = Int32}},
                           moveFn: {x = Int32, y = Int32} -> Unit \ World.Command):
            Unit \ {World.Command, BoardQuery} =
        // player cast の blowback 経路。board 読みは World 由来。
        let board: Board = BoardQuery.board();
        let path = Board.knockbackPath(geom#hit, geom#dir, board);
        match List.last(path) {
            case None       => ()
            case Some(last) => moveFn(last)
        }

    /// いれかえ × 味方: 自分と相手の gridPos を瞬間 swap する。
    /// 将来: sequence engine が揃えば交差するアニメーションに置換できる（現在は瞬間移動）。
    /// いれかえ対象の (id, 盤面セル)。id と cell の組を 2 つ取る関数で誤順しやすいので束ねる。
    type alias UnitCell = {id = Int32, cell = {x = Int32, y = Int32}}

    def applySwapWithPlayer(src: UnitCell, other: UnitCell):
            Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery} =
        GameLogger.playerLog("${PlayerScene.displayName(src#id)} と ${PlayerScene.displayName(other#id)} がいれかわった");
        PlayerScene.snapTo(src#id, other#cell);
        PlayerScene.snapTo(other#id, src#cell)

    /// いれかえ × 敵: 自分（Player）と敵を交換する。
    /// 将来: sequence engine が揃えば交差するアニメーションに置換できる（現在は瞬間移動）。
    def applySwapWithEnemy(src: UnitCell, enemy: UnitCell):
            Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery} =
        GameLogger.playerLog("${PlayerScene.displayName(src#id)} と ${EnemyScene.displayName(enemy#id)} がいれかわった");
        PlayerScene.snapTo(src#id, enemy#cell);
        EnemyScene.snapTo(enemy#id, src#cell)

    // ── かなしばり / 一時しのぎ（完全停止 / 停止 + ワープ）──────────────

    // 完全停止 Status 付与 bindStatuses は純 leaf として StaffRules.flix へ移動（A6）。

    /// 完全停止の既定ターン数（legacy / stopgap 経路が使う。DSL からは effectRule の turn 数が入る）。
    def defaultBindTurns(): Int32 = 5

    /// 敵→味方 Bind の hit ログ。legacy `applyBindToPlayer` と ECS 経路 `ecsResolveEnemyStaff` で
    /// 文字列を一元化し hit-log parity を保全する（`applyEcsStaffSceneEffects` は状態のみ・log 非配線）。
    def bindPlayerLog(srcLabel: String, targetId: Int32): Unit \ {GameLogger.GameLogger, World.WorldQuery} =
        GameLogger.playerLog("${srcLabel} は ${PlayerScene.displayName(targetId)} を かなしばりにした")

    /// かなしばり × 味方: 対象を `turns` ターン完全停止にする。`srcLabel` は撃った側の表示名（敵詠唱でも使う）。
    def applyBindToPlayer(srcLabel: String, targetId: Int32, turns: Int32):
            Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery} =
        bindPlayerLog(srcLabel, targetId);
        // statuses は World 権威＝現在値に bind を適用して Seed（全置換）で書く。
        PlayerScene.updateStatuses(targetId, xs -> StaffRules.bindStatuses(turns, xs))

    /// かなしばり × 敵: 対象を `turns` ターン完全停止にする。
    def applyBindToEnemy(srcLabel: String, enemyId: Int32, turns: Int32):
            Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery} =
        GameLogger.playerLog("${srcLabel} は ${EnemyScene.displayName(enemyId)} を かなしばりにした");
        EnemyScene.updateStatuses(enemyId, xs -> StaffRules.bindStatuses(turns, xs))

    /// 一時しのぎ × 味方: 完全停止にしたうえで階段（埋まっていれば隣接の空き）へワープさせる。
    def applyStopgapToPlayer(srcLabel: String, targetId: Int32):
            Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery, BoardQuery} =
        applyBindToPlayer(srcLabel, targetId, defaultBindTurns());
        warpPlayer(targetId)

    /// 一時しのぎ × 敵: 同上（敵対象）。
    def applyStopgapToEnemy(srcLabel: String, enemyId: Int32):
            Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery, BoardQuery} =
        applyBindToEnemy(srcLabel, enemyId, defaultBindTurns());
        warpEnemy(enemyId)

    /// 味方をワープ先（階段 or 隣接空き）へ瞬間移動させる。行き先が無ければ停止のみ。
    def warpPlayer(targetId: Int32):
            Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery, BoardQuery} =
        // warp（player/enemy cast 共有）の board 読みは World 由来。階段位置も World 権威。
        let board = BoardQuery.board();
        match StaffRules.warpCellFor(World.stairsPosOf(World.WorldQuery.get()), board) {
            case Some(cell) =>
                GameLogger.playerLog("${PlayerScene.displayName(targetId)} は 階段の方へ とばされた");
                PlayerScene.snapTo(targetId, cell)
            case None       =>
                GameLogger.playerLog("ワープ先がなかった")
        }

    /// 敵をワープ先（階段 or 隣接空き）へ瞬間移動させる。行き先が無ければ停止のみ。
    def warpEnemy(enemyId: Int32):
            Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery, BoardQuery} =
        // player cast が敵に当てた warp 経路。board 読みは World 由来。階段位置も World 権威。
        let board = BoardQuery.board();
        match StaffRules.warpCellFor(World.stairsPosOf(World.WorldQuery.get()), board) {
            case Some(cell) =>
                GameLogger.playerLog("${EnemyScene.displayName(enemyId)} は 階段の方へ とばされた");
                EnemyScene.snapTo(enemyId, cell)
            case None       =>
                GameLogger.playerLog("ワープ先がなかった")
        }

    // ワープ先セル選定 warpCellFor / adjacentFreeCell は純 leaf として StaffRules.flix へ移動（A6）。

    /// 杖の耐久を 1 減らし、0 なら staves から除去 + 破損ログ。
    def consumeStaff(playerId: Int32, staffIdx: Int32, staff: Staff.StaffResource):
            Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery} =
        let consumed = Staff.consume(staff);
        // 在庫は World 権威＝現在値を読んで耐久消費後の並びを Cmd で書く。
        let newStaves = replaceOrDropAt(staffIdx, consumed, PlayerScene.stavesW(playerId));
        if (Option.isEmpty(consumed))
            GameLogger.playerLog("${PlayerScene.displayName(playerId)} の ${staff#name} がこわれた")
        else ();
        PlayerScene.putStaves(playerId, newStaves)

    // ────────────────────────────────────────────────────────
    // 消費アイテム（きずぐすり等）の使用
    // ────────────────────────────────────────────────────────

    /// 消費アイテム（きずぐすり等）を「つかう」: 使用者自身を回復し、耐久を 1 減らして
    /// 0 なら一覧から除去、選択クリア → ターン消費して次へ進む。杖と違い方向・対象選択は無いので
    /// `StaffAim` のような中間フェーズは経由せず、メニュー確定経路でそのまま完結する。
    /// 該当プレイヤー / アイテムが見つからない場合は防御的に no-op。
    pub def applyConsumableUse(playerId: Int32, idx: Int32):
            Unit
            \ {RangeOverlayState.State, GameLogger.GameLogger,
                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State, CursorState.State, GameEngine.Audio,
                World.Command, World.WorldQuery} =
        // プレイヤーと消費アイテムの両方が解決できたときだけ使用。欠ければ no-op。
        // forM による短絡は applyStaffCast と同様。
        // 在庫（consumables）は World 権威＝dataFromWorld で読む。
        let used = forM (
            player <- World.dataFromWorld(playerId, World.WorldQuery.get());
            item   <- List.nth(idx, player#consumables)
        ) yield useConsumable(playerId, idx, player, item);
        Option.getWithDefault((), used)

    /// プレイヤーと消費アイテムが解決できたときの本体: 使用音 → 回復 → 耐久消費 →
    /// 選択クリア → ターン進行。
    def useConsumable(playerId: Int32, idx: Int32, player: PlayerScene.Data,
                       item: Consumable.ConsumableResource):
            Unit
            \ {RangeOverlayState.State, GameLogger.GameLogger,
                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State, CursorState.State, GameEngine.Audio,
                World.Command, World.WorldQuery} =
        // 消費アイテムは使う時点で効果が自己確定するため、杖の空振り判定とは異なり無条件で使用音を鳴らす
        ViewReplay.sound("cure");
        applyConsumableSelfEffect(playerId, player, item);
        consumeConsumable(playerId, idx, item);
        PlayerScene.clearSelectedItem(playerId);
        TurnFlow.commitWaitedAndAdvance();
        ()

    /// 自己使用（SelfUse）の効果を **DSL 経路** で適用する。
    /// item を `EffectBridge.consumableRule` で効果ルールへ写し、`EffectPlan.planActions` で
    /// 「誰に・何を・いくつ」を確定し、`EffectRunner.runPlan` が既存 primitive
    /// （applyConsumableHeal / applyFullHeal / applySelfStatus）へ振り分ける。maxHpUp は境界の
    /// `World.emitHpSets` が処理する。HP/状態変更・ログは primitive をそのまま呼ぶので **旧経路と挙動同一**。
    /// 投擲（Directional）・自動（AutoOnDeath）が万一来たら従来どおり防御ログ。
    pub def applyConsumableSelfEffect(playerId: Int32, player: PlayerScene.Data,
                                   item: Consumable.ConsumableResource):
            Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery} =
        match dslUseRule(item) {
            // IDE 合成エディタの effectRule（onUse）があればそれを優先発火。PlanItem の値（IDE で
            // 編集した量/op/継続）で効くので、ゲーム挙動が IDE の設定に追従する。対象は自分。
            case Some(rule) =>
                let ctx = {selfId = playerId, attackerId = playerId, actorIsPlayer = true,
                           rayUnits = ({id = playerId, ally = true, immobilized = false, alive = true}: EffectRule.RayUnit) :: Nil,
                           amount = {max = player#resource#hp, dealt = 0, incoming = 0, magic = 0}};
                let plan = EffectPlan.planActions(rule, ctx);
                World.emitStatusAdds(plan);  // 境界で World へ status を発行
                EffectRunner.runPlan(throwEffectHandlers(), plan, ());
                World.emitHpSets(plan)  // hp も境界で World へ emit
            // effectRule が無い（または onUse でない）→ 従来どおり legacy effect で動く。
            case None =>
                if (isSelfUseEffect(item#effect)) {
                    let rule = EffectBridge.consumableRule(item);
                    let ctx = {selfId = playerId, attackerId = playerId, actorIsPlayer = true,
                               rayUnits = (Nil: List[EffectRule.RayUnit]),
                               amount = {max = player#resource#hp, dealt = 0, incoming = 0, magic = 0}};
                    let plan = EffectPlan.planActions(rule, ctx);
                    World.emitStatusAdds(plan);  // 境界で World へ status を発行
                    EffectRunner.runPlan(selfEffectHandlers(item), plan, ());
                    World.emitHpSets(plan)  // hp も境界で World へ emit
                } else {
                    GameLogger.playerLog("${PlayerScene.displayName(playerId)} の ${item#name} は ここでは使えなかった")
                }
        }

    /// effectRule があり trigger が onUse（つかう）なら EffectRule を返す。IDE 合成効果を優先する判定。
    def dslUseRule(item: Consumable.ConsumableResource): Option[EffectRule.EffectRule] =
        match item#effectRule {
            case Some(j) => match EffectBridge.fromComposer(j) {
                case Some(rule) => if (rule#trigger == EffectRule.Trigger.OnUse) Some(rule) else None
                case None       => None
            }
            case None => None
        }

    /// self-use（つかうと自分に効く）効果か。これら以外がここへ来たら防御ログへ落とす。
    def isSelfUseEffect(effect: Consumable.ConsumableEffect): Bool = match effect {
        case Consumable.ConsumableEffect.Heal     => true
        case Consumable.ConsumableEffect.FullHeal => true
        case Consumable.ConsumableEffect.MaxHpUp  => true
        case Consumable.ConsumableEffect.AtkUp    => true
        case Consumable.ConsumableEffect.SpdUp    => true
        case _                                    => false
    }

    /// PlanItem を既存 primitive へ振り分ける handler。HP/status 変更・ログは primitive がそのまま行う
    /// （＝旧 match と挙動同一）。self-use では heal/fullHeal/status のみ発火する
    /// （maxHpUp は境界の `World.emitHpSets` が処理するので no-op）。
    def selfEffectHandlers(item: Consumable.ConsumableResource):
            EffectRunner.PlanHandlers[Unit, {GameLogger.GameLogger, World.Command, World.WorldQuery}] = {
        // self-use なので対象は常に自分（ally=true）。ally は使わない。
        heal       = (_u, id, _, _)        -> checked_ecast(withPlayer(id, p -> applyConsumableHeal(id, p, item))),
        fullHeal   = (_u, id, _)           -> checked_ecast(withPlayer(id, p -> applyFullHeal(id, p, item))),
        maxHpUp    = (u, _, _, _)         -> checked_ecast(u),
        status     = (_u, id, _, se, _, _) -> checked_ecast(applySelfStatus(id, item, se)),  // Seed
        // self-use では発火しない handler。全 handler が同一 effect(GameLogger) を持つ必要があるため
        // 純粋な恒等を checked_ecast で GameLogger へ上げる（実際の作用は無し）。
        damage     = (u, _, _, _)         -> checked_ecast(u),
        immobilize = (u, _, _, _)         -> checked_ecast(u),
        revive     = (u, _, _)            -> checked_ecast(u),
        custom     = (u, _, _, _)         -> checked_ecast(u),
        sfx        = (u, _)               -> checked_ecast(u),
        noOp       = (u, _)               -> checked_ecast(u)
    }

    /// id のプレイヤーが居れば f を適用、居なければ no-op（防御）。
    def withPlayer(id: Int32, f: PlayerScene.Data -> Unit \ ef): Unit \ {ef, World.WorldQuery} =
        match PlayerScene.get(id) {
            case Some(p) => f(p)
            case None    => ()
        }

    /// 消費アイテムで使用者自身の HP を `magnitude` 回復、ログ。
    /// `applyConsumableSelfEffect` から呼ばれる内部処理だが、回復量を単体検証できるように
    /// pub にしている（`TestStaffCast` 参照）。
    pub def applyConsumableHeal(playerId: Int32, player: PlayerScene.Data,
                             item: Consumable.ConsumableResource):
            Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery} =
        // 現在 hp は World 読み。
        let curHp = World.hpOf(World.EntityRef.Player(playerId), World.WorldQuery.get())
                        |> Option.getWithDefault(player#hp);
        let result = Combat.heal(curHp, player#resource#hp, item#magnitude);
        let healed = result#newHp - curHp;
        GameLogger.playerLog("${PlayerScene.displayName(playerId)} は ${item#name} で ${healed}回復");
        // 書き込みは setHp funnel（SetHp emit 併記＝World 即時反映）。
        PlayerScene.setHp(playerId, result#newHp)

    /// 全快薬: HP を最大まで戻す。`magnitude` は不使用。
    pub def applyFullHeal(playerId: Int32, player: PlayerScene.Data,
                           item: Consumable.ConsumableResource):
            Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery} =
        // 現在 hp は World 読み・書き込みは setHp funnel（SetHp emit 併記）。
        let maxHp  = player#resource#hp;
        let curHp  = World.hpOf(World.EntityRef.Player(playerId), World.WorldQuery.get())
                         |> Option.getWithDefault(player#hp);
        let healed = maxHp - curHp;
        GameLogger.playerLog("${PlayerScene.displayName(playerId)} は ${item#name} で ${healed}回復");
        PlayerScene.setHp(playerId, maxHp)

    /// 命の草: 最大 HP を `magnitude` 永続上昇させ、現在 HP も同量上げる（その場で増えた分が回復）。
    /// 本番経路（DSL/legacy handler）では `World.emitHpSets` の MaxHpUpAt 分岐が
    /// SetHp/SetBaseStats/SetPlayerResource を境界 emit するため呼ばれない。回復量ロジックを
    /// 単体検証できるよう pub の test seam として残し、resource テンプレも自前で emit する。
    pub def applyMaxHpUp(playerId: Int32, player: PlayerScene.Data,
                          item: Consumable.ConsumableResource):
            Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery} =
        let inc       = item#magnitude;
        let newMax    = player#resource#hp + inc;
        let newHp     = (World.hpOf(World.EntityRef.Player(playerId), World.WorldQuery.get())
                            |> Option.getWithDefault(player#hp)) + inc;
        let newResource = {hp = newMax | player#resource};
        GameLogger.playerLog("${PlayerScene.displayName(playerId)} は ${item#name} で 最大HP+${inc}");
        World.Command.emit(World.Cmd.SetPlayerResource(playerId, newResource));
        World.Command.emit(World.Cmd.SetBaseStats(World.EntityRef.Player(playerId), Combat.baseStatsFrom(newResource)));
        PlayerScene.setHp(playerId, newHp)

    /// ちから薬 / すばやさ薬: 使用者へ時限バフ（`magnitude` を `duration` ターン）を付与する。
    /// `kind` は付与する `StatusEffect`（AtkUp / SpdUp）。効果は次の戦闘予測・実戦闘に反映される。
    def applySelfStatus(playerId: Int32, item: Consumable.ConsumableResource,
                         kind: StatusSystem.StatusEffect):
            Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery} =
        let status = {effect = kind, magnitude = item#magnitude, remaining = item#duration};
        GameLogger.playerLog("${PlayerScene.displayName(playerId)} は ${item#name} を使った (${item#duration}ターン)");
        // statuses は World 権威＝現在値に add を適用して Seed（全置換）で書く。
        PlayerScene.updateStatuses(playerId, xs -> StatusSystem.add(status, xs))

    /// 消費アイテムの耐久（使用回数）を 1 減らし、0 なら consumables から除去 + 使い切りログ。
    /// `consumeStaff` と構造は同じだが、型が `Consumable.ConsumableResource` のため共通化できない。
    def consumeConsumable(playerId: Int32, idx: Int32,
                           item: Consumable.ConsumableResource):
            Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery} =
        let consumed = Consumable.consume(item);
        // 在庫は World 権威＝現在値を読んで耐久消費後の並びを Cmd で書く。
        let newConsumables = replaceOrDropAt(idx, consumed, PlayerScene.consumablesW(playerId));
        if (Option.isEmpty(consumed))
            GameLogger.playerLog("${PlayerScene.displayName(playerId)} の ${item#name} を使い切った")
        else ();
        PlayerScene.putConsumables(playerId, newConsumables)

    // ────────────────────────────────────────────────────────
    // 投擲系（Directional）消費アイテム — 目潰し薬 / 鈍足薬
    //   杖と同じく方向を選んで直線に飛ばし、最初に当たったキャラへ時限デバフを付与する。
    //   `StaffAim` フェーズを杖と共用し、`Game.staffAimConfirm` から呼ばれる。
    // ────────────────────────────────────────────────────────

    /// 投擲系消費アイテムを発動する。`StaffAim` フェーズで Z 確定時に方向付きで呼ばれる。
    /// 該当プレイヤー / アイテムが見つからなければ防御的に no-op。
    pub def applyConsumableDirectional(playerId: Int32, idx: Int32,
                                        direction: Dir4.Dir4):
            Unit
            \ {RangeOverlayState.State,
                BoardQuery, GameLogger.GameLogger,
                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State, CursorState.State,
                World.Command, World.WorldQuery} =
        // 在庫（consumables）は World 権威＝dataFromWorld で読む。
        let cast = forM (
            player <- World.dataFromWorld(playerId, World.WorldQuery.get());
            item   <- List.nth(idx, player#consumables)
        ) yield fireConsumable(playerId, idx, player, item, direction);
        Option.getWithDefault((), cast)

    /// 投擲系の本体: レイキャスト → 当たり対象へデバフ付与 → 耐久消費 → 選択クリア → ターン進行。
    /// 杖の `fireStaff` と同構造（方向投擲を間借りする）。
    def fireConsumable(playerId: Int32, idx: Int32, player: PlayerScene.Data,
                        item: Consumable.ConsumableResource, direction: Dir4.Dir4):
            Unit
            \ {RangeOverlayState.State,
                BoardQuery, GameLogger.GameLogger,
                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State, CursorState.State,
                World.Command, World.WorldQuery} =
        let board = BoardQuery.board();
        let dir   = Staff.toVec2i(direction);
        let hit   = Board.rayCast(player#gridPos, dir, staffMaxRange(), board);
        applyDirectionalEffect(playerId, item, hit);
        consumeConsumable(playerId, idx, item);
        PlayerScene.clearSelectedItem(playerId);
        TurnFlow.commitWaitedAndAdvance();
        ()

    /// 当たった対象（敵 / 味方）へ時限デバフを付与する。空振りはログのみ。
    /// 効果が投擲系でない（誤用）場合も `directionalStatus` が None を返して不発ログにする。
    /// `applyStaffEffect` と同じく `(付与する Status, hit)` のタプルで 1 段マッチに畳む。
    def applyDirectionalEffect(playerId: Int32, item: Consumable.ConsumableResource,
                                hit: RayHit):
            Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery} =
        // directionalStatus は「投擲系デバフか（Some/None）」の門番として使い、状態適用そのものは
        // 統一 DSL 経路（applyConsumableEffectDsl）へ寄せる（当たった敵/味方を ally で出し分け）。
        match (StaffRules.directionalStatus(item), hit) {
            case (Some(_), RayHit.HitEnemy(enemyId, _))   =>
                GameLogger.playerLog("${PlayerScene.displayName(playerId)} は ${EnemyScene.displayName(enemyId)} に ${item#name} を当てた");
                applyConsumableEffectDsl(item, enemyId, false)
            case (Some(_), RayHit.HitPlayer(targetId, _)) =>
                GameLogger.playerLog("${PlayerScene.displayName(playerId)} は ${PlayerScene.displayName(targetId)} に ${item#name} を当てた");
                applyConsumableEffectDsl(item, targetId, true)
            // 効果が投擲系でない（None）→ 不発。投擲系だが壁/盤外に消えた → 届かなかった。
            case (None, _)                                     =>
                GameLogger.playerLog("${PlayerScene.displayName(playerId)} の ${item#name} は不発に終わった")
            case (Some(_), _)                                  =>
                GameLogger.playerLog("${PlayerScene.displayName(playerId)} の ${item#name} は届かなかった")
        }

    // 投擲デバフ Status 生成 directionalStatus は純 leaf として StaffRules.flix へ移動（A6）。

    // ────────────────────────────────────────────────────────
    // アイテム投擲（一律「投げる」） — 武器 / 杖 / 薬 を方向投擲する
    //   命中率は 60%（レンジャー・ローグは 80%）。当たれば:
    //     武器 → 攻撃力の 8 割を防御無視で与える
    //     薬   → 薬の効果が当たったキャラに出る
    //     杖   → 杖の効果が当たったキャラに出る（発動と同じ）
    //     指輪 → 効果なし
    //   外れ / 空振りでもアイテムは 1 個消費し、ターンを消費する。
    // ────────────────────────────────────────────────────────

    /// 「投げる」を実行する。`StaffAim`（投擲モード）で Z 確定時に方向付きで呼ばれる。
    /// 該当プレイヤー / アイテムは各 throw* が解決するので、ここはプレイヤー解決のみ。
    pub def applyThrow(playerId: Int32, kind: PlayerData.ItemKind,
                        direction: Dir4.Dir4):
            Unit
            \ {RangeOverlayState.State, BoardQuery, GameLogger.GameLogger,
                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State, CursorState.State, GameEngine.Audio,
                Math.Random, CustomEffects.GameOverRequest, World.Command, World.WorldQuery} =
        // 在庫（投げるアイテムの index 解決）は World 権威＝dataFromWorld で読む。
        let cast = forM (player <- World.dataFromWorld(playerId, World.WorldQuery.get()))
            yield fireThrow(playerId, kind, player, direction);
        Option.getWithDefault((), cast)

    /// 投擲本体: レイキャスト → 命中ロール込みで効果適用 → 投擲アイテム消費 → 選択クリア → ターン進行。
    def fireThrow(playerId: Int32, kind: PlayerData.ItemKind, player: PlayerScene.Data,
                   direction: Dir4.Dir4):
            Unit
            \ {RangeOverlayState.State, BoardQuery, GameLogger.GameLogger,
                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State, CursorState.State, GameEngine.Audio,
                Math.Random, CustomEffects.GameOverRequest, World.Command, World.WorldQuery} =
        let board = BoardQuery.board();
        let dir   = Staff.toVec2i(direction);
        let hit   = Board.rayCast(player#gridPos, dir, staffMaxRange(), board);
        applyThrowHit(playerId, kind, player, dir, hit);
        consumeThrownItem(playerId, kind);
        PlayerScene.clearSelectedItem(playerId);
        TurnFlow.commitWaitedAndAdvance();
        ()

    /// 当たり対象（キャラ）が居れば命中ロールへ、壁・盤外なら空振りログのみ。1 段マッチ。
    def applyThrowHit(playerId: Int32, kind: PlayerData.ItemKind, player: PlayerScene.Data,
                       dir: {x = Int32, y = Int32}, hit: RayHit):
            Unit
            \ {GameLogger.GameLogger,
                Math.Random, CustomEffects.GameOverRequest, SelectedPlayer.State,
                GameEngine.Audio, World.Command, World.WorldQuery, BoardQuery} =
        match hit {
            case RayHit.HitEnemy(_, _)  => rolledThrow(playerId, kind, player, dir, hit)
            case RayHit.HitPlayer(_, _) => rolledThrow(playerId, kind, player, dir, hit)
            case _                      =>
                GameLogger.playerLog("${PlayerScene.displayName(playerId)} の 投げ は届かなかった")
        }

    /// 命中ロール（60% / レンジャー・ローグは 80%）を引き、当たれば種別ごとに効果を適用する。
    def rolledThrow(playerId: Int32, kind: PlayerData.ItemKind, player: PlayerScene.Data,
                     dir: {x = Int32, y = Int32}, hit: RayHit):
            Unit
            \ {GameLogger.GameLogger,
                Math.Random, CustomEffects.GameOverRequest, SelectedPlayer.State,
                GameEngine.Audio, World.Command, World.WorldQuery, BoardQuery} =
        let roll = throwRoll();
        let threshold = Combat.throwHitRate(isAccurateThrower(player));
        if (not Combat.isHit(threshold, roll)) {
            GameLogger.playerLog("${PlayerScene.displayName(playerId)} の 投げ は外れた")
        } else
            dispatchThrowEffect(playerId, kind, player, dir, hit)

    /// 命中ロール用の 0..99 一様乱数（`CombatDriver.rollPercent` と同形）。
    def throwRoll(): Int32 \ Math.Random =
        Float64.truncateToInt32(Float64.floor(Math.Random.randomFloat64() * 100.0))

    /// 投げ手が命中の高い職（レンジャー / ローグ）か。`resource#description` を職名として判定する。
    def isAccurateThrower(player: PlayerScene.Data): Bool =
        let cls = player#resource#description;
        cls == "レンジャー" or cls == "ローグ"

    /// 当たったキャラへ種別ごとの効果を適用する。各アイテム取得は forM、効果適用は別関数へ委譲し
    /// match のネストを避ける。
    def dispatchThrowEffect(playerId: Int32, kind: PlayerData.ItemKind, player: PlayerScene.Data,
                             dir: {x = Int32, y = Int32}, hit: RayHit):
            Unit
            \ {GameLogger.GameLogger,
                CustomEffects.GameOverRequest, SelectedPlayer.State, GameEngine.Audio,
                World.Command, World.WorldQuery, BoardQuery} =
        match kind {
            case PlayerData.ItemKind.Weapon(idx) =>
                Option.getWithDefault((),
                    forM (w <- List.nth(idx, player#weapons))
                        yield throwWeaponResolved(playerId, player, w, hit))
            case PlayerData.ItemKind.Consumable(idx) =>
                Option.getWithDefault((),
                    forM (c <- List.nth(idx, player#consumables))
                        yield throwConsumableHit(playerId, c, hit))
            case PlayerData.ItemKind.Staff(idx) =>
                Option.getWithDefault((),
                    forM (s <- List.nth(idx, player#staves))
                        yield applyStaffEffect(playerId, player, s, dir, hit))
            case PlayerData.ItemKind.Ring(_) =>
                GameLogger.playerLog("${PlayerScene.displayName(playerId)} の 指輪 を投げたが 効果はなかった")
        }

    /// 武器投げの解決。攻撃力の 8 割（防御無視・最低 1）を当たったキャラへ与える。1 段マッチ。
    def throwWeaponResolved(playerId: Int32, player: PlayerScene.Data,
                             weapon: UnitCatalog.WeaponResource, hit: RayHit):
            Unit
            \ {GameLogger.GameLogger,
                CustomEffects.GameOverRequest, SelectedPlayer.State, World.Command, World.WorldQuery} =
        let atkPower = Combat.attackStatFor(player#resource#attack, player#resource#magicAttack,
                                             weapon#attack, WeaponCatalog.isPhysical(weapon#weaponType));
        let dmg = Combat.thrownWeaponDamage(atkPower);
        match hit {
            case RayHit.HitEnemy(enemyId, _)   =>
                throwDamageToEnemy("${PlayerScene.displayName(playerId)}", enemyId, dmg, weapon#name)
            case RayHit.HitPlayer(targetId, _) =>
                throwDamageToPlayer("${PlayerScene.displayName(playerId)}", targetId, dmg, weapon#name)
            case _                             => ()
        }

    /// 投げダメージを敵へ（防御無視）。死亡なら撃破演出、生存なら HP 反映。
    /// `srcLabel` は投げ手の表示名（兵種名。例: "傭兵" / "ゴブリン"）。味方投擲・敵投擲で共用する。
    def throwDamageToEnemy(srcLabel: String, enemyId: Int32, dmg: Int32, name: String):
            Unit
            \ {GameLogger.GameLogger, World.Command, World.WorldQuery} =
        Option.getWithDefault((),
            forM (enemy <- EnemyScene.get(enemyId)) yield {
                // 現在 hp は World 読み。
                let curHp = World.hpOf(World.EntityRef.Enemy(enemyId), World.WorldQuery.get())
                                |> Option.getWithDefault(enemy#hp);
                let dmgResult = Combat.damage(hp = curHp, amount = dmg);
                if (dmgResult#isDead) {
                    GameLogger.playerLog("${srcLabel} は ${name} を投げて ${EnemyScene.displayName(enemyId)} を撃破 (${dmg}ダメージ)");
                    EnemyScene.startDeathAnimation(enemyId)
                } else {
                    GameLogger.playerLog("${srcLabel} は ${name} を投げて ${EnemyScene.displayName(enemyId)} に ${dmg}ダメージ");
                    // アイテムをぶつけられたので、かなしばり中なら完全停止を解除する。
                    EnemyScene.setHp(enemyId, dmgResult#newHp);
                    EnemyScene.releaseBind(enemyId)
                }
            })

    /// 投げダメージを味方へ（誤射 / 敵の投擲・防御無視）。死亡なら removeDead 経由でゲームオーバー判定。
    def throwDamageToPlayer(srcLabel: String, targetId: Int32, dmg: Int32, name: String):
            Unit \ {GameLogger.GameLogger, CustomEffects.GameOverRequest,
                               SelectedPlayer.State, World.Command, World.WorldQuery} =
        Option.getWithDefault((),
            forM (target <- PlayerScene.get(targetId)) yield {
                // 現在 hp は World 読み。
                let curHp = World.hpOf(World.EntityRef.Player(targetId), World.WorldQuery.get())
                                |> Option.getWithDefault(target#hp);
                let dmgResult = Combat.damage(hp = curHp, amount = dmg);
                GameLogger.playerLog("${srcLabel} の ${name} が ${PlayerScene.displayName(targetId)} に当たった (${dmg}ダメージ)");
                // アイテムをぶつけられたので、かなしばり中なら完全停止を解除する。
                PlayerScene.setHp(targetId, dmgResult#newHp);
                PlayerScene.releaseBind(targetId);
                if (dmgResult#isDead)
                    PlayerScene.removeDeadAndCheckGameOver(targetId :: Nil)
                else ()
            })

    /// 薬投げの種別振り分け: 火炎瓶 / 爆発瓶（固定ダメージ + 効果音）はダメージ処理へ、
    /// それ以外は当たったキャラへ効果を出す通常処理へ。1 段マッチ。
    def throwConsumableHit(playerId: Int32, item: Consumable.ConsumableResource,
                            hit: RayHit):
            Unit
            \ {GameLogger.GameLogger,
                CustomEffects.GameOverRequest, SelectedPlayer.State, GameEngine.Audio,
                World.Command, World.WorldQuery} =
        match item#effect {
            case Consumable.ConsumableEffect.FireBottle  => throwBottleSingle("${PlayerScene.displayName(playerId)}", item, hit)
            case Consumable.ConsumableEffect.BlastBottle => throwBottleBlast("${PlayerScene.displayName(playerId)}", item, hit)
            case _                                       =>
                // 効果の良し悪しで効果音を出し分ける: 回復・バフ系は "cure"、デバフ系は "damage"。
                ViewReplay.sound(consumableHitSound(item#effect));
                throwConsumableResolved(playerId, item, hit)
        }

    /// 投擲した薬が当たったときの効果音。回復・最大HP・蘇生・バフ（対象に有利）は "cure"、
    /// 目潰し・鈍足など相手を弱らせるデバフ系は "damage"。瓶（FireBottle/BlastBottle）は
    /// それぞれ専用音を別経路で鳴らすのでここには来ない（来ても "cure" に倒す）。
    def consumableHitSound(effect: Consumable.ConsumableEffect): String = match effect {
        case Consumable.ConsumableEffect.BlindHit   => "damage"
        case Consumable.ConsumableEffect.SpdDownHit => "damage"
        case Consumable.ConsumableEffect.DefDownHit => "damage"
        case _                                      => "cure"
    }

    /// 火炎瓶: 当たった対象に固定ダメージ（防御無視）。効果音は魔法と同じ "magic"。味方/敵で共用。
    pub def throwBottleSingle(srcLabel: String, item: Consumable.ConsumableResource,
                           hit: RayHit):
            Unit
            \ {GameLogger.GameLogger,
                CustomEffects.GameOverRequest, SelectedPlayer.State, GameEngine.Audio,
                World.Command, World.WorldQuery} =
        ViewReplay.sound("magic");
        let dmg = item#magnitude;
        // 着弾セルに爆発エフェクトを出してからダメージを与える。
        match hit {
            case RayHit.HitEnemy(enemyId, cell)   =>
                ExplosionFx.emitAtCell(cell);
                throwDamageToEnemy(srcLabel, enemyId, dmg, item#name)
            case RayHit.HitPlayer(targetId, cell) =>
                ExplosionFx.emitAtCell(cell);
                throwDamageToPlayer(srcLabel, targetId, dmg, item#name)
            case _                                => ()
        }

    /// 爆発瓶: 当たったセルとその周囲 1 マス（チェビシェフ距離 1、味方も含む）に固定ダメージ。
    /// 効果音は "critical"（爆発専用音が無いため流用）。当たりセルが取れなければ no-op。味方/敵で共用。
    pub def throwBottleBlast(srcLabel: String, item: Consumable.ConsumableResource,
                          hit: RayHit):
            Unit
            \ {GameLogger.GameLogger,
                CustomEffects.GameOverRequest, SelectedPlayer.State, GameEngine.Audio,
                World.Command, World.WorldQuery} =
        ViewReplay.sound("critical");
        let dmg = item#magnitude;
        match rayHitCell(hit) {
            case None       => ()
            case Some(cell) =>
                GameLogger.playerLog("${srcLabel} の ${item#name} が爆発した (${dmg}ダメージ)");
                // 爆発瓶は中心に大きい爆発を 1 つ出す（3×3 範囲を覆う見た目）。
                ExplosionFx.emitBigAtCell(cell);
                blastDamageEnemies(srcLabel, dmg, item#name, cell);
                blastDamagePlayers(srcLabel, dmg, item#name, cell)
        }

    /// RayHit から当たりセルを取り出す（キャラに当たったときのみ Some）。
    def rayHitCell(hit: RayHit): Option[{x = Int32, y = Int32}] =
        match hit {
            case RayHit.HitEnemy(_, cell)  => Some(cell)
            case RayHit.HitPlayer(_, cell) => Some(cell)
            case _                         => None
        }

    /// チェビシェフ距離（周囲 1 マス判定に使う。8 近傍 + 中心が距離 ≤ 1）。
    def chebyshev(a: {x = Int32, y = Int32}, b: {x = Int32, y = Int32}): Int32 =
        Int32.max(Int32.abs(a#x - b#x), Int32.abs(a#y - b#y))

    /// 爆発: 中心セルの周囲 1 マス内の全敵に固定ダメージを与える。
    def blastDamageEnemies(srcLabel: String, dmg: Int32, name: String,
                            center: {x = Int32, y = Int32}):
            Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery} =
        let ids = EnemyScene.getAll()
                    |> List.filter(e -> chebyshev(e#gridPos, center) <= 1)
                    |> List.map(e -> e#id);
        List.forEach(id -> throwDamageToEnemy(srcLabel, id, dmg, name), ids)

    /// 爆発: 中心セルの周囲 1 マス内の全味方に固定ダメージを与える（自分たちも巻き込む）。
    def blastDamagePlayers(srcLabel: String, dmg: Int32, name: String,
                            center: {x = Int32, y = Int32}):
            Unit \ {GameLogger.GameLogger, CustomEffects.GameOverRequest,
                               SelectedPlayer.State, World.Command, World.WorldQuery} =
        let ids = PlayerScene.getAll()
                    |> List.filter(p -> chebyshev(p#gridPos, center) <= 1)
                    |> List.map(p -> p#id);
        List.forEach(id -> throwDamageToPlayer(srcLabel, id, dmg, name), ids)

    // ────────────────────────────────────────────────────────
    // 敵の投擲（ローグ_T3=爆発瓶 / クレリック_T3=火炎瓶、敵ターンに 1 回だけ）
    //   `description` で持つ瓶を判定し、縦横 4 方向の直線上に味方が居れば投げる。
    //   ダメージ処理は味方投擲と同じ throwBottleSingle / throwBottleBlast を共用する。
    // ────────────────────────────────────────────────────────

    /// 敵の職名（`resource#description`）から持っている瓶を返す。持たない職は None。
    def enemyBottleFor(description: String): Option[Consumable.ConsumableResource] =
        if (description == "ローグ_T3")
            Some(Consumable.bottle(Consumable.ConsumableEffect.BlastBottle, 10, 0, "爆発瓶"))
        else if (description == "クレリック_T3")
            Some(Consumable.bottle(Consumable.ConsumableEffect.FireBottle, 15, 0, "火炎瓶"))
        else if (description == "レンジャー_T2" or description == "レンジャー_T3")
            // ほころび薬: 当たった味方の守備を 5 下げる（3 ターン）。
            Some(Consumable.bottle(Consumable.ConsumableEffect.DefDownHit, 5, 3, "ほころび薬"))
        else None

    /// 敵が瓶を投げられるか試す。`description` の瓶を持ち、縦横 4 方向のいずれかの直線上に
    /// 味方が居れば、その方向へ投げてダメージを与え true を返す。投げられなければ false。
    /// 呼び出し側（EnemyTurnDriver）が true/false で通常 AI と投擲を分岐する。
    pub def enemyTryThrow(enemyId: Int32, origin: {x = Int32, y = Int32},
                           description: String):
            Bool
            \ {GameLogger.GameLogger,
                CustomEffects.GameOverRequest, SelectedPlayer.State, GameEngine.Audio,
                World.Command, World.WorldQuery, BoardQuery} =
        match enemyBottleFor(description) {
            case None       => false
            case Some(item) => enemyThrowWith(enemyId, origin, item)
        }

    /// 瓶が確定した敵について、味方が居る直線方向を探して投げる。方向が無ければ false。
    def enemyThrowWith(enemyId: Int32, origin: {x = Int32, y = Int32},
                        item: Consumable.ConsumableResource):
            Bool
            \ {GameLogger.GameLogger,
                CustomEffects.GameOverRequest, SelectedPlayer.State, GameEngine.Audio,
                World.Command, World.WorldQuery, BoardQuery} =
        // 敵投擲（mid-frame）の board 読みは World 由来。
        let board: Board = BoardQuery.board();
        match enemyThrowDirection(origin, board) {
            case None      => false
            case Some(dir) =>
                let hit = Board.rayCast(origin, Staff.toVec2i(dir), staffMaxRange(), board);
                GameLogger.enemyLog("${EnemyScene.displayName(enemyId)} が ${item#name} を投げた");
                enemyApplyBottle("${EnemyScene.displayName(enemyId)}", item, hit);
                true
        }

    /// 縦横 4 方向で、レイの最初の当たりが味方になる方向を返す（無ければ None）。
    def enemyThrowDirection(origin: {x = Int32, y = Int32}, board: Board): Option[Dir4.Dir4] =
        let dirs = Dir4.Up :: Dir4.Down
                    :: Dir4.Left :: Dir4.Right :: Nil;
        List.findLeft(d -> rayHitsPlayer(origin, d, board), dirs)

    /// 指定方向のレイの最初の当たりが味方か。
    def rayHitsPlayer(origin: {x = Int32, y = Int32}, dir: Dir4.Dir4, board: Board): Bool =
        match Board.rayCast(origin, Staff.toVec2i(dir), staffMaxRange(), board) {
            case RayHit.HitPlayer(_, _) => true
            case _                      => false
        }

    // ────────────────────────────────────────────────────────
    // 敵クレリックの杖詠唱（クレリック_T2=かなしばり / クレリック_T3=一時しのぎ）
    //   瓶投げ（enemyTryThrow）と同じ description 駆動。縦横直線上に「まだ停止していない味方」が
    //   居れば詠唱する。詠唱は耐久を消費しない（瓶と同じ方針）。
    // ────────────────────────────────────────────────────────

    /// 敵の職名から詠唱する杖効果を返す（持たない職は None）。
    pub def enemyStaffFor(description: String): Option[Staff.StaffEffect] =
        if (description == "クレリック_T2") Some(Staff.StaffEffect.Bind)
        else if (description == "クレリック_T3") Some(Staff.StaffEffect.Stopgap)
        else None

    /// 敵が杖を詠唱できるか試す。詠唱職で、4 方向の直線上に「まだ停止していない味方」が居れば、
    /// その味方へ詠唱して true を返す。撃てなければ false（呼び出し側で投擲 / 通常 AI へ）。
    pub def enemyTryStaff(enemyId: Int32, origin: {x = Int32, y = Int32},
                           description: String):
            Bool \ {GameLogger.GameLogger, World.Command, BoardQuery, World.WorldQuery} =
        // 敵詠唱（mid-frame）の board 読みは World 由来。
        let board: Board = BoardQuery.board();
        let cast = forM (
            effect <- enemyStaffFor(description);
            dir    <- enemyThrowDirection(origin, board);
            target <- castableHitPlayer(origin, dir, board)
        ) yield {
            let (targetId, hit) = target;
            enemyCastStaff(enemyId, effect, targetId, Staff.toVec2i(dir), hit)
        };
        Option.nonEmpty(cast)

    /// 指定方向のレイが最初に当たる味方が「まだ停止していない」なら (id, その RayHit) を返す。
    /// 既に停止中なら None（無駄詠唱を避け、呼び出し側で接近 → 殴って解除する流れに任せる）。
    /// RayHit を id と一緒に透過するのは ECS 経路（`resolveStaffCast`）が hit cell を必要とするため
    /// （targeting golden が cell 透過を pin する）。`pub` は targeting golden の直叩き用。
    pub def castableHitPlayer(origin: {x = Int32, y = Int32}, dir: Dir4.Dir4,
                           board: Board): Option[(Int32, RayHit)] \ World.WorldQuery =
        match Board.rayCast(origin, Staff.toVec2i(dir), staffMaxRange(), board) {
            case RayHit.HitPlayer(id, cell) =>
                if (playerImmobilized(id)) None else Some((id, RayHit.HitPlayer(id, cell)))
            case _                           => None
        }

    /// 指定味方が完全停止中か。居なければ false。
    def playerImmobilized(id: Int32): Bool \ World.WorldQuery =
        World.dataFromWorld(id, World.WorldQuery.get())
            |> Option.map(d -> StatusSystem.isImmobilized(d#statuses))
            |> Option.getWithDefault(false)

    /// 解決済みの「敵 → 味方 への詠唱」を適用する dispatcher（壁空振りは ecsResolveEnemyStaff 内で no-op）。
    def enemyCastStaff(enemyId: Int32, effect: Staff.StaffEffect, _targetId: Int32,
                        dir: {x = Int32, y = Int32}, hit: RayHit):
            Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery} =
        ecsResolveEnemyStaff(enemyId, effect, dir, hit)

    /// 敵 Bind/Stopgap 詠唱の解決経路: `StaffSystem.resolveStaffCast` に caster=Enemy を渡して sim を
    /// 解き、events→Cmds で World 反映 + `applyEcsStaffSceneEffects` で World 権威（味方 #statuses）反映。
    /// Bind は view fx 0・Moved 無＝World 不変ゆえ `ViewReplay.replay` は呼ばない。
    /// hit 時は `bindPlayerLog` で『かなしばりにした』ログを出す（`applyEcsStaffSceneEffects`
    /// は #statuses のみ反映ゆえ log を補う）。events が空（壁=空振り。castableHitPlayer ゲートで
    /// 通常到達しない防御）なら no-op。`applyEcsStaffSceneEffects` の
    /// Afflicted(Player) arm を共用する（敵 Bind の target は味方）。`TestEnemyStaffGolden` が直駆動するため pub。
    pub def ecsResolveEnemyStaff(enemyId: Int32, effect: Staff.StaffEffect,
                             dir: {x = Int32, y = Int32}, hit: RayHit):
            Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery} =
        let world = World.WorldQuery.get();
        let (_, events) = StaffSystem.resolveStaffCast(world,
            World.EntityRef.Enemy(enemyId), effect, dir, hit);
        if (List.isEmpty(events))
            // 空振り（壁=盤外）: castableHitPlayer ゲートで通常到達しない防御 no-op。
            ()
        else {
            List.forEach(c -> World.Command.emit(c), events |> List.flatMap(World.eventToCmds));
            // hit-log: 敵 hit は `bindPlayerLog`/warp ログを出す（`applyEcsStaffSceneEffects` は #statuses のみ
            // 反映・log 非配線ゆえここで補う）。warp の位置は `Moved`→eventToCmds→World 反映で描画されるため replay 不要。
            // 不変条件: enemyStaffFor ∩ ecsHandlesStaff = {Bind, Stopgap}。敵杖カタログに新 ECS 効果を足すときは、
            // この log 分岐も同時拡張しないと hit-log が黙って落ちる。
            let srcLabel = EnemyScene.displayName(enemyId);
            match effect {
                case Staff.StaffEffect.Bind    => bindPlayerLog(srcLabel, hitTargetId(hit))
                case Staff.StaffEffect.Stopgap =>
                    // Stopgap = bind + warp。legacy applyStopgapToPlayer の 2 ログ（かなしばり →
                    // 階段の方へ／ワープ先なし）を events から復元し順序も一致させる。
                    bindPlayerLog(srcLabel, hitTargetId(hit));
                    warpPlayerLog(events, hitTargetId(hit))
                case _                         => ()
            };
            applyEcsStaffSceneEffects(events)
        }

    /// Stopgap（敵詠唱）の warp ログ parity。sim が対象への `Moved` を出したら legacy warpPlayer 成功枝の
    /// 『… は 階段の方へ とばされた』、出さなければ失敗枝の『ワープ先がなかった』を復元する（位置反映は World 経由）。
    def warpPlayerLog(events: List[World.SimEvent], targetId: Int32): Unit \ {GameLogger.GameLogger, World.WorldQuery} =
        let warped = List.exists(e -> match e {
            case World.SimEvent.Moved(World.EntityRef.Player(id), _) => id == targetId
            case _                                                   => false
        }, events);
        if (warped)
            GameLogger.playerLog("${PlayerScene.displayName(targetId)} は 階段の方へ とばされた")
        else
            GameLogger.playerLog("ワープ先がなかった")

    /// hit が味方/敵ならその id、壁/盤外なら -1（空振り fallback の targetId 用・存在しない id は legacy が no-op）。
    def hitTargetId(hit: RayHit): Int32 = match hit {
        case RayHit.HitPlayer(id, _) => id
        case RayHit.HitEnemy(id, _)  => id
        case _                       => -1
    }

    /// 瓶の種別で固定ダメージ投擲を分岐（火炎瓶=単体 / 爆発瓶=範囲）。味方投擲と同じ処理を共用。
    def enemyApplyBottle(srcLabel: String, item: Consumable.ConsumableResource,
                          hit: RayHit):
            Unit
            \ {GameLogger.GameLogger,
                CustomEffects.GameOverRequest, SelectedPlayer.State, GameEngine.Audio,
                World.Command, World.WorldQuery} =
        match item#effect {
            case Consumable.ConsumableEffect.FireBottle  => throwBottleSingle(srcLabel, item, hit)
            case Consumable.ConsumableEffect.BlastBottle => throwBottleBlast(srcLabel, item, hit)
            // 投擲デバフ（ほころび薬=守備ダウン等）: デバフ音を鳴らし、当たった対象へ時限デバフを付与。
            case _                                       => enemyApplyDebuff(item, hit)
        }

    /// 敵が投げたデバフ薬を当たった対象へ適用する。デバフ音 + 時限ステータス付与。
    def enemyApplyDebuff(item: Consumable.ConsumableResource, hit: RayHit):
            Unit \ {GameEngine.Audio, World.Command, World.WorldQuery} =
        ViewReplay.sound(consumableHitSound(item#effect));
        applyStatusToHit(StaffRules.directionalStatus(item), hit)

    /// `directionalStatus` の Option をそのまま受け、Some なら当たったキャラ（敵/味方）へ付与。
    /// `(status, hit)` のタプル 1 段マッチでネストを避ける。
    def applyStatusToHit(statusOpt: Option[StatusSystem.Status], hit: RayHit):
            Unit \ {World.Command, World.WorldQuery} =
        // 投擲デバフが当たったら、その効果を足しつつ、かなしばり中なら完全停止を解除する
        // （add→clearImmobilized を合成して 1 回の Seed で書く＝従来の releaseBind 経由と同じ 1 Seed）。
        match (statusOpt, hit) {
            case (Some(status), RayHit.HitEnemy(id, _))  =>
                EnemyScene.updateStatuses(id, xs -> StatusSystem.clearImmobilized(StatusSystem.add(status, xs)))
            case (Some(status), RayHit.HitPlayer(id, _)) =>
                PlayerScene.updateStatuses(id, xs -> StatusSystem.clearImmobilized(StatusSystem.add(status, xs)))
            case _                                       => ()
        }

    /// 薬投げの解決: 当たったキャラ（敵/味方）へ薬の効果を出す。1 段マッチ。
    def throwConsumableResolved(playerId: Int32, item: Consumable.ConsumableResource,
                                 hit: RayHit):
            Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery} =
        match hit {
            case RayHit.HitEnemy(enemyId, _)   => throwConsumableAtEnemy(playerId, item, enemyId)
            case RayHit.HitPlayer(targetId, _) => throwConsumableAtPlayer(playerId, item, targetId)
            case _                             => ()
        }

    /// 薬の効果を敵へ。効果種別で 1 段マッチ。
    def throwConsumableAtEnemy(playerId: Int32, item: Consumable.ConsumableResource,
                                enemyId: Int32):
            Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery} =
        Option.getWithDefault((),
            forM (enemy <- EnemyScene.get(enemyId)) yield {
                GameLogger.playerLog("${PlayerScene.displayName(playerId)} は ${EnemyScene.displayName(enemyId)} に ${item#name} を当てた");
                applyConsumableEffectToEnemy(item, enemy, enemyId)
            })

    /// 投擲効果を当たったユニット (id, ally) へ **DSL 経路** で適用する。
    /// consumableThrowRule（投げ版＝当たった相手・陣営無視）を planActions → runPlan で発火し、
    /// 統一ハンドラが ally で player/enemy ノードを出し分ける。HP/status の数値・挙動は旧 per-effect
    /// match と同一。火炎瓶/爆発瓶は throwConsumableHit が先に処理するためここには来ない。
    pub def applyConsumableEffectDsl(item: Consumable.ConsumableResource,
                                  id: Int32, ally: Bool): Unit \ {World.Command, World.WorldQuery} =
        let target = ({id = id, ally = ally, immobilized = false, alive = true}: EffectRule.RayUnit);
        let ctx = {selfId = id, attackerId = id, actorIsPlayer = true, rayUnits = target :: Nil,
                   amount = {max = 0, dealt = 0, incoming = 0, magic = 0}};
        let plan = EffectPlan.planActions(EffectBridge.consumableThrowRule(item), ctx);
        World.emitStatusAdds(plan);  // 境界で World へ status を発行
        EffectRunner.runPlan(throwEffectHandlers(), plan, ());
        World.emitHpSets(plan)  // hp も境界で World へ emit

    /// 投擲効果の統一ハンドラ。ally で player/enemy を出し分け、HP/status を適用する（ログなし）。
    /// maxHpUp は境界の `World.emitHpSets` が処理するので no-op。damage/immobilize 等は
    /// 投擲薬の経路には現れないので恒等。
    def throwEffectHandlers(): EffectRunner.PlanHandlers[Unit, {World.Command, World.WorldQuery}] = {
        heal       = (_u, id, ally, n)         -> checked_ecast(healUnit(id, ally, n)),
        fullHeal   = (_u, id, ally)            -> checked_ecast(fullHealUnit(id, ally)),
        maxHpUp    = (u, _, _, _)             -> checked_ecast(u),
        status     = (_u, id, ally, se, m, t)  -> checked_ecast(statusUnit(id, ally, se, m, t)),  // Seed
        damage     = (u, _, _, _)             -> checked_ecast(u),
        immobilize = (u, _, _, _)             -> checked_ecast(u),
        revive     = (u, _, _)                -> checked_ecast(u),
        custom     = (u, _, _, _)             -> checked_ecast(u),
        sfx        = (u, _)                   -> checked_ecast(u),
        noOp       = (u, _)                   -> checked_ecast(u)
    }

    /// HP 回復を ally で出し分け（旧 Heal arm と同一）。
    def healUnit(id: Int32, ally: Bool, n: Int32): Unit \ {World.Command, World.WorldQuery} =
        // 入力 hp は World 読み・書き込みは setHp funnel（SetHp emit 併記）。plan 内の連鎖は
        // read-after-write（worldRef 即時適用）で成立する。境界の emitHpSets は同値の再 emit＝冪等。
        let w = World.WorldQuery.get();
        if (ally)
            match PlayerScene.get(id) {
                case Some(p) =>
                    let cur = World.hpOf(World.EntityRef.Player(id), w) |> Option.getWithDefault(p#hp);
                    let r = Combat.heal(cur, p#resource#hp, n);
                    PlayerScene.setHp(id, r#newHp)
                case None => ()
            }
        else
            match EnemyScene.get(id) {
                case Some(e) =>
                    let cur = World.hpOf(World.EntityRef.Enemy(id), w) |> Option.getWithDefault(e#hp);
                    let r = Combat.heal(cur, e#resource#hp, n);
                    EnemyScene.setHp(id, r#newHp)
                case None => ()
            }

    /// 全回復を ally で出し分け（旧 FullHeal / AutoRevive arm と同一）。
    def fullHealUnit(id: Int32, ally: Bool): Unit \ {World.Command, World.WorldQuery} =
        // 書き込みは setHp funnel（SetHp emit 併記）。全回復は入力 hp 不要。
        if (ally)
            match PlayerScene.get(id) {
                case Some(p) => PlayerScene.setHp(id, p#resource#hp)
                case None => ()
            }
        else
            match EnemyScene.get(id) {
                case Some(e) => EnemyScene.setHp(id, e#resource#hp)
                case None => ()
            }

    /// 時限ステータス付与を ally で出し分け（旧 addEnemyStatus / addPlayerStatus と同一）。
    def statusUnit(id: Int32, ally: Bool, kind: StatusSystem.StatusEffect,
                   mag: Int32, turns: Int32): Unit \ {World.Command, World.WorldQuery} =
        let status = {effect = kind, magnitude = mag, remaining = turns};
        // statuses は World 権威＝現在値に add を適用して Seed（全置換）で書く。
        if (ally)
            PlayerScene.updateStatuses(id, xs -> StatusSystem.add(status, xs))
        else
            EnemyScene.updateStatuses(id, xs -> StatusSystem.add(status, xs))

    /// 敵 1 体への薬効果適用 → DSL 経路へ委譲（数値・挙動は同一、ally=false）。
    def applyConsumableEffectToEnemy(item: Consumable.ConsumableResource,
                                      _enemy: EnemyScene.Data, enemyId: Int32):
            Unit \ {World.Command, World.WorldQuery} =
        applyConsumableEffectDsl(item, enemyId, false)

    /// 薬の効果を味方へ。効果種別で 1 段マッチ。
    def throwConsumableAtPlayer(playerId: Int32, item: Consumable.ConsumableResource,
                                 targetId: Int32):
            Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery} =
        Option.getWithDefault((),
            forM (target <- PlayerScene.get(targetId)) yield {
                GameLogger.playerLog("${PlayerScene.displayName(playerId)} は ${PlayerScene.displayName(targetId)} に ${item#name} を当てた");
                applyConsumableEffectToPlayer(item, target, targetId)
            })

    /// 味方 1 体への薬効果適用 → DSL 経路へ委譲（数値・挙動は同一、ally=true）。
    def applyConsumableEffectToPlayer(item: Consumable.ConsumableResource,
                                       _target: PlayerScene.Data, targetId: Int32):
            Unit \ {World.Command, World.WorldQuery} =
        applyConsumableEffectDsl(item, targetId, true)

    /// 投げたアイテムを 1 個（耐久 1）消費する。種別ごとに対応リストへ反映。match ネストなし。
    def consumeThrownItem(playerId: Int32, kind: PlayerData.ItemKind):
            Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery} =
        match kind {
            case PlayerData.ItemKind.Consumable(idx) =>
                Option.getWithDefault((),
                    forM (c <- List.nth(idx, PlayerScene.getConsumables(playerId)))
                        yield consumeConsumable(playerId, idx, c))
            case PlayerData.ItemKind.Weapon(idx) =>
                PlayerScene.dropWeapon(playerId, idx)
            case PlayerData.ItemKind.Staff(idx) =>
                // 投げた杖は残り回数に関わらず消失する（武器投げ＝dropWeapon と対称）。
                // 詠唱(consumeStaff)は耐久 -1 だが、投擲は物理的に手放すので完全除去。
                // dropStaff が staves を World へ dual-write する（[STAVES DIFF] 無音維持）。
                PlayerScene.dropStaff(playerId, idx)
            case PlayerData.ItemKind.Ring(_) => ()
        }

    /// idx 番目を `updatedOpt` の中身で差し替えたリストを返す。
    /// `None`（耐久 0 で消滅）ならその要素を除去し、`Some` なら更新値で置換する。
    def replaceOrDropAt(idx: Int32, updatedOpt: Option[a], list: List[a]): List[a] =
        match updatedOpt {
            case Some(updated) =>
                List.mapWithIndex(i -> x -> if (i == idx) updated else x, list)
            case None =>
                dropAt(idx, list)
        }

    /// List から `idx` 番目を取り除く（範囲外なら元のリスト）。
    def dropAt(idx: Int32, list: List[a]): List[a] =
        List.zipWithIndex(list)
            |> List.filter(pair -> let (i, _) = pair; i != idx)
            |> List.map(pair -> let (_, x) = pair; x)
}
