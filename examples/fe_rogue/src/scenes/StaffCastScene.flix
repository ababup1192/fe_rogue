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
        // 消費アイテムは使う時点で効果が自己確定するため、杖の空振り判定とは異なり無条件で回復音を鳴らす
        AudioStreamPlayer.play("cure");
        let afterHeal    = applyConsumableHeal(playerId, player, item, scene);
        let afterConsume = consumeConsumable(playerId, idx, item, afterHeal);
        let cleared      = PlayerScene.clearSelectedItem(playerId, afterConsume);
        TurnFlow.commitWaitedAndAdvance(cleared)

    /// 消費アイテムで使用者自身の HP を `healAmount` 回復、HPBar 更新、ログ。
    /// `applyConsumableUse` から呼ばれる内部処理だが、回復量を単体検証できるように
    /// pub にしている（`TestStaffCastScene` 参照）。
    pub def applyConsumableHeal(playerId: Int32, player: PlayerScene.Data,
                             item: Consumable.ConsumableResource,
                             scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameLogger.GameLogger =
        let result = Combat.heal(player#hp, player#resource#hp, item#healAmount);
        let healed = result#newHp - player#hp;
        GameLogger.playerLog("P${playerId} は ${item#name} で ${healed}回復");
        scene
            |> PlayerScene.mapPlayer(playerId, d -> {hp = result#newHp | d})
            |> UnitHPBarScene.update(PlayerScene.playerPath(playerId), result#newHp)

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
