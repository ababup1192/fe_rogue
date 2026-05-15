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

    /// 直前に発生した行動の結果（メッセージ生成用: 誰が誰に何ダメージ与えたか）。
    pub type alias ActionResult = {
        actor  = String,
        target = String,
        damage = Int32
    }

    /// バトル全体のスナップショット。 hero / enemy のステータスは Resource モジュール側で
    /// 定義された型を再利用する（resources/player.json と resources/monsters.json から
    /// 読み込まれる）。
    pub type alias State = {
        hero       = PlayerStats.HeroStats,
        enemy      = MonsterCatalog.EnemyStats,
        lastAction = Option[ActionResult]
    }

    /// NodeTag.BattleState に持たせるデータ。 `initial` は Resource から構築した不変の
    /// 初期値で、 `current` がフレーム毎に更新される。 `resetBattle` は `initial` を
    /// `current` にコピーするだけ。
    pub type alias Data = {
        current = State,
        initial = State
    }

    // ── 定数 ──

    def sceneJsonPath(): String = "src/scenes/BattleScene.scene.json"
    def playerJsonPath(): String = "resources/player.json"
    def monstersJsonPath(): String = "resources/monsters.json"

    /// 起動時にロードされる敵 id。 PR4 で複数敵 / 階層別を扱うときは catalog から
    /// 別の id を選ぶ or pool 化する。
    def initialEnemyId(): String = "slime"

    pub def layerName(): String = "battle"
    pub def stateName(): String = "state"
    pub def statePath(): NodePath = layerName() :: stateName() :: Nil

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
            case Some(unknown)         => Err(JsonError(Root, Set#{"BattleScene tag (got: ${unknown})"}))
        }

    /// scene.json をロード + Resource (player.json / monsters.json) から初期 State を
    /// 構築 + 隠し Marker2D に BattleState を保持。 ファイル読みはここで 1 度だけ走る。
    pub def add(fontAtlas: FontAtlas, scene: Scene[NodeTag]):
                Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        let loaded = SceneLoader.loadSceneWithFont(sceneJsonPath(), fontAtlas, tagParser, scene);
        let hero = PlayerStats.load(playerJsonPath());
        let catalog = MonsterCatalog.load(monstersJsonPath());
        let enemy = MonsterCatalog.get(initialEnemyId(), catalog);
        let initial = ({ hero = hero, enemy = enemy, lastAction = None }: State);
        let data = ({ current = initial, initial = initial }: Data);
        let marker = Marker2D.make(Vec2.zero());
        let stateNode = EngineNode.Marker2DWithState(marker, NodeTag.BattleState(data));
        Scene.addChildAt(layerName() :: Nil, stateName(), stateNode, loaded)

    // ── 攻撃適用 (純粋関数 Battle.computeAttack を呼ぶ) ──

    /// 勇者の通常攻撃。 ダメージ計算 → 敵 HP 減算 → lastAction 更新。
    pub def applyPlayerAttack(scene: Scene[NodeTag]): Scene[NodeTag] \ Math.Random =
        let state = readState(scene);
        let rng = Math.Random.randomFloat64();
        let dmg = Battle.computeAttack(state#hero#attack, state#enemy#defense, rng);
        let newHp = Int32.max(0, state#enemy#hp - dmg);
        let action = ({ actor = state#hero#name, target = state#enemy#name, damage = dmg }: ActionResult);
        let newEnemy = { hp = newHp | state#enemy };
        let newState = { lastAction = Some(action), enemy = newEnemy | state };
        writeState(newState, scene)

    /// 敵の通常攻撃。 勇者 HP 減算 + lastAction 更新。
    pub def applyEnemyAttack(scene: Scene[NodeTag]): Scene[NodeTag] \ Math.Random =
        let state = readState(scene);
        let rng = Math.Random.randomFloat64();
        let dmg = Battle.computeAttack(state#enemy#attack, state#hero#defense, rng);
        let newHp = Int32.max(0, state#hero#hp - dmg);
        let action = ({ actor = state#enemy#name, target = state#hero#name, damage = dmg }: ActionResult);
        let newHero = { hp = newHp | state#hero };
        let newState = { lastAction = Some(action), hero = newHero | state };
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

    // ── process: visible 切替 ──

    pub def processLayer(_delta: Duration.Duration, node: EngineNode[NodeTag],
                         _path: NodePath,
                         scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) \ GamePhaseState =
        match node {
            case EngineNode.CanvasLayerWithState(cl, NodeTag.BattleLayer) =>
                let visible = GamePhaseState.get() != GamePhase.Title;
                (EngineNode.CanvasLayerWithState(CanvasItem.setVisible(visible, cl), NodeTag.BattleLayer), scene)
            case _ => (node, scene)
        }

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

    // ── process: EnemyLabel を BattleState から更新 (敵 HP <= 0 で非表示) ──

    pub def processEnemyLabel(_delta: Duration.Duration, node: EngineNode[NodeTag],
                              _path: NodePath,
                              scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) =
        match node {
            case EngineNode.Label2DWithState(label, NodeTag.EnemyLabel) =>
                let s = readState(scene);
                let updated = label
                    |> Label2D.setText(s#enemy#name)
                    |> CanvasItem.setVisible(s#enemy#hp > 0);
                (EngineNode.Label2DWithState(updated, NodeTag.EnemyLabel), scene)
            case _ => (node, scene)
        }
}
