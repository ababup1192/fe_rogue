/// PlayerCombatScene — 味方の体当たり攻撃・ダメージ・経験値の解決
///
/// `PlayerScene` から「攻撃モーション → 命中判定 → ダメージ → 経験値 → レベルアップ」という
/// 一連の戦闘ロジックを切り出したシーン補助モジュール。`PlayerScene` 本体は味方の状態所有・
/// 移動・選択・インベントリに専念し、ここは攻撃の解決だけを担う。
///
/// 攻撃の流れ:
///   1. `startAttack` で `attack_lunge` アニメを登録し `attackTargetId` を立てる
///   2. アニメ中点の `attack:hit` メソッドで `onAttackHit` → `applyAttackHit` → `applyDamageToEnemy`
///      （命中ロール → ダメージ/EXP → レベルアップ）
///   3. アニメ終端の finished で `onAttackLungeDone` → 撃破/反撃/確定を `CounterAttackRules` で分岐
///
/// `process` のシグナル配信（`PlayerScene.process`）から `onAttackHit`/`onAttackLungeDone` が
/// 委譲呼び出しされる。`PlayerScene` と `EnemyScene` は `Data`/`get`/`mapXxx` を**両方が**持つため、
/// 味方側は `PlayerScene.`、敵側は `EnemyScene.` で完全修飾する（`use` は開かない）。
///
/// 注意（意図的な責務越境）: `onAttackLungeDone` は「攻撃完了 → 次ターン進行判断」の orchestrator
/// で、`PlayerScene.commitWaitedAndAdvance`（汎用ターン進行・残置）/ `EnemyScene.startAttack`（反撃）/
/// `PhaseTransitions` を跨ぐ。これは `EnemyScene`(:610) も `commitWaitedAndAdvance` を呼ぶ確立パターンと
/// 同種で、攻撃の完了がそのままターン遷移のトリガになるための設計。
mod PlayerCombatScene {

    // ────────────────────────────────────────────────────────
    // 攻撃ターゲットの記録 / クリア
    // ────────────────────────────────────────────────────────

    /// 攻撃ターゲットの敵 id を Data#attackTargetId に記録する。
    /// 武器選択ウィンドウを開く前に GameManager から呼ばれ、ウィンドウ確定後の
    /// フェーズが AttackForecast に進み、`BattlePanelScene.confirm` がこの値を読んで
    /// 実際の攻撃モーションを開始する。
    pub def setAttackTargetId(playerId: Int32, targetEnemyId: Int32,
                                scene: Scene[NodeTag]): Scene[NodeTag] =
        PlayerScene.mapPlayer(playerId, d -> {attackTargetId = Some(targetEnemyId) | d}, scene)

    /// `attackTargetId` をクリアする（武器選択をキャンセルしたとき等）。
    pub def clearAttackTargetId(playerId: Int32,
                                  scene: Scene[NodeTag]): Scene[NodeTag] =
        PlayerScene.mapPlayer(playerId, d -> {attackTargetId = None | d}, scene)

    // ────────────────────────────────────────────────────────
    // 体当たり攻撃モーション — AnimationPlayer ベース
    // ────────────────────────────────────────────────────────

    /// 体当たりの片道（origin → target）所要時間。Forward + Returning の合計が
    /// アニメ全長になる。視認性を保つため移動 (16/120) より速めに設定する。
    def attackPhaseDuration(): Duration.Duration =
        Duration.frames(count = 16, fps = 200)   // ≈ 0.08 秒 / 片道

