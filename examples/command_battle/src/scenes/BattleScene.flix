/// バトル背景シーン。黒背景 + 敵テキスト + 勇者ステータス + 戦闘状態 (BattleState)。
///
/// 設計:
///   - 起動時 (`add`) に `resources/player.json` と `resources/monsters.json` を 1 度だけ
///     読み込み、 そこから作った初期 State を `BattleState({current, initial})` データで
///     scene 内の隠し Marker2D に保持する。
///   - `resetBattle` は scene 内の `initial` を `current` にコピーするだけで、 再度の
///     ファイル読みは不要 (effect なし)。
///   - 各フェーズ遷移ロジック (`advancePhaseOnEnter`) もここに集約し、 Game.flix の
///     InputHandler は dispatch のみに留める。
mod BattleScene {

    use JsonCompat.PathTag.Root

    // ── 型 ──

    /// 直前に発生した行動の種別。 メッセージ生成で文体を分岐するのに使う。
    pub enum ActionKind with Eq, ToString {
        case Attack         // 通常攻撃 (たたかう / 敵反撃)
        case SpellDamage    // 攻撃呪文 (メラ等)
        case SpellHeal      // 回復呪文 (ホイミ等)
        case Insufficient   // MP 不足で発動できなかった
    }

    /// 直前に発生した行動の結果（メッセージ生成用: 誰が誰に何ダメージ与えたか + 種別）。
    pub type alias ActionResult = {
        actor  = String,
        target = String,
        damage = Int32,
        kind   = ActionKind
    }

    /// TargetSelect 中に「何を発動しようとしているか」 を覚えておくための情報。
    ///   - AttackAction: たたかう（target 確定後に通常攻撃を実行）
    ///   - SpellAction(spellId): 攻撃呪文（target 確定後にダメージ呪文を実行）
    pub enum PendingAction with Eq {
        case AttackAction
        case SpellAction(String)
    }

    /// バトル全体のスナップショット。 hero / enemy のステータスは Resource モジュール側で
    /// 定義された型を再利用する（resources/player.json と resources/monsters.json から
    /// 読み込まれる）。
    /// `inventory` はアイテム所持リストで、 戦闘中に applyItem で消費される。
    /// `enemyBlinkRemaining` は敵が攻撃を受けたときに正値が設定され、 process が delta 分
    /// 減算しながら EnemySprite を visible toggle してダメージ演出を出す（0 で通常表示）。
    /// 戦闘の全状態。 hero と enemies (複数) を保持し、 演出用の残り時間も載せる。
    /// `enemyTurnIndex` は EnemyActing 中に「次の敵」を探すカーソル（-1 = 敵ターン未開始）。
    /// `enemyBlinkIndex` は直前に被弾した敵のインデックス（-1 = 点滅対象なし）。
    pub type alias State = {
        hero                 = PlayerStats.HeroStats,
        enemies              = List[MonsterCatalog.EnemyStats],
        inventory            = List[ItemCatalog.InventoryEntry],
        lastAction           = Option[ActionResult],
        enemyTurnIndex       = Int32,
        enemyBlinkIndex      = Int32,
        enemyBlinkRemaining  = Float64,
        flashRemaining       = Float64,
        flashColor           = Color,
        shakeRemaining       = Float64,
        pendingAction        = Option[PendingAction],
        targetCursor         = Int32
    }

    /// NodeTag.BattleState に持たせるデータ。 `initial` は Resource から構築した不変の
    /// 初期値で、 `current` がフレーム毎に更新される。 `resetBattle` は `initial` を
    /// `current` にコピーするだけ。 `spellCatalog` は起動時に 1 度ロードした不変カタログで、
    /// applySpell から effect なしで参照できる。
    pub type alias Data = {
        current      = State,
        initial      = State,
        spellCatalog = SpellCatalog.Catalog,
        itemCatalog  = ItemCatalog.Catalog
    }

    // ── 定数 ──

    def sceneJsonPath(): String = "src/scenes/BattleScene.scene.json"
    def playerJsonPath(): String = "resources/player.json"
    def monstersJsonPath(): String = "resources/monsters.json"
    def spellsJsonPath(): String = "resources/spells.json"
    def itemsJsonPath(): String = "resources/items.json"

    /// 起動時にロードされる敵 id のリスト（順序がそのまま画面上の左→右配置 = enemy0/enemy1 と
    /// 一致する）。 enemies フィールドにそのまま格納される。
    def initialEnemyIds(): List[String] = "slime" :: "drakee" :: Nil

    pub def layerName(): String = "battle"
    pub def stateName(): String = "state"
    pub def statePath(): NodePath = layerName() :: stateName() :: Nil

    /// UI パネルをまとめて格納する CanvasLayer のパス。 `battle` CanvasLayer の child として
    /// 配置することで、 battle.visible 1 つで Title 時に UI 全体が親子伝播で hidden になる
    /// （Godot の Control hierarchy 流）。
    pub def uiLayerName(): String = "ui_layer"
    pub def uiLayerPath(): NodePath = layerName() :: uiLayerName() :: Nil

