/// StaffCastScene — 杖の発動と消費アイテムの使用（効果の適用層）
///
/// `PlayerScene` から「杖を撃つ / 消費アイテムを使う」という、盤面・敵・アニメ・ターン進行に
/// またがる適用ロジックを切り出したシーン補助モジュール。`PlayerScene` 本体は味方の状態所有と
/// 移動・選択・戦闘に専念し、ここは「選択中の杖/アイテムを実際に効かせる」段だけを担う。
///
/// 杖の発動の流れ（`applyStaffCast`）:
///   1. プレイヤーの `staves[staffIdx]` と `gridPos` / `magicAttack` を取り出す
///   2. `Board.rayCast` で射線上の最初の当たり対象を `RayHit` で得る
///   3. `staff#effect × hit` で効果を分岐適用（Heal / Blowback / Swap）
///   4. `Staff.consume` で耐久 -1、0 なら staves から除去 + 破損ログ
///   5. 選択中アイテムをクリア → `commitWaitedAndAdvance` で waited 確定し次ターンへ
/// 杖は CounterAttackRules を経由しない（反撃なし）。
///
/// `PlayerScene` と `EnemyScene` は `Data` / `get` / `mapXxx` / `snapTo` を**両方が**持つため、
/// このモジュールでは味方側を必ず `PlayerScene.`、敵側を `EnemyScene.` で完全修飾する。
/// 方向選択の純粋計算（`deltaToDirection` / `pickHealDirection`）は `Staff` モジュールに置く。
mod StaffCastScene {

    // ────────────────────────────────────────────────────────
    // 杖の発動 — direction → 直線レイキャスト → 効果適用 → ターン進行
    // ────────────────────────────────────────────────────────