    /// `attack_lunge` アニメーション。
    /// - position track: origin → target → origin の 3 keyframe
    /// - method "attack:hit": 中点（target に重なる瞬間）で発火 → ダメージ適用 + SE 再生
    /// - finished: 攻撃モーション終了 → GameManager が waited 確定 / 次状態へ
    ///
    /// `targetPath` は攻撃側マーカー（PlayerScene なら `playerPath(id)`）。
    /// アニメ全長は 2 phase 分で、method "attack:hit" は phase 1 つぶん経過した時点
    /// （正規化 t = 0.5）で発火する。
    pub def attackLungeAnimation(targetPath: NodePath,
                                  originGrid: {x = Int32, y = Int32},
                                  targetGrid: {x = Int32, y = Int32}):
                                 AnimationPlayer.Animation =
        let phase    = attackPhaseDuration();
        let total    = Duration.add(phase, phase);
        let originW  = MapScene.cellCenter(originGrid);
        let targetW  = MapScene.cellCenter(targetGrid);
        let posKeys: List[AnimationPlayer.PosKey] =
            ({time = 0.0, pos = originW}: AnimationPlayer.PosKey) ::
            ({time = 0.5, pos = targetW}: AnimationPlayer.PosKey) ::
            ({time = 1.0, pos = originW}: AnimationPlayer.PosKey) ::
            Nil;
        let track: AnimationPlayer.Track = {
            target = targetPath,
            prop   = AnimationPlayer.Property.Position(posKeys)
        };
        let methodHit: AnimationPlayer.MethodKey = {
            time = phase,
            name = AnimEvent.tagToString(AnimEvent.Tag.AttackHit)
        };
        {
            name    = AnimEvent.tagToString(AnimEvent.Tag.AttackLunge),
            length  = total,
            tracks  = track :: Nil,
            methods = methodHit :: Nil
        }