    // ── ヘルパー: BattleState ノードへの read/write ──

    /// 戦闘 Data (current + initial) を取得。 存在しないなら panic。
    pub def readData(scene: Scene[NodeTag]): Data =
        match Scene.getState(statePath(), scene) {
            case Some(NodeTag.BattleState(d)) => d
            case _ => bug!("BattleScene: BattleState node not found at ${statePath()}")
        }

    /// 現在の State (current) を取得。
    pub def readState(scene: Scene[NodeTag]): State = readData(scene)#current

    /// 戦闘 Data を新しい値で置き換える。
    pub def writeData(data: Data, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.setState(statePath(), NodeTag.BattleState(data), scene)

    /// current State だけを置き換える（initial は維持）。
    pub def writeState(state: State, scene: Scene[NodeTag]): Scene[NodeTag] =
        let data = readData(scene);
        writeData({current = state | data}, scene)

    // ── SceneLoader 用 ──

    def tagParser(opt: Option[String]): Result[Util.Json.JsonError, NodeTag] =
        match opt {
            case None                  => Ok(NodeTag.NoTag)
            case Some("NoTag")         => Ok(NodeTag.NoTag)
            case Some("BattleLayer")   => Ok(NodeTag.BattleLayer)
            case Some("EnemySprite0")  => Ok(NodeTag.EnemySprite(0))
            case Some("EnemySprite1")  => Ok(NodeTag.EnemySprite(1))
            case Some("StatusLabel")   => Ok(NodeTag.StatusLabel)
            case Some("FlashOverlay")  => Ok(NodeTag.FlashOverlay)
            case Some("TargetCursor")  => Ok(NodeTag.TargetCursor)
            case Some(unknown)         => Err(JsonCompat.jsonError(Root, Set#{"BattleScene tag (got: ${unknown})"}))
        }

    /// scene.json をロード + Resource (player.json / monsters.json / spells.json) から
    /// 初期 State と SpellCatalog を構築 + 隠し Marker2D に BattleState を保持。
    /// ファイル読みはここで 1 度だけ走り、 以降の applySpell 等は Data 経由で effect なし
    /// アクセスできる。
    pub def add(fontAtlas: FontAtlas, scene: Scene[NodeTag]):
                Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        let loaded = SceneLoader.loadSceneWithFont(sceneJsonPath(), fontAtlas, tagParser, scene);
        let hero = PlayerStats.load(playerJsonPath());
        let monsters = MonsterCatalog.load(monstersJsonPath());
        let enemies = List.map(id -> MonsterCatalog.get(id, monsters), initialEnemyIds());
        let spells = SpellCatalog.load(spellsJsonPath());
        let items = ItemCatalog.load(itemsJsonPath());
        let initial = ({
            hero = hero, enemies = enemies,
            inventory = items#inventory,
            lastAction = None,
            enemyTurnIndex = -1,
            enemyBlinkIndex = -1,
            enemyBlinkRemaining = 0.0,
            flashRemaining = 0.0,
            flashColor = damageFlashColor(),
            shakeRemaining = 0.0,
            pendingAction = None,
            targetCursor = 0
        }: State);
        let data = ({
            current = initial, initial = initial,
            spellCatalog = spells, itemCatalog = items
        }: Data);
        let marker = Marker2D.make(Vec2.zero());
        let stateNode = EngineNode.Marker2DWithState(marker, NodeTag.BattleState(data));
        // battle CanvasLayer の child として state ノード + ui_layer (UI 全体の親) を追加。
        // ui_layer 配下に Message/Command/Spell/Item の各 Panel が後で（Game.buildScene の
        // chain で）入る。 battle.visible を切り替えると ui_layer 配下も親子伝播で hide される。
        let uiLayerNode = EngineNode.CanvasLayerWithState(CanvasLayer.make(0), NodeTag.NoTag);
        loaded
            |> Scene.addChildAt(layerName() :: Nil, stateName(), stateNode)
            |> Scene.addChildAt(layerName() :: Nil, uiLayerName(), uiLayerNode)
            |> applyEnemySprites(enemies)

    /// `enemies` リストの各 `sprite` 情報を、 scene.json で配置された enemy0 / enemy1 の
    /// Sprite2D に流し込む。 texture / hframes / vframes / frame をそれぞれ反映。
    /// これにより monsters.json で texture を切り替えるとそのまま戦闘画面に反映される。
    def applyEnemySprites(enemies: List[MonsterCatalog.EnemyStats],
                          scene: Scene[NodeTag]): Scene[NodeTag] =
        List.zipWithIndex(enemies)
            |> List.foldLeft((acc, pair) -> {
                let (idx, e) = pair;
                let spec = e#sprite;
                Scene.mapEngineNode(layerName() :: "enemy${idx}" :: Nil, n -> match n {
                    case EngineNode.Sprite2DWithState(sp, tag) =>
                        let updated = sp
                            |> Sprite2D.setTexture(spec#texture)
                            |> Sprite2D.setHframes(spec#hframes)
                            |> Sprite2D.setVframes(spec#vframes)
                            |> Sprite2D.setFrame(spec#frame);
                        EngineNode.Sprite2DWithState(updated, tag)
                    case other => other
                }, acc)
            }, scene)

    // ── 攻撃適用 (純粋関数 Battle.computeAttack を呼ぶ) ──

    /// 敵が攻撃を受けたときの点滅時間（秒）。 process が `delta` ずつ減算しながら
    /// EnemySprite を visible toggle して、 DQ 風「ダメージで一瞬チカチカする」 を出す。
    def enemyBlinkDuration(): Float64 = 0.4

    /// 呪文発動時の画面フラッシュ時間（秒）。
    def flashDuration(): Float64 = 0.3

    /// フラッシュのピーク alpha (0.0..1.0)。 数値大きいほど派手に光る。
    def flashPeakAlpha(): Float32 = 0.45f32

    /// 攻撃呪文 (メラ等) のフラッシュ色: 赤。
    def damageFlashColor(): Color = {r = 1.0f32, g = 0.2f32, b = 0.2f32}

    /// 回復呪文 (ホイミ等) のフラッシュ色: 緑系。
    def healFlashColor(): Color = {r = 0.4f32, g = 1.0f32, b = 0.5f32}

    /// 勇者が被ダメージしたときの画面揺れ時間（秒）。
    def shakeDuration(): Float64 = 0.3

    /// 画面揺れの最大振幅（px）。 残り時間に応じて 0 まで減衰する。
    def shakeAmplitude(): Float64 = 8.0

    // ── List[EnemyStats] ヘルパー ──

    /// 生きている (hp > 0) 最初の敵の (index, EnemyStats) を返す。 全滅なら None。
    def firstAlive(enemies: List[MonsterCatalog.EnemyStats]):
                   Option[(Int32, MonsterCatalog.EnemyStats)] =
        List.zipWithIndex(enemies)
            |> List.findMap(pair -> {
                let (idx, e) = pair;
                if (e#hp > 0) Some((idx, e)) else None
            })

    /// `after` 以降で次に生きている敵の (index, EnemyStats) を返す。 いなければ None。
    def nextAliveAfter(after: Int32, enemies: List[MonsterCatalog.EnemyStats]):
                       Option[(Int32, MonsterCatalog.EnemyStats)] =
        List.zipWithIndex(enemies)
            |> List.findMap(pair -> {
                let (idx, e) = pair;
                if (idx > after and e#hp > 0) Some((idx, e)) else None
            })

    /// `idx` 番目の敵を `f` で変換した新しいリストを返す。 範囲外なら原リスト。
    def updateEnemyAt(idx: Int32,
                      f: MonsterCatalog.EnemyStats -> MonsterCatalog.EnemyStats,
                      enemies: List[MonsterCatalog.EnemyStats]):
                      List[MonsterCatalog.EnemyStats] =
        List.zipWithIndex(enemies)
            |> List.map(pair -> {
                let (i, e) = pair;
                if (i == idx) f(e) else e
            })

    /// `idx` 番目の敵を返す。 範囲外なら None。
    pub def enemyAt(idx: Int32, enemies: List[MonsterCatalog.EnemyStats]):
                    Option[MonsterCatalog.EnemyStats] =
        List.nth(idx, enemies)

    /// 全敵が hp <= 0 か。
    def allDead(enemies: List[MonsterCatalog.EnemyStats]): Bool =
        List.forAll(e -> e#hp <= 0, enemies)

    /// 生きている敵の数。
    def aliveCount(enemies: List[MonsterCatalog.EnemyStats]): Int32 =
        List.count(e -> e#hp > 0, enemies)

    /// 生きている敵の (index) のみのリスト。
    def aliveIndices(enemies: List[MonsterCatalog.EnemyStats]): List[Int32] =
        List.zipWithIndex(enemies)
            |> List.filterMap(pair -> {
                let (i, e) = pair;
                if (e#hp > 0) Some(i) else None
            })

    /// 生きている最初の敵のインデックス。
    def firstAliveIndex(enemies: List[MonsterCatalog.EnemyStats]): Option[Int32] =
        match firstAlive(enemies) {
            case Some(p) => { let (i, _) = p; Some(i) }
            case None    => None
        }

    /// 勇者の通常攻撃を指定 index の敵に適用する。 ダメージ計算 → 敵 HP 減算 →
    /// lastAction 更新 + 敵点滅 + damage SE。 範囲外 / 既に倒れている敵が指定されたら何もしない。
    pub def applyPlayerAttackAt(targetIdx: Int32,
                                scene: Scene[NodeTag]):
                                Scene[NodeTag] \ {Math.Random, GameEngine.Audio} =
        let state = readState(scene);
        match enemyAt(targetIdx, state#enemies) {
            case None    => scene
            case Some(t) =>
                if (t#hp <= 0) scene
                else {
                    let rng = Math.Random.randomFloat64();
                    let dmg = Battle.computeAttack(state#hero#attack, t#defense, rng);
                    let newEnemies = updateEnemyAt(targetIdx,
                        e -> { hp = Int32.max(0, e#hp - dmg) | e }, state#enemies);
                    let action = ({
                        actor  = state#hero#name,
                        target = t#name,
                        damage = dmg,
                        kind   = ActionKind.Attack
                    }: ActionResult);
                    AudioStreamPlayer.play("damage");
                    writeState({
                        lastAction = Some(action),
                        enemies = newEnemies,
                        enemyBlinkIndex = targetIdx,
                        enemyBlinkRemaining = enemyBlinkDuration()
                        | state
                    }, scene)
                }
        }

    /// MP 不足ケース。 lastAction の damage=0 にして、 メッセージ側で特殊扱い。
    def applySpellInsufficientMp(spell: SpellCatalog.SpellDef, state: State,
                                 scene: Scene[NodeTag]): Scene[NodeTag] =
        let action = ({
            actor  = "${state#hero#name}は ${spell#name}を となえた！",
            target = "",
            damage = 0,
            kind   = ActionKind.Insufficient
        }: ActionResult);
        writeState({lastAction = Some(action) | state}, scene)

    /// 回復呪文の効果適用。 MP は事前にチェック済み。 ターゲット選択は不要（勇者自身）。
    def applySpellHealEffect(spell: SpellCatalog.SpellDef, state: State,
                             scene: Scene[NodeTag]): Scene[NodeTag] \ Math.Random =
        let rng = Math.Random.randomFloat64();
        let power = Battle.computeSpell(spell#minPower, spell#maxPower, rng);
        let mpAfter = state#hero#mp - spell#cost;
        let healed = Int32.min(state#hero#maxHp, state#hero#hp + power);
        let newHero = { hp = healed, mp = mpAfter | state#hero };
        let action = ({
            actor  = "${state#hero#name}の ${spell#name}！",
            target = state#hero#name,
            damage = power,
            kind   = ActionKind.SpellHeal
        }: ActionResult);
        writeState({
            hero = newHero,
            lastAction = Some(action),
            flashRemaining = flashDuration(),
            flashColor = healFlashColor()
            | state
        }, scene)

    /// 攻撃呪文の効果適用。 MP は事前にチェック済み。 ターゲット index は呼び出し側が決定する
    /// （TargetSelect 経由 or 1 体のみ自動）。 ダメージ計算 → 敵 HP 減算 + 点滅 + 画面フラッシュ
    /// + damage SE。
    def applySpellDamageAt(spell: SpellCatalog.SpellDef, targetIdx: Int32, state: State,
                           scene: Scene[NodeTag]):
                           Scene[NodeTag] \ {Math.Random, GameEngine.Audio} =
        let mpAfter = state#hero#mp - spell#cost;
        let heroAfterMp = { mp = mpAfter | state#hero };
        match enemyAt(targetIdx, state#enemies) {
            case None    => writeState({hero = heroAfterMp | state}, scene)
            case Some(t) =>
                if (t#hp <= 0) writeState({hero = heroAfterMp | state}, scene)
                else {
                    let rng = Math.Random.randomFloat64();
                    let power = Battle.computeSpell(spell#minPower, spell#maxPower, rng);
                    let newEnemies = updateEnemyAt(targetIdx,
                        e -> { hp = Int32.max(0, e#hp - power) | e }, state#enemies);
                    let action = ({
                        actor  = "${state#hero#name}の ${spell#name}！",
                        target = t#name,
                        damage = power,
                        kind   = ActionKind.SpellDamage
                    }: ActionResult);
                    AudioStreamPlayer.play("damage");
                    writeState({
                        hero = heroAfterMp,
                        enemies = newEnemies,
                        lastAction = Some(action),
                        enemyBlinkIndex = targetIdx,
                        enemyBlinkRemaining = enemyBlinkDuration(),
                        flashRemaining = flashDuration(),
                        flashColor = damageFlashColor()
                        | state
                    }, scene)
                }
        }

    // ── ターゲット選択 開始エントリ ──

    /// 「たたかう」 発動エントリ。 生きている敵が 1 体なら即攻撃 + Resolving、 複数いるなら
    /// TargetSelect フェーズへ。 全滅状態（来ないはず）なら何もしない。
    pub def beginAttack(scene: Scene[NodeTag]):
                        Scene[NodeTag] \ {GamePhaseState, Math.Random, GameEngine.Audio} =
        let s = readState(scene);
        if (aliveCount(s#enemies) <= 1) {
            match firstAliveIndex(s#enemies) {
                case None      => scene
                case Some(idx) =>
                    let after = applyPlayerAttackAt(idx, scene);
                    GamePhaseState.put(GamePhase.Resolving);
                    after
            }
        } else {
            let cursorIdx = firstAliveIndex(s#enemies) |> Option.getWithDefault(0);
            GamePhaseState.put(GamePhase.TargetSelect);
            writeState({
                pendingAction = Some(PendingAction.AttackAction),
                targetCursor  = cursorIdx
                | s
            }, scene)
        }

    /// 「じゅもん」 確定エントリ。 MP 不足 / Heal / Damage で分岐。
    ///   - MP 不足: Resolving で「足りない！」 メッセージ
    ///   - Heal: そのまま回復適用 + Resolving
    ///   - Damage で敵が複数生存: TargetSelect へ
    ///   - Damage で敵が 1 体: 即発動 + Resolving
    pub def beginSpell(spellId: String, scene: Scene[NodeTag]):
                       Scene[NodeTag] \ {GamePhaseState, Math.Random, GameEngine.Audio} =
        let data = readData(scene);
        let s = data#current;
        let spell = SpellCatalog.get(spellId, data#spellCatalog);
        if (s#hero#mp < spell#cost) {
            let after = applySpellInsufficientMp(spell, s, scene);
            GamePhaseState.put(GamePhase.Resolving);
            after
        } else
            match spell#kind {
                case SpellCatalog.SpellKind.Heal =>
                    let after = applySpellHealEffect(spell, s, scene);
                    GamePhaseState.put(GamePhase.Resolving);
                    after
                case SpellCatalog.SpellKind.Damage =>
                    if (aliveCount(s#enemies) <= 1) {
                        match firstAliveIndex(s#enemies) {
                            case None      => scene
                            case Some(idx) =>
                                let after = applySpellDamageAt(spell, idx, s, scene);
                                GamePhaseState.put(GamePhase.Resolving);
                                after
                        }
                    } else {
                        let cursorIdx = firstAliveIndex(s#enemies)
                                            |> Option.getWithDefault(0);
                        GamePhaseState.put(GamePhase.TargetSelect);
                        writeState({
                            pendingAction = Some(PendingAction.SpellAction(spellId)),
                            targetCursor  = cursorIdx
                            | s
                        }, scene)
                    }
            }

    // ── TargetSelect フェーズの入力処理 ──

    /// ← / → でターゲット敵カーソルを移動する。 生きている敵だけを巡回する（dead は skip）。
    /// `dir = -1` で前、 `+1` で次。 wrap-around。
    pub def moveTargetCursor(dir: Int32, scene: Scene[NodeTag]): Scene[NodeTag] =
        let s = readState(scene);
        let alive = aliveIndices(s#enemies);
        let count = List.length(alive);
        if (count <= 0) scene
        else {
            let currentPos = alive
                |> List.zipWithIndex
                |> List.findMap(pair -> {
                    let (i, idx) = pair;
                    if (idx == s#targetCursor) Some(i) else None
                })
                |> Option.getWithDefault(0);
            let newPos = Int32.modulo(currentPos + dir + count, count);
            let newIdx = List.nth(newPos, alive) |> Option.getWithDefault(s#targetCursor);
            writeState({targetCursor = newIdx | s}, scene)
        }

    /// Escape で TargetSelect をキャンセル → CommandSelect に戻る。
    pub def cancelTargetSelect(scene: Scene[NodeTag]): Scene[NodeTag] \ GamePhaseState =
        let s = readState(scene);
        GamePhaseState.put(GamePhase.CommandSelect);
        writeState({pendingAction = None | s}, scene)

    /// Enter で TargetSelect を確定 → 行動適用 → Resolving。
    /// `pendingAction` が None ならフェーズ整合性が崩れているので何もしない。
    pub def confirmTargetSelect(scene: Scene[NodeTag]):
                                Scene[NodeTag] \ {GamePhaseState, Math.Random, GameEngine.Audio} =
        let s = readState(scene);
        let targetIdx = s#targetCursor;
        let scene2 = match s#pendingAction {
            case Some(PendingAction.AttackAction) =>
                applyPlayerAttackAt(targetIdx, scene)
            case Some(PendingAction.SpellAction(spellId)) =>
                let data = readData(scene);
                let spell = SpellCatalog.get(spellId, data#spellCatalog);
                applySpellDamageAt(spell, targetIdx, s, scene)
            case None => scene
        };
        let s2 = readState(scene2);
        GamePhaseState.put(GamePhase.Resolving);
        writeState({pendingAction = None | s2}, scene2)

    /// 勇者がアイテムを使用する。 inventory から quantity を 1 消費し、 kind に応じて
    /// 効果を適用する（PR4 は Heal のみ）。 残数 0 で呼ばれた場合は何もしない。
    /// 乱数は不要なので effect なし。
    pub def applyItem(itemId: String, scene: Scene[NodeTag]): Scene[NodeTag] =
        let data = readData(scene);
        let state = data#current;
        let item = ItemCatalog.get(itemId, data#itemCatalog);
        let qty = ItemCatalog.quantityOf(itemId, state#inventory);
        if (qty <= 0)
            applyItemUnavailable(item, state, scene)
        else
            applyItemEffect(item, state, scene)

    /// 残数 0 で使えなかったケース（メニュー側で disabled になっているはずだが防御的に）。
    def applyItemUnavailable(item: ItemCatalog.ItemDef, state: State,
                             scene: Scene[NodeTag]): Scene[NodeTag] =
        let action = ({
            actor  = "${state#hero#name}は ${item#name}を つかおうとした！",
            target = "", damage = 0,
            kind   = ActionKind.Insufficient
        }: ActionResult);
        writeState({lastAction = Some(action) | state}, scene)

    /// アイテム効果を実適用する。 quantity 消費 + kind に応じた効果。
    def applyItemEffect(item: ItemCatalog.ItemDef, state: State,
                        scene: Scene[NodeTag]): Scene[NodeTag] =
        let newInventory = ItemCatalog.consume(item#id, state#inventory);
        match item#kind {
            case ItemCatalog.ItemKind.Heal =>
                let healed = Int32.min(state#hero#maxHp, state#hero#hp + item#power);
                let newHero = { hp = healed | state#hero };
                let action = ({
                    actor  = "${state#hero#name}は ${item#name}を つかった！",
                    target = state#hero#name,
                    damage = item#power,
                    kind   = ActionKind.SpellHeal
                }: ActionResult);
                writeState({
                    hero = newHero,
                    inventory = newInventory,
                    lastAction = Some(action),
                    flashRemaining = flashDuration(),
                    flashColor = healFlashColor()
                    | state
                }, scene)
        }

    /// 指定インデックスの敵が勇者を攻撃する。 勇者 HP 減算 + lastAction 更新 + 画面揺れ + damage SE
    /// + enemyTurnIndex を更新（EnemyActing 中に「次の敵」 を見つけるカーソル）。
    /// 範囲外 / 既に倒れている敵が指定された場合は何もしない（防御的）。
    pub def applyEnemyAttackAt(idx: Int32,
                               scene: Scene[NodeTag]):
                               Scene[NodeTag] \ {Math.Random, GameEngine.Audio} =
        let state = readState(scene);
        match enemyAt(idx, state#enemies) {
            case None    => scene
            case Some(e) =>
                if (e#hp <= 0) scene
                else {
                    let rng = Math.Random.randomFloat64();
                    let dmg = Battle.computeAttack(e#attack, state#hero#defense, rng);
                    let newHp = Int32.max(0, state#hero#hp - dmg);
                    let action = ({
                        actor  = e#name,
                        target = state#hero#name,
                        damage = dmg,
                        kind   = ActionKind.Attack
                    }: ActionResult);
                    AudioStreamPlayer.play("damage");
                    writeState({
                        lastAction = Some(action),
                        hero = { hp = newHp | state#hero },
                        enemyTurnIndex = idx,
                        shakeRemaining = shakeDuration()
                        | state
                    }, scene)
                }
        }

    /// バトルを初期状態に戻す（Resource ロードはしない。 initial → current コピー）。
    pub def resetBattle(scene: Scene[NodeTag]): Scene[NodeTag] =
        let data = readData(scene);
        writeData({current = data#initial | data}, scene)

    /// Enter 押下時のフェーズ遷移ロジック。 戦闘サイクルを 1 個のディスパッチに集約する。
    pub def advancePhaseOnEnter(scene: Scene[NodeTag]):
                                Scene[NodeTag] \ {GamePhaseState, Math.Random, GameEngine.Audio} =
        let phase = GamePhaseState.get();
        match phase {
            case GamePhase.Title =>
                GamePhaseState.put(GamePhase.CommandSelect); scene

            case GamePhase.TargetSelect =>
                confirmTargetSelect(scene)

            case GamePhase.Resolving =>
                if (not MessageScene.isComplete(scene))
                    checked_ecast(MessageScene.skipTypewriter(scene))
                else {
                    let s = readState(scene);
                    if (allDead(s#enemies)) {
                        AudioStreamPlayer.play("bonus");
                        GamePhaseState.put(GamePhase.Victory); scene
                    } else {
                        // 生きている最初の敵から敵ターンを開始する
                        match firstAlive(s#enemies) {
                            case None => {
                                AudioStreamPlayer.play("bonus");
                                GamePhaseState.put(GamePhase.Victory); scene
                            }
                            case Some((idx, _)) => {
                                let afterAttack = applyEnemyAttackAt(idx, scene);
                                GamePhaseState.put(GamePhase.EnemyActing);
                                afterAttack
                            }
                        }
                    }
                }

            case GamePhase.EnemyActing =>
                if (not MessageScene.isComplete(scene))
                    checked_ecast(MessageScene.skipTypewriter(scene))
                else {
                    let s = readState(scene);
                    if (s#hero#hp <= 0) {
                        GamePhaseState.put(GamePhase.Defeat); scene
                    } else {
                        // 次に生きている敵があれば連続して行動させる。 いなければ CommandSelect。
                        match nextAliveAfter(s#enemyTurnIndex, s#enemies) {
                            case Some((idx, _)) => applyEnemyAttackAt(idx, scene)
                            case None => {
                                GamePhaseState.put(GamePhase.CommandSelect);
                                checked_ecast(writeState({enemyTurnIndex = -1 | s}, scene))
                            }
                        }
                    }
                }

            case GamePhase.Victory =>
                GamePhaseState.put(GamePhase.Title);
                checked_ecast(resetBattle(scene))

            case GamePhase.Defeat =>
                GamePhaseState.put(GamePhase.Title);
                checked_ecast(resetBattle(scene))

            case _ => scene
        }

    // ── visibility (Push モデル) ──

    /// Title 以外で battle CanvasLayer を visible にする。
    pub def applyVisibility(phase: GamePhase, scene: Scene[NodeTag]): Scene[NodeTag] =
        let visible = phase != GamePhase.Title;
        Scene.mapEngineNode(layerName() :: Nil, node -> match node {
            case EngineNode.CanvasLayerWithState(cl, tag) =>
                EngineNode.CanvasLayerWithState(CanvasItem.setVisible(visible, cl), tag)
            case other => other
        }, scene)

    // ── process: StatusLabel を BattleState から更新 ──

    pub def processStatusLabel(_delta: Duration.Duration, node: EngineNode[NodeTag],
                               _path: NodePath,
                               scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) =
        match node {
            case EngineNode.Label2DWithState(label, NodeTag.StatusLabel) =>
                let s = readState(scene);
                let text = "${s#hero#name}   HP: ${s#hero#hp}/${s#hero#maxHp}"
                         + "   MP: ${s#hero#mp}/${s#hero#maxMp}   LV: ${s#hero#level}";
                (EngineNode.Label2DWithState(Label2D.setText(text, label), NodeTag.StatusLabel), scene)
            case _ => (node, scene)
        }

    // ── process: EnemySprite を BattleState から更新 (敵 HP <= 0 で非表示 + 被弾点滅) ──

    /// EnemySprite(idx) を毎フレーム更新:
    ///   1. enemies[idx].hp <= 0 で hidden
    ///   2. enemyBlinkIndex == idx と enemyBlinkRemaining > 0 のとき、 0.05 秒周期で
    ///      visible を toggle して被弾演出を出す（被弾対象だけが点滅、 別敵は通常表示のまま）
    ///   3. それ以外は visible=true
    /// enemyBlinkRemaining の減算は idx==enemyBlinkIndex の処理時にだけ行う（複数 Sprite で
    /// 二重減算しないため）。
    pub def processEnemySprite(idx: Int32, delta: Duration.Duration,
                               node: EngineNode[NodeTag],
                               _path: NodePath,
                               scene: Scene[NodeTag]):
                               (EngineNode[NodeTag], Scene[NodeTag]) =
        match node {
            case EngineNode.Sprite2DWithState(sprite, NodeTag.EnemySprite(_)) =>
                let s = readState(scene);
                let dtSec = Duration.toSeconds(delta);
                let enemyOpt = enemyAt(idx, s#enemies);
                let hp = enemyOpt |> Option.map(e -> e#hp) |> Option.getWithDefault(0);
                let isBlinkTarget = s#enemyBlinkIndex == idx and s#enemyBlinkRemaining > 0.0;
                let visible =
                    if (hp <= 0) false
                    else if (isBlinkTarget) {
                        let elapsed = enemyBlinkDuration() - s#enemyBlinkRemaining;
                        let phase = Float64.tryToInt32(elapsed / 0.05)
                                        |> Option.getWithDefault(0);
                        Int32.modulo(phase, 2) == 1
                    } else true;
                // enemyBlinkRemaining は被弾対象の sprite 処理時にのみ減算する
                let sceneNext =
                    if (s#enemyBlinkIndex == idx and s#enemyBlinkRemaining > 0.0) {
                        let newBlink = Float64.max(0.0, s#enemyBlinkRemaining - dtSec);
                        let (newBlinkIdx, newRemain) =
                            if (newBlink <= 0.0) (-1, 0.0)
                            else (s#enemyBlinkIndex, newBlink);
                        writeState({
                            enemyBlinkIndex = newBlinkIdx,
                            enemyBlinkRemaining = newRemain | s
                        }, scene)
                    } else scene;
                let updated = CanvasItem.setVisible(visible, sprite);
                (EngineNode.Sprite2DWithState(updated, NodeTag.EnemySprite(idx)), sceneNext)
            case _ => (node, scene)
        }

    // ── process: TargetCursor の位置 / 表示更新 ──

    /// 敵スロットの座標。 scene.json の enemy0 / enemy1 の pos と一致させる（重複は許容）。
    /// scene tree を辿る方式は path lookup の落とし穴があるため、 ハードコードで確実に出す。
    def enemySlotPosition(idx: Int32): Vec2.Vec2 =
        if      (idx == 0) {x = 220.0, y = 140.0}
        else if (idx == 1) {x = 420.0, y = 140.0}
        else               {x = 0.0,   y = 0.0}

    /// `TargetCursor` Label2D を毎フレーム更新:
    ///   - `pendingAction == None` ならカーソルは hidden
    ///   - そうでなければ `targetCursor` index のスプライトの真上に ▼ を表示する
    ///   Sprite2D は centered=true で描画されるので、 スプライト中心 (= スロット pos) から
    ///   半分高さ (scale=1.0、 128px → 64px) ぶん上 + さらに余白を取った位置に置く。
    pub def processTargetCursor(_delta: Duration.Duration, node: EngineNode[NodeTag],
                                _path: NodePath,
                                scene: Scene[NodeTag]):
                                (EngineNode[NodeTag], Scene[NodeTag]) =
        match node {
            case EngineNode.Label2DWithState(label, NodeTag.TargetCursor) =>
                let s = readState(scene);
                let updated = match s#pendingAction {
                    case None    => CanvasItem.setVisible(false, label)
                    case Some(_) =>
                        let pos = enemySlotPosition(s#targetCursor);
                        // ▼ 1 文字を sprite の真上に。 cursorX は ▼ の中心が sprite 中心に揃う
                        // ように左に半文字ぶん寄せる。 cursorY は sprite 上端 (中心 - 64) よりさらに
                        // 上に 20px ほど離す。
                        let cursorPos = {x = pos#x - 14.0, y = pos#y - 96.0};
                        label
                            |> Node2D.setPosition(cursorPos)
                            |> CanvasItem.setVisible(true)
                };
                (EngineNode.Label2DWithState(updated, NodeTag.TargetCursor), scene)
            case _ => (node, scene)
        }

    // ── process: battle CanvasLayer の offset を更新 (画面揺れ) ──

    /// 勇者が被ダメージしたとき `shakeRemaining` が正値にセットされる。 process が delta
    /// 減算しながら CanvasLayer.offset を sin/cos で振動させる。 振幅は残り時間に応じて
    /// 線形減衰し、 残り 0 で offset = (0,0) に戻す。
    pub def processBattleLayer(delta: Duration.Duration, node: EngineNode[NodeTag],
                               _path: NodePath,
                               scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) =
        match node {
            case EngineNode.CanvasLayerWithState(layer, NodeTag.BattleLayer) =>
                let s = readState(scene);
                let dtSec = Duration.toSeconds(delta);
                let shakeLeft = Float64.max(0.0, s#shakeRemaining - dtSec);
                let offset =
                    if (shakeLeft <= 0.0) Vec2.zero()
                    else {
                        let elapsed = shakeDuration() - shakeLeft;
                        let damp = shakeLeft / shakeDuration();
                        let amp = shakeAmplitude() * damp;
                        // 異なる周波数で揺れることでカオス感を出す
                        {x = amp * Vec2.sin(elapsed * 60.0),
                         y = amp * Vec2.cos(elapsed * 70.0)}
                    };
                let updatedLayer = CanvasLayer.setOffset(offset, layer);
                let sceneWithShake = writeState({shakeRemaining = shakeLeft | s}, scene);
                (EngineNode.CanvasLayerWithState(updatedLayer, NodeTag.BattleLayer), sceneWithShake)
            case _ => (node, scene)
        }

    // ── process: FlashOverlay の alpha を時間に応じて更新 ──

    /// 呪文発動で `flashRemaining` が正値にセットされると、 process が delta 減算しながら
    /// alpha を 残り時間 / 総時間 の比率で線形補間する（被弾直後がピーク、 残り 0 で透明）。
    /// 色は `flashColor` を modulate に流し込む（攻撃呪文は赤、 回復呪文は緑）。
    pub def processFlashOverlay(delta: Duration.Duration, node: EngineNode[NodeTag],
                                _path: NodePath,
                                scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) =
        match node {
            case EngineNode.ColorRectWithState(rect, NodeTag.FlashOverlay) =>
                let s = readState(scene);
                let dtSec = Duration.toSeconds(delta);
                let flashLeft = Float64.max(0.0, s#flashRemaining - dtSec);
                let alpha =
                    if (flashLeft <= 0.0) 0.0f32
                    else {
                        let ratio = Float64.truncateToFloat32(flashLeft / flashDuration());
                        ratio * flashPeakAlpha()
                    };
                let updatedRect = rect
                    |> ColorRect.setAlpha(alpha)
                    |> CanvasItem.setModulate(s#flashColor);
                let sceneWithFlash = writeState({flashRemaining = flashLeft | s}, scene);
                (EngineNode.ColorRectWithState(updatedRect, NodeTag.FlashOverlay), sceneWithFlash)
            case _ => (node, scene)
        }
}