    /// 杖を発動する。`StaffAim` フェーズで方向キーが押された瞬間に呼ばれる。
    /// 該当プレイヤー / 杖が見つからない場合は防御的に no-op。
    pub def applyStaffCast(playerId: Int32, staffIdx: Int32,
                             direction: Staff.Direction,
                             scene: Scene[NodeTag]):
            Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                BoardQuery, GameLogger.GameLogger,
                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State, GameEngine.Audio} =
        // プレイヤーと杖の両方が解決できたときだけ発動。どちらか欠ければ scene のまま。
        // ネストした match を避けるため Option を forM で短絡的に畳む。
        let cast = forM (
            player <- PlayerScene.get(playerId, scene);
            staff  <- List.nth(staffIdx, player#staves)
        ) yield fireStaff(playerId, staffIdx, player, staff, direction, scene);
        Option.getWithDefault(scene, cast)

    /// プレイヤーと杖が解決できたときの本体: レイキャスト → 命中音 → 効果適用 →
    /// 耐久消費 → 選択クリア → ターン進行。
    def fireStaff(playerId: Int32, staffIdx: Int32, player: PlayerScene.Data,
                   staff: Staff.StaffResource, direction: Staff.Direction,
                   scene: Scene[NodeTag]):
            Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                BoardQuery, GameLogger.GameLogger,
                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State, GameEngine.Audio} =
        let board = BoardQuery.board();
        let dir   = Staff.toVec2i(direction);
        // 杖は射程を持たない: 盤面外は壁扱いなので、十分大きい上限を渡せば
        // 必ず壁または駒で止まる（無限射程と等価）。
        let hit   = Board.rayCast(player#gridPos, dir, staffMaxRange(), board);
        playHitSound(staff#effect, hit);
        let afterEffect  = applyStaffEffect(playerId, player, staff, dir, hit, scene);
        let afterConsume = consumeStaff(playerId, staffIdx, staff, afterEffect);
        let cleared      = PlayerScene.clearSelectedItem(playerId, afterConsume);
        TurnFlow.commitWaitedAndAdvance(cleared)

    /// 回復の杖が味方/敵に当たった瞬間だけ回復音を鳴らす（空振りは鳴らさない）。
    /// Blowback / Swap は命中と移動が視覚的に自明なため効果音を持たない（現状 SE 未設定）。
    def playHitSound(effect: Staff.StaffEffect, hit: RayHit): Unit \ GameEngine.Audio =
        match (effect, hit) {
            case (Staff.StaffEffect.Heal, RayHit.HitPlayer(_, _)) => AudioStreamPlayer.play("cure")
            case (Staff.StaffEffect.Heal, RayHit.HitEnemy(_, _))  => AudioStreamPlayer.play("cure")
            case _                                                 => ()
        }

    /// 杖の射程上限。盤面の最大寸法より大きければ実質「無限」として機能する。
    def staffMaxRange(): Int32 = 1000

    /// 杖を構えるときの初期照準方向。選択中アイテムが回復の杖で、HP が減っている味方が
    /// 居れば、一番ふさわしい味方の方向(4方位)を返す。同じ行/列に並ぶ(=射線が届く)味方を
    /// 優先し、無ければ最も近い負傷味方の主軸方向を返す。
    /// 回復杖でない / 負傷味方が居ないなら None（呼び出し側はデフォルト Up のまま）。
    /// ネストした match を避けるため Option の forM で短絡的に畳む。
    pub def staffAimInitialDirection(playerId: Int32, scene: Scene[NodeTag]):
            Option[Staff.Direction] =
        forM (
            player <- PlayerScene.get(playerId, scene);
            idx    <- selectedStaffIndex(player);
            staff  <- List.nth(idx, player#staves);
            dir    <- healDirectionFor(player, playerId, staff, scene)
        ) yield dir

    /// 選択中アイテムが杖ならその staves index、それ以外は None。
    def selectedStaffIndex(player: PlayerScene.Data): Option[Int32] =
        match player#selectedItem {
            case Some(PlayerData.ItemKind.Staff(idx)) => Some(idx)
            case _                                      => None
        }

    /// 回復杖なら負傷味方への方向、それ以外（攻撃杖等）は None。
    /// 負傷味方の位置だけを `Staff.pickHealDirection` に渡す（純粋計算へ委譲）。
    def healDirectionFor(player: PlayerScene.Data, playerId: Int32, staff: Staff.StaffResource,
                          scene: Scene[NodeTag]): Option[Staff.Direction] =
        if (staff#effect == Staff.StaffEffect.Heal)
            Staff.pickHealDirection(player#gridPos,
                injuredAlliesExcept(playerId, scene) |> List.map(a -> a#gridPos))
        else None

    /// 自分以外で HP が最大未満（負傷している）の味方一覧。
    /// 自己を除外するのは、自己回復はメニューの「つかう → きずぐすり」で行う別フローだから。
    /// HP < maxHp を「負傷」と定義しており、最大 HP ちょうどの味方は照準候補に含めない。
    def injuredAlliesExcept(playerId: Int32, scene: Scene[NodeTag]): List[PlayerScene.Data] =
        PlayerScene.getAll(scene)
            |> List.filter(a -> a#id != playerId and a#hp < a#resource#hp)

    /// `staff#effect × hit` の組み合わせで効果を適用する。
    /// ヒット種は RayHit.HitPlayer / RayHit.HitEnemy / それ以外（壁・盤外 = 空振り）の 3 種で、
    /// 3 効果 × 3 ヒット種 = 9 通り。空振り（壁/盤外）は `_` arm でまとめてログを出す。
    def applyStaffEffect(playerId: Int32, player: PlayerScene.Data,
                          staff: Staff.StaffResource,
                          dir: {x = Int32, y = Int32},
                          hit: RayHit,
                          scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameLogger.GameLogger} =
        match (staff#effect, hit) {
            case (Staff.StaffEffect.Heal, RayHit.HitPlayer(targetId, _)) =>
                applyHealToPlayer(playerId, player, targetId, scene)
            case (Staff.StaffEffect.Heal, RayHit.HitEnemy(targetId, _)) =>
                applyHealToEnemy(playerId, player, targetId, scene)
            case (Staff.StaffEffect.Blowback, RayHit.HitPlayer(targetId, hitCell)) =>
                applyBlowbackToPlayer(playerId, targetId, hitCell, dir, scene)
            case (Staff.StaffEffect.Blowback, RayHit.HitEnemy(targetId, hitCell)) =>
                applyBlowbackToEnemy(playerId, targetId, hitCell, dir, scene)
            case (Staff.StaffEffect.Swap, RayHit.HitPlayer(otherId, otherCell)) =>
                applySwapWithPlayer(playerId, player#gridPos, otherId, otherCell, scene)
            case (Staff.StaffEffect.Swap, RayHit.HitEnemy(enemyId, enemyCell)) =>
                applySwapWithEnemy(playerId, player#gridPos, enemyId, enemyCell, scene)
            // 空振り系: 効果なし、ログだけ（実際の杖名を表示する）
            case (Staff.StaffEffect.Heal, _) =>
                GameLogger.playerLog("P${playerId} の ${staff#name} は届かなかった");
                scene
            case (Staff.StaffEffect.Blowback, _) =>
                GameLogger.playerLog("P${playerId} の ${staff#name} は届かなかった");
                scene
            case (Staff.StaffEffect.Swap, _) =>
                GameLogger.playerLog("P${playerId} の ${staff#name} は消えた");
                scene
        }

    /// Heal × 味方: 対象味方の HP を「魔力 + 10」回復、HPBar 更新、ログ。
    /// `applyStaffEffect` から呼ばれる内部処理だが、回復量の上限クランプを単体検証できる
    /// ように pub にしている（`TestStaffCastScene` 参照）。
    pub def applyHealToPlayer(srcId: Int32, player: PlayerScene.Data, targetId: Int32,
                           scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameLogger.GameLogger =
        let amount = player#resource#magicAttack + 10;
        match PlayerScene.get(targetId, scene) {
            case None         => scene
            case Some(target) =>
                let result = Combat.heal(target#hp, target#resource#hp, amount);
                let healed = result#newHp - target#hp;
                GameLogger.playerLog("P${srcId} → P${targetId} を ${healed}回復");
                scene
                    |> PlayerScene.mapPlayer(targetId, d -> {hp = result#newHp | d})
                    |> UnitHPBarScene.update(PlayerScene.playerPath(targetId), result#newHp)
        }

    /// Heal × 敵: 敵の HP を「魔力 + 10」回復（敵にも効く仕様）。
    def applyHealToEnemy(srcId: Int32, player: PlayerScene.Data, enemyId: Int32,
                          scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameLogger.GameLogger =
        let amount = player#resource#magicAttack + 10;
        match EnemyScene.get(enemyId, scene) {
            case None        => scene
            case Some(enemy) =>
                let result = Combat.heal(enemy#hp, enemy#resource#hp, amount);
                let healed = result#newHp - enemy#hp;
                GameLogger.playerLog("P${srcId} → 敵${enemyId} を ${healed}回復");
                scene
                    |> EnemyScene.mapEnemy(enemyId, d -> {hp = result#newHp | d})
                    |> UnitHPBarScene.update(EnemyScene.enemyPath(enemyId), result#newHp)
        }

    /// ふきとばし × 味方: 1 ダメ → 死亡なら止まる、生存なら最終位置までスナップで移動。
    /// 将来: sequence engine が揃えば 1 マスずつ tween に置換できる（現在は瞬間移動）。
    def applyBlowbackToPlayer(srcId: Int32, targetId: Int32,
                                hitCell: {x = Int32, y = Int32},
                                dir: {x = Int32, y = Int32},
                                scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, GameLogger.GameLogger} =
        match PlayerScene.get(targetId, scene) {
            case None         => scene
            case Some(target) =>
                let dmgResult = Combat.damage(hp = target#hp, amount = 1);
                let withDamage = scene
                    |> PlayerScene.mapPlayer(targetId, d -> {hp = dmgResult#newHp | d})
                    |> UnitHPBarScene.update(PlayerScene.playerPath(targetId), dmgResult#newHp);
                GameLogger.playerLog(
                    "P${srcId} → P${targetId} を ふきとばし (1ダメージ)");
                if (dmgResult#isDead) withDamage
                else applyBlowbackMove(targetId, hitCell, dir, withDamage,
                                        cell -> PlayerScene.snapTo(targetId, cell, withDamage))
        }

    /// ふきとばし × 敵: 1 ダメ → 死亡なら startDeathAnimation、生存なら最終位置に snapTo。
    def applyBlowbackToEnemy(srcId: Int32, enemyId: Int32,
                               hitCell: {x = Int32, y = Int32},
                               dir: {x = Int32, y = Int32},
                               scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                                GameLogger.GameLogger} =
        match EnemyScene.get(enemyId, scene) {
            case None        => scene
            case Some(enemy) =>
                let dmgResult = Combat.damage(hp = enemy#hp, amount = 1);
                if (dmgResult#isDead) {
                    GameLogger.playerLog("P${srcId} → 敵${enemyId} を ふきとばし撃破");
                    scene
                        |> UnitHPBarScene.update(EnemyScene.enemyPath(enemyId), 0)
                        |> EnemyScene.startDeathAnimation(enemyId)
                } else {
                    let withDamage = scene
                        |> EnemyScene.mapEnemy(enemyId, d -> {hp = dmgResult#newHp | d})
                        |> UnitHPBarScene.update(EnemyScene.enemyPath(enemyId), dmgResult#newHp);
                    GameLogger.playerLog(
                        "P${srcId} → 敵${enemyId} を ふきとばし (1ダメージ)");
                    applyBlowbackMove(enemyId, hitCell, dir, withDamage,
                                       cell -> EnemyScene.snapTo(enemyId, cell, withDamage))
                }
        }

    /// 押される対象の最終位置を `Board.knockbackPath` で計算し、`moveFn` で動かす。
    /// 経路が空（押される先がない）なら何もしない。
    def applyBlowbackMove(_targetId: Int32,
                           hitCell: {x = Int32, y = Int32},
                           dir: {x = Int32, y = Int32},
                           scene: Scene[NodeTag],
                           moveFn: {x = Int32, y = Int32} -> Scene[NodeTag] \ Tween.Scheduler):
            Scene[NodeTag] \ Tween.Scheduler =
        let board: Board = BoardSnapshot.fromScene(scene);
        let path = Board.knockbackPath(hitCell, dir, board);
        match List.last(path) {
            case None       => scene
            case Some(last) => moveFn(last)
        }

    /// いれかえ × 味方: 自分と相手の gridPos を瞬間 swap する。
    /// 将来: sequence engine が揃えば交差するアニメーションに置換できる（現在は瞬間移動）。
    def applySwapWithPlayer(srcId: Int32, srcCell: {x = Int32, y = Int32},
                              otherId: Int32, otherCell: {x = Int32, y = Int32},
                              scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, GameLogger.GameLogger} =
        GameLogger.playerLog("P${srcId} と P${otherId} がいれかわった");
        scene
            |> PlayerScene.snapTo(srcId, otherCell)
            |> PlayerScene.snapTo(otherId, srcCell)

    /// いれかえ × 敵: 自分（Player）と敵を交換する。
    /// 将来: sequence engine が揃えば交差するアニメーションに置換できる（現在は瞬間移動）。
    def applySwapWithEnemy(srcId: Int32, srcCell: {x = Int32, y = Int32},
                             enemyId: Int32, enemyCell: {x = Int32, y = Int32},
                             scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, GameLogger.GameLogger} =
        GameLogger.playerLog("P${srcId} と 敵${enemyId} がいれかわった");
        scene
            |> PlayerScene.snapTo(srcId, enemyCell)
            |> EnemyScene.snapTo(enemyId, srcCell)

    /// 杖の耐久を 1 減らし、0 なら staves から除去 + 破損ログ。
    def consumeStaff(playerId: Int32, staffIdx: Int32, staff: Staff.StaffResource,
                       scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameLogger.GameLogger =
        let consumed = Staff.consume(staff);
        let newStaves = replaceOrDropAt(staffIdx, consumed, PlayerScene.getStaves(playerId, scene));
        if (Option.isEmpty(consumed))
            GameLogger.playerLog("P${playerId} の ${staff#name} がこわれた")
        else ();
        PlayerScene.mapPlayer(playerId, d -> {staves = newStaves | d}, scene)

    // ────────────────────────────────────────────────────────
    // 消費アイテム（きずぐすり等）の使用
    // ────────────────────────────────────────────────────────

    /// 消費アイテム（きずぐすり等）を「つかう」: 使用者自身を回復し、耐久を 1 減らして
    /// 0 なら一覧から除去、選択クリア → ターン消費して次へ進む。杖と違い方向・対象選択は無いので
    /// `StaffAim` のような中間フェーズは経由せず、メニュー確定経路でそのまま完結する。
    /// 該当プレイヤー / アイテムが見つからない場合は防御的に no-op。
    pub def applyConsumableUse(playerId: Int32, idx: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler, GameLogger.GameLogger,
                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State, GameEngine.Audio} =
        // プレイヤーと消費アイテムの両方が解決できたときだけ使用。欠ければ scene のまま。
        // forM による短絡は applyStaffCast と同様。
        let used = forM (
            player <- PlayerScene.get(playerId, scene);
            item   <- List.nth(idx, player#consumables)
        ) yield useConsumable(playerId, idx, player, item, scene);
        Option.getWithDefault(scene, used)

    /// プレイヤーと消費アイテムが解決できたときの本体: 使用音 → 回復 → 耐久消費 →
    /// 選択クリア → ターン進行。
    def useConsumable(playerId: Int32, idx: Int32, player: PlayerScene.Data,
                       item: Consumable.ConsumableResource, scene: Scene[NodeTag]):
            Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler, GameLogger.GameLogger,
                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State, GameEngine.Audio} =
        // 消費アイテムは使う時点で効果が自己確定するため、杖の空振り判定とは異なり無条件で使用音を鳴らす
        AudioStreamPlayer.play("cure");
        let afterEffect  = applyConsumableSelfEffect(playerId, player, item, scene);
        let afterConsume = consumeConsumable(playerId, idx, item, afterEffect);
        let cleared      = PlayerScene.clearSelectedItem(playerId, afterConsume);
        TurnFlow.commitWaitedAndAdvance(cleared)

    /// 自己使用（SelfUse）の効果を種類で分岐適用する。投擲（Directional）・自動（AutoOnDeath）が
    /// 万一ここへ来たら no-op + ログで防御する（`deliveryFor` の取りこぼしでも panic させない）。
    /// 各 arm は小さな関数に切り出し、1 関数へ多ステートを詰め込まない（Flix 推論の安定のため）。
    def applyConsumableSelfEffect(playerId: Int32, player: PlayerScene.Data,
                                   item: Consumable.ConsumableResource,
                                   scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameLogger.GameLogger =
        match item#effect {
            case Consumable.ConsumableEffect.Heal     =>
                applyConsumableHeal(playerId, player, item, scene)
            case Consumable.ConsumableEffect.FullHeal =>
                applyFullHeal(playerId, player, item, scene)
            case Consumable.ConsumableEffect.MaxHpUp  =>
                applyMaxHpUp(playerId, player, item, scene)
            case Consumable.ConsumableEffect.AtkUp    =>
                applySelfStatus(playerId, item, StatusSystem.StatusEffect.AtkUp, scene)
            case Consumable.ConsumableEffect.SpdUp    =>
                applySelfStatus(playerId, item, StatusSystem.StatusEffect.SpdUp, scene)
            case _                                    =>
                GameLogger.playerLog("P${playerId} の ${item#name} は ここでは使えなかった");
                scene
        }

    /// 消費アイテムで使用者自身の HP を `magnitude` 回復、HPBar 更新、ログ。
    /// `applyConsumableSelfEffect` から呼ばれる内部処理だが、回復量を単体検証できるように
    /// pub にしている（`TestStaffCastScene` 参照）。
    pub def applyConsumableHeal(playerId: Int32, player: PlayerScene.Data,
                             item: Consumable.ConsumableResource,
                             scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameLogger.GameLogger =
        let result = Combat.heal(player#hp, player#resource#hp, item#magnitude);
        let healed = result#newHp - player#hp;
        GameLogger.playerLog("P${playerId} は ${item#name} で ${healed}回復");
        scene
            |> PlayerScene.mapPlayer(playerId, d -> {hp = result#newHp | d})
            |> UnitHPBarScene.update(PlayerScene.playerPath(playerId), result#newHp)

    /// 全快薬: HP を最大まで戻す。`magnitude` は不使用。
    pub def applyFullHeal(playerId: Int32, player: PlayerScene.Data,
                           item: Consumable.ConsumableResource,
                           scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameLogger.GameLogger =
        let maxHp  = player#resource#hp;
        let healed = maxHp - player#hp;
        GameLogger.playerLog("P${playerId} は ${item#name} で ${healed}回復");
        scene
            |> PlayerScene.mapPlayer(playerId, d -> {hp = maxHp | d})
            |> UnitHPBarScene.update(PlayerScene.playerPath(playerId), maxHp)

    /// 命の草: 最大 HP を `magnitude` 永続上昇させ、現在 HP も同量上げる（その場で増えた分が回復）。
    pub def applyMaxHpUp(playerId: Int32, player: PlayerScene.Data,
                          item: Consumable.ConsumableResource,
                          scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameLogger.GameLogger =
        let inc    = item#magnitude;
        let newMax = player#resource#hp + inc;
        let newHp  = player#hp + inc;
        GameLogger.playerLog("P${playerId} は ${item#name} で 最大HP+${inc}");
        scene
            |> PlayerScene.mapPlayer(playerId,
                d -> {hp = newHp, resource = {hp = newMax | d#resource} | d})
            |> UnitHPBarScene.updateMaxHp(PlayerScene.playerPath(playerId), newHp, newMax)

    /// ちから薬 / すばやさ薬: 使用者へ時限バフ（`magnitude` を `duration` ターン）を付与する。
    /// `kind` は付与する `StatusEffect`（AtkUp / SpdUp）。効果は次の戦闘予測・実戦闘に反映される。
    def applySelfStatus(playerId: Int32, item: Consumable.ConsumableResource,
                         kind: StatusSystem.StatusEffect, scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameLogger.GameLogger =
        let status = {effect = kind, magnitude = item#magnitude, remaining = item#duration};
        GameLogger.playerLog("P${playerId} は ${item#name} を使った (${item#duration}ターン)");
        PlayerScene.mapPlayer(playerId,
            d -> {statuses = StatusSystem.add(status, d#statuses) | d}, scene)

    /// 消費アイテムの耐久（使用回数）を 1 減らし、0 なら consumables から除去 + 使い切りログ。
    /// `consumeStaff` と構造は同じだが、型が `Consumable.ConsumableResource` のため共通化できない。
    def consumeConsumable(playerId: Int32, idx: Int32,
                           item: Consumable.ConsumableResource,
                           scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameLogger.GameLogger =
        let consumed = Consumable.consume(item);
        let newConsumables = replaceOrDropAt(idx, consumed, PlayerScene.getConsumables(playerId, scene));
        if (Option.isEmpty(consumed))
            GameLogger.playerLog("P${playerId} の ${item#name} を使い切った")
        else ();
        PlayerScene.mapPlayer(playerId, d -> {consumables = newConsumables | d}, scene)

    // ────────────────────────────────────────────────────────
    // 投擲系（Directional）消費アイテム — 目潰し薬 / 鈍足薬
    //   杖と同じく方向を選んで直線に飛ばし、最初に当たったキャラへ時限デバフを付与する。
    //   `StaffAim` フェーズを杖と共用し、`Game.staffAimConfirm` から呼ばれる。
    // ────────────────────────────────────────────────────────

    /// 投擲系消費アイテムを発動する。`StaffAim` フェーズで Z 確定時に方向付きで呼ばれる。
    /// 該当プレイヤー / アイテムが見つからなければ防御的に no-op。
    pub def applyConsumableDirectional(playerId: Int32, idx: Int32,
                                        direction: Staff.Direction,
                                        scene: Scene[NodeTag]):
            Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                BoardQuery, GameLogger.GameLogger,
                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State} =
        let cast = forM (
            player <- PlayerScene.get(playerId, scene);
            item   <- List.nth(idx, player#consumables)
        ) yield fireConsumable(playerId, idx, player, item, direction, scene);
        Option.getWithDefault(scene, cast)

    /// 投擲系の本体: レイキャスト → 当たり対象へデバフ付与 → 耐久消費 → 選択クリア → ターン進行。
    /// 杖の `fireStaff` と同構造（方向投擲を間借りする）。
    def fireConsumable(playerId: Int32, idx: Int32, player: PlayerScene.Data,
                        item: Consumable.ConsumableResource, direction: Staff.Direction,
                        scene: Scene[NodeTag]):
            Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                BoardQuery, GameLogger.GameLogger,
                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State} =
        let board = BoardQuery.board();
        let dir   = Staff.toVec2i(direction);
        let hit   = Board.rayCast(player#gridPos, dir, staffMaxRange(), board);
        let afterEffect  = applyDirectionalEffect(playerId, item, hit, scene);
        let afterConsume = consumeConsumable(playerId, idx, item, afterEffect);
        let cleared      = PlayerScene.clearSelectedItem(playerId, afterConsume);
        TurnFlow.commitWaitedAndAdvance(cleared)

    /// 当たった対象（敵 / 味方）へ時限デバフを付与する。空振りはログのみ。
    /// 効果が投擲系でない（誤用）場合も `directionalStatus` が None を返して不発ログにする。
    /// `applyStaffEffect` と同じく `(付与する Status, hit)` のタプルで 1 段マッチに畳む。
    def applyDirectionalEffect(playerId: Int32, item: Consumable.ConsumableResource,
                                hit: RayHit, scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameLogger.GameLogger =
        match (directionalStatus(item), hit) {
            case (Some(status), RayHit.HitEnemy(enemyId, _))   =>
                GameLogger.playerLog("P${playerId} は 敵${enemyId} に ${item#name} を当てた");
                EnemyScene.mapEnemy(enemyId,
                    d -> {statuses = StatusSystem.add(status, d#statuses) | d}, scene)
            case (Some(status), RayHit.HitPlayer(targetId, _)) =>
                GameLogger.playerLog("P${playerId} は P${targetId} に ${item#name} を当てた");
                PlayerScene.mapPlayer(targetId,
                    d -> {statuses = StatusSystem.add(status, d#statuses) | d}, scene)
            // 効果が投擲系でない（None）→ 不発。投擲系だが壁/盤外に消えた → 届かなかった。
            case (None, _)                                     =>
                GameLogger.playerLog("P${playerId} の ${item#name} は不発に終わった");
                scene
            case (Some(_), _)                                  =>
                GameLogger.playerLog("P${playerId} の ${item#name} は届かなかった");
                scene
        }

    /// 投擲系アイテムが付与する時限デバフ Status を作る。投擲系でなければ None。
    def directionalStatus(item: Consumable.ConsumableResource): Option[StatusSystem.Status] =
        match item#effect {
            case Consumable.ConsumableEffect.BlindHit   =>
                Some({effect = StatusSystem.StatusEffect.HitDown,
                      magnitude = item#magnitude, remaining = item#duration})
            case Consumable.ConsumableEffect.SpdDownHit =>
                Some({effect = StatusSystem.StatusEffect.SpdDown,
                      magnitude = item#magnitude, remaining = item#duration})
            case _                                      => None
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