    /// プレイヤー id の体当たり攻撃モーションを開始する。
    /// AnimationPlayer に `attack_lunge` を登録し、`attackTargetId = Some(targetEnemyId)` を
    /// 立てるだけ。中点で `attack:hit` メソッド、終端で finished が GameManager に届き、
    /// それぞれダメージ適用と waited 確定が行われる。
    /// インベントリが空（`weapons = Nil`）のプレイヤーは攻撃に到達してはいけない設計で、
    /// 防御的に no-op する（呼び出し側 = PlayerAttackRangeScene/TurnRules で禁止される）。
    pub def startAttack(id: Int32, targetEnemyId: Int32,
                         targetGrid: {x = Int32, y = Int32},
                         scene: Scene[NodeTag]): Scene[NodeTag]
            \ AnimationPlayer.Scheduler =
        match PlayerScene.get(id, scene) {
            case None    => scene
            case Some(d) =>
                if (List.isEmpty(d#weapons)) scene
                else {
                    AnimationPlayer.play(PlayerScene.playerPath(id),
                        attackLungeAnimation(PlayerScene.playerPath(id), d#gridPos, targetGrid));
                    PlayerScene.mapPlayer(id, dd -> {attackTargetId = Some(targetEnemyId) | dd}, scene)
                }
        }

    /// scene 内に攻撃モーション中のプレイヤーが居れば true。
    /// stepEnemyTurn 等の「敵の行動を進めて良いか」のガードに使う将来用の保険。
    pub def anyAttacking(scene: Scene[NodeTag]): Bool =
        List.exists(d -> Option.nonEmpty(d#attackTargetId), PlayerScene.getAll(scene))

    /// `attack:hit` メソッド発火時に GameManager から呼ばれるダメージ適用。
    /// 当該 player の `attackTargetId` を読み、対応する敵への攻撃を解決する。
    /// 命中ロールは `applyDamageToEnemy` 側で行い、命中なら SE + ダメージ + ログ、
    /// 回避なら SE を鳴らさず "miss" 表示のみ。HP <= 0 なら death_blink を開始する。
    pub def applyAttackHit(playerId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameEngine.Audio,
                              GameEngine.Game,
                              GameLogger.GameLogger, Math.Random} =
        match PlayerScene.get(playerId, scene) {
            case None    => scene
            case Some(d) =>
                match d#attackTargetId {
                    case None         => scene
                    case Some(enemyId) =>
                        applyDamageToEnemy(playerId, d, enemyId, scene)
                }
        }

    /// `attack_lunge` finished 時に GameManager から呼ばれる。
    /// `attackTargetId` をクリアする。waited 確定 / 次フェーズへの遷移は GameManager の
    /// `commitWaitedAndAdvance` が担当する。
    pub def clearAttackTarget(playerId: Int32,
                               scene: Scene[NodeTag]): Scene[NodeTag] =
        PlayerScene.mapPlayer(playerId, d -> {attackTargetId = None | d}, scene)

    /// AnimationPlayer の `attack:hit` method イベント受信時の処理 (味方側)。
    /// 攻撃ダメージ適用本体は既存 `applyAttackHit` を呼ぶ。
    /// 名前は「event 受信」の semantics を明示するための薄ラッパ。
    pub def onAttackHit(playerId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameEngine.Audio,
                              GameEngine.Game, GameLogger.GameLogger, Math.Random} =
        applyAttackHit(playerId, scene)

    /// AnimationPlayer の `attack_lunge` finished イベント受信時の処理 (味方側)。
    /// 2 通りある:
    ///   - `PlayerAttackHold` (= 味方主攻撃の完了) → CounterAttackRules.decide で分岐:
    ///       Kill (敵瀕死) / Counter (敵反撃) / Commit (waited 確定)。
    ///   - `EnemyTurn` (= 敵攻撃に対する味方反撃の完了) → 単純に attackTargetId クリア。
    ///       次フレーム以降で EnemyTurnDriver が PlayerCombatScene.anyAttacking が false に
    ///       なったのを見て次の step に進む。FE 風で「反撃の反撃」は実装しない。
    pub def onAttackLungeDone(playerId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameLogger.GameLogger,
                              EnemyTurn.Queue, TurnPhase.State,
                              SelectedPlayer.State, Pacing.State} =
        if (TurnPhase.State.get() == TurnPhase.Phase.EnemyTurn) {
            // 敵ターン中の味方反撃が完了した。反撃でレベルアップしていれば、その場で
            // （反撃ごとに）ステータス変化パネルへ割り込む。閉じると敵ターンに戻って続行する。
            let cleared = clearAttackTarget(playerId, scene);
            if (PlayerScene.anyPendingLevelUp(cleared))
                PhaseTransitions.enterLevelUpView(cleared)
            else
                cleared
        } else match PlayerScene.get(playerId, scene) {
            case None         => scene
            case Some(player) =>
                let target = player#attackTargetId
                    |> Option.flatMap(eid -> EnemyScene.get(eid, scene));
                match CounterAttackRules.decide(player, target) {
                    case CounterAttackRules.Outcome.Kill =>
                        let cleared = clearAttackTarget(playerId, scene);
                        TurnPhase.State.put(TurnPhase.Phase.PlayerAttackHold);
                        Pacing.State.hold(700 |> Duration.millis);
                        cleared
                    case CounterAttackRules.Outcome.Counter(enemyId) =>
                        let cleared = clearAttackTarget(playerId, scene);
                        match PlayerScene.get(playerId, cleared) {
                            case None    => PlayerScene.commitWaitedAndAdvance(cleared)
                            case Some(p) =>
                                GameLogger.enemyLog("敵${enemyId} の反撃");
                                EnemyScene.startAttack(enemyId, playerId, p#gridPos, cleared)
                        }
                    case CounterAttackRules.Outcome.Commit =>
                        let cleared = clearAttackTarget(playerId, scene);
                        PlayerScene.commitWaitedAndAdvance(cleared)
                }
        }

    // ────────────────────────────────────────────────────────
    // ダメージ・経験値の解決
    // ────────────────────────────────────────────────────────

    /// 命中ロール用の 0..99 の一様乱数。`Combat.isHit(hitRate, roll)` に渡す。
    def rollPercent(): Int32 \ Math.Random =
        Float64.truncateToInt32(Float64.floor(Math.Random.randomFloat64() * 100.0))

    /// 攻撃 1 回の純粋な算出結果（命中率・与ダメージ・撃破後 HP・撃破か・経験値）。
    /// 乱数も Scene も使わないので、これ単体で命中率やダメージ式をテストできる。
    pub type alias AttackForecast = {
        hitRate = Int32,   // 命中率 0..100（命中ロールと比較する）
        dmg     = Int32,   // 命中時の与ダメージ
        newHp   = Int32,   // 命中後の敵 HP（0 以上）
        killed  = Bool,    // この命中で敵を撃破するか
        exp     = Int32    // 命中で得る経験値
    }

    /// 装備武器と敵から、命中率・与ダメージ・経験値を**純粋に**算出する（乱数・Scene 非依存）。
    /// 武器タイプ習熟（苦手なら威力・命中 80%）と武器相性を 1 か所で解決し、命中判定と
    /// ダメージ計算に同じ補正を効かせる（戦闘予報と実ダメージを一致させる）。
    /// 敵が武器未装備なら相性は中立。テストしやすいよう pub。
    pub def attackForecast(player: PlayerScene.Data, weapon: UnitCatalog.WeaponResource,
                            enemy: EnemyScene.Data): AttackForecast =
        let phys        = UnitCatalog.isPhysical(weapon#weaponType);
        let proficient  = UnitCatalog.proficientWith(player#resource, weapon#weaponType);
        let totalAttack = Combat.attackStatFor(player#resource#attack,
                                               player#resource#magicAttack, weapon#attack, phys);
        let (adjAttack, adjHit) = Combat.proficiencyAdjust(totalAttack, weapon#hit, proficient);
        let rel       = WeaponTriangle.relationOpt(weapon#weaponType,
                                                   enemy#weapon |> Option.map(w -> w#weaponType));
        let hitRate   = Combat.hitRate(player#resource#skill, player#resource#luck, adjHit,
                                       enemy#resource#speed, enemy#resource#luck, rel);
        let targetDef = Combat.defenseStatFor(enemy#resource#defense, enemy#resource#magicDefense, phys);
        let dmg       = Combat.attackDamage(adjAttack, targetDef, rel);
        let result    = Combat.damage(hp = enemy#hp, amount = dmg);
        {hitRate = hitRate, dmg = dmg, newHp = result#newHp, killed = result#isDead,
         exp = Combat.battleExp(enemy#resource#level, player#level, result#isDead)}

    /// 敵 id にダメージを与える。装備武器（`weapons.head`）と敵が揃っていなければ no-op。
    /// 実体は `resolveAttack`。ここは前提（武器あり・敵あり）の解決だけを担い、
    /// ネストを避けるため Option を `forM` で短絡的に畳む。
    def applyDamageToEnemy(playerId: Int32, player: PlayerScene.Data, enemyId: Int32,
                            scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameEngine.Audio,
                               GameEngine.Game, GameLogger.GameLogger, Math.Random} =
        // 常に先頭武器（= 装備中）を使う。
        let resolved = forM (
            weapon <- List.nth(0, player#weapons);
            enemy  <- EnemyScene.get(enemyId, scene)
        ) yield resolveAttack(playerId, player, weapon, enemy, enemyId, scene);
        Option.getWithDefault(scene, resolved)

    /// 装備武器と敵が揃ったときの攻撃解決の流れ:
    ///   命中率を算出 → 乱数ロール → 命中なら `applyHit` / 回避なら `applyMiss`
    ///   → 武器の耐久を 1 減らす → 命中していれば経験値を加算。
    def resolveAttack(playerId: Int32, player: PlayerScene.Data,
                       weapon: UnitCatalog.WeaponResource, enemy: EnemyScene.Data,
                       enemyId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameEngine.Audio,
                               GameEngine.Game, GameLogger.GameLogger, Math.Random} =
        let plan       = attackForecast(player, weapon, enemy);
        let popupPos   = MapScene.cellCenter(enemy#gridPos);
        let popupColor = DamagePopupScene.damageToEnemyColor();
        // 命中なら経験値を得る（回避時は 0）。
        let (afterDamage, expGain) =
            if (Combat.isHit(plan#hitRate, rollPercent()))
                (applyHit(playerId, enemyId, plan, popupPos, popupColor, scene), plan#exp)
            else
                (applyMiss(playerId, enemyId, popupPos, popupColor, scene), 0);
        let afterWeapon = consumeEquippedWeapon(playerId, weapon, afterDamage);
        // 命中していれば EXP を加算する。自分の攻撃でも敵ターンの反撃でも同様（FE 流）。
        // 反撃で得たレベルアップは敵ターン終了後にまとめて表示する。
        if (expGain <= 0) afterWeapon
        else applyExpGain(playerId, expGain, afterWeapon)

    /// 回避: miss SE を鳴らし "miss" を浮かす。HP も死亡演出も変えない。
    def applyMiss(playerId: Int32, enemyId: Int32, popupPos: Vec2.Vec2, color: Color,
                   scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameEngine.Audio, GameEngine.Game, GameLogger.GameLogger} =
        GameLogger.playerLog("P${playerId} → 敵${enemyId} ミス");
        AudioStreamPlayer.play("miss");
        DamagePopupScene.emitText(popupPos, "miss", color, scene)

    /// 命中: damage SE を鳴らしダメージを適用。撃破なら死亡演出、生存なら敵 HP を更新。
    /// どちらでも与ダメージの数値ポップアップを浮かす。
    def applyHit(playerId: Int32, enemyId: Int32, plan: AttackForecast,
                  popupPos: Vec2.Vec2, color: Color, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameEngine.Audio,
                               GameEngine.Game, GameLogger.GameLogger} =
        AudioStreamPlayer.play("damage");
        let withPopup = DamagePopupScene.emit(popupPos, plan#dmg, color, scene);
        if (plan#killed) {
            GameLogger.playerLog("P${playerId} → 敵${enemyId} を撃破");
            withPopup
                |> UnitHPBarScene.update(EnemyScene.enemyPath(enemyId), plan#newHp)
                |> EnemyScene.startDeathAnimation(enemyId)
        } else {
            GameLogger.playerLog("P${playerId} → 敵${enemyId} に ${plan#dmg}ダメージ");
            withPopup
                |> EnemyScene.mapEnemy(enemyId, enemyData -> {hp = plan#newHp | enemyData})
                |> UnitHPBarScene.update(EnemyScene.enemyPath(enemyId), plan#newHp)
        }

    /// 攻撃したので装備武器（先頭）の耐久を 1 減らす。0 になったら先頭を取り除き破損ログを出す。
    def consumeEquippedWeapon(playerId: Int32, weapon: UnitCatalog.WeaponResource,
                               scene: Scene[NodeTag]): Scene[NodeTag] \ GameLogger.GameLogger =
        let consumed = Weapon.consume(weapon);
        if (Option.isEmpty(consumed))
            GameLogger.playerLog("P${playerId} の ${weapon#name} がこわれた")
        else ();
        PlayerScene.mapPlayer(playerId,
            d -> {weapons = replaceOrDropHead(consumed, d#weapons) | d}, scene)

    /// 先頭要素を `updated` の中身で差し替える。`None`（耐久 0 で破損）なら先頭を取り除く。
    def replaceOrDropHead(updated: Option[a], list: List[a]): List[a] =
        match (updated, list) {
            case (Some(w), _ :: rest) => w :: rest
            case (None,    _ :: rest) => rest
            case (_,       Nil)       => list
        }

    /// 6 ステータスぶんの成長判定用乱数 (各 0..99) をまとめて振る。
    /// 値の意味づけ・成長判定は LevelSystem 側のピュア関数が行う。
    def rollGrowth(): LevelSystem.Rolls \ Math.Random =
        {hp           = rollPercent(),
         attack       = rollPercent(),
         defense      = rollPercent(),
         magicAttack  = rollPercent(),
         magicDefense = rollPercent(),
         speed        = rollPercent(),
         skill        = rollPercent(),
         luck         = rollPercent()}

    /// 味方 id に EXP を加算し、100 到達ならレベルアップを解決する。
    ///   - レベルアップしない → `exp` だけ更新。
    ///   - レベルアップする   → 成長ロールを振って各ステータスを成長させ、最大 HP が
    ///     増えた分だけ現在 HP も増やし、`pendingLevelUp` に結果を積む（パネル表示の合図）。
    /// `pendingLevelUp` が立つと commitWaitedAndAdvance がターンを進めずパネルへ割り込む。
    def applyExpGain(playerId: Int32, expGain: Int32,
                      scene: Scene[NodeTag]): Scene[NodeTag] \ {Math.Random, GameLogger.GameLogger} =
        match PlayerScene.get(playerId, scene) {
            case None    => scene
            case Some(d) =>
                let outcome = LevelSystem.gainExp(d#exp, expGain);
                if (not outcome#levelUp)
                    PlayerScene.mapPlayer(playerId, dd -> {exp = outcome#exp | dd}, scene)
                else {
                    let rolls  = rollGrowth();
                    let before = LevelSystem.statsOf(d#resource);
                    let after  = LevelSystem.applyGrowth(before, d#resource#growthRates, rolls);
                    let hpGain = after#hp - before#hp;
                    let result = LevelSystem.buildResult(d#resource#description, d#level,
                                                         before, after);
                    let newHp  = d#hp + hpGain;
                    GameLogger.playerLog("P${playerId} Lv${d#level} → Lv${d#level + 1}");
                    PlayerScene.mapPlayer(playerId, dd ->
                        {exp            = outcome#exp,
                         level          = dd#level + 1,
                         resource       = LevelSystem.withStats(after, dd#resource),
                         hp             = newHp,
                         pendingLevelUp = Some(result) | dd}, scene)
                        |> UnitHPBarScene.update(PlayerScene.playerPath(playerId), newHp)
                }
        }
}
