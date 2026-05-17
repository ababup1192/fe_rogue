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

    use Json.JsonError.JsonError
    use Json.Path.Path.Root

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

    /// バトル全体のスナップショット。 hero / enemy のステータスは Resource モジュール側で
    /// 定義された型を再利用する（resources/player.json と resources/monsters.json から
    /// 読み込まれる）。
    /// `inventory` はアイテム所持リストで、 戦闘中に applyItem で消費される。
    /// `enemyBlinkRemaining` は敵が攻撃を受けたときに正値が設定され、 process が delta 分
    /// 減算しながら EnemyLabel を visible toggle してダメージ演出を出す（0 で通常表示）。
    pub type alias State = {
        hero                 = PlayerStats.HeroStats,
        enemy                = MonsterCatalog.EnemyStats,
        inventory            = List[ItemCatalog.InventoryEntry],
        lastAction           = Option[ActionResult],
        enemyBlinkRemaining  = Float64,
        flashRemaining       = Float64,
        flashColor           = Color,
        shakeRemaining       = Float64
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

    /// 起動時にロードされる敵 id。 PR4 で複数敵 / 階層別を扱うときは catalog から
    /// 別の id を選ぶ or pool 化する。
    def initialEnemyId(): String = "slime"

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

    def tagParser(opt: Option[String]): Result[Json.JsonError, NodeTag] =
        match opt {
            case None                  => Ok(NodeTag.NoTag)
            case Some("NoTag")         => Ok(NodeTag.NoTag)
            case Some("BattleLayer")   => Ok(NodeTag.BattleLayer)
            case Some("EnemyLabel")    => Ok(NodeTag.EnemyLabel)
            case Some("StatusLabel")   => Ok(NodeTag.StatusLabel)
            case Some("FlashOverlay")  => Ok(NodeTag.FlashOverlay)
            case Some(unknown)         => Err(JsonError(Root, Set#{"BattleScene tag (got: ${unknown})"}))
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
        let enemy = MonsterCatalog.get(initialEnemyId(), monsters);
        let spells = SpellCatalog.load(spellsJsonPath());
        let items = ItemCatalog.load(itemsJsonPath());
        let initial = ({
            hero = hero, enemy = enemy,
            inventory = items#inventory,
            lastAction = None,
            enemyBlinkRemaining = 0.0,
            flashRemaining = 0.0,
            flashColor = damageFlashColor(),
            shakeRemaining = 0.0
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

    // ── 攻撃適用 (純粋関数 Battle.computeAttack を呼ぶ) ──

    /// 敵が攻撃を受けたときの点滅時間（秒）。 process が `delta` ずつ減算しながら
    /// EnemyLabel を visible toggle して、 DQ 風「ダメージで一瞬チカチカする」 を出す。
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

    /// 勇者の通常攻撃。 ダメージ計算 → 敵 HP 減算 → lastAction 更新 + 敵点滅トリガー。
    pub def applyPlayerAttack(scene: Scene[NodeTag]): Scene[NodeTag] \ Math.Random =
        let state = readState(scene);
        let rng = Math.Random.randomFloat64();
        let dmg = Battle.computeAttack(state#hero#attack, state#enemy#defense, rng);
        let newHp = Int32.max(0, state#enemy#hp - dmg);
        let action = ({ actor = state#hero#name, target = state#enemy#name, damage = dmg, kind = ActionKind.Attack }: ActionResult);
        let newEnemy = { hp = newHp | state#enemy };
        let newState = {
            lastAction = Some(action),
            enemy = newEnemy,
            enemyBlinkRemaining = enemyBlinkDuration()
            | state
        };
        writeState(newState, scene)

    /// 勇者の呪文発動。 `SpellCatalog` から spell を取り出し、 kind に応じて heal (勇者 HP
    /// 回復) or damage (敵 HP 減算) を計算 + MP 消費。 MP 不足なら lastAction に「足りない」
    /// 情報だけ書いて何もしない。
    /// SpellCatalog は起動時にロード済みで Data に保持してあるので、 effect なしで読める。
    pub def applySpell(spellId: String, scene: Scene[NodeTag]):
                       Scene[NodeTag] \ Math.Random =
        let data = readData(scene);
        let state = data#current;
        let spell = SpellCatalog.get(spellId, data#spellCatalog);
        if (state#hero#mp < spell#cost)
            applySpellInsufficientMp(spell, state, scene)
        else
            applySpellEffect(spell, state, scene)

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

    /// 呪文効果適用 (heal / damage)。 MP は事前にチェック済み。
    def applySpellEffect(spell: SpellCatalog.SpellDef, state: State,
                         scene: Scene[NodeTag]): Scene[NodeTag] \ Math.Random =
        let rng = Math.Random.randomFloat64();
        let power = Battle.computeSpell(spell#minPower, spell#maxPower, rng);
        let mpAfter = state#hero#mp - spell#cost;
        let heroAfterMp = { mp = mpAfter | state#hero };
        match spell#kind {
            case SpellCatalog.SpellKind.Heal =>
                let healed = Int32.min(state#hero#maxHp, state#hero#hp + power);
                let newHero = { hp = healed | heroAfterMp };
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
            case SpellCatalog.SpellKind.Damage =>
                let newHp = Int32.max(0, state#enemy#hp - power);
                let newEnemy = { hp = newHp | state#enemy };
                let action = ({
                    actor  = "${state#hero#name}の ${spell#name}！",
                    target = state#enemy#name,
                    damage = power,
                    kind   = ActionKind.SpellDamage
                }: ActionResult);
                writeState({
                    hero = heroAfterMp,
                    enemy = newEnemy,
                    lastAction = Some(action),
                    enemyBlinkRemaining = enemyBlinkDuration(),
                    flashRemaining = flashDuration(),
                    flashColor = damageFlashColor()
                    | state
                }, scene)
        }

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

    /// 敵の通常攻撃。 勇者 HP 減算 + lastAction 更新 + 画面揺れトリガー。
    pub def applyEnemyAttack(scene: Scene[NodeTag]): Scene[NodeTag] \ Math.Random =
        let state = readState(scene);
        let rng = Math.Random.randomFloat64();
        let dmg = Battle.computeAttack(state#enemy#attack, state#hero#defense, rng);
        let newHp = Int32.max(0, state#hero#hp - dmg);
        let action = ({ actor = state#enemy#name, target = state#hero#name, damage = dmg, kind = ActionKind.Attack }: ActionResult);
        let newHero = { hp = newHp | state#hero };
        let newState = {
            lastAction = Some(action),
            hero = newHero,
            shakeRemaining = shakeDuration()
            | state
        };
        writeState(newState, scene)

    /// バトルを初期状態に戻す（Resource ロードはしない。 initial → current コピー）。
    pub def resetBattle(scene: Scene[NodeTag]): Scene[NodeTag] =
        let data = readData(scene);
        writeData({current = data#initial | data}, scene)

    /// Enter 押下時のフェーズ遷移ロジック。 戦闘サイクルを 1 個のディスパッチに集約する。
    pub def advancePhaseOnEnter(scene: Scene[NodeTag]): Scene[NodeTag] \ {GamePhaseState, Math.Random} =
        let phase = GamePhaseState.get();
        match phase {
            case GamePhase.Title =>
                GamePhaseState.put(GamePhase.CommandSelect); scene

            case GamePhase.Resolving =>
                if (not MessageScene.isComplete(scene))
                    checked_ecast(MessageScene.skipTypewriter(scene))
                else {
                    let s = readState(scene);
                    if (s#enemy#hp <= 0) {
                        GamePhaseState.put(GamePhase.Victory); scene
                    } else {
                        let afterCounter = applyEnemyAttack(scene);
                        GamePhaseState.put(GamePhase.EnemyActing);
                        afterCounter
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
                        GamePhaseState.put(GamePhase.CommandSelect); scene
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

    // ── process: EnemyLabel を BattleState から更新 (敵 HP <= 0 で非表示 + 被弾点滅) ──

    /// EnemyLabel を毎フレーム更新:
    ///   1. text を `state#enemy#name` で更新
    ///   2. enemyBlinkRemaining > 0 のとき、 残り時間を `delta` 減らして visible を toggle
    ///      （0.05 秒間隔で on/off）。 完了で visible=true（HP>0 のとき）に戻す
    ///   3. 敵 HP <= 0 で hidden
    pub def processEnemyLabel(delta: Duration.Duration, node: EngineNode[NodeTag],
                              _path: NodePath,
                              scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) =
        match node {
            case EngineNode.Label2DWithState(label, NodeTag.EnemyLabel) =>
                let s = readState(scene);
                let dtSec = Duration.toSeconds(delta);
                let blinkLeft = s#enemyBlinkRemaining - dtSec;
                let (visible, newBlink) =
                    if (s#enemy#hp <= 0) (false, 0.0)
                    else if (blinkLeft > 0.0) {
                        // 0.05 秒周期で on/off。 「総時間 - 残り」 = 経過時間を 0.05 で割った
                        // floor の偶奇で visible を判定。 開始フレーム phase=0 は invisible に
                        // して被弾の瞬間に「パッ」 と消えるようにする (DQ 風)。
                        let elapsed = enemyBlinkDuration() - blinkLeft;
                        let phase = Float64.tryToInt32(elapsed / 0.05)
                                        |> Option.getWithDefault(0);
                        ((Int32.modulo(phase, 2) == 1), blinkLeft)
                    } else (true, 0.0);
                let updated = label
                    |> Label2D.setText(s#enemy#name)
                    |> CanvasItem.setVisible(visible);
                let sceneWithBlink = writeState({enemyBlinkRemaining = newBlink | s}, scene);
                (EngineNode.Label2DWithState(updated, NodeTag.EnemyLabel), sceneWithBlink)
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
